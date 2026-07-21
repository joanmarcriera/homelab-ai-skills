#!/usr/bin/env bash
# replicate.sh — incremental ZFS replication TrueNAS → optiplex7040 DR.
# Usage: ./replicate.sh <source-dataset> <dr-dataset> [snapname]
# Example: ./replicate.sh BigDisk/applications DR_pool/truenas_backup/applications
set -eu
SRC="${SRC:-admin@<TRUENAS_IP>}"
DST_HOST="${DST_HOST:-<USER>@<DR_HOST_IP>}"
SRC_DS="${1:?source dataset required}"
DST_DS="${2:?dr dataset required}"
SNAP="${3:-auto-$(date +%Y-%m-%d_%H%M)}"

# Inputs end up inside a root "sh -c" on the source host — reject anything
# beyond dataset/snapshot/ssh-target charsets before interpolating.
case "${SRC_DS}${DST_DS}${SNAP}" in (*[!A-Za-z0-9/_.:@-]*)
  echo "ERROR: invalid character in dataset/snapshot name" >&2; exit 1;;
esac
case "$DST_HOST" in (*[!A-Za-z0-9_.@-]*)
  echo "ERROR: invalid character in DST_HOST" >&2; exit 1;;
esac

run_src() { ssh -o BatchMode=yes "$SRC" "export PATH=\$PATH:/sbin:/usr/sbin; $*"; }

echo "[1/4] snapshot ${SRC_DS}@${SNAP}"
run_src "sudo -n zfs snapshot -r '${SRC_DS}@${SNAP}'"

echo "[2/4] find newest common snapshot"
common=$(comm -12 \
  <(run_src "zfs list -t snapshot -H -o name -d 1 '$SRC_DS'" | sed 's/.*@//' | sort) \
  <(ssh -o BatchMode=yes "$DST_HOST" "export PATH=\$PATH:/sbin:/usr/sbin; zfs list -t snapshot -H -o name -d 1 '$DST_DS' 2>/dev/null" | sed 's/.*@//' | sort) \
  | tail -1)

if [ -z "$common" ]; then
  echo "ERROR: no common snapshot — full send required. Aborting (confirm manually)." >&2
  exit 1
fi
echo "      incremental base: @$common"

echo "[3/4] send -R -I @$common → ${DST_DS} (this may take a while)"
# send runs ON truenas as root, piping to DR over root's ssh key
run_src "sudo -n sh -c \"zfs send -R -I '@${common}' '${SRC_DS}@${SNAP}' | ssh ${DST_HOST} 'sudo -n zfs recv -F ${DST_DS}'\""

echo "[4/4] verify"
if ssh -o BatchMode=yes "$DST_HOST" "export PATH=\$PATH:/sbin:/usr/sbin; zfs list -t snapshot -o name,creation -d 1 '$DST_DS' | grep -F '$SNAP'"; then
  echo "OK: ${DST_DS}@${SNAP} on DR"
else
  echo "FAIL: snapshot not found on DR" >&2
  exit 1
fi
