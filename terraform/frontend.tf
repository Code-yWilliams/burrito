# The React SPA is served by Cloudflare Pages (static hosting, HTTPS
# automatic on both the *.pages.dev subdomain and the custom domain).
# Terraform owns the project/domain/DNS; CI uploads each build with
# `wrangler pages deploy` (a "direct upload" project — no `source` block,
# so Cloudflare never builds from git itself).
#
# NOTE: the Cloudflare API token (TF_VAR_cloudflare_api_token in the
# vault) must include the account-level "Cloudflare Pages: Edit"
# permission for these resources and for wrangler in CI.

resource "cloudflare_pages_project" "web" {
  account_id        = var.cloudflare_account_id
  name              = "burrito-web"
  production_branch = "main"
}

resource "cloudflare_pages_domain" "web" {
  account_id   = var.cloudflare_account_id
  project_name = cloudflare_pages_project.web.name
  name         = local.web_hostname
}

resource "cloudflare_dns_record" "web" {
  zone_id = local.cloudflare_zone_id
  name    = "burrito"
  type    = "CNAME"
  content = cloudflare_pages_project.web.subdomain # burrito-web.pages.dev
  proxied = true
  ttl     = 1
}
