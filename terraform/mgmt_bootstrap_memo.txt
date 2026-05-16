#!/bin/bash
set -e

# Install Python for Ansible
dnf install -y python3 python3-pip

# Create user1
useradd -m -s /bin/bash user1
mkdir -p /home/user1/.ssh

# Inject the public key passed securely from Terraform
echo "${PUBLIC_KEY_CONTENT}" >> /home/user1/.ssh/authorized_keys

chown -R user1:user1 /home/user1/.ssh
chmod 700 /home/user1/.ssh
chmod 600 /home/user1/.ssh/authorized_keys
echo "user1 ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/user1

# Install and start Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable --now tailscaled
sleep 5

# Start Tailscale with variables mapped from Terraform
tailscale up \
  --authkey="${TS_AUTH_KEY}" \
  --advertise-tags="tag:project1-ec2" \
  --advertise-routes="${VPC_CIDR_BLOCK}" \
  --ephemeral \
  --accept-routes \
  --accept-dns=false \
  --hostname="aws-mgmt"
