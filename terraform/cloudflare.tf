# SSH-over-tunnel replaces the k8s API's public NSG exposure: CI reaches
# the node only through this tunnel (an outbound-only connection from the
# node to Cloudflare's edge), authenticated by the Access policy below,
# then runs kubectl/helm locally on the node over that SSH session using
# its own always-current kubeconfig. See network.tf for the corresponding
# k8s_api NSG rule removal (done in a follow-up once this is verified).

data "cloudflare_zones" "moldysandwich" {
  name = "moldysandwich.com"
}

locals {
  cloudflare_zone_id  = data.cloudflare_zones.moldysandwich.result[0].id
  ssh_tunnel_hostname = "ssh-burrito.moldysandwich.com"
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
      name       = "CI service token only"
      decision   = "allow"
      precedence = 1
      include = [
        {
          # token_id here must be the token's client_id (what's actually
          # sent as Cf-Access-Client-Id at auth time), not its resource id
          # (an unrelated internal UUID) -- confirmed by testing against
          # the real API after the resource id version silently failed
          # auth and fell back to interactive browser login.
          service_token = {
            token_id = cloudflare_zero_trust_access_service_token.ci.client_id
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
