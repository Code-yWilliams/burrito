#!/usr/bin/env bash
# Fetch a kubeconfig from the k3s node, rewritten to point at its public IP.
# Usage: scripts/fetch-kubeconfig.sh <node-public-ip> [output-path]
set -euo pipefail

IP="${1:?usage: fetch-kubeconfig.sh <node-public-ip> [output-path]}"
OUT="${2:-kubeconfig}"
KEY="${SSH_KEY:-$HOME/.ssh/burrito_k3s}"

ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "ubuntu@$IP" \
  "sudo cat /etc/rancher/k3s/k3s.yaml" \
  | sed "s/127.0.0.1/$IP/" > "$OUT"
chmod 600 "$OUT"
echo "kubeconfig written to $OUT — try: KUBECONFIG=$OUT kubectl get nodes"
