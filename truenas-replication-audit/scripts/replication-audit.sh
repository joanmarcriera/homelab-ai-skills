#!/usr/bin/env bash
# replication-audit.sh — compare source vs DR snapshots, report lag.
# Run from any machine with SSH keys to both hosts.
set -u
SRC="${SRC:-admin@<TRUENAS_IP>}"
DST="${DST:-<USER>@<DR_HOST_IP>}"

# fail fast (and clearly) if a host is unreachable, instead of reporting
# every dataset as "NO SOURCE SNAPSHOTS"
for h in "$SRC" "$DST"; do
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$h" true 2>/dev/null \
    || { echo "ERROR: cannot SSH to $h" >&2; exit 1; }
done
# "<source-dataset>:<dr-dataset>" pairs to audit
PAIRS=(
  "FastPool/ix-apps:DR_pool/truenas_backup/ix-apps"
  "FastPool/applications:DR_pool/truenas_backup/applications-fast"
  "BigDisk/applications:DR_pool/truenas_backup/applications"
  "BigDisk/media/tubearchivist:DR_pool/truenas_backup/media/tubearchivist"
  # daily class
  "BigDisk/CryptoBackup:DR_pool/truenas_backup/CryptoBackup"
  "BigDisk/timemachine:DR_pool/truenas_backup/timemachine"
  "BigDisk/backup:DR_pool/truenas_backup/backup"
  # monthly class (lag up to ~31d is normal)
  "BigDisk/media:DR_pool/truenas_backup/media"
  "BigDisk/dataLeaks:DR_pool/truenas_backup/dataLeaks"
  "BigDisk/enCatala:DR_pool/truenas_backup/enCatala"
  "BigDisk/randomVideos:DR_pool/truenas_backup/randomVideos"
)

snaps() { # $1=ssh-target $2=dataset → "name<TAB>unixtime" lines, newest last
  ssh -o BatchMode=yes "$1" "export PATH=\$PATH:/sbin:/usr/sbin;
    zfs list -t snapshot -Hp -o name,creation -s creation -d 1 '$2' 2>/dev/null" |
    awk -F'\t' '{sub(/.*@/,"",$1); print $1"\t"$2}'
}

now=$(date +%s)
printf '%-45s %-28s %8s\n' DATASET "NEWEST COMMON SNAPSHOT" "LAG(d)"
for pair in "${PAIRS[@]}"; do
  src_ds="${pair%%:*}" dst_ds="${pair##*:}"
  src_snaps=$(snaps "$SRC" "$src_ds"); dst_snaps=$(snaps "$DST" "$dst_ds")
  if [ -z "$src_snaps" ]; then printf '%-45s %s\n' "$src_ds" "NO SOURCE SNAPSHOTS"; continue; fi
  if [ -z "$dst_snaps" ]; then printf '%-45s %s\n' "$src_ds" "NOT ON DR (full send needed)"; continue; fi
  # newest snapshot name present on both sides
  common=$(comm -12 <(echo "$src_snaps" | cut -f1 | sort) <(echo "$dst_snaps" | cut -f1 | sort))
  if [ -z "$common" ]; then printf '%-45s %s\n' "$src_ds" "NO COMMON SNAPSHOT"; continue; fi
  # exact-name match (grep -F substring matching could pair the wrong lines)
  newest=$(awk -F'\t' 'NR==FNR{c[$1];next} $1 in c' <(echo "$common") <(echo "$src_snaps") | tail -1)
  name=$(echo "$newest" | cut -f1); ts=$(echo "$newest" | cut -f2)
  lag=$(( (now - ts) / 86400 ))
  flag=""; [ "$lag" -gt 7 ] && flag="  <-- STALE"
  printf '%-45s %-28s %8s%s\n' "$src_ds" "@$name" "$lag" "$flag"
done
