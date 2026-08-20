#!/usr/bin/env bash
# Installs cloudflared and registers it as a systemd service running the
# burrito-ssh tunnel. This is the single source of truth for that install —
# cloud-init runs it automatically on every new node boot (embedded via
# terraform's filebase64() in compute.tf); it can also be run by hand
# against an already-running node that predates this change, with the same
# token (1Password field CLOUDFLARE_TUNNEL_TOKEN on burrito-ci).
# Usage: bootstrap-cloudflared.sh <tunnel-token>
set -euo pipefail

TOKEN="${1:?usage: bootstrap-cloudflared.sh <tunnel-token>}"

curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' > /etc/apt/sources.list.d/cloudflared.list
apt-get update -qq
apt-get install -y -qq cloudflared
cloudflared service install "$TOKEN"
