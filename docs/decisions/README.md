# Decision records

Decision records for the burrito project, written primarily **for AI
consumption**: they capture the *why* behind choices, the alternatives that
were rejected and the exact reasons, and the gotchas discovered empirically
— the knowledge that cannot be reconstructed by reading the code. They are
intended to be vectorized and retrieved by an agent acting as a domain
expert on this repository.

Authoring rules (so chunking/embedding works well):

- Every section must stand alone: repeat the subject noun instead of using
  pronouns that refer to a previous section ("the Access policy", not "it").
- Use exact resource names, field names, CLI commands, and verbatim error
  strings — these are what retrieval queries will contain.
- Dates are absolute (e.g. "August 2026"), never relative.
- Rejected alternatives get their own subsections with the concrete reason
  for rejection, not just the winner's justification.
- When a lesson was learned by hitting a failure, include the observed
  failure symptom verbatim, then the root cause, then the fix — symptom
  text is what a future debugging session will search for.

Index:

- [0001 — Secrets: one 1Password vault item feeds local dev and CI](0001-secrets-one-1password-item.md)
- [0002 — Terraform state on OCI Object Storage via the AWS S3 backend](0002-terraform-state-oci-s3-compat.md)
- [0003 — Deploys via Cloudflare Tunnel SSH; no public k8s API](0003-cloudflare-tunnel-ssh-deploys.md)
- [0004 — OCI instance metadata is immutable; the bootstrap-script pattern](0004-oci-metadata-immutability.md)
- [0005 — CI applies the exact reviewed plan artifact; merge-timing rule](0005-plan-artifact-gating.md)
- [0006 — Platform constraints: OCI free tier, single node, SSH trust](0006-platform-constraints.md)
- [0007 — HTTPS everywhere: API through the Cloudflare Tunnel, frontend on Cloudflare Pages](0007-https-tunnel-api-pages-frontend.md)
- [0008 — Selective deploys, deploy ordering, and per-package rollback](0008-selective-ordered-deploys-rollback.md)
