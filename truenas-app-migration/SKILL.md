---
name: truenas-app-migration
description: Move TrueNAS 25.04 Docker apps data between pools — ix-apps pool migration, relocating an ix_volume to a host_path, or moving host-path datasets. Use for "move apps to another pool", "relocate app data", "migrate ix-apps".
---

# TrueNAS App/Dataset Migration Between Pools

## System facts (verify on your system before trusting them)
- TrueNAS 25.04.x, apps = Docker. Apps dataset `<pool>/ix-apps` is mounted at
  `/mnt/.ix-apps` (NOT /mnt/<pool> — this surprises everyone once).
- Structure: `ix-apps/{app_configs, app_mounts/<app>/<volume>, docker, truenas_catalog}`.
- Pools import with `altroot=/mnt`: set mountpoints WITHOUT the /mnt prefix.
- Middleware CLI: `midclt call <method>`; long-running jobs need `midclt call -j`.

## A. Relocate one app volume (ix_volume → host_path) — instant, same pool
1. Stop the app.
2. Rename the volume dataset to its destination (same pool only; cross-pool
   needs a send/receive copy).
3. Fix the mountpoint (it was inherited from ix-apps; altroot adds /mnt).
4. Repoint the app's storage to the new host path via `app.update`.
5. Start the app, verify the data is visible inside the container.

## B. Migrate the whole ix-apps to another pool
1. Pre-flight: DR replication current; destination has space; prune docker
   images first (74% was reclaimable last time — measure, don't assume).
2. The safe path on 25.04 is the UI: Apps → Settings → Choose Pool, which
   offers to migrate data when changing pools.
3. Manual path: recursive snapshot, local send/receive copy, repoint docker
   at the new pool, verify every app starts. Keep the source dataset until
   everything is confirmed, then remove it.
4. After: replicate the new location to DR — especially if it's a
   single-stripe NVMe pool.

## C. Move a host-path dataset cross-pool
Snapshot → send/receive → fix mountpoint → update every app referencing the
old path (grep the app configs via `app.query`) → test → remove the source.

## Gotchas learned the hard way
- `zfs list` shows ix-apps children under /mnt/.ix-apps; do not assume /mnt/<pool>.
- App postgres datasets: stop the app before snapshotting if you need
  guaranteed-clean DB state.
- After a UI pool change, the old ix-apps stays on the source pool; clean it
  up manually once stable.
