# burrito

Bare-minimum production cloud on OCI's Always Free tier: a single-node
[k3s](https://k3s.io) cluster running an Express API (one `GET /healthz`
endpoint) and Postgres, plus a React SPA on Cloudflare Pages that calls it.

Live: <https://burrito.moldysandwich.com> (frontend) →
<https://api-burrito.moldysandwich.com/healthz> (API).

## Architecture

- **Infra (terraform/)** — OCI compartment, VCN + public subnet + NSG,
  a `VM.Standard.A1.Flex` (4 OCPU / 24 GB, Always Free) Ubuntu 24.04 arm64
  instance with a reserved public IP. cloud-init installs k3s on first boot.
  State lives in an OCI Object Storage bucket (`burrito-tfstate`, versioned)
  via the S3-compatible backend. Cloudflare (tunnel, DNS, Pages project,
  custom domain) is terraform-managed too (`cloudflare.tf`, `frontend.tf`).
- **API (app/)** — Express 5 + TypeScript. `GET /healthz`
  runs `SELECT 1` against Postgres: `200 {status: ok, db: ok}` when healthy,
  `503` when the DB is unreachable. CORS is an explicit origin allowlist
  (`ALLOWED_ORIGINS`, set by the chart): the Pages frontend plus local dev.
  Docker image is arm64, pushed to OCIR
  (`sjc.ocir.io/ax9hmp43wxua/burrito/app`).
- **Web (web/)** — Vite + React 19 + TypeScript SPA: a single page that
  fetches the API's `/healthz` and renders the response. Served by
  Cloudflare Pages (direct-upload project `burrito-web`; HTTPS automatic)
  at `burrito.moldysandwich.com`.
- **Chart (helm/burrito/)** — app Deployment/Service/Ingress (k3s Traefik)
  and a Postgres 16 StatefulSet with an 8 Gi PVC on k3s's local-path
  provisioner. Public traffic reaches Traefik as
  `https://api-burrito.moldysandwich.com` through the Cloudflare Tunnel
  (TLS terminates at Cloudflare's edge — no certs on the node).
- **CI/CD (.github/workflows/deploy.yml)** — on every PR and push to main:
  both packages built (`check`) and `terraform plan`, diff in the job
  summary. On merge, a `changes` job classifies the PR's files and
  **only what changed deploys** (`app/`+`helm/` → image build + helm;
  `web/` → Pages upload; `terraform/` → apply only; docs-only merges
  skip deploy entirely). The run **pauses on the `production`
  environment**; approving it applies the reviewed plan file, then
  builds everything before deploying anything, deploys the API first and
  the frontend second (label the PR `web-first` before merging to flip),
  verifying each over HTTPS. `rollback.yml` (manual dispatch,
  `target: api|web`) rolls one package back to its previous version.

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
SSHes into the node with `~/.ssh/burrito_k3s`, but the node only trusts two
keys — the owner's personal key (`TF_VAR_ssh_public_key` in the vault) and
the CI deploy key. A second person needing kubectl access would need their
own key added to the instance (a terraform change — not set up yet) rather
than sharing a private key directly (not recommended).

## Day-to-day

- Change infra or app → PR (plan diff, no apply) → merge → approve the
  `production` deployment in the Actions UI → applied + deployed (only
  the packages the PR touched; add the `web-first` label before merging
  to deploy the frontend before the API).
- Roll back one package: `gh workflow run rollback -f target=api` (or
  `target=web`), or trigger it from the Actions UI. API → previous Helm
  revision; web → previous Pages production deployment.
- Local kubectl: `scripts/fetch-kubeconfig.sh <node-ip>` fetches the node's
  kubeconfig (it points at `https://127.0.0.1:6443` — the k8s API is not
  publicly exposed), then open the SSH port-forward the script prints and
  `KUBECONFIG=kubeconfig kubectl get nodes`.
- Local terraform: `direnv` handles everything (see Getting started above)
  — just run `terraform` normally from `terraform/`.

## GitHub Actions secrets

`OP_SERVICE_ACCOUNT_TOKEN` is the only GitHub secret this repo needs — a
1Password Service Account token, scoped read-only to the `Burrito` vault.
Every other value (OCI/AWS/OCIR/Postgres creds, the SSH allowlist IP, the
Cloudflare Access service token and CI SSH key) lives as a field on the
`burrito-ci` item in that vault and is pulled in per job by the
`1password/load-secrets-action` step — the same vault item local dev reads
via `.env.tpl`/direnv.

The Cloudflare API token is created by hand in the dashboard, so its
required permissions are codified as an executable check:
`scripts/check-cloudflare-token.sh` (run by CI before every plan and
apply) is the canonical scope list — update it when terraform grows a new
Cloudflare resource family.

## Deploy path (no public k8s API)

The k8s API (6443) has no public ingress rule at all. The deploy job
reaches it by SSHing to the node through a **Cloudflare Tunnel**
(`terraform/cloudflare.tf`): the node runs `cloudflared` (installed by
`scripts/bootstrap-cloudflared.sh` via cloud-init) holding an
outbound-only connection to Cloudflare's edge, and a Cloudflare Access
**Service Auth** policy admits only the dedicated CI service token —
nothing else can even open a connection. The runner then port-forwards
6443 and uses the node's own `/etc/rancher/k3s/k3s.yaml`, which is always
current (no stored kubeconfig to go stale when the node is recreated).
Local kubectl uses the same port-forward trick over direct SSH (port 22
is open to `my_ip_cidr` only).

The same tunnel also publishes the app: `api-burrito.moldysandwich.com`
routes to Traefik on `localhost:80`, deliberately with **no** Access
policy (it's the public API), unlike the SSH hostname.

## Known MVP tradeoffs

- CI authenticates with the tenancy admin's API key; a least-privilege
  `burrito-ci` IAM user/policy is the natural next step.
- The node's ports 80/443 are still open to the world (plain HTTP on the
  node IP reaches Traefik directly, bypassing Cloudflare). The advertised
  path is HTTPS via the tunnel, so removing those NSG rules is the natural
  next step once the tunnel path has been verified in production.
- Postgres data lives on the node's boot volume (single node, no offsite
  backups).
- Only one SSH public key is trusted on the node (see Getting started) —
  fine for a single operator, but doesn't scale to a second person without
  a terraform change.
- Forked-PR workflows don't get secrets, so `terraform plan` only works on
  branches in this repo.
