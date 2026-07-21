---
name: truenas-health
description: One-shot health check of Marc's 3-host ZFS fleet — TrueNAS (<TRUENAS_IP>), optiplex7040 (<DR_HOST_IP>), optiplex990 (<SECONDARY_IP>). Use when asked "how are my servers", "pool health", "is everything ok", or before/after any risky storage operation.
---

# TrueNAS Fleet Health Check

## Fleet facts
| Host | SSH | Pools | Role |
|---|---|---|---|
| truenas (25.04.x) | admin@<TRUENAS_IP> (passwordless sudo) | BigDisk (116T raw: 8× MG08 16T raidz2 on LSI SAS3008 + hot spare on chipset), FastPool (928G NVMe stripe, apps), boot-pool | Main |
| optiplex7040 | <USER>@<DR_HOST_IP> (passwordless sudo) | DR_pool (87T, 5× MG08 on ASM1166) | DR target |
| optiplex990 | <USER>@<SECONDARY_IP> (2.5G nic25g) | 2× Marvell 88SE9215 cards, test disks | Backup/test |

Note: `zpool`/`zfs` are in `/sbin` — non-login SSH shells need `export PATH=$PATH:/sbin:/usr/sbin`.

## Procedure
Run `scripts/health-check.sh` (works from any machine with SSH keys to the fleet).
It reports, per host: pool status (`zpool status -x`), capacity (warn >80%),
errors, last scrub, latest snapshot per key dataset, and on TrueNAS also
`docker system df` and stopped-apps count.

Interpret:
- `all pools are healthy` — good; anything else, show full `zpool status` of the sick pool.
- FastPool is a SINGLE STRIPE — any FastPool error is urgent; check its DR replication immediately.
- Snapshot older than 7 days on ix-apps/applications → recommend running the replication (see truenas-replication-audit skill).
