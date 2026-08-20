#!/usr/bin/env bash
# Fetch a kubeconfig from the k3s node over SSH. The k8s API is not
# publicly exposed — the kubeconfig points at https://127.0.0.1:6443, so
# kubectl needs an SSH port-forward open alongside it (printed below).
# Usage: scripts/fetch-kubeconfig.sh <node-public-ip> [output-path]
set -euo pipefail

IP="${1:?usage: fetch-kubeconfig.sh <node-public-ip> [output-path]}"
OUT="${2:-kubeconfig}"
KEY="${SSH_KEY:-$HOME/.ssh/burrito_k3s}"

ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "ubuntu@$IP" \
  "sudo cat /etc/rancher/k3s/k3s.yaml" > "$OUT"
chmod 600 "$OUT"
echo "kubeconfig written to $OUT (server: https://127.0.0.1:6443)"
echo "Open the port-forward, then use kubectl:"
echo "  ssh -i $KEY -f -N -L 6443:127.0.0.1:6443 ubuntu@$IP"
echo "  KUBECONFIG=$OUT kubectl get nodes"
