#!/bin/bash
# 사용법: ./restart_service.sh [host] [service]
HOST=$1
SERVICE=$2
KEY="/home/user1/.ssh/project.pem"

echo "[$(date '+%H:%M:%S')] 복구 시도: $SERVICE @ $HOST"
ssh -i $KEY -o StrictHostKeyChecking=no user1@$HOST \
  "sudo systemctl restart $SERVICE"

if [ $? -eq 0 ]; then
  echo "[$(date '+%H:%M:%S')] 복구 성공: $SERVICE @ $HOST"
else
  echo "[$(date '+%H:%M:%S')] 복구 실패: $SERVICE @ $HOST"
  exit 1
fi