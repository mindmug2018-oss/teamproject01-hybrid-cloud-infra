import subprocess, os, logging
from fastapi import FastAPI
from pydantic import BaseModel
from typing import List
from datetime import datetime
import httpx

# 로그 파일 설정
logging.basicConfig(
    filename='/var/log/recovery.log',
    level=logging.INFO,
    format='%(asctime)s %(message)s'
)
log = logging.getLogger(__name__)

app = FastAPI(title="Auto Recovery Webhook Server")
SLACK = os.getenv("SLACK_WEBHOOK_URL", "")
SSH_KEY = "/home/user1/.ssh/project.pem"

# Alert 이름 → 복구할 서비스 매핑
RECOVERY_MAP = {
    "FastAPIDown":     "fastapi",
    "NodeDown":        "node_exporter",
}

# Prometheus job 이름 → 대상 호스트 IP 매핑
HOST_MAP = {
    "fastapi-rocky1": "192.168.61.134",
    "fastapi-rocky2": "192.168.61.135",
    "node-rocky1":    "192.168.61.134",
    "node-rocky2":    "192.168.61.135",
    "node-ubuntu1":   "192.168.61.136",
}

class Alert(BaseModel):
    status: str
    labels: dict
    annotations: dict

class Payload(BaseModel):
    alerts: List[Alert]

@app.post("/alert")
async def handle_alert(payload: Payload):
    for alert in payload.alerts:
        if alert.status != "firing":
            continue

        name    = alert.labels.get("alertname", "")
        job     = alert.labels.get("job", "")
        host    = HOST_MAP.get(job)
        service = RECOVERY_MAP.get(name)

        if not host or not service:
            msg = f"알 수 없는 Alert: {name} / job={job} — 수동 확인 필요"
            log.warning(msg)
            await notify(f"UNKNOWN {msg}")
            continue

        ts = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        log.info(f"복구 시작: {name} | {service}@{host} | {ts}")
        await notify(f"자동복구 시작: *{name}*\n서버: {host} | 서비스: {service} | {ts}")

        ok = run_ssh(host, f"sudo systemctl restart {service}")

        if ok:
            msg = f"복구 완료 ✅: {name} | {service}@{host}"
        else:
            msg = f"복구 실패 ❌: {name} | {service}@{host} — 수동 개입 필요"

        log.info(msg)
        await notify(msg)

    return {"ok": True}

@app.get("/health")
def health():
    return {"status": "ok", "server": "recovery-webhook"}

def run_ssh(host: str, cmd: str) -> bool:
    try:
        result = subprocess.run(
            [
                "ssh", "-i", SSH_KEY,
                "-o", "StrictHostKeyChecking=no",
                "-o", "ConnectTimeout=10",
                f"user1@{host}", cmd
            ],
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode != 0:
            log.error(f"SSH 오류: {result.stderr.strip()}")
        return result.returncode == 0
    except Exception as e:
        log.error(f"SSH 예외: {e}")
        return False

async def notify(msg: str):
    if not SLACK:
        return
    try:
        async with httpx.AsyncClient() as c:
            await c.post(SLACK, json={"text": msg}, timeout=5)
    except Exception as e:
        log.error(f"Slack 알림 실패: {e}")