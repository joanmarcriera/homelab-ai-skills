---
name: truenas-disk-replacement
description: Guided procedure for replacing failed/failing disks on TrueNAS and planning the bigger balanced pool rebuild. Use for "replace disk", "resilver", "degraded pool", "rebuild pool", "add vdev", "which spare disk".
---

# Disk Replacement & Pool Rebuild

## Fleet disk state (example — keep yours current, it's the point of the skill)
BigDisk = raidz2, 8× Toshiba MG08 16T on an LSI SAS3008 HBA + hot spare on the
chipset SATA. With a hot spare present, ZFS auto-resilvers on member failure —
your job is to replace the failed unit and re-add a new spare.
A ranked inventory of burn-in-tested spares lives in a CSV keyed by serial +
WWN; match physical disks by the firmware serial printed on the label.
Retired disks are kept as a restore point until trust in the new pool is total.
One rule learned the hard way: an SMR disk is never pooled, however healthy.

## 1. Identify the failed disk
- `zpool status -v BigDisk` — vdev member + READ/WRITE/CKSUM counters.
- `smartctl -a /dev/sdX` — serial, reallocated/pending sectors, test result.
- `lsblk -o NAME,SIZE,SERIAL,MODEL` — device → serial for the physical pull.
- `midclt call disk.query '[["name","=","sdX"]]'` — middleware's view.

## 2. Replace (keep redundancy at all times)
- Pick a spare from the ranked CSV (prefer lowest power-on hours).
- `zpool offline` the member, swap the physical disk (match the label serial!),
  then replace via UI: Storage → Manage Devices → Replace.
- Watch the resilver; do NOT reboot mid-resilver.
- raidz1 during resilver has ZERO redundancy — verify DR replication is green
  FIRST (truenas-replication-audit skill).
- Scrub after resilver, then capture a fresh disk inventory snapshot.

## 3. Balanced pool rebuild (the real fix when the layout is wrong)
- A pool cannot remove raidz vdevs: rebuild = new pool + restore from DR.
- Sequence: final replication → destroy → build new raidz2 from tested,
  burnt-in spares → restore with `zfs send -R` from the DR host.
- Budget honestly: 18T over 1GbE ≈ 2+ days; the disk shelf can feed far more
  than the network — consider a direct link between the hosts.

## Safety rules
- One disk operation at a time; re-check `zpool status` between steps.
- A single-stripe pool has NO redundancy — its failure plan is
  restore-from-DR, so its nightly replication must stay green.
