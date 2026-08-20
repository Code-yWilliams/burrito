# 0007 — HTTPS everywhere: API through the Cloudflare Tunnel, frontend on Cloudflare Pages

Status: adopted August 2026, alongside the Express+TypeScript rewrite of
`app/` and the new `web/` React SPA.

## The decision

Two public HTTPS hostnames on the existing `moldysandwich.com` zone, both
fully terraform-managed:

- `api-burrito.moldysandwich.com` — the Express API. A second ingress rule
  on the **existing** `burrito-ssh` Cloudflare Tunnel
  (`cloudflare_zero_trust_tunnel_cloudflared_config.burrito` in
  `terraform/cloudflare.tf`) routes the hostname to `http://localhost:80`,
  which is k3s Traefik on the node cloudflared already runs on. TLS
  terminates at Cloudflare's edge; edge-to-node rides the tunnel's own
  encrypted connection. No certificates exist on the node at all.
- `burrito.moldysandwich.com` — the React SPA, on a Cloudflare Pages
  **direct-upload** project named `burrito-web`
  (`cloudflare_pages_project.web` in `terraform/frontend.tf`, plus
  `cloudflare_pages_domain.web` and a proxied CNAME). CI builds the SPA on
  a GitHub runner and uploads it with
  `wrangler pages deploy web/dist --project-name=burrito-web --branch=main`.

The tunnel's API hostname deliberately has **no** Zero Trust Access
application in front of it — the API is public. Only the SSH hostname
(`ssh-burrito.moldysandwich.com`) is gated by the Service Auth policy
(decision 0003). Do not "fix" the asymmetry.

Both DNS records must be `proxied = true`: the CNAME targets
(`<tunnel-id>.cfargotunnel.com` and `burrito-web.pages.dev` via the
project's computed `subdomain` attribute) only work through Cloudflare's
edge, and unproxied records would also lose the edge TLS certificate.

## CORS

The SPA origin (`https://burrito.moldysandwich.com`) is different from the
API origin (`https://api-burrito.moldysandwich.com`), so the browser
requires CORS headers on API responses. The Express app uses the `cors`
package with an explicit allowlist from the `ALLOWED_ORIGINS` env var
(comma-separated; set by the Helm value `app.allowedOrigins` to the Pages
origin plus `http://localhost:5173` for Vite local dev). The `cors`
package echoes the matching origin into `Access-Control-Allow-Origin` and
sends `Vary: Origin`; a non-matching origin gets no CORS headers at all.
Never `*` — an allowlist costs nothing and stays correct if credentials
are ever added.

## Rejected alternatives

### cert-manager + Let's Encrypt on Traefik (rejected)

Would put certificates and ACME renewal state in-cluster on a single node
whose recreation already loses data (decision 0006), add a controller to
a 1 OCPU / 6 GB node, and require ports 80/443 to stay publicly open for
ACME challenges. The tunnel already existed with remote-managed config
(`config_src = "cloudflare"`), so publishing the API was one ingress rule
plus one DNS record, propagated to the running cloudflared with **zero
node changes**.

### Cloudflare Workers static assets for the frontend (rejected)

Cloudflare has recommended Workers over Pages for new projects since
2025, and a future migration is straightforward. Pages was still chosen
in August 2026 because for a pure static SPA it is fewer moving parts:
no wrangler config file in the repo (the deploy command carries all
flags), three small terraform resources, and automatic HTTPS on both
`burrito-web.pages.dev` and the custom domain.

### Pages git integration (rejected)

Letting Cloudflare build from the GitHub repo directly would deploy on
push, bypassing the `production` environment approval gate that every
other deploy in this repo goes through (decision 0005). Direct upload
keeps the build on GitHub runners inside the same gated `deploy` job.

## Gotchas

- **Cloudflare API token scope.** The shared token
  (`TF_VAR_cloudflare_api_token` on the `burrito-ci` 1Password item) was
  originally scoped to Tunnel/Access/DNS edit + Zone read. Both the
  `cloudflare_pages_*` terraform resources and `wrangler pages deploy`
  additionally need the account-level **"Cloudflare Pages: Edit"**
  permission. `terraform plan` succeeds without it (creating new
  resources needs no API reads at plan time) — the failure only appears
  at apply/deploy time as an authentication error, so widen the token
  scope in the Cloudflare dashboard *before* merging.
- **First-deploy latency.** The custom-domain certificate for
  `burrito.moldysandwich.com` is issued on first use and can take a few
  minutes; the deploy job's "Verify frontend" step retries for 5 minutes
  for this reason. Tunnel-config and DNS propagation for the API hostname
  are much faster (seconds) but the healthz verify retries for 2 minutes.
- **Ports 80/443 on the node are still open** (`oci_core_network_security_group_security_rule.http`/`.https`
  in `terraform/network.tf`), so plain `http://<node-ip>/healthz` still
  reaches Traefik directly, bypassing Cloudflare. Removing those rules is
  the planned follow-up once the tunnel path is verified in production —
  the same staged pattern used for closing the k8s API (decision 0003).
- **Traefik ingress matches all hosts.** The chart's Ingress has no
  `host:` rule, which is what lets the tunnel-forwarded
  `api-burrito.moldysandwich.com` Host header route without any chart
  change — and is also why the raw node-IP path keeps working.
