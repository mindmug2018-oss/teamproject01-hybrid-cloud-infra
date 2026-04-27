# project1-onpremise

## 구성
- proj-mgmt  (172.16.1.150): HAProxy + Ansible + 모니터링 스택
- proj-rocky1 (172.16.1.151): Nginx + FastAPI
- proj-rocky2 (172.16.1.152): Nginx + FastAPI
- proj-ubuntu1 (172.16.1.153): PostgreSQL

## 기술 스택
Ansible · Prometheus · Grafana · AlertManager · FastAPI · PostgreSQL · HAProxy · Cloudflared

## 실행
ansible-playbook -i inventory/hosts.ini playbooks/site.yml
