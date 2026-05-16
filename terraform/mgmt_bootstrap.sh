#!/bin/bash
set -e

# ── 1. Python & Mirror Sync (With Retry) ──────────────────────────────
# Background mirrors can take a moment to sync on fresh boot. Retry up to 3 times.
for i in {1..3}; do
  dnf clean all && dnf makecache && dnf install -y python3 python3-pip && break || sleep 10
done

# ── 2. User Setup ─────────────────────────────────────────────────────
useradd -m -s /bin/bash user1 || true
mkdir -p /home/user1/.ssh
echo "${PUBLIC_KEY_CONTENT}" >> /home/user1/.ssh/authorized_keys
chown -R user1:user1 /home/user1/.ssh
chmod 700 /home/user1/.ssh
chmod 600 /home/user1/.ssh/authorized_keys
echo "user1 ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/user1

# ── 3. IP Forwarding ──────────────────────────────────────────────────
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.d/99-tailscale.conf
sysctl -p /etc/sysctl.d/99-tailscale.conf || true

# ── 4. Tailscale Installation ─────────────────────────────────────────
curl -fsSL https://tailscale.com | sh

systemctl daemon-reload || true
systemctl enable --now tailscaled

# Wait cleanly for the systemd socket to initialize
until tailscale status &>/dev/null 2>&1; do
  sleep 2
done

# ── 5. Network Authentication ─────────────────────────────────────────
# ⚠️ RE-ADDED THE ADVERTISE TAGS THAT SUCCESSFULY AUTHENTICATED MANUALLY
tailscale up \
  --authkey="${TS_AUTH_KEY}" \
  --advertise-tags="tag:project1-ec2" \
  --advertise-routes="${VPC_CIDR_BLOCK}" \
  --accept-routes \
  --accept-dns=false \
  --hostname="aws-mgmt"

echo "mgmt bootstrap complete - Tailscale IP: $(tailscale ip -4)"
