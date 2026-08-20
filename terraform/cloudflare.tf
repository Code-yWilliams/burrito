# The tunnel (an outbound-only connection from the node to Cloudflare's
# edge) carries two hostnames with very different exposure:
#   - ssh-burrito: CI's SSH path to the node, locked to the CI service
#     token by the Access policy below. Replaces the k8s API's public NSG
#     exposure — CI runs kubectl/helm over this SSH session using the
#     node's own always-current kubeconfig.
#   - api-burrito: the public HTTPS front for the app. Cloudflare
#     terminates TLS at the edge and hands requests to Traefik on the
#     node's localhost:80 — no cert management on the node, and
#     deliberately NO Access application (it's a public API).

data "cloudflare_zones" "moldysandwich" {
  name = "moldysandwich.com"
}

locals {
  cloudflare_zone_id  = data.cloudflare_zones.moldysandwich.result[0].id
  ssh_tunnel_hostname = "ssh-burrito.moldysandwich.com"
  api_hostname        = "api-burrito.moldysandwich.com"
  web_hostname        = "burrito.moldysandwich.com"
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "burrito" {
  account_id = var.cloudflare_account_id
  name       = "burrito-ssh"
  config_src = "cloudflare"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "burrito" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.burrito.id
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "burrito" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.burrito.id

  config = {
    ingress = [
      {
        hostname = local.ssh_tunnel_hostname
        service  = "ssh://localhost:22"
      },
      {
        # k3s Traefik listens on the node's port 80 and routes to the app;
        # cloudflared runs on the same node, so localhost reaches it.
        hostname = local.api_hostname
        service  = "http://localhost:80"
      },
      {
        service = "http_status:404"
      }
    ]
  }
}

resource "cloudflare_dns_record" "ssh_tunnel" {
  zone_id = local.cloudflare_zone_id
  name    = "ssh-burrito"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.burrito.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

# Must be proxied: TLS terminates at Cloudflare's edge and the record's
# target only resolves inside Cloudflare's network.
resource "cloudflare_dns_record" "api" {
  zone_id = local.cloudflare_zone_id
  name    = "api-burrito"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.burrito.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

# The CI identity. Its client_id/client_secret are pulled out as outputs
# and stored in 1Password (burrito-ci item), same as every other secret CI
# uses — never in this repo or GitHub secrets directly.
resource "cloudflare_zero_trust_access_service_token" "ci" {
  account_id = var.cloudflare_account_id
  name       = "burrito-ci"
}

resource "cloudflare_zero_trust_access_application" "ssh_tunnel" {
  account_id       = var.cloudflare_account_id
  name             = "burrito-ssh"
  domain           = local.ssh_tunnel_hostname
  type             = "self_hosted"
  session_duration = "24h"

  # The actual "who can reach SSH at all" gate: only the CI service token,
  # nothing else. Cloudflare rejects the connection before it ever reaches
  # the tunnel/node for anyone/anything not matching this policy.
  policies = [
    {
      name = "CI service token only"
      # Service tokens are only honored by a "Service Auth" (non_identity)
      # policy. An "allow" policy demands an identity from SSO, so even a
      # valid service token falls through to the interactive login page --
      # Access's redirect JWT shows service_token_status:true (token
      # recognized) alongside auth_status:NONE (not accepted as auth),
      # which is how this was diagnosed.
      decision   = "non_identity"
      precedence = 1
      include = [
        {
          # token_id is the service token's resource id (a UUID), not its
          # client_id -- the live API rejects client_id outright with
          # "service token not found".
          service_token = {
            token_id = cloudflare_zero_trust_access_service_token.ci.id
          }
        }
      ]
    }
  ]
}

output "cloudflare_tunnel_token" {
  description = "Token cloudflared needs to run this tunnel (goes into the node's systemd unit, not committed anywhere)"
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.burrito.token
  sensitive   = true
}

output "cf_access_client_id" {
  description = "Service token client ID (goes into 1Password as CF_ACCESS_CLIENT_ID)"
  value       = cloudflare_zero_trust_access_service_token.ci.client_id
}

output "cf_access_client_secret" {
  description = "Service token client secret (goes into 1Password as CF_ACCESS_CLIENT_SECRET)"
  value       = cloudflare_zero_trust_access_service_token.ci.client_secret
  sensitive   = true
}
