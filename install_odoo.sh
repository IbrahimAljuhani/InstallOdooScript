#!/bin/bash
################################################################################
# Odoo Multi-Instance Installation Script - Professional Edition
# Author: Ibrahim Aljuhani
# Version: 3.0.0
# Supports: Ubuntu 22.04+
# Architecture: Configuration-First Pattern (Gather → Validate → Execute)
# Modes: Interactive | Non-Interactive | Dry-Run
################################################################################
set -e
export DEBIAN_FRONTEND=noninteractive

# ─────────────────────────────────────────────────────────────────────────────
#  Color Definitions
# ─────────────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

print_info()      { echo -e "${GREEN}[✔ DONE ]${NC} $1"; }
print_warn()      { echo -e "${YELLOW}[⚠ WARN ]${NC} $1"; }
print_error()     { echo -e "${RED}[✖ ERROR]${NC} $1"; exit 1; }
print_step()      { echo -e "${CYAN}[  ==>  ]${NC} $1"; }
print_danger()    { echo -e "${RED}[🔥 WARN ]${NC} $1"; }
print_security()  { echo -e "${PURPLE}[🔒 SEC  ]${NC} $1"; }

print_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║         Odoo Multi-Instance Installer - Professional Edition     ║"
    echo "║                        Version 3.0.0                            ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_divider() {
    echo -e "${BLUE}──────────────────────────────────────────────────────────────────${NC}"
}

print_section() {
    echo ""
    echo -e "${BOLD}${CYAN}▶ $1${NC}"
    print_divider
}

# ─────────────────────────────────────────────────────────────────────────────
#  Global Configuration
# ─────────────────────────────────────────────────────────────────────────────
CONFIG_MODE="interactive"    # interactive | non-interactive | dry-run
DRY_RUN=false

OE_USER=""
OE_VERSION=""
OE_PORT=""
LONGPOLLING_PORT=""
NGINX_CHOICE="n"
NGINX_DOMAIN=""
SSL_CHOICE="n"
LETSENCRYPT_EMAIL=""
INSTALL_WKHTMLTOPDF="True"
GENERATE_RANDOM_PASSWORD="True"
OE_SUPERADMIN=""

SERVER_IP=$(hostname -I | awk '{print $1}')
SECRETS_FILE="/root/odoo-secrets.txt"
MANIFEST_DIR="/root/odoo-installs"
BACKUP_DIR="/root/odoo-backups"

# ─────────────────────────────────────────────────────────────────────────────
#  Validation Helpers
# ─────────────────────────────────────────────────────────────────────────────
check_instance_exists() {
    local user="$1"
    id "$user" &>/dev/null && return 0
    [ -f "/etc/${user}-server.conf" ] && return 0
    systemctl list-unit-files --type=service 2>/dev/null | grep -q "^${user}-server\.service" && return 0
    return 1
}

check_port_in_use() {
    local port="$1"
    ss -tuln 2>/dev/null | grep -q ":$port\b" && return 0
    return 1
}

check_nginx_installed() {
    command -v nginx &>/dev/null
}

validate_instance_name() {
    [[ "$1" =~ ^[a-z][a-z0-9_-]*$ ]]
}

validate_port_range() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1024 ] && [ "$1" -le 65535 ]
}

# ─────────────────────────────────────────────────────────────────────────────
#  CLI Argument Parsing
# ─────────────────────────────────────────────────────────────────────────────
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --non-interactive)  CONFIG_MODE="non-interactive"; shift ;;
            --dry-run)          DRY_RUN=true; CONFIG_MODE="non-interactive"; shift ;;
            --instance)         OE_USER="$2"; shift 2 ;;
            --version)          OE_VERSION="$2"; shift 2 ;;
            --port)             OE_PORT="$2"; shift 2 ;;
            --nginx)            NGINX_CHOICE="y"; shift ;;
            --domain)           NGINX_DOMAIN="$2"; shift 2 ;;
            --ssl)              SSL_CHOICE="y"; shift ;;
            --email)            LETSENCRYPT_EMAIL="$2"; shift 2 ;;
            --help|-h)          show_help; exit 0 ;;
            *)                  shift ;;
        esac
    done
}

show_help() {
    print_banner
    echo -e "${BOLD}Usage:${NC}"
    echo ""
    echo "  Interactive (default):"
    echo "    sudo ./install_odoo.sh"
    echo ""
    echo "  Non-Interactive:"
    echo "    sudo ./install_odoo.sh --non-interactive \\"
    echo "      --instance <name> --version <17.0|18.0|19.0> --port <port> \\"
    echo "      [--nginx] [--domain <domain>] [--ssl] [--email <email>]"
    echo ""
    echo "  Dry-Run (simulate only):"
    echo "    sudo ./install_odoo.sh --dry-run --instance test --version 18.0 --port 8069"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    printf "  %-20s %s\n" "--instance"   "Instance name (e.g., odoo-prod)"
    printf "  %-20s %s\n" "--version"    "Odoo version: 19.0 | 18.0 | 17.0 | 16.0"
    printf "  %-20s %s\n" "--port"       "HTTP port (default: 8069)"
    printf "  %-20s %s\n" "--nginx"      "Enable Nginx reverse proxy"
    printf "  %-20s %s\n" "--domain"     "Domain name for Nginx"
    printf "  %-20s %s\n" "--ssl"        "Enable Let's Encrypt SSL"
    printf "  %-20s %s\n" "--email"      "Email for SSL notifications"
    printf "  %-20s %s\n" "--dry-run"    "Simulate without making changes"
    printf "  %-20s %s\n" "--help, -h"   "Show this help message"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Handle Existing Instance (with optional backup)
# ─────────────────────────────────────────────────────────────────────────────
handle_existing_instance() {
    local user="$1"

    echo -e "${RED}"
    echo "  ┌─────────────────────────────────────────────────────────┐"
    echo "  │  ⚠  WARNING: This action is IRREVERSIBLE!               │"
    echo "  │     All files, logs, configs, and data will be lost.    │"
    echo "  └─────────────────────────────────────────────────────────┘"
    echo -e "${NC}"

    # Offer backup before deletion
    read -p "  Create automatic backup before deletion? (y/N): " BACKUP_CHOICE
    BACKUP_CHOICE=$(echo "$BACKUP_CHOICE" | tr '[:upper:]' '[:lower:]')
    if [[ "$BACKUP_CHOICE" == "y" || "$BACKUP_CHOICE" == "yes" ]]; then
        sudo mkdir -p "$BACKUP_DIR"
        local BACKUP_FILE="$BACKUP_DIR/${user}_$(date +%Y%m%d_%H%M%S).tar.gz"
        local DB_BACKUP="$BACKUP_DIR/${user}_db_$(date +%Y%m%d_%H%M%S).sql"

        print_step "Creating filesystem backup: $BACKUP_FILE"
        sudo tar -czf "$BACKUP_FILE" \
            "/$user" \
            "/etc/${user}-server.conf" \
            "/var/log/$user" 2>/dev/null || true

        print_step "Creating PostgreSQL backup: $DB_BACKUP"
        sudo -u postgres pg_dump "$user" > "$DB_BACKUP" 2>/dev/null || true

        print_info "Full backup saved to: $BACKUP_DIR"
    fi

    # Ask about PostgreSQL separately
    read -p "  Also delete the PostgreSQL database and user? (y/N): " DROP_DB_CHOICE
    local DROP_POSTGRES=false
    [[ "$(echo "$DROP_DB_CHOICE" | tr '[:upper:]' '[:lower:]')" =~ ^(y|yes)$ ]] && DROP_POSTGRES=true

    print_step "Stopping Odoo service and killing related processes..."
    sudo systemctl stop "${user}-server"  2>/dev/null || true
    sudo systemctl kill --signal=SIGKILL "${user}-server" 2>/dev/null || true
    sleep 2
    sudo pkill -9 -u "$user" 2>/dev/null || true

    print_step "Removing systemd service and config files..."
    sudo systemctl disable --quiet "${user}-server" 2>/dev/null || true
    sudo rm -f "/etc/systemd/system/${user}-server.service"
    sudo rm -f "/etc/${user}-server.conf"
    sudo systemctl daemon-reload

    print_step "Removing system user and home directory..."
    sudo userdel -r "$user" 2>/dev/null || true
    sudo rm -rf "/$user"
    sudo rm -rf "/var/log/$user"

    if [ "$DROP_POSTGRES" == true ]; then
        print_danger "Deleting PostgreSQL database and user: '$user'"
        sudo -u postgres psql -d postgres -c \
            "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$user';" \
            >/dev/null 2>&1 || true
        sudo -u postgres psql -d postgres -c "DROP DATABASE IF EXISTS \"$user\";" >/dev/null 2>&1 || true
        sudo -u postgres psql -d postgres -c "DROP USER IF EXISTS \"$user\";"     >/dev/null 2>&1 || true
        print_info "PostgreSQL database and user deleted."
    else
        print_info "PostgreSQL database and user preserved."
    fi

    # Remove Nginx config if present
    sudo rm -f "/etc/nginx/sites-available/$user"
    sudo rm -f "/etc/nginx/sites-enabled/$user"

    print_info "Instance '$user' removed successfully."
}

# ─────────────────────────────────────────────────────────────────────────────
#  Phase 1: Gather Inputs
# ─────────────────────────────────────────────────────────────────────────────
gather_inputs() {
    clear
    print_banner

    # ── Instance Name ──────────────────────────────────────────────────────
    print_section "Instance Configuration"
    while true; do
        read -p "  Instance name (e.g., odoo-prod): " OE_USER
        if ! validate_instance_name "$OE_USER"; then
            print_error "Invalid name. Must start with a lowercase letter and contain only: a-z 0-9 - _"
        fi
        if check_instance_exists "$OE_USER"; then
            echo ""
            print_warn "Instance '$OE_USER' already exists!"
            echo "  What would you like to do?"
            echo "    1) Delete the existing instance and reinstall"
            echo "    2) Enter a different instance name"
            read -p "  Choice (1/2): " CONFLICT_CHOICE
            case $CONFLICT_CHOICE in
                1) handle_existing_instance "$OE_USER"; break ;;
                2) OE_USER=""; continue ;;
                *) print_warn "Invalid choice. Please enter 1 or 2." ;;
            esac
        else
            break
        fi
    done

    # ── Odoo Version ───────────────────────────────────────────────────────
    print_section "Odoo Version"
    echo "    1) 19.0  — Latest"
    echo "    2) 18.0  — Stable (recommended)"
    echo "    3) 17.0  — LTS"
    echo "    4) 16.0  — Legacy"
    echo ""
    while true; do
        read -p "  Select version (1-4): " VER_CHOICE
        case $VER_CHOICE in
            1) OE_VERSION="19.0"; break ;;
            2) OE_VERSION="18.0"; break ;;
            3) OE_VERSION="17.0"; break ;;
            4) OE_VERSION="16.0"; break ;;
            *) print_warn "Please select 1, 2, 3, or 4." ;;
        esac
    done
    print_info "Selected Odoo version: $OE_VERSION"

    # ── HTTP Port ──────────────────────────────────────────────────────────
    print_section "Port Configuration"
    while true; do
        read -p "  HTTP port [default: 8069]: " OE_PORT
        OE_PORT="${OE_PORT:-8069}"
        if ! validate_port_range "$OE_PORT"; then
            print_warn "Port must be between 1024 and 65535."
            continue
        fi
        if check_port_in_use "$OE_PORT"; then
            print_warn "Port $OE_PORT is already in use!"
            read -p "  Enter a different port: " OE_PORT
            continue
        fi
        break
    done
    LONGPOLLING_PORT=$((OE_PORT + 3))
    if check_port_in_use "$LONGPOLLING_PORT"; then
        print_warn "Longpolling port $LONGPOLLING_PORT is in use. Live features may not work."
    fi
    print_info "HTTP port: $OE_PORT  |  Longpolling port: $LONGPOLLING_PORT"

    # ── Nginx ──────────────────────────────────────────────────────────────
    print_section "Nginx Reverse Proxy"
    read -p "  Configure Nginx for this instance? (y/N): " NGINX_CHOICE
    NGINX_CHOICE=$(echo "$NGINX_CHOICE" | tr '[:upper:]' '[:lower:]')

    if [[ "$NGINX_CHOICE" == "y" || "$NGINX_CHOICE" == "yes" ]]; then
        read -p "  Domain name [default: $SERVER_IP]: " NGINX_DOMAIN
        NGINX_DOMAIN="${NGINX_DOMAIN:-$SERVER_IP}"

        read -p "  Enable Let's Encrypt SSL? (y/N): " SSL_CHOICE
        SSL_CHOICE=$(echo "$SSL_CHOICE" | tr '[:upper:]' '[:lower:]')

        if [[ "$SSL_CHOICE" == "y" || "$SSL_CHOICE" == "yes" ]]; then
            while true; do
                read -p "  Email for SSL notifications: " LETSENCRYPT_EMAIL
                [[ -n "$LETSENCRYPT_EMAIL" ]] && break
                print_warn "Email is required for Let's Encrypt."
            done
        fi
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  Phase 2: Validation Summary
# ─────────────────────────────────────────────────────────────────────────────
validate_configuration() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                      Installation Summary                       ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════════╣${NC}"
    printf  "${BLUE}║${NC}  %-22s : %-40s ${BLUE}║${NC}\n" "Instance Name"     "$OE_USER"
    printf  "${BLUE}║${NC}  %-22s : %-40s ${BLUE}║${NC}\n" "Odoo Version"      "$OE_VERSION"
    printf  "${BLUE}║${NC}  %-22s : %-40s ${BLUE}║${NC}\n" "HTTP Port"         "$OE_PORT"
    printf  "${BLUE}║${NC}  %-22s : %-40s ${BLUE}║${NC}\n" "Longpolling Port"  "$LONGPOLLING_PORT"
    printf  "${BLUE}║${NC}  %-22s : %-40s ${BLUE}║${NC}\n" "Nginx"             "${NGINX_CHOICE:-no}"
    if [[ "$NGINX_CHOICE" =~ ^(y|yes)$ ]]; then
        printf "${BLUE}║${NC}  %-22s : %-40s ${BLUE}║${NC}\n" "Domain"           "$NGINX_DOMAIN"
        if [[ "$SSL_CHOICE" =~ ^(y|yes)$ ]]; then
            printf "${BLUE}║${NC}  %-22s : %-40s ${BLUE}║${NC}\n" "SSL"           "Let's Encrypt"
            printf "${BLUE}║${NC}  %-22s : %-40s ${BLUE}║${NC}\n" "SSL Email"     "$LETSENCRYPT_EMAIL"
        else
            printf "${BLUE}║${NC}  %-22s : %-40s ${BLUE}║${NC}\n" "SSL"           "None"
        fi
    fi
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [[ "$CONFIG_MODE" == "non-interactive" ]]; then
        print_info "Non-interactive mode — proceeding automatically."
        return 0
    fi

    read -p "Proceed with installation? (y/N): " CONFIRM
    CONFIRM=$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "yes" ]]; then
        print_info "Installation cancelled."
        exit 0
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  Execute Step Helper
# ─────────────────────────────────────────────────────────────────────────────
execute_step() {
    local name="$1"
    local func="$2"
    print_step "$name"
    if $DRY_RUN; then
        print_info "[DRY RUN] Would execute: $func"
        return 0
    fi
    $func
}

# ─────────────────────────────────────────────────────────────────────────────
#  Installation Steps
# ─────────────────────────────────────────────────────────────────────────────
step_check_tools() {
    for cmd in wget git gpg curl bc lsb_release; do
        command -v "$cmd" &>/dev/null || print_error "'$cmd' is required but not installed."
    done
    print_info "All required tools are present."
}

step_check_ubuntu() {
    UBUNTU_VERSION=$(lsb_release -r -s 2>/dev/null || echo "unknown")
    [[ "$UBUNTU_VERSION" == "unknown" ]] && print_error "Cannot detect Ubuntu version."
    if (( $(echo "$UBUNTU_VERSION >= 22.04" | bc -l) )); then
        print_info "Ubuntu $UBUNTU_VERSION is supported."
    else
        print_error "Ubuntu 22.04+ is required. Detected: $UBUNTU_VERSION"
    fi
}

step_update_system() {
    sudo apt update -y
    sudo apt full-upgrade -y
    sudo apt autoremove -y
    sudo apt autoclean -y
    print_info "System packages updated."
}

step_install_packages() {
    sudo apt install -y \
        curl wget gnupg apt-transport-https git build-essential \
        libxslt-dev libzip-dev libldap2-dev libsasl2-dev \
        libjpeg-dev libpng-dev gdebi libpq-dev \
        fonts-dejavu-core fonts-font-awesome fonts-roboto-unhinted \
        adduser lsb-base vim \
        python3 python3-dev python3-venv python3-wheel \
        lsb-release bc
    print_info "System packages installed."
}

step_install_nodejs() {
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - \
        || print_error "Failed to add NodeSource repository."
    sudo apt install -y nodejs || print_error "Failed to install Node.js 20."
    sudo npm install -g rtlcss
    print_info "Node.js 20 LTS and rtlcss installed."
}

step_install_wkhtmltopdf() {
    if [ "$INSTALL_WKHTMLTOPDF" != "True" ]; then
        print_warn "Skipping wkhtmltopdf installation."
        return
    fi
    local WKHTML_DEB="/tmp/wkhtmltox_${OE_USER}.deb"
    local WKHTML_URL="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb"
    wget -q "$WKHTML_URL" -O "$WKHTML_DEB" || print_error "Failed to download wkhtmltopdf."
    sudo gdebi -n "$WKHTML_DEB"            || print_error "Failed to install wkhtmltopdf."
    rm -f "$WKHTML_DEB"
    print_info "wkhtmltopdf 0.12.6.1-3 installed."
}

step_setup_postgresql() {
    if dpkg -l 2>/dev/null | grep -q "postgresql-16"; then
        print_info "PostgreSQL 16 is already installed."
        systemctl is-active --quiet postgresql || {
            sudo systemctl start postgresql
            sudo systemctl enable postgresql
        }
    else
        curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
            | gpg --dearmor \
            | sudo tee /usr/share/keyrings/postgresql.gpg > /dev/null
        echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] \
http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
            | sudo tee /etc/apt/sources.list.d/pgdg.list > /dev/null
        sudo apt update -y
        sudo apt install -y postgresql-16 || print_error "Failed to install PostgreSQL 16."
        print_info "PostgreSQL 16 installed."
    fi
}

step_create_pg_user() {
    if ! sudo -u postgres psql -d postgres -tAc \
        "SELECT 1 FROM pg_roles WHERE rolname='$OE_USER'" 2>/dev/null | grep -q 1
    then
        sudo -u postgres createuser -s "$OE_USER"
        print_info "PostgreSQL user '$OE_USER' created."
    else
        print_warn "PostgreSQL user '$OE_USER' already exists."
    fi
}

step_create_system_user() {
    if id "$OE_USER" &>/dev/null; then
        print_warn "System user '$OE_USER' already exists."
    else
        sudo adduser --system --quiet --shell=/bin/bash \
            --home="/$OE_USER" --gecos 'ODOO' --group "$OE_USER"
        print_info "System user '$OE_USER' created."
    fi
}

step_setup_log_dir() {
    sudo mkdir -p "/var/log/$OE_USER"
    sudo chown "$OE_USER:$OE_USER" "/var/log/$OE_USER"
    print_info "Log directory: /var/log/$OE_USER"
}

step_clone_odoo() {
    local OE_HOME_EXT="/$OE_USER/${OE_USER}-server"
    if [ -d "$OE_HOME_EXT" ]; then
        print_warn "Odoo source directory exists. Skipping clone."
    else
        sudo -u "$OE_USER" git clone --depth 1 --branch "$OE_VERSION" \
            https://github.com/odoo/odoo "$OE_HOME_EXT"
        print_info "Odoo $OE_VERSION cloned."
    fi
}

step_create_addons_dir() {
    sudo -u "$OE_USER" mkdir -p "/$OE_USER/custom/addons"
    print_info "Custom addons directory: /$OE_USER/custom/addons"
}

step_set_permissions() {
    sudo chown -R "$OE_USER:$OE_USER" "/$OE_USER"
    print_info "Permissions set for /$OE_USER"
}

step_create_venv() {
    local VENV_PATH="/$OE_USER/venv"
    sudo -u "$OE_USER" python3 -m venv "$VENV_PATH"

    print_step "Upgrading pip, setuptools, and wheel..."
    sudo -u "$OE_USER" "$VENV_PATH/bin/pip" install --upgrade pip setuptools wheel

    print_step "Installing extra required packages..."
    sudo -u "$OE_USER" "$VENV_PATH/bin/pip" install qifparse python-escpos pillow
    print_info "Python virtual environment ready: $VENV_PATH"
}

step_install_python_deps() {
    local VENV_PATH="/$OE_USER/venv"
    local REQ_FILE="/tmp/odoo_reqs_${OE_USER}.txt"
    local REQ_URL="https://github.com/odoo/odoo/raw/${OE_VERSION}/requirements.txt"

    wget -q "$REQ_URL" -O "$REQ_FILE" || print_error "Failed to download requirements.txt"

    # cbor2==5.4.2 in requirements.txt is broken on Python 3.10 — its setup.py
    # calls pkg_resources which is missing even with --no-build-isolation on newer pip.
    # Fix: replace the pinned broken version with cbor2>=5.4.6 which ships a proper
    # wheel and installs cleanly on Python 3.10 without any build step.
    sed -i 's/^cbor2==.*/cbor2>=5.4.6/' "$REQ_FILE"
    print_step "cbor2 version unpinned to >=5.4.6 (fixes Python 3.10 build failure)"

    # Fix known gevent compatibility issue on Odoo 16-18
    if [[ "$OE_VERSION" =~ ^1[6-8]\.0$ ]]; then
        print_warn "Detected Odoo $OE_VERSION -- pinning gevent to 23.9.1 for compatibility."
        sed -i '/gevent/d' "$REQ_FILE"
        sudo -u "$OE_USER" "$VENV_PATH/bin/pip" install -r "$REQ_FILE" || print_warn "Some packages failed."
        sudo -u "$OE_USER" "$VENV_PATH/bin/pip" install "gevent==23.9.1"
    else
        sudo -u "$OE_USER" "$VENV_PATH/bin/pip" install -r "$REQ_FILE" || print_warn "Some packages failed."
    fi

    rm -f "$REQ_FILE"
    print_info "Python dependencies installed."
}

step_create_config() {
    local OE_HOME_EXT="/$OE_USER/${OE_USER}-server"
    local VENV_PATH="/$OE_USER/venv"
    local CONFIG_FILE="/etc/${OE_USER}-server.conf"

    if [ "$GENERATE_RANDOM_PASSWORD" == "True" ]; then
        OE_SUPERADMIN=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)
        echo "$(date '+%Y-%m-%d %H:%M:%S')  instance='$OE_USER'  master_password='$OE_SUPERADMIN'" \
            >> "$SECRETS_FILE"
        sudo chmod 600 "$SECRETS_FILE"
    fi

    sudo touch "$CONFIG_FILE"
    sudo chmod 640 "$CONFIG_FILE"
    sudo chown "$OE_USER:$OE_USER" "$CONFIG_FILE"

    sudo tee "$CONFIG_FILE" > /dev/null <<EOF
[options]
admin_passwd       = ${OE_SUPERADMIN}
http_port          = ${OE_PORT}
longpolling_port   = ${LONGPOLLING_PORT}
logfile            = /var/log/${OE_USER}/${OE_USER}-server.log
addons_path        = ${OE_HOME_EXT}/addons,/$OE_USER/custom/addons
EOF

    print_info "Config file: $CONFIG_FILE"
}

step_create_service() {
    local OE_HOME_EXT="/$OE_USER/${OE_USER}-server"
    local VENV_PATH="/$OE_USER/venv"
    local CONFIG_FILE="/etc/${OE_USER}-server.conf"
    local SERVICE_FILE="/etc/systemd/system/${OE_USER}-server.service"

    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Odoo Instance: $OE_USER
Documentation=https://www.odoo.com
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
    print_info "Systemd service: ${OE_USER}-server"
}

step_start_service() {
    sudo systemctl start "${OE_USER}-server"
    sleep 3
    if ! sudo systemctl is-active --quiet "${OE_USER}-server"; then
        print_error "Odoo service failed to start. Run: journalctl -u ${OE_USER}-server -n 50"
    fi
    print_info "Odoo service is running."
}

step_configure_nginx() {
    if ! check_nginx_installed; then
        print_step "Installing Nginx..."
        sudo apt install -y nginx || print_error "Failed to install Nginx."
        sudo ufw allow 'Nginx Full' 2>/dev/null || true
        print_info "Nginx installed."
    else
        print_info "Nginx is already installed."
    fi

    # Ensure www-data exists
    id www-data &>/dev/null || print_error "Nginx user 'www-data' not found."

    # Global: client_max_body_size
    if ! grep -q "client_max_body_size 1G;" /etc/nginx/nginx.conf; then
        sudo sed -i '/http {/a \    client_max_body_size 1G;' /etc/nginx/nginx.conf
        print_info "Set global client_max_body_size = 1G"
    fi

    # WebSocket global map (in conf.d)
    if ! grep -rq 'map \$http_upgrade \$connection_upgrade' \
            /etc/nginx/nginx.conf /etc/nginx/conf.d/ 2>/dev/null; then
        sudo tee /etc/nginx/conf.d/ws_upgrade_map.conf > /dev/null <<'WSMAP'
# WebSocket upgrade map — required for Odoo Bus, Live Chat, POS, IoT
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
WSMAP
        print_info "WebSocket upgrade map added."
    fi

    # ACME challenge directory
    sudo mkdir -p /var/www/certbot/.well-known/acme-challenge
    sudo chown -R www-data:www-data /var/www/certbot

    # Nginx cache directories
    sudo mkdir -p "/var/cache/nginx/odoo_static_${OE_USER}"
    sudo chown -R www-data:www-data /var/cache/nginx

    local NGINX_SITE="/etc/nginx/sites-available/${OE_USER}"
    local UPSTREAM_MAIN="odoo_${OE_USER}"
    local UPSTREAM_LP="odoo_${OE_USER}_lp"
    local CACHE_ZONE="static_${OE_USER}"

    sudo tee "$NGINX_SITE" > /dev/null <<NGINXEOF
# ──────────────────────────────────────────────────────────────────────────
# Nginx Configuration for Odoo Instance: ${OE_USER}
# ──────────────────────────────────────────────────────────────────────────

upstream ${UPSTREAM_MAIN} {
    server 127.0.0.1:${OE_PORT};
    keepalive 32;
}

upstream ${UPSTREAM_LP} {
    server 127.0.0.1:${LONGPOLLING_PORT};
    keepalive 32;
}

proxy_cache_path /var/cache/nginx/odoo_static_${OE_USER}
    levels=1:2
    keys_zone=${CACHE_ZONE}:100m
    inactive=60m
    max_size=2g;

server {
    listen 80;
    listen [::]:80;
    server_name ${NGINX_DOMAIN};
    charset utf-8;

    # ── ACME Challenge (Let's Encrypt) ──────────────────────────────────
    location ^~ /.well-known/acme-challenge/ {
        allow all;
        root /var/www/certbot;
        default_type "text/plain";
        try_files \$uri =404;
    }

    # ── Block Database Manager (security) ───────────────────────────────
    location ~* ^/web/database {
        deny all;
        return 403;
    }

    # ── Static Assets (cached) ──────────────────────────────────────────
    location /web/static/ {
        proxy_pass http://${UPSTREAM_MAIN};
        proxy_cache ${CACHE_ZONE};
        proxy_cache_valid 200 7d;
        proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
        proxy_ignore_headers Cache-Control Expires;
        expires 7d;
        add_header Cache-Control "public, max-age=604800" always;
    }

    # ── WebSocket (Bus, Live Chat, Kitchen Screen, IoT) ─────────────────
    location /websocket {
        proxy_pass http://${UPSTREAM_MAIN};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 3600;
        proxy_buffering off;
    }

    # ── Longpolling ─────────────────────────────────────────────────────
    location /longpolling {
        proxy_pass http://${UPSTREAM_LP};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 3600;
        proxy_buffering off;
    }

    # ── Main Application ────────────────────────────────────────────────
    location / {
        proxy_pass http://${UPSTREAM_MAIN};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_connect_timeout 60;
        proxy_send_timeout 300;
        proxy_read_timeout 600;
        client_max_body_size 128M;
    }

    access_log /var/log/nginx/${OE_USER}_access.log;
    error_log  /var/log/nginx/${OE_USER}_error.log warn;
}
NGINXEOF

    sudo ln -sf "$NGINX_SITE" "/etc/nginx/sites-enabled/${OE_USER}"

    sudo nginx -t || print_error "Nginx configuration test failed!"
    sudo systemctl reload nginx
    print_info "Nginx configured for instance '$OE_USER'."

    # Enable proxy_mode in Odoo config
    local CONFIG_FILE="/etc/${OE_USER}-server.conf"
    if ! grep -q "^proxy_mode" "$CONFIG_FILE"; then
        echo "proxy_mode         = True" | sudo tee -a "$CONFIG_FILE" > /dev/null
        sudo systemctl restart "${OE_USER}-server"
    fi

    # ── SSL / Let's Encrypt ────────────────────────────────────────────
    if [[ "$SSL_CHOICE" =~ ^(y|yes)$ ]]; then
        print_step "Requesting SSL certificate from Let's Encrypt..."
        sudo apt install -y certbot python3-certbot-nginx \
            || print_error "Failed to install Certbot."

        if sudo certbot --nginx \
                --non-interactive --agree-tos \
                --email "$LETSENCRYPT_EMAIL" \
                --domains "$NGINX_DOMAIN" \
                --redirect 2>/dev/null; then
            print_info "SSL certificate installed. HTTPS enabled."
            NGINX_ACCESS_URL="https://${NGINX_DOMAIN}"
        else
            print_warn "SSL certificate request failed. Falling back to HTTP."
            NGINX_ACCESS_URL="http://${NGINX_DOMAIN}"
        fi

        # Block direct port access when using Nginx+SSL
        sudo ufw deny "$OE_PORT" 2>/dev/null || true
        print_info "Direct port $OE_PORT blocked (Nginx handles traffic)."
    else
        NGINX_ACCESS_URL="http://${NGINX_DOMAIN}"
        sudo ufw deny "$OE_PORT" 2>/dev/null || true
        print_info "Direct port $OE_PORT blocked (Nginx handles traffic)."
    fi
}

step_generate_manifest() {
    sudo mkdir -p "$MANIFEST_DIR"
    local MANIFEST_FILE="$MANIFEST_DIR/${OE_USER}_$(date +%Y%m%d_%H%M%S)_manifest.json"
    local NGINX_EN="false"
    local SSL_EN="false"
    [[ "$NGINX_CHOICE" =~ ^(y|yes)$ ]] && NGINX_EN="true"
    [[ "$SSL_CHOICE"   =~ ^(y|yes)$ ]] && SSL_EN="true"

    cat > "$MANIFEST_FILE" <<EOF
{
  "instance_name":    "$OE_USER",
  "odoo_version":     "$OE_VERSION",
  "http_port":        $OE_PORT,
  "longpolling_port": $LONGPOLLING_PORT,
  "nginx_enabled":    $NGINX_EN,
  "domain":           "$NGINX_DOMAIN",
  "ssl_enabled":      $SSL_EN,
  "ssl_email":        "$LETSENCRYPT_EMAIL",
  "server_ip":        "$SERVER_IP",
  "installation_date":"$(date -Iseconds)"
}
EOF
    sudo chmod 600 "$MANIFEST_FILE"
    print_info "Manifest saved: $MANIFEST_FILE"
}

step_cleanup() {
    rm -f "/tmp/odoo_reqs_${OE_USER}.txt" "/tmp/wkhtmltox_${OE_USER}.deb" 2>/dev/null || true
    print_info "Temporary files removed."
}

# ─────────────────────────────────────────────────────────────────────────────
#  Phase 3: Execute Installation
# ─────────────────────────────────────────────────────────────────────────────
execute_installation() {
    local START_TIME
    START_TIME=$(date +%s)

    print_section "System Preparation"
    execute_step "Checking required tools"   step_check_tools
    execute_step "Checking Ubuntu version"   step_check_ubuntu
    execute_step "Updating system packages"  step_update_system
    execute_step "Installing system packages" step_install_packages
    execute_step "Installing Node.js 20 LTS" step_install_nodejs
    execute_step "Installing wkhtmltopdf"    step_install_wkhtmltopdf

    print_section "PostgreSQL Setup"
    execute_step "Setting up PostgreSQL 16"  step_setup_postgresql
    execute_step "Creating PostgreSQL user"  step_create_pg_user

    print_section "System User & Directories"
    execute_step "Creating system user"      step_create_system_user
    execute_step "Setting up log directory"  step_setup_log_dir

    print_section "Odoo Source & Python"
    execute_step "Cloning Odoo source"       step_clone_odoo
    execute_step "Creating custom addons dir" step_create_addons_dir
    execute_step "Setting permissions"       step_set_permissions
    execute_step "Creating Python venv"      step_create_venv
    execute_step "Installing Python deps"    step_install_python_deps

    print_section "Service Configuration"
    execute_step "Creating Odoo config file" step_create_config
    execute_step "Creating systemd service"  step_create_service
    execute_step "Starting Odoo service"     step_start_service

    if [[ "$NGINX_CHOICE" =~ ^(y|yes)$ ]]; then
        print_section "Nginx & SSL"
        execute_step "Configuring Nginx"     step_configure_nginx
    else
        NGINX_ACCESS_URL="http://${SERVER_IP}:${OE_PORT}"
    fi

    print_section "Finalization"
    execute_step "Generating manifest"       step_generate_manifest
    execute_step "Cleaning up temp files"    step_cleanup

    # ── Duration ────────────────────────────────────────────────────────────
    local END_TIME DURATION
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    # ── Production Security Advisory ────────────────────────────────────────
    echo -e "${PURPLE}"
    echo "  ─── Production Hardening Checklist ─────────────────────────────"
    echo ""
    echo "  [ ] Disable the database manager (production only):"
    echo ""
    echo "      Option A — Nginx (recommended):"
    echo "        sudo nano /etc/nginx/sites-available/${OE_USER}"
    echo "        # Ensure this block exists:"
    echo "        #   location ~* ^/web/database { deny all; return 403; }"
    echo "        sudo nginx -t && sudo systemctl reload nginx"
    echo ""
    echo "      Option B — Odoo config:"
    echo "        sudo nano /etc/${OE_USER}-server.conf"
    echo "        # Add:  list_db = False"
    echo "        #        dbfilter = ^${OE_USER}\$"
    echo "        sudo systemctl restart ${OE_USER}-server"
    echo ""
    echo "  [ ] Review UFW firewall rules:   sudo ufw status"
    echo "  [ ] Enable automatic OS updates: sudo dpkg-reconfigure unattended-upgrades"
    echo "  [ ] Set up log rotation:         /etc/logrotate.d/"
    echo ""
    echo "  ─────────────────────────────────────────────────────────────────"
    echo -e "${NC}"

    # ── Final Summary Box ───────────────────────────────────────────────────
    echo ""
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                   ✅  Installation Complete!                    ║"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    printf "║  %-22s : %-40s║\n" "Instance Name"     "$OE_USER"
    printf "║  %-22s : %-40s║\n" "Odoo Version"      "$OE_VERSION"
    printf "║  %-22s : %-40s║\n" "Service Name"      "${OE_USER}-server"
    printf "║  %-22s : %-40s║\n" "HTTP Port"         "$OE_PORT"
    printf "║  %-22s : %-40s║\n" "Longpolling Port"  "$LONGPOLLING_PORT"
    printf "║  %-22s : %-40s║\n" "Access URL"        "$NGINX_ACCESS_URL"
    printf "║  %-22s : %-40s║\n" "Config File"       "/etc/${OE_USER}-server.conf"
    printf "║  %-22s : %-40s║\n" "Log File"          "/var/log/$OE_USER/${OE_USER}-server.log"
    printf "║  %-22s : %-40s║\n" "Source Code"       "/$OE_USER/${OE_USER}-server"
    printf "║  %-22s : %-40s║\n" "Custom Addons"     "/$OE_USER/custom/addons"
    printf "║  %-22s : %-40s║\n" "Install Time"      "$((DURATION / 60)) min $((DURATION % 60)) sec"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    echo -e "${NC}${BOLD}${RED}"
    printf "║  %-22s : %-40s║\n" "🔑 Master Password" "$OE_SUPERADMIN"
    echo -e "${NC}${GREEN}"
    printf "║  %-22s : %-40s║\n" "Password Backup"   "$SECRETS_FILE"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # ── Security Warning ────────────────────────────────────────────────────
    echo -e "${YELLOW}"
    echo "  ╔─────────────────────────────────────────────────────────────╗"
    echo "  │  🔒  SECURITY REMINDER — ACTION REQUIRED                    │"
    echo "  ├─────────────────────────────────────────────────────────────┤"
    echo "  │                                                             │"
    echo "  │  ⚠  The master password is displayed above in plain text.  │"
    echo "  │                                                             │"
    echo "  │  Before leaving this terminal, please:                     │"
    echo "  │                                                             │"
    echo "  │    1. Note or copy the master password somewhere safe.     │"
    echo "  │    2. Clear the terminal history:                          │"
    echo "  │         history -c && history -w                           │"
    echo "  │    3. Or scroll the terminal to push logs off-screen.      │"
    echo "  │                                                             │"
    echo "  │  The password is also saved in (root-only):               │"
    echo "  │    $SECRETS_FILE"
    printf "  │  %-61s│\n" ""
    echo "  ╚─────────────────────────────────────────────────────────────╝"
    echo -e "${NC}"

    # ── Quick Commands ───────────────────────────────────────────────────────
    echo -e "${CYAN}  Quick commands:${NC}"
    echo "    Status  : sudo systemctl status ${OE_USER}-server"
    echo "    Restart : sudo systemctl restart ${OE_USER}-server"
    echo "    Logs    : sudo journalctl -u ${OE_USER}-server -f"
    echo "    Config  : sudo nano /etc/${OE_USER}-server.conf"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
#  Main
# ─────────────────────────────────────────────────────────────────────────────
main() {
    # Must run as root
    if [[ "$EUID" -ne 0 ]]; then
        echo -e "${RED}[✖ ERROR]${NC} Please run as root: sudo $0 $*"
        exit 1
    fi

    parse_arguments "$@"

    if [[ "$CONFIG_MODE" == "interactive" ]]; then
        gather_inputs
    else
        # Validate non-interactive required fields
        [[ -z "$OE_USER" ]]    && print_error "--instance is required in non-interactive mode."
        [[ -z "$OE_VERSION" ]] && print_error "--version is required in non-interactive mode."
        [[ -z "$OE_PORT" ]]    && OE_PORT="8069"
        validate_instance_name "$OE_USER" || print_error "Invalid instance name: $OE_USER"
        validate_port_range "$OE_PORT"    || print_error "Invalid port: $OE_PORT"
        LONGPOLLING_PORT=$((OE_PORT + 3))
    fi

    validate_configuration
    execute_installation
}

main "$@"
