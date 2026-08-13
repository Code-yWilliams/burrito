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

## Day-to-day

- Change infra or app → PR (plan diff, no apply) → merge → approve the
  `production` deployment in the Actions UI → applied + deployed.
- Local kubectl: `scripts/fetch-kubeconfig.sh <node-ip>` then
  `KUBECONFIG=kubeconfig kubectl get nodes`.
- Local terraform: copy `terraform/terraform.tfvars.example` to
  `terraform.tfvars`, export the state-bucket keys
  (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` = OCI customer secret key).

## GitHub Actions secrets

| Secret | What it is |
| --- | --- |
| `OCI_TENANCY_OCID`, `OCI_USER_OCID`, `OCI_FINGERPRINT`, `OCI_PRIVATE_KEY` | OCI API-key auth for terraform |
| `OCI_S3_ACCESS_KEY`, `OCI_S3_SECRET_KEY` | Customer secret key for the state bucket (S3-compatible) |
| `OCIR_USERNAME`, `OCIR_TOKEN` | `<namespace>/<user>` + auth token for OCIR docker login |
| `KUBECONFIG_B64` | base64 kubeconfig pointing at the node's public IP |
| `POSTGRES_PASSWORD` | Injected into the chart at deploy time |
| `MY_IP_CIDR`, `SSH_PUBLIC_KEY` | terraform vars (SSH allowlist, node key) |

## Known MVP tradeoffs

- CI authenticates with the tenancy admin's API key; a least-privilege
  `burrito-ci` IAM user/policy is the natural next step.
- k8s API (6443) is exposed publicly (TLS + client-cert auth) so GitHub
  runners can deploy; alternatives are SSH-tunnel deploys or a self-hosted
  runner.
- Plain HTTP, no domain/TLS on the app ingress.
- Postgres data lives on the node's boot volume (single node, no offsite
  backups). If the node is recreated, k3s regenerates its CA — refetch the
  kubeconfig and update `KUBECONFIG_B64`.
- Forked-PR workflows don't get secrets, so `terraform plan` only works on
  branches in this repo.
