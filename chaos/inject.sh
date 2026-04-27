#!/bin/bash
# 장애 주입 스크립트
# 사용법: ./inject.sh [시나리오]
# 시나리오: fastapi1 | fastapi2 | nginx1 | nginx2 | db | cpu1 | haproxy | all

SLACK="${SLACK_WEBHOOK_URL}"
LOG="/var/log/chaos.log"

notify(){
  echo "[$(date '+%H:%M:%S')] $1" | tee -a $LOG
  [ -n "$SLACK" ] && curl -s -X POST "$SLACK" \
    -H 'Content-type: application/json' \
    --data "{\"text\":\"[CHAOS] $1\"}" > /dev/null
}

case $1 in
  fastapi1)
    notify "장애 주입 시작: proj-rocky1 FastAPI 중지"
    ssh 172.16.1.151 "sudo systemctl stop fastapi"
    notify "완료: 30초 후 FastAPIDown Alert 발생 예정"
    ;;

  fastapi2)
    notify "장애 주입 시작: proj-rocky2 FastAPI 중지"
    ssh 172.16.1.152 "sudo systemctl stop fastapi"
    notify "완료: 30초 후 FastAPIDown Alert 발생 예정"
    ;;

  nginx1)
    notify "장애 주입 시작: proj-rocky1 Nginx 중지"
    ssh 172.16.1.151 "sudo systemctl stop nginx"
    ;;

  nginx2)
    notify "장애 주입 시작: proj-rocky2 Nginx 중지"
    ssh 172.16.1.152 "sudo systemctl stop nginx"
    ;;

  db)
    notify "장애 주입 시작: proj-ubuntu1 PostgreSQL 중지"
    ssh 172.16.1.153 "sudo systemctl stop postgresql"
    notify "완료: 1분 후 NodeDown Alert 발생 예정"
    ;;

  cpu1)
    notify "장애 주입 시작: proj-rocky1 CPU 과부하 (120초)"
    ssh 172.16.1.151 \
      "nohup stress-ng --cpu 2 --timeout 120s > /dev/null 2>&1 &"
    notify "완료: 5분 후 HighCPU Alert 발생 예정"
    ;;

  haproxy)
    notify "장애 주입 시작: HAProxy 중지 (로드밸런서 다운)"
    sudo systemctl stop haproxy
    ;;

  all)
    notify "전체 서비스 복구 시작"
    ssh 172.16.1.151 "sudo systemctl start fastapi nginx" && \
      notify "rocky1 fastapi+nginx 복구 완료"
    ssh 172.16.1.152 "sudo systemctl start fastapi nginx" && \
      notify "rocky2 fastapi+nginx 복구 완료"
    ssh 172.16.1.153 "sudo systemctl start postgresql" && \
      notify "ubuntu1 postgresql 복구 완료"
    sudo systemctl start haproxy && \
      notify "haproxy 복구 완료"
    notify "전체 복구 완료"
    ;;

  status)
    echo "=== 전체 서비스 상태 ==="
    echo -n "HAProxy:      " && sudo systemctl is-active haproxy
    echo -n "FastAPI-r1:   " && ssh 172.16.1.151 "systemctl is-active fastapi"
    echo -n "Nginx-r1:     " && ssh 172.16.1.151 "systemctl is-active nginx"
    echo -n "FastAPI-r2:   " && ssh 172.16.1.152 "systemctl is-active fastapi"
    echo -n "Nginx-r2:     " && ssh 172.16.1.152 "systemctl is-active nginx"
    echo -n "PostgreSQL:   " && ssh 172.16.1.153 "systemctl is-active postgresql"
    echo -n "Prometheus:   " && sudo systemctl is-active prometheus
    echo -n "Grafana:      " && sudo systemctl is-active grafana-server
    echo -n "AlertManager: " && sudo systemctl is-active alertmanager
    echo -n "Recovery:     " && sudo systemctl is-active recovery
    ;;

  *)
    echo "사용법: $0 [fastapi1|fastapi2|nginx1|nginx2|db|cpu1|haproxy|all|status]"
    exit 1
    ;;
esac