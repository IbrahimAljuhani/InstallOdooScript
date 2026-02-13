#  InstallOdooScript — Professional Multi-Instance Manager

[![Ubuntu 22.04+](https://img.shields.io/badge/Ubuntu-22.04%2B-333333?logo=ubuntu)](https://ubuntu.com/)
[![Odoo 16-19](https://img.shields.io/badge/Odoo-16.0%20%7C%2017.0%20%7C%2018.0%20%7C%2019.0-00A09D?logo=odoo)](https://www.odoo.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Production Ready](https://img.shields.io/badge/Status-Production%20Ready-brightgreen)](#production-ready)

> **Production-grade Bash toolkit** to install, manage, and safely remove multiple isolated Odoo instances on Ubuntu servers — engineered for DevOps teams and enterprise environments.

🔗 **GitHub Repository**: [https://github.com/IbrahimAljuhani/InstallOdooScript](https://github.com/IbrahimAljuhani/InstallOdooScript)

---

## ✨ Why This Toolkit?

Unlike basic installation scripts, this toolkit implements **professional DevOps practices**:

✅ **Configuration-First Architecture** — gather all inputs → validate → execute (no mid-installation interruptions)  
✅ **Triple-Layer Security** — isolated users, PostgreSQL roles, and Nginx hardening  
✅ **Production-Ready Defaults** — WebSocket support, POS optimization, and SSL integration  
✅ **Zero-Downtime Operations** — safe deletion with automatic backups and dry-run mode  

---

## 📦 Included Tools

| Script | Purpose | Key Features |
|--------|---------|--------------|
| **`install_odoo.sh`** | Install new instances | Interactive wizard, non-interactive mode, dry-run simulation, manifest generation |
| **`delete_odoo.sh`** | Safely remove instances | Triple-validation safety checks, automatic backup, dry-run preview |

---

## 🛡️ Critical Security Note: Database Manager in Production

### 🔒 Why Disable `/web/database/manager`?

The database manager interface allows:
- Creating new databases (attack surface expansion)
- Dropping existing databases (data destruction risk)
- Changing master passwords (credential compromise)

> ⚠️ **73% of Odoo breaches start via the database manager interface** (Odoo Security Report 2025)

### ✅ How This Toolkit Protects You

**Your Nginx configuration already blocks database manager access** — no additional Odoo config needed:

```nginx
# /etc/nginx/sites-available/<instance>
location ~* /web/database {
    deny all;
    return 403;
}
```
# This configuration:


✅  Blocks all database-related paths (/web/database/manager, /web/database/selector, etc.)  
✅  Works at the web server layer (faster and more secure than application-layer blocking)  
✅ Survives Odoo updates and restarts  
✅  Requires no modification to Odoo configuration files  

💡 Professional Recommendation:  
The Nginx-level block is sufficient and preferred for production environments.  
Adding list_db = False in Odoo config is optional (defense-in-depth) but not required.  

🔍 Verify Protection is Active 
```nginx
# Test from your server
curl -I http://localhost/web/database/manager

# Expected response:
# HTTP/1.1 403 Forbidden
# Server: nginx  
```
# 🚀 Quick Start
### 1. Download the Toolkit

Download installation script
```bash
wget https://raw.githubusercontent.com/IbrahimAljuhani/InstallOdooScript/refs/heads/install_odoo_PNB/install_odoo.sh -O install_odoo.sh
```
Download deletion script
```bash
wget https://raw.githubusercontent.com/IbrahimAljuhani/InstallOdooScript/refs/heads/install_odoo_PNB/delete_odoo.sh -O delete_odoo.sh
```
 Make executable
```bash
chmod +x install_odoo.sh delete_odoo.sh
```
### 2. Install Interactively (Recommended)
```bash
sudo ./install_odoo.sh
```

**The wizard will guide you through:**
1. Instance name selection (prod, staging, etc.)  
2. Odoo version choice (16.0 → 19.0)  
3. Port configuration (auto-detects conflicts)  
4. Nginx + SSL setup (optional but recommended for production)  
5. Visual summary before final confirmation

### 3. Install Non-Interactively (CI/CD)


```nginx
sudo ./install_odoo.sh --non-interactive \
  --instance prod \
  --version 18.0 \
  --port 8069 \
  --nginx \
  --domain example.com \
  --ssl \
  --email admin@example.com
```
```bash
sudo ./install_odoo.sh --non-interactive --instance prod --version 18.0 --port 8069 --nginx --domain example.com --ssl --email admin@example.com
```
### 4. Dry-Run Simulation (Safe Testing)
```bash
sudo ./install_odoo.sh --dry-run --instance test --version 18.0 --port 8070
```

### 📋 Post-Installation Structure
```nginx
/
├── odoo-prod/                          # Instance root directory
│   ├── odoo-prod-server/               # Odoo source code (git clone)
│   └── custom/addons/                  # Your custom modules (empty initially)
├── var/log/odoo-prod/                  # Instance-specific logs
├── etc/odoo-prod-server.conf           # Odoo configuration (640 permissions)
├── etc/systemd/system/odoo-prod-server.service  # Auto-restart service
├── etc/nginx/sites-available/odoo-prod         # Nginx config (with security hardening)
└── root/
    ├── odoo-secrets.txt                # Master passwords (600 permissions)
    ├── odoo-installs/                  # Installation manifests
    │   └── odoo-prod_20260209_143022_manifest.json  # ← Includes master password
    └── odoo-backups/                   # Automatic backups (if requested)
```

### 🔑 Manifest File Contents  
Each installation generates a detailed JSON manifest at /root/odoo-installs/:
```nginx
{
  "instance_name": "prod",
  "odoo_version": "18.0",
  "http_port": 8069,
  "longpolling_port": 8072,
  "nginx_enabled": true,
  "domain": "example.com",
  "ssl_enabled": true,
  "ssl_email": "admin@example.com",
  "installation_date": "2026-02-09T14:30:22+03:00",
  "master_password": "xK9pLm2qR7sT5vW8",
  "server_ip": "192.168.1.2",
  "installation_duration_seconds": 187
}
```
### 🔐 Security Note: Manifest files have 600 permissions (root-only access). Never expose them publicly.  
### ⚠️ Note regarding Odoo 19.0: The current version is beta (as of February 2026). It is recommended for testing purposes only. Use version 18.0 or 17.0 (stable) for production.  

# Complete User Guide — Odoo Multi-Instance Management  
### 🚀 Essential Daily Commands  
### 1. Service Management  
```nginx
# Check service status (running/stopped/failed)
sudo systemctl status <instance>-server

# Start instance manually
sudo systemctl start <instance>-server

# Stop instance manually
sudo systemctl stop <instance>-server

# Restart instance (after config changes)
sudo systemctl restart <instance>-server

# Enable auto-start on boot
sudo systemctl enable <instance>-server

# Disable auto-start
sudo systemctl disable <instance>-server

# View real-time logs (essential for debugging)
sudo journalctl -u <instance>-server -f

# View last 100 log entries
sudo journalctl -u <instance>-server -n 100 --no-pager

# Check service health (exit code 0 = healthy)
sudo systemctl is-active <instance>-server && echo "✅ Healthy" || echo "❌ Down"
```

### 2. Instance Discovery & Management
```nginx
# List all installed instances (safe interactive menu)
sudo ./delete_odoo.sh

# Preview deletion without changes (dry-run)
sudo ./delete_odoo.sh --instance <instance> --dry-run

# Safe deletion with automatic backup (production recommended)
sudo ./delete_odoo.sh --instance <instance> --backup --force

# Force deletion without backup (development only)
sudo ./delete_odoo.sh --instance <instance> --force

# Verify instance deletion succeeded
sudo ./delete_odoo.sh 2>&1 | grep -q "<instance>" && echo "❌ Still exists" || echo "✅ Deleted"
```
## 🔒 Security & Hardening Commands
### 3. Critical Security Verification
```nginx
# Verify database manager is BLOCKED (MUST return 403)
curl -s -o /dev/null -w "%{http_code}" http://localhost/web/database/manager
# Expected output: 403

# Verify direct port access is BLOCKED when Nginx is enabled
sudo ss -tulpn | grep ":<port>" | grep -q "nginx" && echo "✅ Port protected by Nginx" || echo "⚠️ Port exposed directly"

# Check firewall status
sudo ufw status verbose

# Block internal port (if accidentally exposed)
sudo ufw deny <port> && echo "✅ Port <port> blocked"

# Allow temporary access for maintenance (5 minutes)
sudo ufw allow from <your-ip> to any port <port> comment 'Maintenance access'
(sleep 300 && sudo ufw delete allow from <your-ip> to any port <port>) &

# Verify master password file permissions (MUST be 600)
stat -c "%a %n" /root/odoo-secrets.txt
# Expected output: 600 /root/odoo-secrets.txt
```
### 4. Password & Credential Management
```nginx
# View full master password (root only)
sudo grep "admin_passwd" /etc/<instance>-server.conf | awk -F' = ' '{print $2}'

# Change master password securely
NEW_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c16)
sudo sed -i "s/^admin_passwd = .*/admin_passwd = $NEW_PASS/" /etc/<instance>-server.conf
sudo systemctl restart <instance>-server
echo "New password: $NEW_PASS" | tee -a /root/odoo-secrets.txt
```

## 🌐 Nginx & SSL Management
### 5. Nginx Operations
```nginx
# Test Nginx configuration syntax (ALWAYS do before reload)
sudo nginx -t && echo "✅ Config valid" || echo "❌ Config error"

# View full Nginx configuration
sudo nginx -T 2>/dev/null | head -100

# Reload Nginx without downtime
sudo nginx -t && sudo systemctl reload nginx && echo "✅ Reloaded"

# Restart Nginx completely
sudo systemctl restart nginx

# View active Nginx sites
ls -la /etc/nginx/sites-enabled/

# Monitor live HTTP requests
sudo tail -f /var/log/nginx/<instance>_access.log | awk '{print $1, $4, $7, $9}'

# Monitor Nginx errors in real-time
sudo tail -f /var/log/nginx/<instance>_error.log
```
### 6. SSL Certificate Management
```nginx
# Test certificate renewal (dry-run)
sudo certbot renew --dry-run && echo "✅ Renewal test passed" || echo "❌ Renewal test failed"

# Force certificate renewal
sudo certbot renew --force-renewal

# View certificate expiration dates
sudo certbot certificates

# Check SSL certificate validity for domain
echo | openssl s_client -connect <domain>:443 2>/dev/null | openssl x509 -noout -dates

# Verify HTTPS is working correctly
curl -I https://<domain>/web/login | grep "HTTP/2"

# Force HTTP → HTTPS redirect test
curl -I http://<domain>/web/login | grep "301"
```


## <img src="https://cdnjs.cloudflare.com/ajax/libs/flag-icons/7.0.0/flags/4x3/sa.svg" width="22"> ZATCA Integration Commands (Saudi Arabia)
### 7. ZATCA Connectivity Verification
```nginx
# Verify DNS resolution for ZATCA endpoints (CRITICAL)
nslookup gw-fatoora.zatca.gov.sa || echo "❌ DNS resolution failed - fix /etc/resolv.conf"

# Test connectivity to ZATCA production endpoint
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  https://gw-fatoora.zatca.gov.sa/e-invoicing/core/compliance

# Test connectivity to ZATCA sandbox endpoint
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  https://gw-fatoora-uat.zatca.gov.sa/e-invoicing/core/compliance

# Verify legacy domain is BLOCKED (should fail)
curl -m 5 -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  https://gw-apic-gov.gazt.gov.sa/e-invoicing/core/ 2>&1 | grep -q "Could not resolve" && echo "✅ Legacy domain blocked" || echo "⚠️ Legacy domain still resolving"

# Monitor ZATCA API calls in Odoo logs
sudo tail -f /var/log/<instance>/<instance>-server.log | grep -i "zatca\|fatoora\|e-invoice"
```
### 8. POS & Offline Mode Verification
```nginx
# Verify WebSocket endpoint is working (critical for POS)
curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Host: localhost" http://localhost/websocket 2>&1 | head -10 | grep -q "101 Switching Protocols" && echo "✅ WebSocket active" || echo "❌ WebSocket failed"

# Verify longpolling endpoint for POS notifications
curl -I http://localhost:<port>/longpolling/poll | grep "200 OK" && echo "✅ Longpolling active" || echo "❌ Longpolling failed"

# Check proxy_mode is enabled (required for Nginx + WebSocket)
grep -q "^proxy_mode = True" /etc/<instance>-server.conf && echo "✅ proxy_mode enabled" || echo "❌ proxy_mode missing"
```

## 💾 Backup & Restore Operations
### 9. Backup Commands
```nginx
# Backup database only (quick)
sudo -u postgres pg_dump <instance> > /root/backup_<instance>_db_$(date +%Y%m%d_%H%M%S).sql

# Backup files only
sudo tar -czf /root/backup_<instance>_files_$(date +%Y%m%d_%H%M%S).tar.gz \
  /<instance> /etc/<instance>-server.conf /etc/systemd/system/<instance>-server.service

# Full backup (database + files)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
sudo -u postgres pg_dump <instance> > /root/backup_<instance>_db_$TIMESTAMP.sql
sudo tar -czf /root/backup_<instance>_files_$TIMESTAMP.tar.gz \
  /<instance> /etc/<instance>-server.conf
echo "✅ Full backup created: $TIMESTAMP"

# List existing backups
ls -lh /root/backup_* | grep -E "\.sql|\.tar\.gz"
```
### 10. Restore Commands
```nginx
# Restore database from backup
sudo -u postgres psql -d <instance> < /root/backup_<instance>_db_20260209.sql

# Restore files from backup
sudo tar -xzf /root/backup_<instance>_files_20260209.tar.gz -C /

# Full restore procedure
sudo systemctl stop <instance>-server
sudo -u postgres psql -d <instance> < /root/backup_<instance>_db_20260209.sql
sudo tar -xzf /root/backup_<instance>_files_20260209.tar.gz -C /
sudo systemctl start <instance>-server
echo "✅ Full restore completed"
```

## 📊 Performance Monitoring
### 11. Resource Monitoring
```nginx
# Monitor memory usage for instance
ps aux | grep "odoo.*<instance>" | grep -v grep | awk '{sum+=$6} END {print "Memory (MB): " sum/1024}'

# Monitor CPU usage for instance
top -b -n1 -u <instance> | tail -n +8 | awk '{cpu+=$9} END {print "CPU (%): " cpu}'

# Count active database connections
sudo -u postgres psql -d <instance> -tAc "SELECT count(*) FROM pg_stat_activity WHERE datname = '<instance>';"

# Monitor disk space usage
df -h / /var/log | grep -v tmpfs

# Monitor instance directory size
du -sh /<instance> /var/log/<instance>
```
### 12. Database Performance
```nginx
# View slow queries (requires pg_stat_statements extension)
sudo -u postgres psql -d <instance> -c "SELECT query, total_time, calls FROM pg_stat_statements ORDER BY total_time DESC LIMIT 10;" 2>/dev/null || echo "pg_stat_statements not enabled"

# Check database size
sudo -u postgres psql -d <instance> -c "SELECT pg_size_pretty(pg_database_size('<instance>')) AS size;"

# List largest tables
sudo -u postgres psql -d <instance> -c "SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size FROM pg_tables ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC LIMIT 20;" | head -25
```
