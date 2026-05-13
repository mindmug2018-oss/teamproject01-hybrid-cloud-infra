# project1-onpremise

## 구성
- proj-mgmt  (192.168.61.133): HAProxy + Ansible + 모니터링 스택
- proj-rocky1 (192.168.61.134): Nginx + FastAPI
- proj-rocky2 (192.168.61.135): Nginx + FastAPI
- proj-ubuntu1 (192.168.61.136): PostgreSQL

## 기술 스택
Ansible · Prometheus · Grafana · AlertManager · FastAPI · PostgreSQL · HAProxy · Cloudflared

## 실행
ansible-playbook -i inventory/hosts.ini playbooks/site.yml
