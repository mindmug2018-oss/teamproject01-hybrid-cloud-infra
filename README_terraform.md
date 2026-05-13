# Hybrid Cloud — Terraform Setup Guide

This folder provisions the AWS side of your hybrid infrastructure,
mirroring the on-premise VMware topology exactly.

## Architecture

```
Internet
    │
    ▼
[ ALB :80 ]  ──────────────── public subnets (2 AZs)
    │
    ├──▶ [ rocky1 :80 ] Nginx → FastAPI :8000 (Docker)   ─── private subnet AZ-a
    └──▶ [ rocky2 :80 ] Nginx → FastAPI :8000 (Docker)   ─── private subnet AZ-b
                                        │
                                        ▼
                              [ ubuntu1 :5432 ] PostgreSQL  ─ private subnet AZ-a

[ mgmt (public) ]
  • Ansible control node (SSH jump to private instances)
  • HAProxy :80/:8404 (internal LB — mirrors on-prem mgmt)
  • Prometheus :9090
  • Grafana    :3000
  • AlertManager :9093
  • Node Exporter scrapes all 4 instances
```

## On-Prem ↔ AWS IP Mapping

| Role    | On-Prem VMware      | AWS            |
|---------|---------------------|----------------|
| mgmt    | 192.168.61.133      | public IP (output) |
| rocky1  | 192.168.61.134      | private IP (output) |
| rocky2  | 192.168.61.135      | private IP (output) |
| ubuntu1 | 192.168.61.136      | private IP (output) |

## Prerequisites

1. AWS CLI configured: `aws configure`
2. Terraform ≥ 1.5 installed
3. Your SSH public key derived from the existing .pem:
   ```bash
   ssh-keygen -y -f ~/.ssh/teamproj01ansiblekey.pem \
     > ~/.ssh/teamproj01ansiblekey.pub
   ```

## Step 1 — Configure variables

Edit `terraform.tfvars`:
- Set `admin_cidr` to your actual public IP (`curl ifconfig.me`)
- Verify AMI IDs are still current (see comments in variables.tf)

## Step 2 — Deploy AWS infrastructure

```bash
cd terraform-hybrid
terraform init
terraform plan        # review what will be created
terraform apply       # type 'yes' to confirm
```

## Step 3 — Generate Ansible inventory

```bash
terraform output -raw ansible_inventory > ../inventory/hosts_aws.ini
```

## Step 4 — Update Prometheus config

```bash
terraform output prometheus_scrape_targets
# Copy the IPs into monitoring/prometheus_aws.yml
# replacing the PLACEHOLDER values
```

## Step 5 — Deploy with Ansible

```bash
cd ..   # back to project root
# SSH to mgmt first to confirm connectivity
ssh -i ~/.ssh/teamproj01ansiblekey.pem user1@$(terraform -chdir=terraform-hybrid output -raw mgmt_public_ip)

# Then run the playbook from mgmt
ansible-playbook playbooks/site.yml -i inventory/hosts_aws.ini
```

## Step 6 — Verify

```bash
# ALB health check
curl http://$(terraform -chdir=terraform-hybrid output -raw alb_dns_name)/health

# Grafana dashboard
open http://$(terraform -chdir=terraform-hybrid output -raw mgmt_public_ip):3000
# default login: admin / admin123
```

## Teardown

```bash
terraform destroy
```
