# burrito

Bare-minimum production cloud on OCI's Always Free tier: a single-node
[k3s](https://k3s.io) cluster running a Node.js backend (one `GET /healthz`
endpoint) and Postgres.

## Architecture

- **Infra (terraform/)** — OCI compartment, VCN + public subnet + NSG,
  a `VM.Standard.A1.Flex` (4 OCPU / 24 GB, Always Free) Ubuntu 24.04 arm64
  instance with a reserved public IP. cloud-init installs k3s on first boot.
  State lives in an OCI Object Storage bucket (`burrito-tfstate`, versioned)
  via the S3-compatible backend.
- **App (app/)** — dependency-free Node HTTP server + `pg`. `GET /healthz`
  runs `SELECT 1` against Postgres: `200 {status: ok, db: ok}` when healthy,
  `503` when the DB is unreachable. Docker image is arm64, pushed to OCIR
  (`sjc.ocir.io/ax9hmp43wxua/burrito/app`).
- **Chart (helm/burrito/)** — app Deployment/Service/Ingress (k3s Traefik,
  plain HTTP on the node IP) and a Postgres 16 StatefulSet with an 8 Gi PVC
  on k3s's local-path provisioner.
- **CI/CD (.github/workflows/deploy.yml)** — on every PR and push to main:
  `terraform plan`, diff in the job summary. On pushes, an image build to
  OCIR runs too, then the run **pauses on the `production` environment**;
  approving it in the GitHub UI applies the reviewed plan file and runs
  `helm upgrade --install`, then curls `/healthz`.

### Why AWS_* variables in an OCI project?

Terraform has no native OCI state backend, so state uses the `s3` backend
pointed at OCI Object Storage's S3-compatible endpoint instead. That backend
is written for real AWS and only knows how to authenticate the AWS way, so:

- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` aren't AWS credentials at
  all — they're an OCI "customer secret key" pair (generated in the OCI
  console for exactly this S3-compatibility use case), just handed to the
  backend under the names it expects.
- `AWS_REQUEST_CHECKSUM_CALCULATION` / `AWS_RESPONSE_CHECKSUM_VALIDATION`
  (set to `when_required` in `.envrc` and in `deploy.yml`'s workflow-level
  `env:`) exist because the AWS SDK's newer default is to *always*
  calculate/validate a checksum on every S3 request, using a chunked-transfer
  encoding OCI's S3-compatibility layer doesn't implement — requests fail
  with "AWS chunked encoding not supported". `when_required` reverts to the
  older behavior of only doing checksum work when the specific API call
  actually requires it, which is the subset OCI's implementation tolerates.
  The backend block in `terraform/versions.tf` disables a further batch of
  AWS-specific validation (region/credentials/account-ID checks, the
  metadata API probe) that doesn't apply to a non-AWS endpoint at all.

## Getting started

Requires access to the `Burrito` 1Password vault — ask the repo owner to
invite your account (needs at least a Families or Teams plan; vault sharing
isn't available on an Individual plan). Then, one time per machine:

1. Install and sign in to the 1Password desktop app, then in
   Settings → Developer, enable **Integrate with 1Password CLI**.
2. `brew install direnv` and `brew install --cask 1password-cli`.
3. Hook direnv into your shell: add `eval "$(direnv hook zsh)"` (or the
   bash equivalent) to your shell rc file.
4. Clone the repo, `cd` in, and run `direnv allow` once.

From there, `.envrc` resolves every value automatically on every `cd` into
the repo — no tfvars file, no manually-exported env vars, no local secrets.
`terraform` commands work directly from `terraform/`.

Local `kubectl` access is separate: `scripts/fetch-kubeconfig.sh <node-ip>`
SSHes into the node with `~/.ssh/burrito_k3s`, but the node currently only
trusts a single public key (`TF_VAR_ssh_public_key` in the vault). A second
person needing kubectl access would need either their own key added to the
instance (a terraform change — not set up yet) or the private key shared
directly (not recommended).

## Day-to-day

- Change infra or app → PR (plan diff, no apply) → merge → approve the
  `production` deployment in the Actions UI → applied + deployed.
- Local kubectl: `scripts/fetch-kubeconfig.sh <node-ip>` then
  `KUBECONFIG=kubeconfig kubectl get nodes`.
- Local terraform: `direnv` handles everything (see Getting started above)
  — just run `terraform` normally from `terraform/`.

## GitHub Actions secrets

`OP_SERVICE_ACCOUNT_TOKEN` is the only GitHub secret this repo needs — a
1Password Service Account token, scoped read-only to the `Burrito` vault.
Every other value (OCI/AWS/OCIR/Postgres creds, the SSH allowlist IP, the
base64 kubeconfig) lives as a field on the `burrito-ci` item in that vault
and is pulled in per job by the `1password/load-secrets-action` step —
the same vault item local dev reads via `.env.tpl`/direnv.

## Known MVP tradeoffs

- CI authenticates with the tenancy admin's API key; a least-privilege
  `burrito-ci` IAM user/policy is the natural next step.
- k8s API (6443) is exposed publicly (TLS + client-cert auth) so GitHub
  runners can deploy; alternatives are SSH-tunnel deploys or a self-hosted
  runner.
- Plain HTTP, no domain/TLS on the app ingress.
- Postgres data lives on the node's boot volume (single node, no offsite
  backups). If the node is recreated, k3s regenerates its CA — refetch the
  kubeconfig and update the `KUBECONFIG_B64` field on the `burrito-ci` item
  in 1Password.
- Only one SSH public key is trusted on the node (see Getting started) —
  fine for a single operator, but doesn't scale to a second person without
  a terraform change.
- Forked-PR workflows don't get secrets, so `terraform plan` only works on
  branches in this repo.
