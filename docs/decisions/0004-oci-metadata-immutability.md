# 0004 — OCI instance metadata is immutable; the bootstrap-script pattern

Status: adopted August 2026.

## The constraint

On OCI, an instance's `metadata` (which carries both `user_data` /
cloud-init and `ssh_authorized_keys`) **cannot be updated after creation**.
Any change to `metadata` in the `oci_core_instance` resource makes
Terraform plan a **destroy-and-recreate** of the node. Because Postgres
data lives on that node's boot volume with no offsite backups, an
accidental metadata-triggered replacement would destroy the database.

## Decision

`terraform/compute.tf` sets
`lifecycle { ignore_changes = [source_details, metadata] }` on
`oci_core_instance.k3s`. Consequences every future change must respect:

- Edits to `terraform/cloud-init.yaml.tpl` or to the trusted SSH keys take
  effect **only on a freshly created node**. Terraform will show "No
  changes" for the live node — that is intentional, not a bug.
- To apply such a change to the **live** node, run the same repo-tracked
  script manually over SSH. The pattern: the logic lives in one executable
  script (`scripts/bootstrap-cloudflared.sh`), cloud-init embeds that exact
  file via `write_files` + Terraform `filebase64()` and runs it on first
  boot, and a human applies the identical file to a running node with
  `scp` + one `sudo bash` invocation. Never retype the steps ad hoc —
  the script is the single source of truth, so a fresh node and a
  hand-updated node are guaranteed to converge.

## History

The cloudflared install was first written inline in cloud-init `runcmd`
and applied to the live node by typing the same commands over SSH; this
was rejected ("everything must be codified so a lost node can be
recreated") and refactored into the bootstrap-script pattern above in
August 2026.
