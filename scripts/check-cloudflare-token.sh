#!/usr/bin/env bash
# Canonical, executable list of the Cloudflare API token permissions this
# repo needs. CI runs it before every terraform plan AND before every
# apply, so a missing scope fails fast with a named permission instead of
# a mid-apply 403 (observed August 2026: creating cloudflare_pages_project
# failed with 403 {"code":10000,"message":"Authentication error"} halfway
# through an apply, leaving the reviewed plan stale — see decision 0007).
#
# The token itself is created/edited by hand in the Cloudflare dashboard;
# terraform cannot manage its own credential (the root token can never be
# codified), so this script is the source of truth for its scopes. Add a
# probe here whenever terraform grows a new Cloudflare resource family.
#
# Limitation: probes are GET requests, so they prove the permission group
# is present (Edit implies Read) but can't distinguish Edit from Read.
#
# Usage: CLOUDFLARE_API_TOKEN=... check-cloudflare-token.sh <account-id>
set -euo pipefail

ACCOUNT_ID="${1:?usage: check-cloudflare-token.sh <account-id>}"
TOKEN="${CLOUDFLARE_API_TOKEN:?set CLOUDFLARE_API_TOKEN}"
BASE="https://api.cloudflare.com/client/v4"
ZONE_NAME="moldysandwich.com"
FAILED=0

probe() { # <url> <dashboard permission name>
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer $TOKEN" "$1")
  if [ "$code" = "200" ]; then
    echo "ok:      $2"
  else
    echo "MISSING (HTTP $code): $2"
    FAILED=1
  fi
}

probe "$BASE/user/tokens/verify" \
  "token is valid and active"
probe "$BASE/zones?name=$ZONE_NAME" \
  "Zone / Zone / Read"
probe "$BASE/accounts/$ACCOUNT_ID/cfd_tunnel" \
  "Account / Cloudflare Tunnel / Edit"
probe "$BASE/accounts/$ACCOUNT_ID/access/apps" \
  "Account / Access: Apps and Policies / Edit"
probe "$BASE/accounts/$ACCOUNT_ID/access/service_tokens" \
  "Account / Access: Service Tokens / Edit"
probe "$BASE/accounts/$ACCOUNT_ID/pages/projects" \
  "Account / Cloudflare Pages / Edit"

# DNS is zone-scoped: resolve the zone id, then list its records.
ZONE_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE/zones?name=$ZONE_NAME" | jq -r '.result[0].id // empty')
if [ -n "$ZONE_ID" ]; then
  probe "$BASE/zones/$ZONE_ID/dns_records" "Zone / DNS / Edit"
else
  echo "MISSING: could not resolve zone id for $ZONE_NAME (Zone Read?)"
  FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
  echo >&2 "Cloudflare token is missing permissions. Edit the token in the" \
    "Cloudflare dashboard (the one stored as TF_VAR_cloudflare_api_token" \
    "on the burrito-ci 1Password item) and add the permissions named above."
fi
exit "$FAILED"
