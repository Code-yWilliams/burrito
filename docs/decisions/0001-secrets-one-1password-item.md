# 0001 — Secrets: one 1Password vault item feeds local dev and CI

Status: adopted, August 2026.

## Decision

All secrets live as fields on a single 1Password item: vault `Burrito`,
item `burrito-ci`. Field labels are exactly the environment variable names
they become (`AWS_ACCESS_KEY_ID`, `TF_VAR_tenancy_ocid`, `OCIR_TOKEN`,
`POSTGRES_PASSWORD`, `CF_ACCESS_CLIENT_ID`, `CI_SSH_PRIVATE_KEY`, …).

- **Local dev**: direnv's `.envrc` runs `op inject -i .env.tpl -o
  .env.resolved` on every `cd` into the repo; `.env.tpl` (tracked, no
  secrets) maps env var names to `op://Burrito/burrito-ci/<field>`
  references. `op` authenticates through the unlocked 1Password desktop app
  (Settings → Developer → "Integrate with 1Password CLI"). No tfvars file,
  no local secret files.
- **CI (GitHub Actions)**: each job starts with `1password/load-secrets-action@v2`
  reading the same `op://Burrito/burrito-ci/<field>` references,
  authenticated by a 1Password Service Account scoped read-only to the
  `Burrito` vault. `OP_SERVICE_ACCOUNT_TOKEN` is the **only** GitHub
  Actions secret in the repository; every other former GitHub secret was
  deleted in August 2026.
- The one local-only exception that existed (`TF_VAR_oci_private_key_path`
  pointing at a local PEM file) was eliminated: both local and CI use the
  PEM *contents* from the vault field `TF_VAR_oci_private_key`.

## Why one item with many fields, not many items

A single item means one `op://` path prefix everywhere, one thing to grant
the Service Account, one screen to audit. Field granularity is enough; the
grouping is arbitrary and can be split later by updating the `op://` paths
in `.env.tpl` and `.github/workflows/deploy.yml` together.

## Rejected: 1Password "Environments" (the .env pipe mount)

The project originally used a 1Password **Environment** ("Burrito Prod")
that mounts a live named pipe (FIFO) at `.env`. Rejected for CI because in
August 2026 there was **no headless read path for Environments**:

- 1Password CLI 2.39.0 has **no `op environment` command** (docs found
  online describing `op environment read` referred to a beta that did not
  ship in the stable CLI).
- Service Accounts are scoped to **vaults**; secret references
  (`op://vault/item/field`) address vault items, not Environments.
- "Brokered access" / Credential Broker (OIDC, `OP_INTEGRATION_KEY`) can
  connect Environments to CI but is a public-preview feature gated to
  1Password **Business** accounts; this account is not Business.

Lesson: verify CLI capabilities against `op <command> --help` of the
installed binary, not against scraped docs — the docs described commands
that do not exist.

## Gotchas discovered empirically

- **`terraform.tfvars` silently overrides `TF_VAR_*` env vars.** Terraform's
  precedence puts tfvars files above environment variables. The env-based
  flow only works after deleting `terraform/terraform.tfvars`. There is no
  way for a tfvars file to reference environment variables (HCL in tfvars
  accepts only static literals).
- **direnv's `dotenv` cannot parse multi-line values.** The OCI API key PEM
  (field `TF_VAR_oci_private_key`) breaks `dotenv` even when quoted, with
  `direnv: error invalid line`. Fix: `.envrc` reads that one field via
  `op read op://Burrito/burrito-ci/TF_VAR_oci_private_key` and exports it
  directly, bypassing the dotenv parser. All single-line fields go through
  `.env.tpl`/`op inject` with values **quoted** in the template (unquoted
  values with spaces, like SSH public keys, also fail dotenv parsing).
- **Secret values contain shell metacharacters** (`;`, `#`, spaces).
  Never `source`/`eval` raw secret material; parse `KEY=VALUE` literally or
  use quoted `op inject` templates.
- **A 1Password Service Account token is shown exactly once** at creation
  (`op service-account create <name> --vault Burrito:read_items --raw`).
  Save it to a 1Password item **in the same command pipeline** before
  handing it to `gh secret set`; GitHub secrets are write-only and the
  token is otherwise unrecoverable (this mistake was made once — the
  first service account had to be abandoned and revoked).
- **A service token's `id` (resource UUID) and `client_id`
  (`<hex>.access`) are different values** returned by different fields;
  which one an API wants varies by context (see decision 0003).
- The 1Password desktop-app CLI integration intermittently reports
  `account is not signed in` with zero server requests in `op --debug`;
  it resolved without a definitive fix in August 2026. Traditional
  `op account add` sign-in is blocked while app integration is enabled —
  the toggle must be turned off first to use it.
