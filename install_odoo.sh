#!/bin/bash
################################################################################
# Odoo Multi-Instance Installation Script for Ubuntu 22.04+
# Final Unified Version with Nginx, Let's Encrypt & Backup
# Author: Ibrahim Aljuhani
################################################################################
set -e

#-------------------------------#
#        Color Definitions      #
#-------------------------------#
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info()  { echo -e "${GREEN}[✔ DONE ]${NC} $1"; }
print_warn()  { echo -e "${YELLOW}[‼ WARN]${NC} $1"; }
print_error() { echo -e "${RED}[✖ ERROR]${NC} $1"; exit 1; }
print_step()  { echo -e "${CYAN}==> $1${NC}"; }
print_conflict() { echo -e "${RED}⚠ $1${NC}"; }
print_danger() { echo -e "${RED}🔥 $1${NC}"; }

#-------------------------------#
#     Validation Functions      #
#-------------------------------#
check_instance_exists() {
  local user="$1"
  if id "$user" &>/dev/null; then return 0; fi
  if [ -f "/etc/${user}-server.conf" ]; then return 0; fi
  if systemctl list-unit-files --type=service | grep -q "^${user}-server\\.service"; then return 0; fi
  return 1
}

check_port_in_use() {
  local port="$1"
  if ss -tuln | grep -q ":$port\b"; then return 0; fi
  return 1
}

check_nginx_installed() {
  command -v nginx &>/dev/null
}

#-------------------------------#
#     User Input & Validation   #
#-------------------------------#
read -p "Enter instance name (e.g., odoo-prod): " INSTANCE_NAME
OE_USER="$INSTANCE_NAME"
if [[ ! "$OE_USER" =~ ^[a-z][a-z0-9_-]*$ ]]; then
  print_error "Invalid instance name. Must start with lowercase letter, and contain only letters, digits, hyphens, or underscores."
fi

#-------------------------------#
#     Conflict Validation       #
#-------------------------------#
while check_instance_exists "$OE_USER"; do
  print_conflict "Instance name '$OE_USER' is already in use."
  echo "What would you like to do?"
  echo "1) Delete the existing instance and proceed"
  echo "2) Enter a different instance name"
  read -p "Choose an option (1 or 2): " CONFLICT_CHOICE
  case $CONFLICT_CHOICE in
    1)
      echo -e "${RED}────────────────────────────────────────────────────${NC}"
      echo -e "${RED}⚠  WARNING: This action is IRREVERSIBLE!${NC}"
      echo -e "${RED}   - All files, logs, configs, and DB will be deleted.${NC}"
      read -p "   Create automatic backup before deletion? (y/N): " BACKUP_CHOICE
      BACKUP_CHOICE=$(echo "$BACKUP_CHOICE" | tr '[:upper:]' '[:lower:]')
      if [[ "$BACKUP_CHOICE" == "y" || "$BACKUP_CHOICE" == "yes" ]]; then
        BACKUP_DIR="/root/odoo-backups"
        sudo mkdir -p "$BACKUP_DIR"
        BACKUP_FILE="$BACKUP_DIR/${OE_USER}_$(date +%Y%m%d_%H%M%S).tar.gz"
        print_step "Creating file backup: $BACKUP_FILE"
        sudo tar -czf "$BACKUP_FILE" \
          "/$OE_USER" \
          "/etc/${OE_USER}-server.conf" \
          "/var/log/$OE_USER" 2>/dev/null || true

        # ✅ NEW: Backup PostgreSQL database
        DB_BACKUP_FILE="$BACKUP_DIR/${OE_USER}_db_$(date +%Y%m%d_%H%M%S).sql"
        print_step "Creating database backup: $DB_BACKUP_FILE"
        sudo -u postgres pg_dump "$OE_USER" > "$DB_BACKUP_FILE" 2>/dev/null || true

        print_info "✅ Full backup saved to: $BACKUP_DIR"
      fi
      read -p "   Also delete the PostgreSQL database and user? (y/N): " DROP_DB_CHOICE
      echo -e "${RED}────────────────────────────────────────────────────${NC}"
      DROP_DB=$(echo "$DROP_DB_CHOICE" | tr '[:upper:]' '[:lower:]')
      if [[ "$DROP_DB" == "y" || "$DROP_DB" == "yes" ]]; then
        DROP_POSTGRES=true
      else
        DROP_POSTGRES=false
      fi
      print_step "Force-stopping Odoo service and killing all related processes..."
      sudo systemctl stop "${OE_USER}-server" 2>/dev/null || true
      sudo systemctl kill --signal=SIGKILL "${OE_USER}-server" 2>/dev/null || true
      sleep 2
      sudo pkill -9 -u "$OE_USER" 2>/dev/null || true
      print_step "Removing systemd service and config files..."
      sudo systemctl disable --quiet "${OE_USER}-server" 2>/dev/null || true
      sudo rm -f "/etc/systemd/system/${OE_USER}-server.service"
      sudo rm -f "/etc/${OE_USER}-server.conf"
      sudo systemctl daemon-reload
      print_step "Force-deleting system user and home directory..."
      sudo userdel -r "$OE_USER" 2>/dev/null || true
      sudo rm -rf "/$OE_USER"
      sudo rm -rf "/var/log/$OE_USER"
      if [ "$DROP_POSTGRES" == true ]; then
        print_danger "🔥 PREPARING TO DELETE POSTGRESQL DATABASE: '$OE_USER'"
        sudo -u postgres psql -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$OE_USER';" >/dev/null 2>&1 || true
        sudo -u postgres psql -d postgres -c "DROP DATABASE IF EXISTS \"$OE_USER\";" >/dev/null 2>&1 || true
        sudo -u postgres psql -d postgres -c "DROP USER IF EXISTS \"$OE_USER\";" >/dev/null 2>&1 || true
        print_info "✅ PostgreSQL database and user DELETED successfully."
      else
        print_info "ℹ️  PostgreSQL database and user preserved."
      fi
      print_info "✅ Existing instance '$OE_USER' has been COMPLETELY removed."
      break
      ;;
    2)
      read -p "Enter a new instance name: " INSTANCE_NAME
      OE_USER="$INSTANCE_NAME"
      if [[ ! "$OE_USER" =~ ^[a-z][a-z0-9_-]*$ ]]; then
        print_error "Invalid instance name. Must start with lowercase letter, and contain only letters, digits, hyphens, or underscores."
      fi
      ;;
    *)
      print_warn "Invalid choice. Please enter 1 or 2."
      ;;
  esac
done

#-------------------------------#
#        Port Validation        #
#-------------------------------#
read -p "Enter HTTP port (default 8069): " OE_PORT
OE_PORT="${OE_PORT:-8069}"
if ! [[ "$OE_PORT" =~ ^[0-9]+$ ]] || [ "$OE_PORT" -lt 1024 ] || [ "$OE_PORT" -gt 65535 ]; then
  print_error "Port must be a number between 1024 and 65535."
fi
while check_port_in_use "$OE_PORT"; do
  print_conflict "Port $OE_PORT is already in use."
  read -p "Enter a different port: " OE_PORT
  if ! [[ "$OE_PORT" =~ ^[0-9]+$ ]] || [ "$OE_PORT" -lt 1024 ] || [ "$OE_PORT" -gt 65535 ]; then
    print_error "Port must be a number between 1024 and 65535."
  fi
done
LONGPOLLING_PORT=$((OE_PORT + 3))
if check_port_in_use "$LONGPOLLING_PORT"; then
  print_warn "Longpolling port $LONGPOLLING_PORT is in use. Live features may not work properly."
fi

#-------------------------------#
#     Configuration Variables   #
#-------------------------------#
OE_HOME="/$OE_USER"
OE_HOME_EXT="${OE_HOME}/${OE_USER}-server"
VENV_PATH="$OE_HOME/venv"
OE_VERSION=""
OE_SUPERADMIN=""
INSTALL_WKHTMLTOPDF="True"
GENERATE_RANDOM_PASSWORD="True"
SECRETS_FILE="/root/odoo-secrets.txt"
SERVER_IP=$(hostname -I | awk '{print $1}')

#-------------------------------#
#      Odoo Version Choice      #
#-------------------------------#
choose_odoo_version() {
  echo -e "${CYAN}Choose the Odoo version to install:${NC}"
  echo -e "${YELLOW}1) 19.0${NC}"
  echo -e "${GREEN}2) 18.0${NC}"
  echo -e "${GREEN}3) 17.0${NC}"
  echo -e "${GREEN}4) 16.0${NC}"
  read -p "Enter your choice (1-3): " version_choice
  case $version_choice in
    1) OE_VERSION="19.0" ;;
    2) OE_VERSION="18.0" ;;
    3) OE_VERSION="17.0" ;;
    4) OE_VERSION="16.0" ;;
    *) print_error "Invalid choice. Please select 1, 2, 3, or 4." ;;
  esac
  print_info "Selected Odoo version: $OE_VERSION"
}

#-------------------------------#
#      System Preparation       #
#-------------------------------#
print_step "Checking required tools: wget git gpg curl bc"
for cmd in wget git gpg curl bc; do
  if ! command -v "$cmd" &> /dev/null; then
    print_error "$cmd is required but not installed."
  fi
done

print_step "Checking Ubuntu version"
UBUNTU_VERSION=$(lsb_release -r -s 2>/dev/null || echo "unknown")
if [[ "$UBUNTU_VERSION" == "unknown" ]]; then
  print_error "Unable to detect Ubuntu version. Make sure 'lsb-release' is installed."
fi
if (( $(echo "$UBUNTU_VERSION >= 22.04" | bc -l) )); then
  print_info "Ubuntu version $UBUNTU_VERSION is supported."
else
  print_error "This script requires Ubuntu 22.04 or newer. Detected version: $UBUNTU_VERSION"
fi

print_step "Updating system packages"
sudo apt update -y
sudo apt full-upgrade -y
sudo apt autoremove -y
sudo apt autoclean -y

choose_odoo_version

print_step "Installing required system packages"
sudo apt install -y curl wget gnupg apt-transport-https git build-essential \
  libxslt-dev libzip-dev libldap2-dev libsasl2-dev libjpeg-dev libpng-dev \
  gdebi libpq-dev fonts-dejavu-core fonts-font-awesome fonts-roboto-unhinted \
  adduser lsb-base vim python3 python3-dev python3-venv python3-wheel lsb-release bc
print_info "System packages installed."

#-------------------------------#
#     Install Node.js 20 LTS    #
#-------------------------------#
print_step "Installing Node.js 20 LTS from NodeSource"
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - || print_error "Failed to add NodeSource repo"
sudo apt install -y nodejs || print_error "Failed to install Node.js 20"
sudo npm install -g rtlcss
print_info "Node.js 20 LTS and rtlcss installed."

#-------------------------------#
#     Install wkhtmltopdf        #
#-------------------------------#
if [ "$INSTALL_WKHTMLTOPDF" == "True" ]; then
  print_step "Installing official wkhtmltopdf 0.12.6.1-3 for Ubuntu 22.04+"
  WKHTML_DEB="/tmp/wkhtmltox_${OE_USER}.deb"
  WKHTML_URL="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb"
  wget -q "$WKHTML_URL" -O "$WKHTML_DEB" || print_error "Failed to download wkhtmltopdf from official source"
  sudo gdebi -n "$WKHTML_DEB" || print_error "Failed to install wkhtmltopdf .deb package"
  print_info "wkhtmltopdf installed from official .deb (0.12.6.1-3)"
else
  print_warn "Skipping wkhtmltopdf installation."
fi

#-------------------------------#
#     PostgreSQL 15 Setup       #
#-------------------------------#
if dpkg -l | grep -q "postgresql-15"; then
  print_info "PostgreSQL 15 is already installed. Skipping installation."
  if ! systemctl is-active --quiet postgresql; then
    print_step "Starting PostgreSQL service..."
    sudo systemctl start postgresql
    sudo systemctl enable postgresql
  fi
else
  print_step "PostgreSQL 15 not found. Installing from PGDG..."
  curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | \
    sudo tee /usr/share/keyrings/postgresql.gpg > /dev/null
  echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" | \
    sudo tee /etc/apt/sources.list.d/pgdg.list > /dev/null
  sudo apt update -y
  sudo apt install -y postgresql-15 || print_error "Failed to install PostgreSQL 15"
  print_info "PostgreSQL 15 installed successfully."
fi

#-------------------------------#
#   PostgreSQL User Creation    #
#-------------------------------#
print_step "Creating PostgreSQL user '$OE_USER'"
if ! sudo -u postgres psql -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='$OE_USER'" 2>/dev/null | grep -q 1; then
  sudo -u postgres createuser -s "$OE_USER"
  print_info "PostgreSQL user '$OE_USER' created."
else
  print_warn "PostgreSQL user '$OE_USER' already exists."
fi

#-------------------------------#
#     System User Creation      #
#-------------------------------#
print_step "Creating system user '$OE_USER'"
if id "$OE_USER" &>/dev/null; then
  print_warn "User '$OE_USER' already exists."
else
  sudo adduser --system --quiet --shell=/bin/bash --home="$OE_HOME" --gecos 'ODOO' --group "$OE_USER"
  print_info "User '$OE_USER' created."
fi

#-------------------------------#
#       Log Directory Setup     #
#-------------------------------#
sudo mkdir -p /var/log/$OE_USER
sudo chown $OE_USER:$OE_USER /var/log/$OE_USER
print_info "Log directory created."

#-------------------------------#
#    Clone Odoo Source Code     #
#-------------------------------#
CONFIG_FILE="/etc/${OE_USER}-server.conf"
SERVICE_FILE="/etc/systemd/system/${OE_USER}-server.service"
SKIP_CLONE=false
if [ -d "$OE_HOME_EXT" ]; then
  print_warn "Odoo directory exists. Skipping clone."
  SKIP_CLONE=true
fi
if [ "$SKIP_CLONE" != true ]; then
  print_step "Cloning Odoo $OE_VERSION"
  sudo -u "$OE_USER" git clone --depth 1 --branch "$OE_VERSION" https://github.com/odoo/odoo "$OE_HOME_EXT"
  print_info "Odoo source cloned."
fi

#-------------------------------#
#   Custom Addons Directory     #
#-------------------------------#
sudo -u "$OE_USER" mkdir -p "${OE_HOME}/custom/addons"
print_info "Custom addons directory created."

#-------------------------------#
#       Permissions Setup       #
#-------------------------------#
sudo chown -R "$OE_USER":"$OE_USER" "$OE_HOME"
print_info "Permissions set."

#-------------------------------#
#   Python Virtual Environment  #
#-------------------------------#
print_step "Creating Python virtual environment"
sudo -u "$OE_USER" python3 -m venv "$VENV_PATH"
print_step "Upgrading pip in venv"
sudo -u "$OE_USER" "$VENV_PATH/bin/pip" install --upgrade pip
print_step "Downloading Odoo requirements"
REQUIREMENTS_FILE="/tmp/odoo_reqs_${OE_USER}.txt"
REQUIREMENTS_URL="https://github.com/odoo/odoo/raw/${OE_VERSION}/requirements.txt"
wget -q "$REQUIREMENTS_URL" -O "$REQUIREMENTS_FILE" || print_error "Failed to download requirements.txt"
if [[ "$OE_VERSION" =~ ^1[6-8]\.0$ ]]; then
  print_warn "Detected Odoo $OE_VERSION — removing 'gevent' from requirements.txt"
  sed -i '/gevent/d' "$REQUIREMENTS_FILE"
  sudo -u "$OE_USER" "$VENV_PATH/bin/pip" install -r "$REQUIREMENTS_FILE" || print_warn "Some packages failed"
  sudo -u "$OE_USER" "$VENV_PATH/bin/pip" install "gevent==23.9.1"
else
  sudo -u "$OE_USER" "$VENV_PATH/bin/pip" install -r "$REQUIREMENTS_FILE" || print_warn "Some packages failed"
fi
print_info "Odoo Python dependencies installed in virtual environment."

#-------------------------------#
#     Configuration File        #
#-------------------------------#
print_step "Creating Odoo config at $CONFIG_FILE"
if [ ! -f "$CONFIG_FILE" ]; then
  sudo touch "$CONFIG_FILE"
  sudo chmod 640 "$CONFIG_FILE"
  sudo chown "$OE_USER":"$OE_USER" "$CONFIG_FILE"
fi
if [ "$GENERATE_RANDOM_PASSWORD" == "True" ]; then
  OE_SUPERADMIN=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
  echo "$(date '+%Y-%m-%d %H:%M:%S'): Instance '$OE_USER' admin password: $OE_SUPERADMIN" >> "$SECRETS_FILE"
  chmod 600 "$SECRETS_FILE"
  print_info "Admin password saved to $SECRETS_FILE (root-only access)."
fi
sudo tee "$CONFIG_FILE" > /dev/null <<EOF
[options]
admin_passwd = ${OE_SUPERADMIN}
http_port = ${OE_PORT}
longpolling_port = ${LONGPOLLING_PORT}
logfile = /var/log/${OE_USER}/${OE_USER}-server.log
addons_path = ${OE_HOME_EXT}/addons,${OE_HOME}/custom/addons
EOF
print_info "Configuration file created."

#-------------------------------#
#     Systemd Service Setup     #
#-------------------------------#
print_step "Creating systemd service"
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Odoo Instance: $OE_USER
After=network.target postgresql.service
Requires=postgresql.service
[Service]
Type=simple
User=$OE_USER
ExecStart=$VENV_PATH/bin/python $OE_HOME_EXT/odoo-bin --config=$CONFIG_FILE
WorkingDirectory=$OE_HOME_EXT
StandardOutput=journal
StandardError=journal
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable "${OE_USER}-server"
sudo systemctl start "${OE_USER}-server"
if ! sudo systemctl is-active --quiet "${OE_USER}-server"; then
  print_error "Odoo service failed to start. Check logs with: journalctl -u ${OE_USER}-server"
fi
print_info "Odoo service started and enabled."

#-------------------------------#
#        Nginx Setup            #
#-------------------------------#
print_step "Configure Nginx as reverse proxy (recommended for production)?"
read -p "Install and configure Nginx for this instance? (y/N): " NGINX_CHOICE
NGINX_CHOICE=$(echo "$NGINX_CHOICE" | tr '[:upper:]' '[:lower:]')
if [[ "$NGINX_CHOICE" == "y" || "$NGINX_CHOICE" == "yes" ]]; then
  if ! check_nginx_installed; then
    print_step "Installing Nginx..."
    sudo apt install -y nginx || print_error "Failed to install Nginx"
    sudo ufw allow 'Nginx Full' 2>/dev/null || true
    print_info "Nginx installed."
  else
    print_info "Nginx is already installed."
  fi

  # ✅ Verify www-data user exists
  if ! id www-data &>/dev/null; then
    print_error "Nginx user 'www-data' not found. Nginx may not be installed correctly."
  fi

  # ✅ Set global client_max_body_size in nginx.conf (survives Certbot)
  if ! grep -q "client_max_body_size 1G;" /etc/nginx/nginx.conf; then
    sudo sed -i '/http {/a \    client_max_body_size 1G;' /etc/nginx/nginx.conf
    print_info "✅ Set global client_max_body_size = 1G in /etc/nginx/nginx.conf"
  fi

  # Ensure ACME challenge directory exists
  sudo mkdir -p /var/www/certbot/.well-known/acme-challenge
  sudo chown -R www-data:www-data /var/www/certbot

  read -p "Enter domain name (or press Enter to use server IP: $SERVER_IP): " NGINX_DOMAIN
  NGINX_DOMAIN="${NGINX_DOMAIN:-$SERVER_IP}"

  NGINX_SITE="/etc/nginx/sites-available/${OE_USER}"
  NGINX_ENABLED="/etc/nginx/sites-enabled/${OE_USER}"

  print_step "Creating Nginx configuration for $OE_USER..."
  sudo tee "$NGINX_SITE" > /dev/null <<EOF
upstream odoo_${OE_USER} {
    server 127.0.0.1:${OE_PORT};
}
upstream odoo_${OE_USER}_longpolling {
    server 127.0.0.1:${LONGPOLLING_PORT};
}

server {
    listen 80;
    server_name ${NGINX_DOMAIN};

    # Let's Encrypt ACME challenge support
    location ^~ /.well-known/acme-challenge/ {
        allow all;
        root /var/www/certbot;
        default_type "text/plain";
        try_files \$uri =404;
    }

    location /web/database/manager {
        deny all;
        return 403;
    }

    location /web/static/ {
        proxy_cache_valid 200 60m;
        proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
        proxy_ignore_headers Cache-Control;
        proxy_pass http://odoo_${OE_USER};
    }

    location / {
        proxy_pass http://odoo_${OE_USER};
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_connect_timeout 600;
        proxy_send_timeout 600;
        proxy_read_timeout 600;
    }

    location /longpolling {
        proxy_pass http://odoo_${OE_USER}_longpolling;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600;
    }
}
EOF

  sudo ln -sf "$NGINX_SITE" "$NGINX_ENABLED"
  sudo nginx -t || print_error "Nginx configuration test failed!"
  sudo systemctl reload nginx || print_error "Failed to reload Nginx"

  echo "proxy_mode = True" | sudo tee -a "$CONFIG_FILE" > /dev/null
  sudo systemctl restart "${OE_USER}-server"

  print_info "Nginx configured successfully for $OE_USER."

  #-------------------------------#
  #     Let's Encrypt SSL Setup   #
  #-------------------------------#
  NGINX_ACCESS_URL="http://${NGINX_DOMAIN}"
  print_step "Enable HTTPS with Let's Encrypt (free SSL certificate)?"
  read -p "Enable SSL for $NGINX_DOMAIN? (y/N): " SSL_CHOICE
  SSL_CHOICE=$(echo "$SSL_CHOICE" | tr '[:upper:]' '[:lower:]')
  if [[ "$SSL_CHOICE" == "y" || "$SSL_CHOICE" == "yes" ]]; then
    print_step "Installing Certbot..."
    sudo apt install -y certbot python3-certbot-nginx || print_error "Failed to install Certbot"

    read -p "Enter email for Let's Encrypt notifications: " LETSENCRYPT_EMAIL
    if [[ -z "$LETSENCRYPT_EMAIL" ]]; then
      print_error "Email is required for Let's Encrypt."
    fi

    print_step "Requesting SSL certificate from Let's Encrypt..."
    sudo certbot --nginx \
      --non-interactive \
      --agree-tos \
      --email "$LETSENCRYPT_EMAIL" \
      --domains "$NGINX_DOMAIN" \
      --redirect 2>/dev/null || print_error "Failed to obtain SSL certificate"

    print_info "✅ SSL certificate installed successfully!"
    NGINX_ACCESS_URL="https://${NGINX_DOMAIN}"

    # 🔒 Close internal port for security
    sudo ufw deny "$OE_PORT" 2>/dev/null || true
    print_info "🔒 Internal port $OE_PORT closed for security."
  else
    # Still close port if Nginx is used
    sudo ufw deny "$OE_PORT" 2>/dev/null || true
    print_info "🔒 Internal port $OE_PORT closed (Nginx is handling traffic)."
  fi

else
  NGINX_ACCESS_URL="http://${SERVER_IP}:${OE_PORT}"
fi

#-------------------------------#
#         Final Output          #
#-------------------------------#
echo -e "${GREEN}-----------------------------------------------------------${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo "Instance Name:          $OE_USER"
echo "Service Name:           ${OE_USER}-server"
echo "HTTP Port:              $OE_PORT"
echo "Longpolling Port:       $LONGPOLLING_PORT"
echo "Linux User:             $OE_USER"
echo "Configuration File:     $CONFIG_FILE"
echo "Log File:               /var/log/$OE_USER/${OE_USER}-server.log"
echo "Odoo Code Location:     $OE_HOME_EXT"
echo "Addons Folders:         $OE_HOME_EXT/addons, $OE_HOME/custom/addons"
echo "Superadmin Password:    $OE_SUPERADMIN"
echo "Password also saved in: $SECRETS_FILE"
echo -e "${CYAN}Access your Odoo ==> :${NC} $NGINX_ACCESS_URL"
echo -e "${GREEN}-----------------------------------------------------------${NC}"

#-------------------------------#
#     Cleanup Temp Files        #
#-------------------------------#
print_step "Cleaning temporary files"
rm -f "/tmp/odoo_reqs_${OE_USER}.txt" "/tmp/wkhtmltox_${OE_USER}.deb"
exit 0
