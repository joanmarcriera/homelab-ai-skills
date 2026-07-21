#!/usr/bin/env bash
# health-check.sh — fleet-wide ZFS/app health for Marc's homelab.
# Usage: ./health-check.sh            (all hosts)
#        ./health-check.sh truenas    (single host: truenas|o7040|o990)
set -u

# host alias -> ssh target
declare -A HOSTS=(
  [truenas]="admin@<TRUENAS_IP>"
  [o7040]="<USER>@<DR_HOST_IP>"
  [o990]="<USER>@<SECONDARY_IP>"
)
# datasets whose newest snapshot age we report, per host
declare -A KEY_DS=(
  [truenas]="BigDisk/applications FastPool/ix-apps"
  [o7040]="DR_pool/truenas_backup/applications DR_pool/truenas_backup/ix-apps"
  [o990]=""
)

check_host() {
  local alias="$1"
  if [ -z "${HOSTS[$alias]+x}" ]; then
    echo "ERROR: unknown host '$alias' (valid: ${!HOSTS[*]})" >&2; return 1
  fi
  local target="${HOSTS[$alias]}"
  echo "===================== $alias ($target) ====================="
  # Single SSH round-trip per host; PATH fix for non-login shells.
  ssh -o BatchMode=yes -o ConnectTimeout=8 "$target" '
    export PATH=$PATH:/sbin:/usr/sbin
    echo "--- pools ---"
    zpool status -x
    zpool list -o name,size,alloc,free,cap,frag,health
    echo "--- capacity warnings ---"
    zpool list -H -o name,cap | awk -F"\t" {'"'"'gsub(/%/,"",$2); if ($2+0>80) print "WARN: "$1" at "$2"%"'"'"'}
    echo "--- last scrub ---"
    zpool status | grep -E "scan:|pool:"
    echo "--- key dataset snapshots ---"
    for ds in '"${KEY_DS[$alias]}"'; do
      zfs list -t snapshot -o name,creation -s creation -d 1 "$ds" 2>/dev/null | tail -1
    done
    # TrueNAS-only extras (sudo is passwordless for truenas_admin)
    if [ -e /etc/version ] && command -v docker >/dev/null 2>&1; then
      echo "--- docker ---"
      sudo -n docker system df 2>/dev/null
      echo "--- apps not running ---"
      sudo -n midclt call app.query 2>/dev/null | python3 -c "
import json,sys
apps=json.load(sys.stdin)
bad=[a[\"name\"] for a in apps if a[\"state\"]!=\"RUNNING\"]
print(len(bad),\"stopped/crashed:\",\", \".join(bad) if bad else \"-\")"
    fi
  ' 2>&1 | grep -v "Pseudo-terminal"
  # PIPESTATUS[0] = the ssh exit code (grep masks it)
  [ "${PIPESTATUS[0]}" -eq 0 ] || echo "WARN: $alias unreachable or remote commands failed"
  echo
}

if [ $# -ge 1 ]; then
  check_host "$1"
else
  for h in truenas o7040 o990; do check_host "$h"; done
fi
