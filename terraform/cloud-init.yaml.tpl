#cloud-config
package_update: true

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
  - curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg
  - echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' > /etc/apt/sources.list.d/cloudflared.list
  - apt-get update
  - apt-get install -y cloudflared
  - cloudflared service install ${cloudflare_tunnel_token}
