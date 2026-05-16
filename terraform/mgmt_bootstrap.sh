#!/bin/bash
exec > >(tee /var/log/bootstrap.log | logger -t bootstrap) 2>&1
set -x

# ── 1. Python & Package Setup (Safe OS Check) ──────────────────────────
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_TYPE=$ID
fi

if [ "$OS_TYPE" = "ubuntu" ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y python3 python3-minimal
else
    dnf clean all && dnf makecache
    dnf install -y python3 python3-pip
fi

# ── 2. User Setup (Idempotent Check) ──────────────────────────────────
if ! id "user1" &>/dev/null; then
    useradd -m -s /bin/bash user1
fi
mkdir -p /home/user1/.ssh

if ! grep -qF "${PUBLIC_KEY_CONTENT}" /home/user1/.ssh/authorized_keys 2>/dev/null; then
  echo "${PUBLIC_KEY_CONTENT}" >> /home/user1/.ssh/authorized_keys
fi

chown -R user1:user1 /home/user1/.ssh
chmod 700 /home/user1/.ssh
chmod 600 /home/user1/.ssh/authorized_keys
echo "user1 ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/user1
chmod 440 /etc/sudoers.d/user1

# ── 3. Tailscale Installation ─────────────────────────────────────────
curl -fsSL https://tailscale.com/install.sh | sh

systemctl daemon-reload || true
systemctl enable --now tailscaled

for i in {1..30}; do
  systemctl is-active --quiet tailscaled && break
  sleep 2
done

# ── 4. Network Authentication ─────────────────────────────────────────
# Handled safely via the official binary directly
/usr/sbin/tailscale up \
  --authkey="${TS_AUTH_KEY}" \
  --advertise-tags="tag:project1-ec2" \
  --advertise-routes="${VPC_CIDR_BLOCK}" \
  --accept-dns=false \
  --hostname="aws-mgmt"

echo "mgmt bootstrap complete - Tailscale IP: $(/usr/sbin/tailscale ip -4)"
