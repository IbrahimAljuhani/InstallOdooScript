# 🚀 Odoo Multi-Instance Manager — Professional Edition

> Production-grade Bash toolkit to **install, manage, and safely remove multiple isolated Odoo instances** on Ubuntu servers.

Deploy Odoo like a DevOps engineer — clean, secure, repeatable, and fully automated.

---

## 📦 Included Scripts

| Script | Description |
|-------|-------------|
| install_odoo.sh | Install and configure new Odoo instances |
| delete_odoo.sh | Safely remove instances (backup + dry-run supported) |

---

## ✨ Features

### 🔧 Installer — install_odoo.sh

✅ Supports Odoo 16 → 19  
✅ Interactive wizard  
✅ Non-interactive automation (CI/CD ready)  
✅ Dry-run simulation mode  
✅ Isolated Linux user per instance  
✅ Dedicated PostgreSQL database + role  
✅ Python virtual environment  
✅ Systemd service (auto-restart)  
✅ Nginx reverse proxy (production hardened)  
✅ Let's Encrypt SSL  
✅ Auto-generated admin password  
✅ Installation manifest (.json)  
✅ Port conflict detection  
✅ Security hardening (UFW + closed ports)

---

### 🗑 Deletion Tool — delete_odoo.sh

✅ Auto-detect installed instances  
✅ Triple-validation safety checks  
✅ Interactive or non-interactive mode  
✅ Optional backup before deletion  
✅ Dry-run preview  
✅ Full cleanup of:
- service
- user
- home directory
- logs
- database
- nginx config

---

# 🧱 Architecture

Installer follows a professional 3-phase pattern:

Gather → Validate → Execute

This guarantees predictable, safe, and repeatable installations.

---

# 🖥 Requirements

- Ubuntu 22.04+
- Root or sudo access

Automatically installs:
- PostgreSQL 15
- Node.js 20 LTS
- wkhtmltopdf
- Python venv
- Nginx (optional)
- Certbot (optional)

---

# 🚀 Install Odoo

## Download

wget https://raw.githubusercontent.com/IbrahimAljuhani/InstallOdooScript/main/install_odoo.sh
chmod +x install_odoo.sh

---

## Interactive Mode

sudo ./install_odoo.sh

---

## Non‑Interactive Mode

sudo ./install_odoo.sh \
  --non-interactive \
  --instance prod \
  --version 18.0 \
  --port 8069 \
  --nginx \
  --domain example.com \
  --ssl \
  --email admin@example.com

---

## Dry‑Run Mode

sudo ./install_odoo.sh --dry-run --instance test --version 18.0 --port 8070

---

# 📂 Installation Structure

| Item | Location |
|--------|-------------|
| Config | /etc/<instance>-server.conf |
| Logs | /var/log/<instance>/ |
| Code | /<instance>/<instance>-server |
| Custom addons | /<instance>/custom/addons |
| Admin password | /root/odoo-secrets.txt |
| Manifest | /root/odoo-installs/*.json |

---

# 🗑 Delete Odoo Instance

## Interactive

sudo ./delete_odoo.sh

## Non‑Interactive

sudo ./delete_odoo.sh --instance prod --force

## With Backup

sudo ./delete_odoo.sh --instance prod --backup --force

## Dry‑Run

sudo ./delete_odoo.sh --instance prod --dry-run

---

# 🔐 Security Highlights

- Per-instance Linux user isolation
- Dedicated DB roles
- Internal ports closed with Nginx
- SSL support
- Firewall rules applied automatically
- Secure file permissions

---

# 📜 Useful Commands

systemctl status <instance>-server
systemctl restart <instance>-server
journalctl -u <instance>-server -f

---

# 👨‍💻 Author

Ibrahim Aljuhani

Professional DevOps-style Odoo automation toolkit.

---

⭐ Star the repo if it helps you!
