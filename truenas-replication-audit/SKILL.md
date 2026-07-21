---
name: truenas-replication-audit
description: Verify TrueNAS→DR ZFS replication is current, and run incremental syncs. Use before any risky storage operation ("is my DR current?", "replicate to DR", "audit backups"), or when a snapshot is older than a week.
---

# Replication Audit & Sync (BigDisk / FastPool → DR_pool)

## Topology
- Source: admin@<TRUENAS_IP> (sudo, root has SSH key to DR)
- Target: <USER>@<DR_HOST_IP>, datasets under `DR_pool/truenas_backup/<name>`
- Transport: incremental `zfs send -R -I` piped over SSH to `zfs recv` on the DR host.
- Middleware handles the daily schedule (4 replication tasks at 03:00 + snapshot tasks, 14-day retention, naming `auto-%Y-%m-%d_%H-%M`). The audit here is for ad-hoc verification before risky work.

## Audit
Compare the newest common snapshot between source and DR for each tracked dataset and print the lag in days. Lag > 7 days = stale. Per-dataset classes matter: apps and ix-apps are daily; big media datasets are monthly (lag up to ~31 days is normal).

## Sync (incremental)
1. Take `zfs snapshot -r <ds>@auto-<date>` on the source.
2. Find the newest snapshot name present on BOTH sides.
3. Send `-R -I` incremental from that base; receive with `-F` on DR.
4. Verify the new snapshot exists on DR before declaring success.

## Rules
- NEVER use `zfs recv -F` toward the SOURCE; only toward DR.
- If no common snapshot exists, a full send is required — confirm with Marc first (could be terabytes).
- ix-apps replication: stop apps first if a crash-consistent copy is required; databases (postgres) may need app stop for clean state.
