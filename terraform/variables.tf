########################################################################
# variables.tf
########################################################################

variable "aws_region" {
  description = "AWS region. ap-northeast-2 = Seoul, closest to on-prem."
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Prefix for all resource names and tags."
  type        = string
  default     = "project1"
}

# ── Network ────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Two public subnet CIDRs (mgmt node + ALB — ALB requires 2 AZs)."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Two private subnet CIDRs (app servers + DB)."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "admin_cidr" {
  description = <<-EOT
    Your admin/office IP in CIDR notation (e.g. 203.0.113.5/32).
    This IP gets SSH + monitoring dashboard access to the mgmt node.
    IMPORTANT: Change this from 0.0.0.0/0 before applying in production.
  EOT
  type        = string
  default     = "0.0.0.0/0"   # <-- replace with your actual IP
}

# ── SSH Key ────────────────────────────────────────────────────────────

variable "public_key_path" {
  description = <<-EOT
    Path to the SSH PUBLIC key file (.pub) for the Ansible key pair.
    Generate from your existing .pem with:
      ssh-keygen -y -f ~/.ssh/teamproj01ansiblekey.pem > ~/.ssh/teamproj01ansiblekey.pub
  EOT
  type        = string
  default     = "~/.ssh/teamproj01ansiblekey.pub"
}

# ── AMI IDs  (ap-northeast-2) ─────────────────────────────────────────
# Always verify AMI IDs before applying — they change with new releases.
#
# Find latest Rocky Linux 9:
#   aws ec2 describe-images \
#     --owners 679593333241 \
#     --filters "Name=name,Values=Rocky-9*" "Name=architecture,Values=x86_64" \
#     --query 'sort_by(Images,&CreationDate)[-1].ImageId' \
#     --region ap-northeast-2
#
# Find latest Ubuntu 22.04:
#   aws ec2 describe-images \
#     --owners 099720109477 \
#     --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64*" \
#     --query 'sort_by(Images,&CreationDate)[-1].ImageId' \
#     --region ap-northeast-2

variable "rocky_ami_id" {
  description = "AMI ID for Rocky Linux 9 in ap-northeast-2."
  type        = string
  default     = "ami-06cb9ab78bd10073b"
}

variable "ubuntu_ami_id" {
  description = "AMI ID for Ubuntu 22.04 LTS in ap-northeast-2."
  type        = string
  default     = "ami-0d555a33c84ad995c"
}

# ── Instance Types ─────────────────────────────────────────────────────

variable "mgmt_instance_type" {
  description = "EC2 type for mgmt node (HAProxy + Ansible + Prometheus + Grafana)."
  type        = string
  default     = "t3.small"
}

variable "app_instance_type" {
  description = "EC2 type for rocky1 and rocky2 (FastAPI Docker + Nginx)."
  type        = string
  default     = "t3.small"
}

variable "db_instance_type" {
  description = "EC2 type for ubuntu1 (PostgreSQL)."
  type        = string
  default     = "t3.small"
}
