########################################################################
# main.tf — Hybrid Cloud Infrastructure
#
# Mirrors the on-premise VMware topology on AWS:
#
#  On-Prem (VMware)                AWS (this file)
#  ─────────────────                ──────────────────────────────────
#  mgmt  192.168.61.133  ←→  aws_mgmt   (public subnet, HAProxy + Ansible)
#  rocky1 192.168.61.134 ←→  aws_rocky1 (private subnet, FastAPI + Nginx)
#  rocky2 192.168.61.135 ←→  aws_rocky2 (private subnet, FastAPI + Nginx)
#  ubuntu1 192.168.61.136 ←→ aws_ubuntu1 (private subnet, PostgreSQL)
#
# After `terraform apply`, copy the outputs into inventory/hosts_aws.ini
# and run:  ansible-playbook playbooks/site.yml -i inventory/hosts_aws.ini
########################################################################

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# 🌟 DYNAMIC LOOKUP FOR OFFICIAL ROCKY LINUX 9 (ARM64)
data "aws_ami" "official_rocky9" {
  most_recent = true
  owners      = ["679593333241"] 

  filter {
    name   = "name"
    # ⬇️ CHANGED FILTER TO LOOK FOR THE OFFICIAL ARM64 BUILD TYPE
    values = ["Rocky-9-EC2-Base-9.*.aarch64*"] 
  }

  filter {
    name   = "architecture"
    # ⬇️ MATCHES YOUR ARM64 EC2 INSTANCE HARDWARE
    values = ["arm64"] 
  }
}

# 🌟 DYNAMIC LOOKUP FOR OFFICIAL UBUNTU 24.04 (ARM64)
data "aws_ami" "official_ubuntu24" {
  most_recent = true
  owners      = ["099720109477"] 

  filter {
    name   = "name"
    # ⬇️ CHANGED PATTERN TO EXTRACT THE OFFICIAL ARM64 BUILD REGISTRY
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }

  filter {
    name   = "architecture"
    # ⬇️ MATCHES YOUR ARM64 EC2 INSTANCE HARDWARE
    values = ["arm64"] 
  }
}

########################################################################
# DATA SOURCES
########################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

########################################################################
# VPC
########################################################################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, { Name = "${var.project_name}-vpc" })
}

########################################################################
# INTERNET GATEWAY
########################################################################

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "${var.project_name}-igw" })
}

########################################################################
# SUBNETS
########################################################################

# Public subnets — mgmt node + ALB (needs 2 AZs for ALB requirement)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-${count.index + 1}"
    Tier = "public"
  })
}

# Private subnets — app servers + DB (no direct internet exposure)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-${count.index + 1}"
    Tier = "private"
  })
}

########################################################################
# NAT GATEWAY  (private instances need outbound internet for yum/apt/pip)
########################################################################

resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
  tags       = merge(local.common_tags, { Name = "${var.project_name}-nat-eip" })
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = merge(local.common_tags, { Name = "${var.project_name}-nat" })
  depends_on    = [aws_internet_gateway.igw]
}

########################################################################
# ROUTE TABLES
########################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = merge(local.common_tags, { Name = "${var.project_name}-public-rt" })
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = merge(local.common_tags, { Name = "${var.project_name}-private-rt" })
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

########################################################################
# SECURITY GROUPS
########################################################################

# ALB — HTTP/HTTPS from internet
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "ALB: HTTP/HTTPS inbound from internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.common_tags, { Name = "${var.project_name}-alb-sg" })
}

# Mgmt — SSH from your admin IP; monitoring ports from admin IP
resource "aws_security_group" "mgmt" {
  name        = "${var.project_name}-mgmt-sg"
  description = "Mgmt/Bastion: SSH + monitoring dashboards from admin"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }
  ingress {
    description = "Prometheus from admin"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }
  ingress {
    description = "Grafana from admin"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }
  ingress {
    description = "AlertManager from admin"
    from_port   = 9093
    to_port     = 9093
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }
  ingress {
    description = "HAProxy stats from admin"
    from_port   = 8404
    to_port     = 8404
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }
  ingress {
  description = "Tailscale UDP"
  from_port   = 41641
  to_port     = 41641
  protocol    = "udp"
  cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.common_tags, { Name = "${var.project_name}-mgmt-sg" })
}

# App (Rocky) — HTTP from ALB; SSH + metrics from mgmt
resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "App servers: HTTP from ALB, SSH/metrics from mgmt"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  ingress {
    description     = "FastAPI direct (Ansible health checks)"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.mgmt.id]
  }
  ingress {
    description     = "SSH from mgmt"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.mgmt.id]
  }
  ingress {
  description = "SSH from Tailscale"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["100.64.0.0/10"]
  }
  ingress {
    description     = "Node Exporter from mgmt (Prometheus scrape)"
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    security_groups = [aws_security_group.mgmt.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.common_tags, { Name = "${var.project_name}-app-sg" })
}

# DB (Ubuntu/PostgreSQL) — 5432 from app; SSH + metrics from mgmt
resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "DB: PostgreSQL from app servers, SSH/metrics from mgmt"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from app servers"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
  ingress {
    description     = "SSH from mgmt"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.mgmt.id]
  }
  ingress {
  description = "SSH from Tailscale"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["100.64.0.0/10"]
  }
  ingress {
    description     = "Node Exporter from mgmt"
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    security_groups = [aws_security_group.mgmt.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.common_tags, { Name = "${var.project_name}-db-sg" })
}

########################################################################
# KEY PAIR  (uses the same .pem already used on-prem)
########################################################################

resource "aws_key_pair" "ansible" {
  key_name   = "${var.project_name}-key"
  public_key = file(var.public_key_path)
  tags       = merge(local.common_tags, { Name = "${var.project_name}-key" })
}

########################################################################
# EC2 INSTANCES
########################################################################

# ── mgmt ──────────────────────────────────────────────────────────────
# Public subnet, Rocky Linux.
# Runs: HAProxy, Ansible control node, Prometheus, Grafana, AlertManager.
#
# Tailscale notes:
#   • NOT ephemeral — this node must stay registered as the subnet router.
#   • --advertise-routes exposes the entire VPC CIDR to the tailnet so the
#     GitHub Actions runner (or your laptop) can reach private instances.
#   • --accept-routes lets mgmt reach on-prem nodes via their Tailscale IPs.
resource "aws_instance" "mgmt" {
  ami                         = data.aws_ami.official_rocky9.id
  instance_type               = var.mgmt_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.mgmt.id]
  key_name                    = aws_key_pair.ansible.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # ⬇️ THE ONLY CHANGED PORTION: CLEANLY DELEGATED TO THE EXTERNAL SCRIPT
  user_data = templatefile("${path.module}/mgmt_bootstrap.sh", {
    PUBLIC_KEY_CONTENT = file(var.public_key_path)
    TS_AUTH_KEY        = var.tailscale_auth_key
    VPC_CIDR_BLOCK     = aws_vpc.main.cidr_block
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-mgmt"
    Role = "mgmt"
  })
}

# ── rocky1 ────────────────────────────────────────────────────────────
# Private subnet, Rocky Linux.
# Runs: FastAPI (Docker container), Nginx (host systemd).
#
# Tailscale notes:
#   • Ephemeral is fine here — app nodes don't need a persistent identity.
#   • No --advertise-routes needed; mgmt handles subnet routing.
#   • --accept-routes lets it reach the tailnet (on-prem nodes, mgmt).
resource "aws_instance" "rocky1" {
  ami                    = data.aws_ami.official_rocky9.id
  instance_type          = var.app_instance_type
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = aws_key_pair.ansible.key_name

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # ── Python ────────────────────────────────────────────────────────
    dnf install -y python3 python3-pip

    # ── user1 ─────────────────────────────────────────────────────────
    useradd -m -s /bin/bash user1
    mkdir -p /home/user1/.ssh
    echo "${file(var.public_key_path)}" >> /home/user1/.ssh/authorized_keys
    chown -R user1:user1 /home/user1/.ssh
    chmod 700 /home/user1/.ssh
    chmod 600 /home/user1/.ssh/authorized_keys
    echo "user1 ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/user1

    # ── Tailscale ─────────────────────────────────────────────────────
    curl -fsSL https://tailscale.com/install.sh | sh
    systemctl enable --now tailscaled
    until tailscale status &>/dev/null 2>&1; do sleep 2; done

    tailscale up \
      --authkey="${var.tailscale_auth_key}" \
      --advertise-tags="tag:project1-ec2" \
      --ephemeral \
      --accept-routes \
      --accept-dns=false \
      --hostname="aws-rocky1"
  EOF

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-rocky1"
    Role = "app"
  })
}

# ── rocky2 ────────────────────────────────────────────────────────────
# Private subnet, Rocky Linux (identical to rocky1 for HA).
resource "aws_instance" "rocky2" {
  ami                    = data.aws_ami.official_rocky9.id
  instance_type          = var.app_instance_type
  subnet_id              = aws_subnet.private[1].id
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = aws_key_pair.ansible.key_name

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # ── Python ────────────────────────────────────────────────────────
    dnf install -y python3 python3-pip

    # ── user1 ─────────────────────────────────────────────────────────
    useradd -m -s /bin/bash user1
    mkdir -p /home/user1/.ssh
    echo "${file(var.public_key_path)}" >> /home/user1/.ssh/authorized_keys
    chown -R user1:user1 /home/user1/.ssh
    chmod 700 /home/user1/.ssh
    chmod 600 /home/user1/.ssh/authorized_keys
    echo "user1 ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/user1

    # ── Tailscale ─────────────────────────────────────────────────────
    curl -fsSL https://tailscale.com/install.sh | sh
    systemctl enable --now tailscaled
    until tailscale status &>/dev/null 2>&1; do sleep 2; done

    tailscale up \
      --authkey="${var.tailscale_auth_key}" \
      --advertise-tags="tag:project1-ec2" \
      --ephemeral \
      --accept-routes \
      --accept-dns=false \
      --hostname="aws-rocky2"
  EOF

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-rocky2"
    Role = "app"
  })
}

# ── ubuntu1 ───────────────────────────────────────────────────────────
# Private subnet, Ubuntu.
# Runs: PostgreSQL 17.
#
# Tailscale notes:
#   • Uses apt-based installer (same curl | sh script works on Ubuntu).
#   • Ephemeral is acceptable; Ansible connects via Tailscale IP from mgmt.
resource "aws_instance" "ubuntu1" {
  ami                    = data.aws_ami.official_ubuntu24.id
  instance_type          = var.db_instance_type
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.db.id]
  key_name               = aws_key_pair.ansible.key_name

  root_block_device {
    volume_size           = 30   # extra space for DB data
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e
    export DEBIAN_FRONTEND=noninteractive

    # ── Python ────────────────────────────────────────────────────────
    apt-get update -y
    apt-get install -y python3 python3-full

    # ── user1 ─────────────────────────────────────────────────────────
    useradd -m -s /bin/bash user1
    mkdir -p /home/user1/.ssh
    echo "${file(var.public_key_path)}" >> /home/user1/.ssh/authorized_keys
    chown -R user1:user1 /home/user1/.ssh
    chmod 700 /home/user1/.ssh
    chmod 600 /home/user1/.ssh/authorized_keys
    echo "user1 ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/user1

    # ── Tailscale ─────────────────────────────────────────────────────
    curl -fsSL https://tailscale.com/install.sh | sh
    systemctl enable --now tailscaled
    until tailscale status &>/dev/null 2>&1; do sleep 2; done

    tailscale up \
      --authkey="${var.tailscale_auth_key}" \
      --advertise-tags="tag:project1-ec2" \
      --ephemeral \
      --accept-routes \
      --accept-dns=false \
      --hostname="aws-ubuntu1"
  EOF

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ubuntu1"
    Role = "db"
  })
}

########################################################################
# APPLICATION LOAD BALANCER
# Replaces on-prem HAProxy for external traffic (HAProxy still used
# for internal health-check routing on the mgmt node).
########################################################################

resource "aws_lb" "alb" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = merge(local.common_tags, { Name = "${var.project_name}-alb" })
}

resource "aws_lb_target_group" "app" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, { Name = "${var.project_name}-tg" })
}

resource "aws_lb_target_group_attachment" "rocky1" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.rocky1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "rocky2" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.rocky2.id
  port             = 80
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
