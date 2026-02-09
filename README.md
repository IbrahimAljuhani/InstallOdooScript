# 🚀 Odoo Multi‑Instance Manager (Professional Edition)

[![Ubuntu 22.04+](https://img.shields.io/badge/Ubuntu-22.04%2B-333333?logo=ubuntu)](https://ubuntu.com/)
[![Odoo 16-19](https://img.shields.io/badge/Odoo-16.0%20%7C%2017.0%20%7C%2018.0%20%7C%2019.0-00A09D?logo=odoo)](https://www.odoo.com/)
[![Bash](https://img.shields.io/badge/Bash-Automation-black?logo=gnu-bash)]
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Status: Production Ready](https://img.shields.io/badge/Status-Production%20Ready-brightgreen)](#production-ready)

> Enterprise‑grade Bash automation toolkit to install, manage, and safely remove multiple isolated Odoo instances on Ubuntu servers.

---

## ✨ Features

### Installer (install_odoo.sh)
- Odoo 16 → 19
- Interactive / Non‑interactive / Dry‑run
- PostgreSQL 15 + Node.js 20
- Python virtualenv
- systemd service
- Hardened Nginx + SSL
- Manifest + secrets file
- Port conflict detection

### Deletion Tool (delete_odoo.sh)
- Auto detect instances
- Backup before delete
- Dry‑run preview
- Full cleanup (user, db, logs, nginx, service)
- Audit log

---

## 🚀 Quick Start

```bash
wget https://raw.githubusercontent.com/IbrahimAljuhani/InstallOdooScript/main/install_odoo.sh
chmod +x install_odoo.sh
sudo ./install_odoo.sh
```

---

## 📂 Paths

| Item | Location |
|------|-------------------------------|
| Config | /etc/<instance>-server.conf |
| Logs | /var/log/<instance>/ |
| Code | /<instance>/<instance>-server |
| Addons | /<instance>/custom/addons |
| Secrets | /root/odoo-secrets.txt |

---

## 🔐 Security
- Per‑instance Linux user
- Dedicated DB role
- SSL support
- Firewall rules
- Safe backups

---

## 👨‍💻 Author
Ibrahim Aljuhani

MIT License
