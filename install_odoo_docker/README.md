# 🐳 Odoo Docker Installer

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Odoo Versions](https://img.shields.io/badge/Odoo-16%20|%2017%20|%2018%20|%2019-blueviolet)]()
[![Docker](https://img.shields.io/badge/Docker-Ready-2496ED.svg?logo=docker)]()

A smart, interactive Bash script to **install Odoo in Docker** with full multi-instance support, automatic configuration, and secure password generation — designed for **Ubuntu/Debian** systems.

Perfect for developers, agencies, and businesses who need to run **multiple isolated Odoo instances** with minimal overhead and maximum flexibility.

> 🔗 **Prerequisite**: This script requires Docker CE, Docker Compose, and optionally NGINX Proxy Manager.  
> If not installed, use: [https://github.com/IbrahimAljuhani/docker_installs](https://github.com/IbrahimAljuhani/docker_installs)

---

## ✅ Features

- **Multi-instance support** – run multiple Odoo versions side-by-side (e.g., `odoo-prod`, `odoo-dev`)
- **Automatic setup** – creates users, directories, config files, and Docker Compose stack
- **Secure by default** – generates a random **admin password** and saves it to `/root/odoo-docker-secrets.txt`
- **Version flexibility** – supports **Odoo 16.0, 17.0, 18.0, and 19.0**
- **Isolated data** – each instance has its own:
  - PostgreSQL database (in container)
  - Filestore
  - Custom addons directory
  - Configuration file
- **No system pollution** – everything runs in containers — no Python or system packages installed globally
- **Easy management** – use `docker compose` commands inside the instance directory

---

## 📥 Installation & Usage

### 1. Install prerequisites (Docker + Compose)

If you haven’t already, install Docker and Docker Compose:

```bash
curl -fsSL -o install_docker_NPM.sh https://raw.githubusercontent.com/IbrahimAljuhani/docker_installs/main/install_docker_NPM.sh
chmod +x install_docker_NPM.sh
./install_docker_NPM.sh
```

✅ This also installs **NGINX Proxy Manager** and **Portainer-CE** (optional but recommended for production).

---

### 2. Download and Run the Odoo Installer

```bash
curl -fsSL -o install_odoo_docker.sh https://raw.githubusercontent.com/IbrahimAljuhani/InstallOdooScript/main/install_odoo_docker/install_odoo_docker.sh
chmod +x install_odoo_docker.sh
./install_odoo_docker.sh
```

You’ll be guided through:
- Instance name (e.g., `odoo-shop`)
- Odoo version (`16–19`)
- HTTP port (default: `8069`)

---

## 📁 Directory Structure

After installation, your instance will be stored at:

```
~/odoo/
└── your-instance-name/
    ├── docker-compose.yml
    ├── config/
    │   └── odoo.conf
    ├── addons/          # Custom modules
    ├── db-data/         # PostgreSQL data (persistent)
    └── filestore/       # Odoo attachments (persistent)
```

Example for multiple instances:
```
~/odoo/
├── odoo-prod/
└── odoo-dev/
```

---

## 🔐 Security

- The **admin password** is generated automatically and saved securely in:

  ```
  /root/odoo-docker-secrets.txt
  ```

  *(Accessible only by root, permissions: 600)*

- PostgreSQL credentials are isolated per instance.  
- All data is persisted outside containers for safe backup and migration.

---

## 🛠️ Management Commands

To manage your Odoo instance:

```bash
cd ~/odoo/your-instance-name
docker compose ps          # Check status
docker compose logs        # View logs
docker compose stop        # Stop instance
docker compose rm          # Remove containers (data preserved)
```

### 🔄 Upgrade Odoo

To upgrade Odoo:
1. Edit `docker-compose.yml`
2. Change the Odoo image version
3. Run:
   ```bash
   docker compose up -d
   ```

---

## 🌐 Reverse Proxy & SSL (Recommended)

If you installed **NGINX Proxy Manager** (via `install_docker_NPM.sh`):

1. Open [http://your-server-ip:81](http://your-server-ip:81)
2. Create a new **Proxy Host**:
   - **Domain**: `odoo.yourdomain.com`
   - **Forward Hostname/IP**: `odoo-your-instance-name` (container name)
   - **Forward Port**: `8069`
3. Enable **SSL** with Let’s Encrypt directly from the UI.

✅ No need to expose ports publicly — NPM handles HTTPS termination securely.

---

## 🧹 Cleanup (Optional)

To completely remove an instance (containers + data):

```bash
cd ~/odoo/your-instance-name
docker compose down -v
rm -rf ~/odoo/your-instance-name
```

---

## 📜 License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE) for details.

---

## 🙌 Author

**Ibrahim Aljuhani**  
GitHub: [@IbrahimAljuhani](https://github.com/IbrahimAljuhani)

🔗 [https://github.com/IbrahimAljuhani](https://github.com/IbrahimAljuhani)

---

<!--
Tags: Odoo, Docker, Installer, Bash, DevOps, Ubuntu, Debian, NGINX Proxy Manager, Odoo Docker Compose
-->
