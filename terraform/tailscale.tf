########################################################################
# tailscale.tf
# Pre-installs Tailscale on all EC2 instances via user_data
# so they join the mesh network on first boot — before Ansible runs
#
# Required Terraform variable: tailscale_auth_key
# Get from: https://login.tailscale.com/admin/settings/keys
# Create a reusable auth key (not one-time) for CI/CD use
########################################################################

# NOTE: tailscale_auth_key is defined in variables.tf
# The user_data in main.tf references var.tailscale_auth_key
# This file just documents the Tailscale setup approach

# ── Tailscale ACL tag for EC2 instances ───────────────────────────────
# In your Tailscale admin console, add this to your ACL policy:
#
# "tagOwners": {
#   "tag:project1-ec2": ["autogroup:admin"]
# }
#
# Then create an auth key with tag:project1-ec2
# This lets you manage all project EC2s as a group

# ── Output Tailscale admin URL for convenience ─────────────────────────
output "tailscale_admin_url" {
  description = "Check your Tailscale machines here after deployment"
  value       = "https://login.tailscale.com/admin/machines"
}

output "tailscale_setup_instructions" {
  description = "Steps to get Tailscale IPs after terraform apply"
  value       = <<-TXT
    After terraform apply completes:
    1. Go to https://login.tailscale.com/admin/machines
    2. Find your 4 new machines (aws-mgmt, aws-rocky1, aws-rocky2, aws-ubuntu1)
    3. Note their 100.x.x.x IPs
    4. Update inventory/hosts_aws_ts.ini with those IPs
    5. GitHub Actions will use those IPs directly (no ProxyJump)
  TXT
}
