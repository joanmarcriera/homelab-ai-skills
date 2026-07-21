# homelab-ai-skills

Runbooks my AI assistant executes against my homelab — published as working
examples of the runbooks-as-skills pattern.

A skill is a small folder: a SKILL.md with the procedure, the safety rules and
the interpretation guide, plus any helper scripts. The assistant loads it when
a job matches ("replace disk", "is my DR current?") and follows it, instead of
improvising against your storage at 11pm.

Why this beats a wiki:

- A wiki runbook is exercised when something breaks — exactly when you find
  out it's wrong. An agent-run skill is exercised constantly, so rot surfaces
  as a failed step within days, not during an outage.
- Safety rules become enforceable ("verify DR replication is green FIRST",
  "never receive with force toward the source"), not advisory.
- The skill records the gotchas the vendor docs don't ("ix-apps mounts at
  /mnt/.ix-apps, not /mnt/<pool>").

## Skills in this repo

| Skill | Job |
|---|---|
| `truenas-health` | One-shot fleet health: pools, capacity, scrubs, snapshot ages, stopped apps |
| `truenas-replication-audit` | Is the DR copy current? Per-dataset lag report + incremental sync procedure |
| `truenas-disk-replacement` | Failed-disk identification, replacement with redundancy intact, pool rebuild planning |
| `truenas-app-migration` | Moving TrueNAS 25.04 Docker app data between pools without losing anything |

## Adapting them

Placeholders like `<TRUENAS_IP>`, `<DR_HOST_IP>` and `<USER>` mark the values
I stripped; pool names (BigDisk, FastPool, DR_pool) are mine — rename to
yours. The "fleet facts" sections are the load-bearing part: keeping them
current is what makes an agent's answers trustworthy. When a fact changes,
the skill changes in the same commit.

These pair with the research and ops tooling on my other repos —
see github.com/joanmarcriera and blog.riera.co.uk.

## License

MIT
