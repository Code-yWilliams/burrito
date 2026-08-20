# 0008 — Selective deploys, deploy ordering, and per-package rollback

Status: adopted August 2026, after the first full-stack deploys revealed
that every merge deployed both packages unconditionally, and that the
frontend was built *after* the API had already deployed (a broken
frontend build stranded a half-shipped release).

## Change detection: the `changes` job

The `changes` job in `.github/workflows/deploy.yml` runs for merged PRs
and classifies the PR's changed files by fetching them from the GitHub
API (`gh api repos/<repo>/pulls/<number>/files --paginate`) — no
checkout, no git plumbing, and it is exactly the merged PR's file list.
The path map:

- `app/*` or `helm/*` → `api=true` (image build + helm deploy)
- `web/*` → `web=true` (frontend build + Pages upload)
- `terraform/*` or `scripts/*` → `infra=true` (terraform apply only)
- `.github/*` → all three true (pipeline changes could affect anything)
- anything else (docs, README) → nothing

If all three outputs are false the `deploy` job is skipped entirely, so
a docs-only merge no longer pauses on the `production` environment
waiting for a pointless approval.

`helm/*` deliberately maps to `api`, not `infra`: the Helm deploy sets
`image.tag` to the merge commit SHA, so any run that deploys the chart
must also have built an image with that tag. Mapping helm-only changes
to `api` preserves the invariant at the cost of an occasional
redundant image build. The alternative — reusing the previously
deployed tag via `helm get values` — was rejected as more moving parts
for a rare case.

Terraform apply runs unconditionally inside the deploy job (whenever the
deploy job runs at all): applying the reviewed plan is a fast no-op when
nothing changed, and skipping it would silently drop drift corrections
the plan may have captured (decision 0005 applies the exact reviewed
plan artifact).

## Everything builds before anything deploys

Failure observed August 2026 (motivating incident): the deploy job
deployed the API via Helm, *then* built the frontend — so a frontend
build failure left the new API live with no matching frontend and no
signal until after the fact. The deploy job now has an explicit build
phase (frontend `npm ci && npm run build`) before the deploy phase; the
API image was already built in the separate `build` job. A compile error
in either package therefore fails the run before production has changed
at all.

## Deploy order: API first by default, `web-first` label to flip

Default order is API then frontend, because the already-deployed old
frontend must keep working against the new API anyway (backward
compatibility is required in that direction regardless of ordering).
The inverse case — a frontend that must land before its API change —
is requested per-PR by adding the **`web-first`** GitHub label to the PR
**before merging**: the deploy job reads
`github.event.pull_request.labels.*.name` from the `closed` event
payload, so a label added after merge has no effect on that run.

The mechanism is two invocations of the local composite action
`.github/actions/deploy-web` (one before the API steps, one after) with
mutually exclusive `if:` conditions on the label. A composite action is
used because GitHub Actions steps cannot be reordered at runtime;
job-level `needs:` ordering is equally static.

## Rollback: the `rollback` workflow

`.github/workflows/rollback.yml` is a `workflow_dispatch` workflow with
one input, `target` (`api` or `web`):

- **api** — `helm rollback burrito -n burrito --wait` (no revision
  argument = previous revision). Release values roll back too,
  including `image.tag`, and old images remain in OCIR, so the previous
  code actually runs. Reaches the cluster through the same
  `.github/actions/tunnel-kubectl` composite action the deploy job uses.
- **web** — Cloudflare Pages keeps every deployment; rollback re-points
  production at the newest production deployment that is not the
  currently-live one (`canonical_deployment.id`), via
  `POST /accounts/{account}/pages/projects/burrito-web/deployments/{id}/rollback`,
  then verifies `canonical_deployment` now matches.

The half-shipped-release playbook: if the API deployed and the frontend
deploy then failed (or vice versa with `web-first`), either fix forward
with a new PR, or dispatch `rollback` against the package that *did*
deploy: `gh workflow run rollback -f target=api` (or `target=web`).

The rollback workflow shares the `production` concurrency group with
`plan-and-deploy` (concurrency groups are repository-wide, spanning
workflows), so a rollback can never race a deploy. It deliberately has
**no** `production` environment approval gate: dispatching it is already
an explicit human action, rollbacks are when approval friction hurts
most, and the 1Password secrets are repository-level (not
environment-scoped), so the gate would add no access control.

Helm deploys also gained `--atomic`: a rollout that never becomes ready
now rolls itself back instead of leaving a broken release as the
"previous revision" a later manual rollback would land on.

## Gotchas

- **Skipped-`needs` semantics.** A job whose `needs:` includes a skipped
  job is itself skipped unless its `if:` uses `always()` or
  `!cancelled()`. The `deploy` job needs `build`, which is skipped for
  web-/infra-only PRs, so its condition starts with `!cancelled()` and
  checks `needs.build.result == 'success' || needs.build.result ==
  'skipped'` explicitly. Removing the `!cancelled()` silently disables
  web-only deploys — nothing errors, the job just never runs.
- **`helm history` shows superseded AND failed revisions.** `helm
  rollback` with no revision goes to the previous revision regardless of
  its status. With `--atomic` on deploys, failed revisions are
  rolled back immediately, so "previous" is a revision that was actually
  live; without `--atomic` that assumption breaks.
- **The `web-first` label is read at merge time.** Labels are taken from
  the `pull_request` `closed` event payload. Adding the label after
  merging does nothing for that deploy.
- **Composite actions require checkout.** Both workflows check out the
  repo before `uses: ./.github/actions/...` — local actions resolve
  from the workspace, so the rollback workflow's checkout step exists
  solely for that.
