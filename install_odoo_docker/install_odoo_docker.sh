#!/bin/bash
# install_odoo_docker.sh
# Author: Ibrahim Aljuhani (Final Optimized Version - Official Images)
# Purpose: Install Odoo in Docker using OFFICIAL Docker Hub images
# Updated: 2025-10-25

set -euo pipefail

LOGFILE="$HOME/install_odoo_docker.log"
INSTALL_DIR="$HOME/odoo"
SECRETS_FILE="$HOME/.odoo-docker-secrets.txt"

# -----------------------------
# 🎨 Terminal Colors
# -----------------------------
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

# -----------------------------
# 🧾 Utility Functions
# -----------------------------
print_info()  { echo -e "${GREEN}[✓]${RESET} $1" >&2; }
print_warn()  { echo -e "${YELLOW}[!]${RESET} $1" >&2; }
print_error() { echo -e "${RED}[✗]${RESET} $1" >&2; exit 1; }
print_step()  { echo -e "\n${BLUE}${BOLD}==> $1${RESET}" >&2; }

show_progress() {
    local msg="$1"
    local cmd="$2"
    echo -ne "  $msg ... " >&2
    (
        eval "$cmd" > /dev/null 2>&1 &
        local pid=$!
        local spin='|/-\\'
        local i=0
        while kill -0 "$pid" 2>/dev/null; do
            i=$(( (i+1) % 4 ))
            printf "\b${spin:$i:1}" >&2
            sleep 0.1
        done
        wait "$pid"
        if [ $? -eq 0 ]; then
            echo -e "\b${GREEN}✓${RESET}" >&2
        else
            echo -e "\b${RED}✗${RESET}" >&2
            print_error "Operation failed during: $msg"
        fi
    )
}

# -----------------------------
# 🚫 Prevent root execution
# -----------------------------
if [[ $EUID -eq 0 ]]; then
  print_error "This script must NOT be run as root. Please run as a regular user in the docker group."
fi

# -----------------------------
# 🔧 Check prerequisites
# -----------------------------
check_prerequisites() {
    local missing=()

    if ! command -v docker &>/dev/null; then
        missing+=("Docker CE")
    fi

    # detect docker compose command
    if docker compose version &>/dev/null; then
        COMPOSE_CMD="docker compose"
    elif docker-compose version &>/dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        missing+=("Docker Compose")
    fi

    if ! command -v openssl &>/dev/null; then
        missing+=("openssl")
    fi
    if ! command -v curl &>/dev/null; then
        missing+=("curl")
    fi

    if [ ${#missing[@]} -ne 0 ]; then
        print_error "Missing required components: ${missing[*]}. Please install them first."
    fi

    print_info "All required components are installed."
}

# -----------------------------
# 📦 Validate instance name
# -----------------------------
validate_instance_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-z][a-z0-9_-]*$ ]]; then
        print_error "Invalid instance name. Must start with lowercase letter and contain only letters, digits, hyphens, or underscores."
    fi
}

# -----------------------------
# 🏷️ Choose Odoo version
# -----------------------------
choose_odoo_version() {
    echo -e "${BOLD}Choose Odoo version:${RESET}" >&2
    echo "1) 18.0 (Stable)"
    echo "2) 17.0 (Stable)"
    echo "3) 19.0 (Development - Use at your own risk)"
    local choice
    while true; do
        read -rp "Enter choice (1-3): " choice
        case "$choice" in
            1) ODOO_VERSION="18.0"; break ;;
            2) ODOO_VERSION="17.0"; break ;;
            3) 
                ODOO_VERSION="19.0"
                print_warn "⚠️  Odoo 19.0 is still in development. May not have official Docker files yet."
                break
                ;;
            *) echo "Invalid choice. Try again." ;;
        esac
    done
}

# -----------------------------
# 📁 Prepare install directory
# -----------------------------
prepare_install_dir() {
    mkdir -p "$INSTALL_DIR" || print_error "Failed to create $INSTALL_DIR"
    [[ -w "$INSTALL_DIR" ]] || print_error "No write permission for $INSTALL_DIR"
}

# -----------------------------
# 🔑 Generate random password
# -----------------------------
generate_password() {
    openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n1
}

# -----------------------------
# ⚓ Check port availability
# -----------------------------
check_port() {
    local port="$1"
    if command -v ss &>/dev/null; then
        if ss -tuln | grep -q ":$port "; then
            print_error "Port $port is already in use."
        fi
    elif command -v netstat &>/dev/null; then
        if netstat -tuln | grep -q ":$port "; then
            print_error "Port $port is already in use."
        fi
    else
        print_warn "Cannot verify port availability (ss/netstat not found)."
    fi
}

# -----------------------------
# 🚀 Main installation process
# -----------------------------
main() {
    # Handle help flag safely
    if [[ $# -gt 0 ]]; then
        case "$1" in
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo "Install Odoo in Docker using official images."
                exit 0
                ;;
        esac
    fi

    print_step "Checking prerequisites..."
    check_prerequisites

    prepare_install_dir

    read -rp "Enter instance name (e.g., odoo-prod): " INSTANCE_NAME
    validate_instance_name "$INSTANCE_NAME"
    INSTANCE_DIR="$INSTALL_DIR/$INSTANCE_NAME"
    [[ -d "$INSTANCE_DIR" ]] && print_error "Instance '$INSTANCE_NAME' already exists."

    choose_odoo_version

    read -rp "Enter HTTP port (default 8069): " ODOO_PORT
    ODOO_PORT="${ODOO_PORT:-8069}"
    if ! [[ "$ODOO_PORT" =~ ^[0-9]+$ ]] || [ "$ODOO_PORT" -lt 1024 ] || [ "$ODOO_PORT" -gt 65535 ]; then
        print_error "Port must be between 1024 and 65535."
    fi
    check_port "$ODOO_PORT"

    echo
    echo "Database Configuration:"
    read -rp "Enter PostgreSQL username (default: odoo): " DB_USER
    DB_USER="${DB_USER:-odoo}"

    read -rsp "Enter PostgreSQL password (leave blank to auto-generate): " DB_PASS
    echo
    if [ -z "$DB_PASS" ]; then
        DB_PASS=$(generate_password)
        print_warn "Auto-generated DB password: $DB_PASS"
    fi

    read -rp "Enter Database name (default: odoo): " DB_NAME
    DB_NAME="${DB_NAME:-odoo}"

    mkdir -p "$INSTANCE_DIR"/{config,addons,db-data,filestore}

    ADMIN_PASS=$(generate_password)

    # Save secrets securely
    {
        [[ ! -f "$SECRETS_FILE" ]] && echo "# Auto-generated Odoo secrets - DO NOT SHARE" > "$SECRETS_FILE"
        echo "$(date '+%F %T'): Instance '$INSTANCE_NAME' admin password: $ADMIN_PASS"
        echo "$(date '+%F %T'): DB '$DB_NAME' credentials: $DB_USER / $DB_PASS"
    } >>"$SECRETS_FILE"
    chmod 600 "$SECRETS_FILE"
    print_info "Credentials saved to $SECRETS_FILE."
    print_warn "⚠️  Keep this file secure. Never share it!"

    # Create .env file for docker-compose
    cat >"$INSTANCE_DIR/.env" <<EOF
POSTGRES_DB=$DB_NAME
POSTGRES_USER=$DB_USER
POSTGRES_PASSWORD=$DB_PASS
ADMIN_PASS=$ADMIN_PASS
EOF
    chmod 600 "$INSTANCE_DIR/.env"

    # Define official image
    CUSTOM_IMAGE="amd64/odoo:$ODOO_VERSION"

    # -----------------------------
    # 🧱 Generate docker-compose.yml
    # -----------------------------
    cat >"$INSTANCE_DIR/docker-compose.yml" <<EOF
services:
  odoo:
    image: $CUSTOM_IMAGE
    container_name: odoo-$INSTANCE_NAME
    depends_on:
      db:
        condition: service_healthy
    ports:
      - "$ODOO_PORT:8069"
    volumes:
      - ./config:/etc/odoo
      - ./addons:/mnt/extra-addons
      - ./filestore:/var/lib/odoo/filestore
    restart: unless-stopped
    environment:
      - ADMIN_PASS=\${ADMIN_PASS}
    env_file:
      - .env
    networks:
      - odoo-net-$INSTANCE_NAME

  db:
    image: postgres:15
    container_name: odoo-$INSTANCE_NAME-db
    env_file:
      - .env
    volumes:
      - ./db-data:/var/lib/postgresql/data
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \$POSTGRES_USER -d \$POSTGRES_DB"]
      interval: 5s
      timeout: 5s
      retries: 10
    networks:
      - odoo-net-$INSTANCE_NAME

networks:
  odoo-net-$INSTANCE_NAME:
    driver: bridge
EOF

    # Minimal config
    cat >"$INSTANCE_DIR/config/odoo.conf" <<EOF
[options]
admin_passwd = \${ADMIN_PASS}
addons_path = /mnt/extra-addons,/etc/odoo/addons
data_dir = /var/lib/odoo
EOF

    print_step "Starting Odoo instance..."
    (
        cd "$INSTANCE_DIR" && $COMPOSE_CMD up -d 2>&1 | tee -a "$LOGFILE"
    ) & show_progress "Starting containers" "cd '$INSTANCE_DIR' && $COMPOSE_CMD up -d"

    # Detect server IP (more compatible)
    SERVER_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || ip addr show scope global | grep inet | grep -v docker | awk '{print $2}' | cut -d'/' -f1 | head -n1)
    [[ -z "$SERVER_IP" ]] && SERVER_IP="127.0.0.1"

    if [[ "$SERVER_IP" == "127.0.0.1" ]]; then
        print_warn "Could not detect public IP. Use localhost or configure network."
    fi

    print_info "Odoo instance '$INSTANCE_NAME' is running!"
    echo
    echo "──────────────────────────────────────────────"
    echo "🌐 URL:          http://$SERVER_IP:$ODOO_PORT"
    echo "📦 Odoo Version: $ODOO_VERSION"
    echo "🗄️  Database:     $DB_NAME"
    echo "👤 DB User:      $DB_USER"
    echo "🔑 DB Password:  $DB_PASS"
    echo "🔐 Admin Pass:   $ADMIN_PASS"
    echo "⚙️  Config:       $INSTANCE_DIR/config/odoo.conf"
    echo "🧩 Addons:       $INSTANCE_DIR/addons"
    echo "💾 DB Data:      $INSTANCE_DIR/db-data"
    echo "📁 Filestore:    $INSTANCE_DIR/filestore"
    echo "📜 Log:          $LOGFILE"
    echo "🔒 Secrets:      $SECRETS_FILE"
    echo "──────────────────────────────────────────────"
    echo
    echo "To manage containers:"
    echo "  cd $INSTANCE_DIR && $COMPOSE_CMD [ps|logs|stop|rm]"
    echo
    echo "💡 Tip: Add your custom addons to $INSTANCE_DIR/addons"
}

main "$@"
