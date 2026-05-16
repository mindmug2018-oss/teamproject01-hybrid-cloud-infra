#!/bin/bash
set -e

# ── Python ────────────────────────────────────────────────────────────
dnf install -y python3 python3-pip

# ── user1 ─────────────────────────────────────────────────────────────
useradd -m -s /bin/bash user1
mkdir -p /home/user1/.ssh
echo "${PUBLIC_KEY_CONTENT}" >> /home/user1/.ssh/authorized_keys
chown -R user1:user1 /home/user1/.ssh
chmod 700 /home/user1/.ssh
chmod 600 /home/user1/.ssh/authorized_keys
echo "user1 ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/user1

# ── IP forwarding (required for Tailscale subnet routing) ─────────────
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.d/99-tailscale.conf
sysctl -p /etc/sysctl.d/99-tailscale.conf

# ── Tailscale ─────────────────────────────────────────────────────────
curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable --now tailscaled

# Wait for tailscaled to be ready
until tailscale status &>/dev/null 2>&1; do
  sleep 2
done

# Join the Tailscale network
# --advertise-routes exposes the entire VPC so GitHub Actions runner
# can reach private instances (rocky1, rocky2, ubuntu1) directly
tailscale up \
  --authkey="${TS_AUTH_KEY}" \
  --advertise-routes="${VPC_CIDR_BLOCK}" \
  --accept-routes \
  --accept-dns=false \
  --hostname="aws-mgmt"

echo "mgmt bootstrap complete - Tailscale IP: $(tailscale ip -4)"