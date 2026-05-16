#!/bin/bash
# Direct all logs to standard outputs and files safely
exec > >(tee /var/log/bootstrap.log | logger -t bootstrap) 2>&1
set -x

echo "=== Starting Hardened MGMT Bootstrap Loop Fix ==="

# ── 1. Python & Mirror Sync (With Fast Fail & Backup) ─────────────────
echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf
echo "fastestmirror=True" >> /etc/dnf/dnf.conf

for i in {1..5}; do
  dnf clean all
  dnf makecache && dnf install -y python3 python3-pip && break
  sleep 5
done

# ── 2. User Setup ─────────────────────────────────────────────────────
useradd -m -s /bin/bash user1 || true
mkdir -p /home/user1/.ssh

if ! grep -qF "${PUBLIC_KEY_CONTENT}" /home/user1/.ssh/authorized_keys 2>/dev/null; then
  echo "${PUBLIC_KEY_CONTENT}" >> /home/user1/.ssh/authorized_keys
fi

chown -R user1:user1 /home/user1/.ssh
chmod 700 /home/user1/.ssh
chmod 600 /home/user1/.ssh/authorized_keys

# Force standard format with a clean trailing newline
echo "user1 ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/user1
chmod 0440 /etc/sudoers.d/user1

# ── 3. IP Forwarding ──────────────────────────────────────────────────
# Safeguard: Overwrite cleanly and handle return codes explicitly
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-tailscale.conf
echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.d/99-tailscale.conf
sysctl --system || true

# ── 4. Tailscale Installation ─────────────────────────────────────────
curl -fsSL https://tailscale.com/install.sh | sh

systemctl daemon-reload || true
systemctl enable --now tailscaled || true

for i in {1..30}; do
  if systemctl is-active --quiet tailscaled; then
    echo "Tailscale daemon is running."
    break
  fi
  sleep 2
done

# ── 5. Network Authentication ─────────────────────────────────────────
# Crucial Fix: No '--accept-routes' to avoid the MGMT loop
tailscale up \
  --authkey="${TS_AUTH_KEY}" \
  --advertise-tags="tag:project1-ec2" \
  --advertise-routes="${VPC_CIDR_BLOCK}" \
  --accept-dns=false \
  --hostname="aws-mgmt" || echo "Warning: Tailscale registration command exited with errors"

echo "mgmt bootstrap complete - Tailscale IP: $(tailscale ip -4 2>/dev/null || echo 'Not Found')"
