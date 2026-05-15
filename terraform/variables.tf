########################################################################
# variables.tf — updated with Tailscale auth key
########################################################################

variable "aws_region" {
  description = "AWS region. ap-northeast-2 = Seoul."
  type    = string
  default = "ap-northeast-2"
}

variable "project_name" {
  description = "Prefix for all resource names and tags."
  type    = string
  default = "teamproject01"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Two public subnet CIDRs (mgmt node + ALB — ALB requires 2 AZs)."
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Two private subnet CIDRs (app servers + DB)."
  type    = list(string)
  default = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "admin_cidr" {
  description = "Your admin IP in CIDR notation. Set to your real IP before applying."
  type    = string
  default = "0.0.0.0/0"
}

variable "public_key_path" {
  description = "Path to SSH public key (.pub) for EC2 key pair."
  type    = string
  default = "~/.ssh/teamproj01ansiblekey.pub"
}


variable "rocky_ami_id" {
  type        = string
  description = "The AMI ID used to provision Rocky Linux instances"
  default     = "ami-01d0a514d7901594e" 
}



variable "mgmt_instance_type" {
  type    = string
  default = "t4g.small"
}

variable "app_instance_type" {
  type    = string
  default = "t4g.small"
}

variable "db_instance_type" {
  type    = string
  default = "t4g.small"
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook URL for CloudWatch SNS notifications."
  type      = string
  sensitive = true
}

# ── NEW: Tailscale ────────────────────────────────────────────────────
# Get auth key from: https://login.tailscale.com/admin/settings/keys
# Create a reusable key (not one-time) tagged with tag:project1-ec2
# Set via GitHub secret TS_AUTH_KEY, passed as -var at apply time

variable "tailscale_auth_key" {
  description = "Tailscale reusable auth key for EC2 instances to join the network on boot"
  type        = string
  sensitive   = true
}
