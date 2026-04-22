# 🐳 Odoo Docker Installer

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Odoo Versions](https://img.shields.io/badge/Odoo-17.0%20|%2018.0%20|%2019.0-blueviolet)]()
[![Docker](https://img.shields.io/badge/Docker-Ready-2496ED.svg?logo=docker)]()

A smart, interactive Bash script to **install Odoo in Docker** using official Docker Hub images, with full multi-instance support, automatic configuration, health checks, resource limits, and secure password generation — designed for **Ubuntu/Debian** systems.

Perfect for developers, agencies, and businesses who need to run **multiple isolated Odoo instances** with minimal overhead and maximum flexibility.

> 🔗 **Prerequisite**: This script requires Docker CE, Docker Compose, `openssl`, and `curl`.  
> If Docker is not installed, use: [https://github.com/IbrahimAljuhani/docker_installs](https://github.com/IbrahimAljuhani/docker_installs)

---

## ✅ Features

- **Official images only** — uses `odoo:<version>` and `postgres:15` from Docker Hub
- **Multi-instance support** — run multiple Odoo versions side-by-side (e.g., `odoo-prod`, `odoo-dev`)
- **Automatic setup** — creates directories, `.env`, `docker-compose.yml`, and `odoo.conf`
- **Secure by default** — generates random passwords for both DB and Odoo admin; saves to `~/.odoo-docker-secrets.txt` (`600` permissions)
- **Version flexibility** — supports **Odoo 17.0, 18.0, and 19.0**
- **Container health checks** — both Odoo and PostgreSQL containers include `healthcheck` definitions
- **Resource limits** — memory limits and reservations defined via `deploy.resources` (Odoo: 2 GB / 512 MB; DB: 1 GB / 256 MB)
- **Isolated data** — each instance has its own:
  - PostgreSQL database (in container with persistent volume)
  - Odoo filestore (`data/`)
  - Custom addons directory (`addons/`)
  - Configuration file (`config/odoo.conf`)
- **No system pollution** — everything runs in containers — no Python or system packages installed globally
- **Easy management** — use `docker compose` commands inside the instance directory

---

## 📥 Installation & Usage

### 1. Install Prerequisites (Docker + Compose)

If you haven't already, install Docker and Docker Compose:

```bash
curl -fsSL -o install_docker_NPM.sh https://raw.githubusercontent.com/IbrahimAljuhani/docker_installs/main/install_docker_NPM.sh
chmod +x install_docker_NPM.sh
sudo ./install_docker_NPM.sh
```

✅ This also installs **NGINX Proxy Manager** and **Portainer-CE** (optional but recommended for production).

---

### 2. Download and Run the Odoo Docker Installer

```bash
curl -fsSL -o install_odoo_docker.sh \
  https://raw.githubusercontent.com/IbrahimAljuhani/InstallOdooScript/main/install_odoo_docker/install_odoo_docker.sh
chmod +x install_odoo_docker.sh
./install_odoo_docker.sh
```

> ⚠️ Do **not** run as root. Your user must be in the `docker` group.  
> To add yourself: `sudo usermod -aG docker $USER` then log out and back in.

You will be guided through:

1. **Instance name** (e.g., `odoo-shop`) — validated (lowercase, letters/digits/hyphens/underscores)
2. **Odoo version** — `19.0` (development) / `18.0` (stable, recommended) / `17.0` (LTS)
3. **HTTP port** — default `8069`, checked for conflicts
4. **PostgreSQL credentials** — username, password (auto-generated if left blank), database name

---

## 📁 Directory Structure

After installation, your instance is stored at:

```
~/odoo/
└── your-instance-name/
    ├── .env                  # DB credentials and admin password (permissions: 600)
    ├── docker-compose.yml    # Stack definition
    ├── config/
    │   └── odoo.conf         # Odoo configuration (DB host, port, user, addons path)
    ├── addons/               # Your custom modules
    ├── db-data/              # PostgreSQL data (persistent volume)
    └── data/                 # Odoo filestore and sessions (persistent volume)
```

Example for multiple instances:

```
~/odoo/
├── odoo-prod/
├── odoo-staging/
└── odoo-dev/
```

---

## 🔐 Security

- **Admin password** and **DB password** are both auto-generated (20-character alphanumeric)
- Credentials are saved to `~/.odoo-docker-secrets.txt` with `600` permissions
- The `.env` file inside each instance directory is also `600`
- PostgreSQL is not exposed outside the Docker network — it's only accessible by the Odoo container on the internal `odoo-net-<instance>` bridge

```
⚠  SECURITY REMINDER:
   Save credentials from ~/.odoo-docker-secrets.txt
   then clear your terminal:  history -c && history -w
```

---

## 🛠️ Management Commands

Navigate to your instance directory first:

```bash
cd ~/odoo/your-instance-name
```

```bash
docker compose ps            # Check container status
docker compose logs -f       # Follow live logs
docker compose logs odoo     # Odoo container logs only
docker compose logs db       # PostgreSQL logs only
docker compose stop          # Stop containers (data preserved)
docker compose start         # Start stopped containers
docker compose restart       # Restart all containers
docker compose down          # Stop and remove containers (data preserved)
docker compose down -v       # ⚠️  Stop, remove containers AND volumes (data lost)
docker compose pull          # Pull latest image versions
```

---

## 🌐 Reverse Proxy & SSL (Recommended)

### Option A: NGINX Proxy Manager (GUI)

If you installed **NGINX Proxy Manager** (via `install_docker_NPM.sh`):

1. Open [http://your-server-ip:81](http://your-server-ip:81)
2. Create a new **Proxy Host**:
   - **Domain**: `odoo.yourdomain.com`
   - **Forward Hostname/IP**: `127.0.0.1`
   - **Forward Port**: `8069` (or your chosen port)
   - Enable **Websockets Support**
3. Enable **SSL** with Let's Encrypt directly from the UI.

✅ No need to expose ports publicly — NPM handles HTTPS termination securely.

### Option B: Certbot + Nginx (Manual)

```bash
sudo apt install -y nginx certbot python3-certbot-nginx
sudo certbot --nginx -d odoo.yourdomain.com
```

---

## 🧹 Complete Cleanup

To completely remove an instance (containers + all data):

```bash
cd ~/odoo/your-instance-name
docker compose down -v
cd ~
rm -rf ~/odoo/your-instance-name
```

To remove only containers and keep data intact:

```bash
cd ~/odoo/your-instance-name
docker compose down
```

---

## 📊 Monitoring

```bash
# Resource usage (live)
docker stats odoo-your-instance-name odoo-your-instance-name-db

# Container health status
docker inspect --format='{{.State.Health.Status}}' odoo-your-instance-name

# PostgreSQL active connections
docker exec odoo-your-instance-name-db \
  psql -U odoo -c "SELECT count(*) FROM pg_stat_activity;"

# Database size
docker exec odoo-your-instance-name-db \
  psql -U odoo -c "SELECT pg_size_pretty(pg_database_size('odoo'));"
```

---

## 📌 Version Notes

| Odoo Version | Status | Notes |
|---|---|---|
| 19.0 | ⚠️ Beta | Development branch — official Docker image may not exist yet |
| 18.0 | ✅ Stable | Recommended for new production deployments |
| 17.0 | ✅ LTS | Long-term support — safe for existing production |

---

## 📜 License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE) for details.

---

## 🙌 Author

**Ibrahim Aljuhani**  
GitHub: [@IbrahimAljuhani](https://github.com/IbrahimAljuhani)

---

<!--
Tags: Odoo, Docker, Installer, Bash, DevOps, Ubuntu, Debian, NGINX Proxy Manager, Odoo Docker Compose
-->
