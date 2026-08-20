# 0003 — Deploys via Cloudflare Tunnel SSH; no public k8s API

Status: adopted August 2026. The public `0.0.0.0/0:6443` NSG rule is
deleted; the k8s API has no public ingress at all.

## Decision

CI deploys by SSHing to the k3s node **through a Cloudflare Tunnel**, then
port-forwarding the k8s API locally:

1. The node runs `cloudflared` as a systemd service (installed by
   `scripts/bootstrap-cloudflared.sh`; token from 1Password field
   `CLOUDFLARE_TUNNEL_TOKEN`) holding an **outbound-only** connection to
   Cloudflare's edge. Tunnel ingress maps
   `ssh-burrito.moldysandwich.com` → `ssh://localhost:22`.
2. A Cloudflare Access **self-hosted application** on that hostname is
   gated by a policy that admits **only** the CI service token
   (`cloudflare_zero_trust_access_service_token.ci`, named `burrito-ci`).
   Cloudflare's edge rejects everyone else before any packet reaches the
   tunnel or the node.
3. The GitHub Actions deploy job installs `cloudflared`, SSHes as `ubuntu`
   with the dedicated CI keypair (1Password field `CI_SSH_PRIVATE_KEY`)
   using `ProxyCommand cloudflared access ssh --hostname %h` — the service
   token flows through the env vars `TUNNEL_SERVICE_TOKEN_ID` /
   `TUNNEL_SERVICE_TOKEN_SECRET`, which cloudflared reads natively, so no
   credentials appear in SSH config or flags.
4. The job fetches the node's own `/etc/rancher/k3s/k3s.yaml` over that
   SSH session and opens a background port-forward
   `-L 6443:127.0.0.1:6443`. k3s's kubeconfig natively points at
   `https://127.0.0.1:6443`, which is exactly where the forward lands —
   **no rewriting, and it can never go stale**, even right after a node
   recreation regenerates the k3s CA. kubectl/helm then run on the runner
   unchanged. This retired the old `KUBECONFIG_B64` static blob and its
   documented stale-after-recreation failure mode.

All Cloudflare resources are Terraform-managed in `terraform/cloudflare.tf`
(provider `cloudflare/cloudflare ~> 5.0`).

## The critical gotcha: Service Auth vs Allow (cost hours)

**A Cloudflare Access policy that should admit a service token MUST use
`decision = "non_identity"` ("Service Auth" in the dashboard). A policy
with `decision = "allow"` will validate the service token and still refuse
it**, because Allow demands an identity from an SSO login, which a service
token does not provide.

Observed failure symptom with `decision = "allow"`: every headless client
(`cloudflared access ssh`, `cloudflared access tcp`, raw curl) fell
through to the interactive browser login page ("A browser window should
have opened at the following URL: …/cdn-cgi/access/cli?..."). The
diagnostic smoking gun: the redirect's `meta` JWT payload contained
`"service_token_status": true` (token recognized as valid) next to
`"auth_status": "NONE"` (token not accepted as authentication). If you see
that pair, the policy decision is wrong — nothing is wrong with the token,
the tunnel, or cloudflared.

This symptom was initially misdiagnosed twice: first as a cloudflared
version regression (GitHub issue #1673 — a red herring for this case;
both cloudflared 2026.5.1 and 2026.6.1 work fine once the policy is
`non_identity`), then as a wrong `token_id` (also wrong, see below).

## Second gotcha: token_id is the resource UUID, not client_id

In the policy's include rule `service_token = { token_id = ... }`, the
value must be the service token's **resource id** (a UUID, the `.id`
attribute, e.g. `8c34b980-…`), **not** its `client_id`
(`<32 hex>.access`). The live Cloudflare API rejects `client_id` at apply
time with `access.api.error.invalid_request: invalid 'include'
configuration … service token not found`. Conversely, the `client_id` is
what the client actually sends in the `CF-Access-Client-Id` header — two
different identifiers for the same object, used in different places.

## Terraform provider v5 schema realities

The Cloudflare Terraform provider v5 restructured resources; most blog
posts and older docs show v4 shapes that fail with "Unexpected attribute"
/ "Blocks of type X are not expected here". Verified-correct v5 shapes
used here:

- Policies are **inline on the application** as a list attribute:
  `cloudflare_zero_trust_access_application { policies = [{ name, decision,
  precedence, include = [{ service_token = { token_id } }] }] }`. The
  standalone `cloudflare_zero_trust_access_policy` resource takes
  `account_id` but **no `application_id`** attribute in v5.
- Tunnel config is a single nested attribute:
  `cloudflare_zero_trust_tunnel_cloudflared_config { config = { ingress =
  [{ hostname, service }, { service = "http_status:404" }] } }` — not
  `config { ingress_rule { } }` blocks.
- The tunnel's run token is **not an attribute** of
  `cloudflare_zero_trust_tunnel_cloudflared`; it comes from the data
  source `cloudflare_zero_trust_tunnel_cloudflared_token`.
- DNS records use `cloudflare_dns_record` (renamed from
  `cloudflare_record`), with required `ttl` (use `1` when `proxied = true`)
  and `content = "<tunnel-id>.cfargotunnel.com"` for tunnel CNAMEs.
- Zone lookup by name uses the plural data source `cloudflare_zones` with
  `name = "moldysandwich.com"`, then `.result[0].id`.

Method lesson: when provider docs conflict with reality, dump ground truth
with `terraform providers schema -json` and read the actual attribute
tree. That is how every shape above was settled.

## Rejected alternatives

- **Tunneling the k8s API directly (TCP)**: Cloudflare's own docs were
  ambiguous on TLS/SNI handling for a raw-TCP k8s API app, and headless
  service-token auth for `cloudflared access tcp` had a churning
  regression history. SSH is the boring, verifiable transport; the k8s API
  rides it as a port-forward.
- **Cloudflare Access for Infrastructure (keyless short-lived SSH
  certs)**: certificate issuance is tied to an authenticated human
  WARP/SSO session; there is **no machine-identity support** — unusable
  for CI regardless of preference.
- **Tailscale**: viable and simpler for pure private networking, but
  Cloudflare won because the account/domain already existed and the same
  tunnel can later front the app itself with a real domain + TLS
  (currently a "natural next step" in the README tradeoffs).
- **Narrowing the 6443 NSG rule to GitHub's runner IP ranges**: still a
  public listener behind a huge shared IP allowlist; rejected as security
  theater compared to removing the listener entirely.
- **Self-hosted runner on a second free-tier node**: rejected for now
  because the repo is public — workflow code from any PR could execute on
  the runner (a standing arbitrary-code-execution landmine), and GitHub
  explicitly recommends against self-hosted runners for public repos.

## Local kubectl after closing 6443

`scripts/fetch-kubeconfig.sh <node-ip>` fetches the node's kubeconfig
as-is (server `https://127.0.0.1:6443`) and prints the SSH port-forward to
open alongside it. Humans reach the node over direct SSH — port 22 is NSG-
restricted to `my_ip_cidr` — not through the Cloudflare Access app, whose
policy admits only the CI service token.
