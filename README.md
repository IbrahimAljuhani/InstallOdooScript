# 🚀 InstallOdooScript — Professional Multi‑Instance Odoo Manager

[![Ubuntu 22.04+](https://img.shields.io/badge/Ubuntu-22.04%2B-333333?logo=ubuntu)](https://ubuntu.com/)
[![Odoo 16-19](https://img.shields.io/badge/Odoo-16.0%20%7C%2017.0%20%7C%2018.0%20%7C%2019.0-00A09D?logo=odoo)](https://www.odoo.com/)
[![Bash](https://img.shields.io/badge/Bash-Automation-black?logo=gnu-bash)]
[![Systemd](https://img.shields.io/badge/Systemd-Service-critical)]
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Production Ready](https://img.shields.io/badge/Status-Production%20Ready-brightgreen)](#production-ready)

A **robust, production‑grade Bash automation toolkit** to deploy, manage, and safely remove **multiple isolated Odoo instances** on Ubuntu 22.04+.

Designed for **DevOps engineers, system administrators, hosting providers, and enterprise environments**.

🔗 GitHub Repository  
https://github.com/IbrahimAljuhani/InstallOdooScript

---

# ✨ Professional Features

## 🧩 Configuration‑First Architecture

Follows a predictable 3‑phase workflow:

Gather → Validate → Execute

Benefits:
- No mid‑installation surprises
- Full summary before execution
- Fail‑fast validation
- CI/CD friendly
- Similar UX to Terraform & Docker Compose

---

## ⚙️ Multi‑Mode Execution

| Mode | Use Case | Example |
|-------|-----------|-----------|
| Interactive | Manual safe installation | sudo ./install_odoo.sh |
| Non‑Interactive | Automation / CI/CD | --non-interactive ... |
| Dry‑Run | Simulation only | --dry-run ... |

---

## 🔒 Enhanced Security

- Per‑instance Linux user isolation
- Dedicated PostgreSQL roles
- Config permissions 640
- Secrets file 600
- Automatic internal port closure with Nginx
- Triple validation before deletion
- Mandatory manual confirmation
- Optional automatic backup

---

## 📦 Full Environment Support

| Environment | Supported |
|--------------|------------|
| Fresh servers | ✅ |
| Existing servers | ✅ |
| Internal networks | ✅ |
| Air‑gapped environments | ✅ |

---

## 🌐 Full WebSocket & POS Support

- /websocket endpoint
- /longpolling endpoint
- Live chat
- IoT devices
- POS real‑time sync
- Kitchen displays
- Offline POS

---

# 📜 Scripts Included

| Script | Purpose |
|-----------|-------------|
| install_odoo.sh | Install new Odoo instance |
| delete_odoo.sh | Safe deletion tool |

---

# 🚀 Quick Start

## 1) Download

wget https://raw.githubusercontent.com/IbrahimAljuhani/InstallOdooScript/main/install_odoo.sh -O install_odoo.sh
wget https://raw.githubusercontent.com/IbrahimAljuhani/InstallOdooScript/main/delete_odoo.sh -O delete_odoo.sh
chmod +x install_odoo.sh delete_odoo.sh

---

## 2) Interactive Installation

sudo ./install_odoo.sh

Process:
- Version selection
- Instance name
- Port
- Nginx option
- SSL option
- Summary confirmation
- Automatic deployment

---

## 3) Non‑Interactive (Automation)

sudo ./install_odoo.sh   --non-interactive   --instance prod   --version 18.0   --port 8069   --nginx   --domain example.com   --ssl   --email admin@example.com

---

## 4) Dry‑Run Simulation

sudo ./install_odoo.sh --dry-run --instance test --version 18.0 --port 8070

Output example:
[DRY RUN] Would install system packages
[DRY RUN] Would create PostgreSQL user
[DRY RUN] Would clone Odoo
[DRY RUN] No changes were made

---

## 5) Safe Deletion

sudo ./delete_odoo.sh

- Lists instances
- Requires typing exact name
- Optional backup
- Generates deletion report

---

# 📊 Automatic Manifest Example

Each installation creates:

/root/odoo-installs/instance_manifest.json

{
  "instance_name": "prod",
  "odoo_version": "18.0",
  "http_port": 8069,
  "nginx_enabled": true,
  "ssl_enabled": true,
  "installation_date": "2026-02-09T14:30:22"
}

---

# 📂 Post‑Installation Structure

/
├── odoo-prod/
│   ├── odoo-prod-server/
│   └── custom/addons/
├── /var/log/odoo-prod/
├── /etc/odoo-prod-server.conf
├── /etc/systemd/system/odoo-prod-server.service
├── /etc/nginx/sites-available/odoo-prod
└── /root/
    ├── odoo-secrets.txt
    ├── odoo-installs/
    └── odoo-backups/

---

# 🔧 Useful Commands

systemctl status odoo-prod-server
journalctl -u odoo-prod-server -f
systemctl restart odoo-prod-server

---

# production-ready

This toolkit is designed for:

- Multi‑tenant hosting
- Enterprise ERP
- Production workloads
- Automation pipelines

---

# 👨‍💻 Author

Ibrahim Aljuhani  
DevOps‑focused Odoo automation tools

---

# 📄 License

MIT License
