#!/usr/bin/env bash
# replication-audit.sh — compare source vs DR snapshots, report lag per dataset.
# Run from any machine with SSH keys to both hosts.
#
# The pair list is DERIVED FROM THE MIDDLEWARE (`replication.query`), not hardcoded.
# A hardcoded list is guaranteed to drift: it sat at 11 of ~19 replicated datasets and
# silently said nothing about the rest — an audit that reports "fine" about datasets it
# never looked at is worse than no audit. Anything added in the TrueNAS UI is audited
# from the next run onward, with no edit here.
#
# Tiers come from each task's own schedule, so a monthly dataset is not called stale at 8 days:
#   daily    (dom=*, auto)   26h window
#   monthly  (dom=1, auto)   768h window (31d + slack)
#   manual   (auto=false)    informational only — never marked stale
#   DISABLED (enabled=false) always flagged: a disabled task is a silent DR hole
#
# Usage: replication-audit.sh [-h]
# Env:   SRC   source ssh target, e.g. admin@nas.example   (REQUIRED)
#        DST   DR ssh target, e.g. user@dr.example         (REQUIRED)
#        PAIRS newline/space-separated "src-dataset:dr-dataset" overrides; skips the
#              middleware query entirely (offline use, or auditing a non-middleware pair)
#        MAX_AGE_H / MONTHLY_MAX_AGE_H  staleness windows (default 26 / 768)
# Exit:  0 all tracked datasets current · 1 something stale/missing · 2 host unreachable
#
# For the deeper per-dataset audit (every filesystem in both pools, including ones NO task
# covers, plus never-snapshotted datasets) you need a second, per-filesystem audit. This
# script answers "are the replication TASKS current"; that one answers "is anything unprotected".
set -u

case "${1:-}" in -h|--help) sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac

: "${SRC:?set SRC to the source ssh target, e.g. SRC=admin@nas.example}"
: "${DST:?set DST to the DR ssh target, e.g. DST=user@dr.example}"
MAX_AGE_H="${MAX_AGE_H:-26}"
MONTHLY_MAX_AGE_H="${MONTHLY_MAX_AGE_H:-768}"

# fail fast (and clearly) if a host is unreachable, instead of reporting
# every dataset as "NO SOURCE SNAPSHOTS"
for h in "$SRC" "$DST"; do
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$h" true 2>/dev/null \
    || { echo "ERROR: cannot SSH to $h" >&2; exit 2; }
done

# Derive "<src-dataset>:<dr-dataset>:<tier>" from the replication tasks.
# Multi-source tasks  point at a PARENT dataset and the
# middleware lands each source at <target>/<basename> — mirror that or the pairs are wrong.
derive_pairs() {
  ssh -o BatchMode=yes "$SRC" 'sudo -n midclt call replication.query' 2>/dev/null \
    | python3 -c '
import json, sys
try:
    tasks = json.load(sys.stdin)
except ValueError:
    sys.exit(1)
for t in tasks:
    srcs, tgt = t["source_datasets"], t["target_dataset"]
    sched = t.get("schedule") or {}
    if not t.get("auto", True):        tier = "manual"
    elif str(sched.get("dom", "*")) == "1": tier = "monthly"
    else:                              tier = "daily"
    if not t.get("enabled", True):     tier = "DISABLED"
    for s in srcs:
        dst = tgt if len(srcs) == 1 else tgt + "/" + s.rsplit("/", 1)[-1]
        print(f"{s}:{dst}:{tier}")
'
}

if [ -n "${PAIRS:-}" ]; then
  # shellcheck disable=SC2206
  pairs=($PAIRS)
  # tier defaults to daily when the caller did not supply one
  for i in "${!pairs[@]}"; do
    case "${pairs[$i]}" in *:*:*) ;; *) pairs[i]="${pairs[$i]}:daily" ;; esac
  done
  echo "Using PAIRS override (${#pairs[@]} datasets) — middleware not consulted."
else
  mapfile -t pairs < <(derive_pairs)
  [ "${#pairs[@]}" -eq 0 ] && {
    echo "ERROR: could not derive pairs from replication.query on $SRC." >&2
    echo "       Check passwordless sudo, or pass PAIRS='src:dst ...' explicitly." >&2
    exit 2; }
fi

snaps() { # $1=ssh-target $2=dataset → "name<TAB>unixtime" lines, newest last
  ssh -o BatchMode=yes "$1" "export PATH=\$PATH:/sbin:/usr/sbin;
    zfs list -t snapshot -Hp -o name,creation -s creation -d 1 '$2' 2>/dev/null" |
    awk -F'\t' '{sub(/.*@/,"",$1); print $1"\t"$2}'
}

now=$(date +%s)
rc=0; nstale=0; nok=0; ninfo=0
printf '%-42s %-9s %-26s %8s\n' DATASET TIER "NEWEST COMMON SNAPSHOT" "LAG(h)"
for pair in "${pairs[@]}"; do
  tier="${pair##*:}"; rest="${pair%:*}"
  src_ds="${rest%%:*}"; dst_ds="${rest#*:}"
  src_snaps=$(snaps "$SRC" "$src_ds"); dst_snaps=$(snaps "$DST" "$dst_ds")
  if [ -z "$src_snaps" ]; then
    printf '%-42s %-9s %s\n' "$src_ds" "$tier" "NO SOURCE SNAPSHOTS"; rc=1; nstale=$((nstale+1)); continue
  fi
  if [ -z "$dst_snaps" ]; then
    printf '%-42s %-9s %s\n' "$src_ds" "$tier" "NOT ON DR (full send needed)"; rc=1; nstale=$((nstale+1)); continue
  fi
  # newest snapshot name present on both sides
  common=$(comm -12 <(echo "$src_snaps" | cut -f1 | sort) <(echo "$dst_snaps" | cut -f1 | sort))
  if [ -z "$common" ]; then
    printf '%-42s %-9s %s\n' "$src_ds" "$tier" "NO COMMON SNAPSHOT"; rc=1; nstale=$((nstale+1)); continue
  fi
  # exact-name match (grep -F substring matching could pair the wrong lines)
  newest=$(awk -F'\t' 'NR==FNR{c[$1];next} $1 in c' <(echo "$common") <(echo "$src_snaps") | tail -1)
  name=$(echo "$newest" | cut -f1); ts=$(echo "$newest" | cut -f2)
  lag=$(( (now - ts) / 3600 ))
  case "$tier" in
    monthly)  limit=$MONTHLY_MAX_AGE_H ;;
    manual)   limit=-1 ;;   # informational: replicated by hand, never "stale"
    DISABLED) limit=0  ;;   # a disabled task is a DR hole regardless of lag
    *)        limit=$MAX_AGE_H ;;
  esac
  flag=""
  if [ "$limit" -lt 0 ]; then
    flag="  (manual tier — informational)"; ninfo=$((ninfo+1))
  elif [ "$tier" = DISABLED ]; then
    flag="  <-- TASK DISABLED"; rc=1; nstale=$((nstale+1))
  elif [ "$lag" -gt "$limit" ]; then
    flag="  <-- STALE (>${limit}h)"; rc=1; nstale=$((nstale+1))
  else
    nok=$((nok+1))
  fi
  printf '%-42s %-9s %-26s %8s%s\n' "$src_ds" "$tier" "@$name" "$lag" "$flag"
done

echo
echo "SUMMARY: ${#pairs[@]} tracked · $nok current · $nstale stale/missing/disabled · $ninfo manual-tier"
[ "$rc" -ne 0 ] && echo "Replication NOT fully current — do NOT run risky storage operations."
exit $rc
