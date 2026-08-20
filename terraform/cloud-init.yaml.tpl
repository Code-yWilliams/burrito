#cloud-config
package_update: true

write_files:
  # Single source of truth for the cloudflared install lives in
  # scripts/bootstrap-cloudflared.sh (repo-tracked, reviewable) — embedded
  # here rather than duplicated inline so cloud-init and a manual re-run
  # against an existing node always run the exact same script.
  - path: /opt/bootstrap-cloudflared.sh
    permissions: '0755'
    encoding: b64
    content: ${bootstrap_cloudflared_b64}

runcmd:
  # OCI Ubuntu images ship iptables REJECT rules that block everything except
  # SSH at the OS level. Network security is enforced by the cloud NSG, so
  # clear them; otherwise 80/443/6443 stay unreachable no matter what the NSG says.
  - iptables -P INPUT ACCEPT
  - iptables -P FORWARD ACCEPT
  - iptables -F
  - netfilter-persistent save
  # The instance boots with no public IP; terraform attaches a reserved IP
  # moments later, and there is zero egress until it does. Wait for egress,
  # learn our own public IP, then install k3s with that IP in the API server
  # cert so remote kubectl/helm (laptop, GitHub Actions) can connect.
  - |
    until PUBLIC_IP=$(curl -sf --max-time 5 https://checkip.amazonaws.com); do sleep 5; done
    PUBLIC_IP=$(echo "$PUBLIC_IP" | tr -d '[:space:]')
    curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable INSTALL_K3S_EXEC="server --tls-san $PUBLIC_IP" sh -
  # cloudflared: the only path CI uses to reach this node (SSH over an
  # outbound-only tunnel) — the k8s API itself is never exposed publicly.
  - /opt/bootstrap-cloudflared.sh ${cloudflare_tunnel_token}
