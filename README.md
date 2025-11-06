# InstallOdooScript

A robust, production-ready Bash script to install multiple Odoo instances (v16–v19) on Ubuntu 22.04+ — with Nginx, Let's Encrypt SSL, and PostgreSQL 15.

🔗 **View on GitHub**: [install_odoo.sh](https://github.com/IbrahimAljuhani/InstallOdooScript/blob/main/install_odoo.sh)  
📥 **Download raw**: [install_odoo.sh (raw)](https://raw.githubusercontent.com/IbrahimAljuhani/InstallOdooScript/main/install_odoo.sh)
-------------------------------------------
# Install Odoo Script

A fully automated, production-grade Bash script to deploy **multiple isolated Odoo instances** (versions 16.0 to 19.0) on **Ubuntu 22.04**.

🔗 **Script URL**:  
https://raw.githubusercontent.com/IbrahimAljuhani/InstallOdooScript/main/install_odoo.sh

## ✨ Features

- Supports Odoo **16.0, 17.0, 18.0, and 19.0**
- Creates isolated system users and PostgreSQL databases per instance
- Installs **PostgreSQL 15**, **Node.js 20**, and **wkhtmltopdf** (official .deb)
- Sets up **Python virtual environment** with proper dependencies (including `gevent` fix for v16–v19)
- Configures **systemd service** for auto-start and monitoring
- Optional **Nginx reverse proxy** with security hardening
- One-click **Let's Encrypt SSL** integration
- Automatic **admin password generation** (saved securely in `/root/odoo-secrets.txt`)
- **Conflict detection & resolution**: safely delete or rename existing instances
- Built-in **backup** before destructive operations
- Closes internal ports when Nginx is used (enhanced security)

## 🚀 Usage

1. **Download the script**:
   ```bash
   wget https://raw.githubusercontent.com/IbrahimAljuhani/InstallOdooScript/main/install_odoo.sh
2. **Make it executable:**
   ```bash
   chmod +x install_odoo.sh
3. **Run as root or with sudo:**
   ```bash
   sudo ./install_odoo.sh
4. Follow the interactive prompts:
   - Enter a unique **instance name** (e.g., `odoo-prod`, `mycompany-erp`)
   - Choose the **Odoo version** (19.0, 18.0, 17.0, or 16.0)
   - Specify the **HTTP port** (default: `8069`; must be ≥1024)
   - Optionally enable **Nginx reverse proxy** for production use
   - If Nginx is enabled, you can also set up **free SSL via Let's Encrypt**

> ⚠️ **Important**:    
> - Must be run as **root** or with **sudo**.  
> - If an instance name already exists, you’ll be offered to **delete it (with optional backup)** or choose a new name.

After installation, your Odoo instance will be:
- Running as a **systemd service** (`<instance>-server`)
- Secured with a **randomly generated admin password** (saved in `/root/odoo-secrets.txt`)
- Ready for custom modules in `/<instance>/custom/addons`

Access your Odoo via the URL shown at the end of the script (e.g., `https://your-domain.com` or `http://SERVER_IP:PORT`).

## 🗑️ Odoo Instance Deletion Script (`delete_odoo.sh`)

A safe and thorough cleanup tool to **completely remove** an Odoo instance installed by the `install_odoo.sh` script.

### ✨ Features

- Automatically **detects all existing Odoo instances** on the system
- Presents a numbered list for easy selection
- Requires **explicit confirmation** (by typing the instance name) to prevent accidental deletion
- Performs **full cleanup**, including:
  - System user and home directory (`/instance-name`)
  - Systemd service (`instance-name-server`)
  - Configuration file (`/etc/instance-name-server.conf`)
  - Log files (`/var/log/instance-name/`)
  - PostgreSQL database and user
  - Nginx site configuration (if present)
- Reloads Nginx after removal (if installed)
- Logs deletion events to `/root/odoo-deletion-log.txt`

### 🚀 Usage

1. Download and make executable:
   ```bash
   curl -O https://raw.githubusercontent.com/IbrahimAljuhani/InstallOdooScript/main/delete_odoo.sh && chmod +x delete_odoo.sh
2. **Run with sudo:**
   ```bash
   sudo ./delete_odoo.sh
3. Follow the prompts to select and confirm deletion.
   - The script will list all detected Odoo instances with numbered options.
   - Enter the number of the instance you wish to delete (or `0` to cancel).
   - To prevent accidents, you must **type the exact instance name** to confirm deletion.

> ⚠️ **Warning**: This action is **irreversible**. All data—including the PostgreSQL database, configuration files, logs, and code—will be **permanently erased**.

Upon successful deletion, the script:
- Stops and removes the systemd service
- Deletes the system user and home directory (`/instance-name`)
- Drops the PostgreSQL database and user
- Removes Nginx site configuration (if any)
- Reloads Nginx (if installed)
- Logs the deletion event to `/root/odoo-deletion-log.txt`

You’ll see a final confirmation message:  
✅ **Instance 'your-instance' has been COMPLETELY and PERMANENTLY deleted.**
