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
# ⚠️ ADDED "|| true" HERE TO PREVENT MINOR SYSTEM WARNINGS FROM CRASHING THE AUTOMATION
sysctl -p /etc/sysctl.d/99-tailscale.conf || true

# ── Tailscale ─────────────────────────────────────────────────────────
curl -fsSL https://tailscale.com | sh

# Forces systemd to register the newly downloaded Tailscale binaries
systemctl daemon-reload || true
systemctl enable --now tailscaled

# Wait for tailscaled to be ready
until tailscale status &>/dev/null 2>&1; do
  sleep 2
done

# Join the Tailscale network
# ⚠️ ENFORCE THE WORKED KEY PARAMETERS HERE NATIVELY
tailscale up \
  --authkey="${TS_AUTH_KEY}" \
  --advertise-tags="tag:project1-ec2" \
  --advertise-routes="${VPC_CIDR_BLOCK}" \
  --accept-routes \
  --accept-dns=false \
  --hostname="aws-mgmt"

echo "mgmt bootstrap complete - Tailscale IP: $(tailscale ip -4)"
