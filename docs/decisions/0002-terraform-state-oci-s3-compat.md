# 0002 — Terraform state on OCI Object Storage via the AWS S3 backend

Status: adopted at project start (August 2026); still current.

## Decision

Terraform has no native OCI state backend, so state lives in a versioned
OCI Object Storage bucket (`burrito-tfstate`, created once out-of-band via
the OCI CLI to avoid a chicken-and-egg) accessed through OCI's
S3-compatible endpoint using Terraform's `s3` backend
(`terraform/versions.tf`).

## The AWS_* variables are not AWS credentials

- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` carry an OCI **"customer
  secret key"** pair (generated in the OCI console specifically for
  S3-compatibility use), handed to the backend under the names the AWS SDK
  expects. There is no AWS account involved anywhere in this project.
- `AWS_REQUEST_CHECKSUM_CALCULATION=when_required` and
  `AWS_RESPONSE_CHECKSUM_VALIDATION=when_required` are **mandatory**: the
  AWS SDK's newer default computes a checksum on every S3 request using a
  chunked transfer encoding that OCI's S3-compatibility layer does not
  implement; without these variables requests fail with
  `AWS chunked encoding not supported`. They are set in `.envrc` (local)
  and at workflow level in `.github/workflows/deploy.yml` (CI).
- The backend block sets `skip_region_validation`,
  `skip_credentials_validation`, `skip_requesting_account_id`,
  `skip_metadata_api_check`, `skip_s3_checksum`, and `use_path_style` —
  all disabling AWS-specific checks that are meaningless against a
  non-AWS endpoint.

## Retrieval hint

If terraform init/plan fails against the state bucket with checksum or
chunked-encoding errors, the first suspects are the two
`AWS_*_CHECKSUM_*` environment variables missing from whatever context is
running terraform.
