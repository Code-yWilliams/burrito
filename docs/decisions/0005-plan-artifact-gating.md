# 0005 — CI applies the exact reviewed plan artifact; merge-timing rule

Status: adopted at project start (August 2026); operational rules hardened
after real failures.

## Design

`.github/workflows/deploy.yml` runs `terraform plan -out=tfplan` on every
PR commit and uploads the plan file as an artifact named
`tfplan-<PR head SHA>`. After merge, the `deploy` job (gated by the
`production` GitHub environment — a human must approve it in the Actions
UI) downloads **that exact artifact** and runs `terraform apply tfplan`.
What gets applied is provably what was reviewed; deploy never re-plans.

## Operational rule learned the hard way: wait for the plan check

**Merging a PR before its `plan` job has fully completed breaks the
subsequent deploy.** Observed failure (August 2026, twice): merging while
`plan` was still running (or after an "Update branch" click added a new
head commit whose plan run was auto-cancelled) meant no artifact existed
for the merged head SHA. The deploy job then fails with its own error:
`No plan artifact found for PR head <sha> (name tfplan-<sha>)`. Recovery:
open a fresh PR (any trivial change), let its `plan` check reach
**completed/success**, then merge. Nothing is left broken in the meantime
— the failed deploy applied nothing.

Related trap: clicking GitHub's "Update branch" button creates a new head
commit and restarts `plan` from zero; the concurrency group
(`group: production, cancel-in-progress: false`) also serializes runs, so
a queued plan can look stuck when it is just waiting.

## Rollout discipline for risky infra changes

The Cloudflare Tunnel migration (August 2026) used a strict order that is
the template for future cutover work:

1. **Additive PR**: create the new path (tunnel, Access policy, keys)
   while leaving the old path (public 6443, `KUBECONFIG_B64`) fully
   working as a fallback.
2. **Verify the new path manually** end-to-end before CI depends on it.
3. **Cutover PR**: switch the deploy job to the new path; the old path's
   infrastructure still exists.
4. **Removal PR**: only after a real production deploy succeeds on the new
   path, delete the old path (NSG rule, dead secrets). The removal PR's
   own deploy doubles as proof the new path doesn't depend on the old one.

## Health-check verification needs retries

The deploy job's final `curl /healthz` originally ran once with `-f`; it
failed a real deploy on a transient 503 during pod rollover, seconds
before the app recovered on its own (`helm --wait` gates on pod readiness,
which does not cover the app→DB path settling). The check now retries for
up to 60 seconds. Single-shot post-deploy health checks are a known
footgun in this repo.
