# 0006 — Platform constraints: OCI free tier, single node, SSH trust

Status: facts as of August 2026. Re-verify the free-tier numbers before
capacity planning — Oracle has changed them without announcement before.

## OCI Always Free tier was cut in half in June 2026

Oracle reduced the Always Free Ampere A1 allowance from 4 OCPU / 24 GB to
**2 OCPU / 12 GB** effective June 15, 2026, with no public announcement
(existing over-limit instances faced shutdown after August 18, 2026).
Technically the allowance is monthly hours: 1,500 OCPU-hours and 9,000
GB-hours. The current node (`burrito-k3s`) uses 1 OCPU / 6 GB —
deliberately half the allowance, sized down in anticipation.

Consequence for the planned second node (staging / PR-preview apps): a
second 1 OCPU / 6 GB instance consumes **100% of the free tier with zero
headroom**. Any burst beyond that risks charges or auto-shutdown. Comments
in `terraform/variables.tf` (`node_ocpus`, `node_memory_gb`) carry the
current numbers.

Also relevant: A1 capacity shortages are real — the node was shrunk to
1 OCPU / 6 GB partly "to dodge A1 capacity shortage" (see git history).
Recreating or adding instances can fail with out-of-capacity errors.

## Single node, data on the boot volume

Postgres data lives on the node's boot volume via k3s's local-path
provisioner. No offsite backups. Losing or recreating the node loses the
database. This is the standing reason to be paranoid about anything that
could trigger node replacement (see decision 0004 on metadata
immutability) and the top candidate for the next reliability investment.

## SSH trust model

The node trusts exactly two SSH public keys, both set at instance creation
(and therefore only updatable on a fresh node, or manually on the live
one — decision 0004):

1. The owner's personal key (`TF_VAR_ssh_public_key` in the vault;
   private half at `~/.ssh/burrito_k3s` on the owner's machine). Humans
   SSH directly to the public IP; port 22 is NSG-restricted to
   `TF_VAR_my_ip_cidr`.
2. The dedicated CI key (`ci_ssh_public_key` variable, default in
   `terraform/variables.tf`; private half in the vault as
   `CI_SSH_PRIVATE_KEY`). CI reaches SSH only through the Cloudflare
   Tunnel (decision 0003) — the tunnel connection is outbound from the
   node, so CI traffic never touches port 22's public listener.

A second human operator is not supported without a Terraform change to add
their key (and, on the live node, a manual authorized_keys append).

## Repository is public

The GitHub repo is public. Two standing consequences: forked-PR workflow
runs get no secrets (so `terraform plan` only works on branches in this
repo), and self-hosted runners are off the table (any PR's workflow code
could execute on the runner — see decision 0003's rejected alternatives).
