# InstallOdooScript — Professional Multi-Instance Manager

[![Ubuntu 22.04+](https://img.shields.io/badge/Ubuntu-22.04%2B-333333?logo=ubuntu)](https://ubuntu.com/)
[![Odoo 16–19](https://img.shields.io/badge/Odoo-16.0%20|%2017.0%20|%2018.0%20|%2019.0-00A09D?logo=odoo)](https://www.odoo.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-3.0.0-blueviolet)](#)
[![Production Ready](https://img.shields.io/badge/Status-Production%20Ready-brightgreen)](#)

> **Production-grade Bash toolkit** to install, manage, and safely remove multiple isolated Odoo instances on Ubuntu servers — engineered for DevOps teams and enterprise environments.

🔗 **GitHub Repository**: [https://github.com/IbrahimAljuhani/InstallOdooScript](https://github.com/IbrahimAljuhani/InstallOdooScript)

---

## ✨ Why This Toolkit?

Unlike basic installation scripts, this toolkit implements **professional DevOps practices**:

✅ **Configuration-First Architecture** — Gather all inputs → Validate → Execute (no mid-installation surprises)  
✅ **Three Operating Modes** — Interactive wizard, Non-interactive CI/CD, and Dry-run simulation  
✅ **Triple-Layer Security** — Isolated system users, PostgreSQL roles, and Nginx hardening  
✅ **Full Lifecycle Management** — Install, inspect, back up, and safely delete instances  
✅ **Zero Leftover Artifacts** — Deletion cleans everything: code, DB, logs, Nginx cache, manifests  
✅ **Gevent Compatibility Fix** — Automatically pins `gevent==23.9.1` for Odoo 16–18  

---

## 📦 Included Tools

| Script | Version | Purpose | Key Features |
|--------|---------|---------|--------------|
| `install_odoo.sh` | v3.0.0 | Install new instances | Interactive wizard, non-interactive mode, dry-run, manifest generation, master password terminal display |
| `delete_odoo.sh` | v3.0.0 | Safely remove instances | 4-artifact validation, smart backup, Nginx cache cleanup, WebSocket map cleanup, no `eval` |

---

## 🚀 Quick Start

### 1. Download the Toolkit

```bash
# Download installation script
wget https://raw.githubusercontent.com/IbrahimAljuhani/InstallOdooScript/main/install_odoo.sh

# Download deletion script
wget https://raw.githubusercontent.com/IbrahimAljuhani/InstallOdooScript/main/delete_odoo.sh

# Make executable
chmod +x install_odoo.sh delete_odoo.sh
```

### 2. Install Interactively (Recommended)

```bash
sudo ./install_odoo.sh
```

The wizard walks you through 5 steps:

1. **Instance name** — validated, conflict-checked, with optional cleanup of existing instances
2. **Odoo version** — choose from 16.0 → 19.0
3. **Port configuration** — auto-detects conflicts on both HTTP and Longpolling ports
4. **Nginx + SSL setup** — optional but recommended for production
5. **Visual summary** — review everything before final confirmation

### 3. Install Non-Interactively (CI/CD)

```bash
sudo ./install_odoo.sh --non-interactive \
  --instance prod \
  --version 18.0 \
  --port 8069 \
  --nginx \
  --domain example.com \
  --ssl \
  --email admin@example.com
```

### 4. Dry-Run Simulation (Safe Testing)

```bash
sudo ./install_odoo.sh --dry-run --instance test --version 18.0 --port 8069
```

Simulates the full installation flow without touching the system. Every step prints `[DRY RUN] Would execute: ...`.

---

## 🗑️ Deleting an Instance

### Interactive (shows a numbered menu of all detected instances)

```bash
sudo ./delete_odoo.sh
```

### Non-Interactive

```bash
# Safe deletion with automatic backup
sudo ./delete_odoo.sh --instance prod --backup --force

# Preview what would be deleted — no changes made
sudo ./delete_odoo.sh --instance prod --dry-run
```

---

## ⚙️ All CLI Options

### `install_odoo.sh`

| Option | Description |
|--------|-------------|
| *(no flags)* | Launch interactive wizard |
| `--non-interactive` | Skip all prompts (requires `--instance` and `--version`) |
| `--dry-run` | Simulate full installation without changes |
| `--instance <name>` | Instance name (lowercase, letters/digits/hyphens/underscores) |
| `--version <ver>` | Odoo version: `19.0` \| `18.0` \| `17.0` \| `16.0` |
| `--port <port>` | HTTP port (default: `8069`; Longpolling = port + 3) |
| `--nginx` | Enable Nginx reverse proxy |
| `--domain <domain>` | Domain name for Nginx (defaults to server IP) |
| `--ssl` | Enable Let's Encrypt SSL via Certbot |
| `--email <email>` | Email for SSL certificate notifications |
| `--help`, `-h` | Show help message |

### `delete_odoo.sh`

| Option | Description |
|--------|-------------|
| *(no flags)* | Launch interactive instance selector |
| `--instance <name>` | Instance name to delete |
| `--backup` | Create full backup before deletion |
| `--force` | Skip confirmation prompt |
| `--dry-run` | Simulate deletion without changes (implies `--force`) |
| `--help`, `-h` | Show help message |

---

## 🏗️ Architecture — Configuration-First Pattern

```
┌─────────────────────────────────────────────────────┐
│               install_odoo.sh Flow                   │
│                                                     │
│  Phase 1: Gather    Phase 2: Validate    Phase 3: Execute
│  ─────────────      ──────────────────   ──────────────
│  Instance name  →   Summary table    →   step_check_tools
│  Odoo version       Confirmation         step_update_system
│  Port (+ LP)        (or auto in          step_install_packages
│  Nginx/SSL          non-interactive)     step_install_nodejs
│                                          step_install_wkhtmltopdf
│                                          step_setup_postgresql
│                                          step_create_pg_user
│                                          step_create_system_user
│                                          step_clone_odoo
│                                          step_create_venv
│                                          step_install_python_deps
│                                          step_create_config
│                                          step_create_service
│                                          step_start_service
│                                          step_configure_nginx  ← optional
│                                          step_generate_manifest
│                                          step_cleanup
└─────────────────────────────────────────────────────┘
```

---

## 📋 Post-Installation File Structure

After installing an instance named `odoo-prod`:

```
/
├── odoo-prod/
│   ├── odoo-prod-server/               # Odoo source code (shallow git clone)
│   │   └── odoo-bin                    # Main executable
│   ├── custom/
│   │   └── addons/                     # Your custom modules (empty initially)
│   └── venv/                           # Isolated Python virtual environment
│
├── var/log/odoo-prod/
│   └── odoo-prod-server.log            # Instance log file
│
├── etc/
│   ├── odoo-prod-server.conf           # Odoo config (permissions: 640)
│   ├── systemd/system/
│   │   └── odoo-prod-server.service    # Systemd service (auto-restart)
│   └── nginx/
│       ├── sites-available/odoo-prod   # Nginx virtual host config
│       ├── sites-enabled/odoo-prod     # Symlink (active)
│       └── conf.d/
│           └── ws_upgrade_map.conf     # Shared WebSocket upgrade map
│
├── var/cache/nginx/
│   └── odoo_static_odoo-prod/          # Nginx static asset cache (2 GB max)
│
└── root/
    ├── odoo-secrets.txt                # Master passwords log (permissions: 600)
    ├── odoo-installs/
    │   └── odoo-prod_20260209_143022_manifest.json
    └── odoo-backups/                   # Automatic backups (if requested)
        ├── odoo-prod_20260209_143022.tar.gz
        └── odoo-prod_db_20260209_143022.sql
```

---

## 🔑 Manifest File

Every installation generates a JSON manifest at `/root/odoo-installs/`:

```json
{
  "instance_name":    "prod",
  "odoo_version":     "18.0",
  "http_port":        8069,
  "longpolling_port": 8072,
  "nginx_enabled":    true,
  "domain":           "example.com",
  "ssl_enabled":      true,
  "ssl_email":        "admin@example.com",
  "server_ip":        "192.168.1.10",
  "installation_date":"2026-02-09T14:30:22+03:00"
}
```

> 🔐 Manifest files are created with `600` permissions (root-only access). Keep them off public storage.

---

## 🔒 Security Model

### Master Password Handling

The master password is:
- **Displayed in the terminal** at the end of installation (highlighted in red)
- **Saved to** `/root/odoo-secrets.txt` with `600` permissions
- **Not included** in the manifest JSON (unlike older versions)

A security reminder is printed before the terminal session ends:

```
⚠  Before leaving this terminal:
   1. Note or copy the master password somewhere safe.
   2. Clear terminal history:  history -c && history -w
```

### Nginx Security Hardening

The generated Nginx config includes:

```nginx
# Block entire database manager path (not just /manager)
location ~* ^/web/database {
    deny all;
    return 403;
}
```

This blocks all sub-paths (`/manager`, `/selector`, `/create`, etc.) at the web server layer — faster and more reliable than application-layer blocking.

**Verify protection is active:**

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost/web/database/manager
# Expected: 403
```

### Port Protection

When Nginx is configured, direct access to the Odoo port is automatically blocked:

```bash
sudo ufw deny <port>
```

---

## 🌐 Nginx Configuration Details

The generated Nginx config includes separate upstreams with `keepalive 32`, a dedicated 2 GB static asset cache zone per instance, full WebSocket support for Bus / Live Chat / Kitchen Screen / IoT, and Longpolling on a dedicated upstream.

```nginx
upstream odoo_prod {
    server 127.0.0.1:8069;
    keepalive 32;
}

upstream odoo_prod_lp {
    server 127.0.0.1:8072;
    keepalive 32;
}

proxy_cache_path /var/cache/nginx/odoo_static_prod
    levels=1:2
    keys_zone=static_prod:100m
    inactive=60m
    max_size=2g;
```

A shared WebSocket upgrade map is written to `/etc/nginx/conf.d/ws_upgrade_map.conf` (created once, shared across all instances). `delete_odoo.sh` automatically removes it only when deleting the last Odoo instance.

---

## 🗑️ What `delete_odoo.sh` Removes

The deletion script validates an instance using **4 required artifacts** before proceeding:

```
✓ /etc/<instance>-server.conf
✓ /etc/systemd/system/<instance>-server.service
✓ /<instance>/<instance>-server/  (directory)
✓ /<instance>/<instance>-server/odoo-bin  (file)
```

If any artifact is missing, the script refuses to run — preventing accidental deletion of non-Odoo users.

**Full cleanup checklist per deletion:**

| Component | Action |
|-----------|--------|
| Odoo service | Stop → SIGKILL → disable → remove service file |
| Config file | `/etc/<instance>-server.conf` removed |
| System user | `userdel -r` + `rm -rf /<instance>` |
| Log directory | `/var/log/<instance>` removed |
| PostgreSQL | Connections terminated → DB dropped → user dropped |
| Nginx site | `sites-available` + `sites-enabled` removed → Nginx reloaded |
| Nginx cache | `/var/cache/nginx/odoo_static_<instance>` removed |
| Manifest files | `/root/odoo-installs/<instance>_*_manifest.json` removed |
| WebSocket map | Removed only if no other Odoo instances remain |

---

## 💾 Backup & Restore

### Backup Before Deletion

```bash
sudo ./delete_odoo.sh --instance prod --backup --force
```

This creates in `/root/odoo-backups/<instance>_<timestamp>/`:

```
home.tar.gz                     # Full home directory compressed
<instance>-server.conf          # Odoo config
<instance>-server.service       # Systemd service
db.sql                          # PostgreSQL full dump
nginx_<instance>                # Nginx virtual host config
<instance>_*_manifest.json      # Installation manifest(s)
```

All files are set to `600` permissions.

### Manual Database Backup

```bash
sudo -u postgres pg_dump <instance> > /root/backup_<instance>_$(date +%Y%m%d).sql
```

### Manual Full Backup

```bash
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
sudo -u postgres pg_dump <instance> > /root/backup_<instance>_db_${TIMESTAMP}.sql
sudo tar -czf /root/backup_<instance>_files_${TIMESTAMP}.tar.gz \
  /<instance> /etc/<instance>-server.conf
```

### Restore from Backup

```bash
sudo systemctl stop <instance>-server
sudo -u postgres psql -d <instance> < /root/backup_<instance>_db_20260209.sql
sudo tar -xzf /root/backup_<instance>_files_20260209.tar.gz -C /
sudo systemctl start <instance>-server
```

---

## 📋 Essential Daily Commands

### Service Management

```bash
# Status
sudo systemctl status <instance>-server

# Start / Stop / Restart
sudo systemctl start <instance>-server
sudo systemctl stop <instance>-server
sudo systemctl restart <instance>-server

# Live logs
sudo journalctl -u <instance>-server -f

# Last 100 lines
sudo journalctl -u <instance>-server -n 100 --no-pager

# Health check (exit 0 = healthy)
sudo systemctl is-active <instance>-server && echo "✅ Healthy" || echo "❌ Down"
```

### Configuration

```bash
# Edit config
sudo nano /etc/<instance>-server.conf

# View master password
sudo grep "master_password" /etc/<instance>-server.conf | awk -F' = ' '{print $2}'

# Rotate master password
NEW_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 20)
sudo sed -i "s/^master_password.*/master_password    = $NEW_PASS/" /etc/<instance>-server.conf
sudo systemctl restart <instance>-server
echo "$(date '+%Y-%m-%d %H:%M:%S')  instance='<instance>'  new_master_password='$NEW_PASS'" \
  | sudo tee -a /root/odoo-secrets.txt
```

### Instance Discovery

```bash
# List all detected Odoo instances (interactive menu)
sudo ./delete_odoo.sh

# Preview deletion without changes
sudo ./delete_odoo.sh --instance <instance> --dry-run
```

---

## 🌐 Nginx & SSL Commands

```bash
# Validate Nginx config (always run before reload)
sudo nginx -t && echo "✅ Config valid"

# Reload without downtime
sudo nginx -t && sudo systemctl reload nginx

# View active sites
ls -la /etc/nginx/sites-enabled/

# Monitor live requests
sudo tail -f /var/log/nginx/<instance>_access.log

# Monitor errors
sudo tail -f /var/log/nginx/<instance>_error.log

# Test SSL renewal (dry-run)
sudo certbot renew --dry-run

# View certificate expiry
sudo certbot certificates

# Verify HTTPS
curl -I https://<domain>/web/login | grep "HTTP"
```

---

## 📊 Performance Monitoring

```bash
# Memory usage for instance
ps aux | grep "odoo.*<instance>" | grep -v grep \
  | awk '{sum+=$6} END {print "Memory (MB): " sum/1024}'

# Active DB connections
sudo -u postgres psql -d <instance> -tAc \
  "SELECT count(*) FROM pg_stat_activity WHERE datname = '<instance>';"

# Database size
sudo -u postgres psql -d <instance> -c \
  "SELECT pg_size_pretty(pg_database_size('<instance>')) AS size;"

# Instance directory size
du -sh /<instance> /var/log/<instance>

# Top 10 largest tables
sudo -u postgres psql -d <instance> -c \
  "SELECT tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
   FROM pg_tables ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC LIMIT 10;"
```

---

## 🔥 Troubleshooting

### Service Fails to Start

```bash
# Check logs
sudo journalctl -u <instance>-server -n 50 --no-pager

# Common causes:
# 1. Port already in use
sudo ss -tulpn | grep :<port>

# 2. PostgreSQL not running
sudo systemctl status postgresql

# 3. Python venv broken
sudo -u <instance> /<instance>/venv/bin/python --version
```

### Nginx Returns 502

```bash
# Check if Odoo is running
sudo systemctl is-active <instance>-server

# Verify proxy_mode is enabled
grep "proxy_mode" /etc/<instance>-server.conf

# Check Nginx upstream config
grep -A3 "upstream odoo_<instance>" /etc/nginx/sites-available/<instance>
```

### WebSocket Not Working (POS / Live Chat)

```bash
# Verify WebSocket map exists
cat /etc/nginx/conf.d/ws_upgrade_map.conf

# Test WebSocket endpoint
curl -i -N \
  -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Host: localhost" http://localhost/websocket 2>&1 | head -5

# Check proxy_mode
grep "proxy_mode" /etc/<instance>-server.conf
# Must output: proxy_mode = True
```

### SSL Certificate Issues

```bash
# Test renewal manually
sudo certbot renew --dry-run --cert-name <domain>

# Check certificate expiry
echo | openssl s_client -connect <domain>:443 2>/dev/null \
  | openssl x509 -noout -dates
```

---

## <img src="https://cdnjs.cloudflare.com/ajax/libs/flag-icons/7.0.0/flags/4x3/sa.svg" width="20"> ZATCA Integration (Saudi Arabia)

```bash
# Verify ZATCA DNS resolution
nslookup gw-fatoora.zatca.gov.sa \
  && echo "✅ DNS OK" || echo "❌ DNS failed — fix /etc/resolv.conf"

# Test ZATCA production endpoint
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  https://gw-fatoora.zatca.gov.sa/e-invoicing/core/compliance

# Test ZATCA sandbox endpoint
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  https://gw-fatoora-uat.zatca.gov.sa/e-invoicing/core/compliance

# Monitor ZATCA-related log entries
sudo journalctl -u <instance>-server -f \
  | grep -i "zatca\|fatoora\|e-invoice"
```

---

## ✅ Production Hardening Checklist

Before going live, verify each item:

```
[ ] Database manager is blocked
    curl -s -o /dev/null -w "%{http_code}" http://localhost/web/database/manager
    → Expected: 403

[ ] Direct port access is blocked (if Nginx is used)
    sudo ufw status | grep <port>
    → Expected: <port> DENY

[ ] Master password file permissions
    stat -c "%a %n" /root/odoo-secrets.txt
    → Expected: 600

[ ] Manifest file permissions
    stat -c "%a %n" /root/odoo-installs/*.json
    → Expected: 600

[ ] SSL certificate is valid and auto-renewing
    sudo certbot certificates
    sudo certbot renew --dry-run

[ ] Firewall rules reviewed
    sudo ufw status verbose

[ ] Automatic OS updates enabled
    sudo dpkg-reconfigure unattended-upgrades

[ ] Log rotation configured
    ls /etc/logrotate.d/

[ ] proxy_mode enabled (required with Nginx)
    grep "proxy_mode" /etc/<instance>-server.conf
    → Expected: proxy_mode = True

[ ] Odoo 19.0 disclaimer acknowledged (beta as of Feb 2026 — use 18.0 for production)
```

---

## 📌 Version Notes

| Odoo Version | Status | Notes |
|---|---|---|
| 19.0 | ⚠️ Beta | Testing only — not recommended for production (as of February 2026) |
| 18.0 | ✅ Stable | Recommended for new production deployments |
| 17.0 | ✅ LTS | Long-term support — safe for existing production |
| 16.0 | ⚠️ Legacy | Approaching end of support |

> **Gevent note:** Odoo 16, 17, and 18 require `gevent==23.9.1`. The installer handles this automatically by removing the version from `requirements.txt` and installing the pinned version separately.

---

## 📁 Key File Locations Reference

| File / Directory | Purpose | Permissions |
|---|---|---|
| `/etc/<instance>-server.conf` | Odoo runtime configuration | `640` |
| `/etc/systemd/system/<instance>-server.service` | Systemd service definition | `644` |
| `/<instance>/<instance>-server/` | Odoo source code | owned by `<instance>` |
| `/<instance>/custom/addons/` | Custom modules directory | owned by `<instance>` |
| `/<instance>/venv/` | Python virtual environment | owned by `<instance>` |
| `/var/log/<instance>/` | Log directory | owned by `<instance>` |
| `/etc/nginx/sites-available/<instance>` | Nginx virtual host | `644` |
| `/var/cache/nginx/odoo_static_<instance>/` | Nginx static cache | owned by `www-data` |
| `/etc/nginx/conf.d/ws_upgrade_map.conf` | Shared WebSocket map | `644` |
| `/root/odoo-secrets.txt` | Master password log | `600` |
| `/root/odoo-installs/` | JSON manifest files | `600` each |
| `/root/odoo-backups/` | Backup archives | `600` each |
| `/root/odoo-deletion-log.txt` | Deletion audit log | `644` |

---

## 👤 Author

**Ibrahim Aljuhani**  
🔗 [github.com/IbrahimAljuhani/InstallOdooScript](https://github.com/IbrahimAljuhani/InstallOdooScript)

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for full terms.
