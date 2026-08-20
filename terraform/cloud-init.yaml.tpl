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
  # clear them; otherwise 80/443 stay unreachable no matter what the NSG says.
  - iptables -P INPUT ACCEPT
  - iptables -P FORWARD ACCEPT
  - iptables -F
  - netfilter-persistent save
  # The instance boots with no public IP; terraform attaches a reserved IP
  # moments later, and there is zero egress until it does. Wait for egress,
  # then install k3s. No extra --tls-san needed: every remote client (CI via
  # the Cloudflare Tunnel, laptops via direct SSH) reaches the API through an
  # SSH port-forward at 127.0.0.1:6443, which k3s certs cover by default.
  - |
    until curl -sf --max-time 5 https://checkip.amazonaws.com >/dev/null; do sleep 5; done
    curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable sh -
  # cloudflared: the only path CI uses to reach this node (SSH over an
  # outbound-only tunnel) — the k8s API itself is never exposed publicly.
  - /opt/bootstrap-cloudflared.sh ${cloudflare_tunnel_token}
