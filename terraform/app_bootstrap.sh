#!/bin/bash
# (No set -e at the top to prevent minor package warnings from crashing the boot process)
exec > >(tee /var/log/bootstrap.log | logger -t bootstrap) 2>&1
set -x

# ── 1. OS Auto-Detection & Package Setup ─────────────────────────────
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_TYPE=$ID
fi

if [ "$OS_TYPE" = "ubuntu" ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y python3 python3-minimal
else
    # Rocky/RHEL handling
    dnf clean all
    dnf makecache
    dnf install -y python3 python3-pip
fi

# ── 2. User Setup ─────────────────────────────────────────────────────
if ! id "user1" &>/dev/null; then
    useradd -m -s /bin/bash user1
fi
mkdir -p /home/user1/.ssh
echo "${PUBLIC_KEY_CONTENT}" >> /home/user1/.ssh/authorized_keys
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

# ── 4. Network Join ───────────────────────────────────────────────────
tailscale up \
  --authkey="${TS_AUTH_KEY}" \
  --advertise-tags="tag:project1-ec2" \
  --accept-routes \
  --accept-dns=false \
  --hostname="${VM_HOSTNAME}"
