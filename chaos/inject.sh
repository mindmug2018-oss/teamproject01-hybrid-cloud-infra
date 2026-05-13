#!/bin/bash
# Chaos Engineering Injection Script - Dynamic AWS Version
# Usage: ./inject.sh [scenario]

# --- 1. Dynamic IP Discovery ---
# This pulls the 'ansible_host' for each node from your Ansible inventory
# Requires 'jq' installed: sudo dnf install jq -y
PROJECT_DIR="/home/user1/project1-onpremise"

# Check for AWS flag
# --- 1. Path Configuration ---
# Absolute path to your project's inventory folder
INV_DIR="/home/user1/project1-onpremise/inventory"

# --- 2. Environment Toggle ---
if [[ "$*" == *"--aws"* ]]; then
    INV_FILE="$INV_DIR/hosts_aws.ini"
    MODE="AWS-EC2"
    # Update this to where your .pem file actually lives
    KEY_PATH="/home/user1/project1-onpremise/your-aws-key.pem"
else
    INV_FILE="$INV_DIR/hosts.ini"
    MODE="ON-PREMISE"
    KEY_PATH=""
fi

echo "------------------------------------------------"
echo "  CHAOS MODE: $MODE"
echo "  USING FILE: $INV_FILE"
echo "------------------------------------------------"

# --- 3. IP Discovery ---
# Fetch IPs using the full path to the inventory file
IP_MGMT=$(sed -n '/\[mgmt\]/,/\[/p' "$INV_FILE" | grep -E '^[0-9]' | sed -n '1p' | awk '{print $1}')
IP_ROCKY1=$(sed -n '/\[rocky\]/,/\[/p' "$INV_FILE" | grep -E '^[0-9]' | sed -n '1p' | awk '{print $1}')
IP_ROCKY2=$(sed -n '/\[rocky\]/,/\[/p' "$INV_FILE" | grep -E '^[0-9]' | sed -n '2p' | awk '{print $1}')
IP_UBUNTU=$(sed -n '/\[ubuntu\]/,/\[/p' "$INV_FILE" | grep -E '^[0-9]' | sed -n '1p' | awk '{print $1}')

# Also, update your Key Path based on your hosts_aws.ini:
if [[ "$*" == *"--aws"* ]]; then
    KEY_PATH="/home/user1/.ssh/teamproj01ansiblekey.pem"
fi

# --- 2. Credentials & Logging ---
SLACK="https://slack.com"
TELEGRAM_TOKEN="8263460077:AAHYulXi7OqeHygQLMg_8pp-cY3zeF2ahfc"
TELEGRAM_CHAT_ID="8646527871"
LOG="/var/log/chaos.log"

# Validate IPs were found
if [[ -z "$IP_ROCKY1" || -z "$IP_ROCKY2" || -z "$IP_UBUNTU" ]]; then
    echo "ERROR: Could not find IPs in Ansible inventory. Check your hosts file!"
    exit 1
fi

notify(){
  echo "[$(date '+%H:%M:%S')] $1" | tee -a $LOG
  [ -n "$SLACK" ] && curl -s -X POST "$SLACK" -H 'Content-type: application/json' --data "{\"text\":\"[AWS-CHAOS] $1\"}" > /dev/null
  [ -n "$TELEGRAM_TOKEN" ] && curl -s -X POST "https://telegram.org{TELEGRAM_TOKEN}/sendMessage" -H 'Content-type: application/json' --data "{\"chat_id\": \"${TELEGRAM_CHAT_ID}\", \"text\": \"[AWS-CHAOS] $1\"}" > /dev/null
}

ssh_cmd() {
  if [[ "$MODE" == "AWS-EC2" ]]; then
    # We use $IP_MGMT instead of the hardcoded IP
    ssh -i "$KEY_PATH" \
        -o ProxyJump="user1@$IP_MGMT" \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=5 \
        "$1" "$2"
  else
    # On-Premise mode
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$1" "$2"
  fi
}

case $1 in
  fastapi1)
    notify "Injecting failure: Stopping FastAPI on $IP_ROCKY1"
    ssh_cmd "$IP_ROCKY1" "sudo docker stop fastapi"
    ;;
  fastapi2)
    notify "Injecting failure: Stopping FastAPI on $IP_ROCKY2"
    ssh_cmd "$IP_ROCKY2" "sudo docker stop fastapi"
    ;;
  nginx1)
    notify "Injecting failure: Killing Nginx on $IP_ROCKY1 (Triggering Self-Heal)"
    # Change 'systemctl stop' to 'pkill'
    ssh_cmd "$IP_ROCKY1" "sudo pkill nginx"
    notify "Done: Nginx should auto-restart within 5 seconds"
    ;;
  nginx2)
    notify "Injecting failure: Killing Nginx on $IP_ROCKY2 (Triggering Self-Heal)"
    # Change 'systemctl stop' to 'pkill'
    ssh_cmd "$IP_ROCKY2" "sudo pkill nginx"
    notify "Done: Nginx should auto-restart within 5 seconds"
    ;;
  db)
    notify "Injecting failure: Stopping PostgreSQL on $IP_UBUNTU"
    ssh_cmd "$IP_UBUNTU" "sudo systemctl stop postgresql"
    ;;
  cpu1)
    notify "Injecting failure: CPU overload on $IP_ROCKY1"
    ssh_cmd "$IP_ROCKY1" "nohup stress --cpu \$(nproc) --timeout 120s > /dev/null 2>&1 &"
    ;;
  haproxy)
    notify "Injecting failure: Stopping HAProxy (local)"
    sudo systemctl stop haproxy
    ;;
  all)
    notify "Starting AWS Cloud Service Recovery"
    ssh_cmd "$IP_ROCKY1" "sudo docker start fastapi && sudo systemctl start nginx"
    ssh_cmd "$IP_ROCKY2" "sudo docker start fastapi && sudo systemctl start nginx"
    ssh_cmd "$IP_UBUNTU" "sudo systemctl start postgresql"
    sudo systemctl start haproxy
    notify "All AWS EC2 services recovered successfully"
    ;;
  
  status)
    echo "=== Full $MODE Service Status ==="
    # Local services (running on mgmt node)
    echo -n "HAProxy:      " && sudo systemctl is-active haproxy
    echo -n "Prometheus:   " && sudo systemctl is-active prometheus
    echo -n "Grafana:      " && sudo systemctl is-active grafana-server
    echo -n "AlertManager: " && sudo systemctl is-active alertmanager
    echo -n "Recovery:     " && sudo systemctl is-active recovery
    
    # Remote Rocky1 services
    echo -n "FastAPI-r1:   " && ssh_cmd "$IP_ROCKY1" "sudo docker inspect -f '{{.State.Status}}' fastapi 2>/dev/null || echo 'not found'"
    echo -n "Nginx-r1:     " && ssh_cmd "$IP_ROCKY1" "sudo systemctl is-active nginx"
    
    # Remote Rocky2 services
    echo -n "FastAPI-r2:   " && ssh_cmd "$IP_ROCKY2" "sudo docker inspect -f '{{.State.Status}}' fastapi 2>/dev/null || echo 'not found'"
    echo -n "Nginx-r2:     " && ssh_cmd "$IP_ROCKY2" "sudo systemctl is-active nginx"
    
    # Remote Ubuntu services
    echo -n "PostgreSQL:   " && ssh_cmd "$IP_UBUNTU" "sudo systemctl is-active postgresql"
    ;;
esac
