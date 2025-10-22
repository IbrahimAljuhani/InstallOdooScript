#!/bin/bash

# install_odoo_docker.sh
# Author: Ibrahim Aljuhani
# GitHub: https://github.com/IbrahimAljuhani/InstallOdooScript
# Purpose: Install Odoo in Docker with multi-instance support

set -euo pipefail

LOGFILE="$HOME/install_odoo_docker.log"
INSTALL_DIR="$HOME/odoo"
SECRETS_FILE="$HOME/.odoo-docker-secrets.txt"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info()  { echo -e "${GREEN}[✔ DONE ]${NC} $1"; }
print_warn()  { echo -e "${YELLOW}[‼ WARN]${NC} $1"; }
print_error() { echo -e "${RED}[✖ ERROR]${NC} $1"; exit 1; }
print_step()  { echo -e "${CYAN}==> $1${NC}"; }

# Prevent running as root
if [[ $EUID -eq 0 ]]; then
  print_error "This script must NOT be run with sudo or as root.\nPlease run as your regular user (who is in the 'docker' group)."
fi

# Check prerequisites
check_prerequisites() {
    local missing=()
    
    if ! command -v docker &>/dev/null; then
        missing+=("Docker CE")
    fi
    if ! docker compose version &>/dev/null; then
        missing+=("Docker Compose")
    fi
    if ! command -v openssl &>/dev/null; then
        missing+=("openssl")
    fi

    if [ ${#missing[@]} -ne 0 ]; then
        print_error "Missing required components: ${missing[*]}
Please install them first using:
  https://github.com/IbrahimAljuhani/docker_installs"
    fi

    # Optional: check for NPM and Portainer
    if ! docker ps --format '{{.Names}}' | grep -q 'npm_app_1'; then
        print_warn "NGINX Proxy Manager not found. You can still access Odoo via IP:PORT."
    fi
    if ! docker ps --format '{{.Names}}' | grep -q 'portainer'; then
        print_warn "Portainer-CE not found. Management will be via CLI only."
    fi

    print_info "All required Docker components are installed."
}

# Validate instance name
validate_instance_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-z][a-z0-9_-]*$ ]]; then
        print_error "Invalid instance name. Must start with lowercase letter, and contain only letters, digits, hyphens, or underscores."
    fi
}

# Choose Odoo version
choose_odoo_version() {
    echo -e "${CYAN}Choose Odoo version:${NC}"
    echo "1) 19.0"
    echo "2) 18.0"
    echo "3) 17.0"
    echo "4) 16.0"
    read -p "Enter choice (1-4): " choice
    case $choice in
        1) echo "19.0" ;;
        2) echo "18.0" ;;
        3) echo "17.0" ;;
        4) echo "16.0" ;;
        *) print_error "Invalid choice." ;;
    esac
}

# Main
main() {
    print_step "Checking prerequisites..."
    check_prerequisites

    read -p "Enter instance name (e.g., odoo-prod): " INSTANCE_NAME
    validate_instance_name "$INSTANCE_NAME"

    ODOO_VERSION=$(choose_odoo_version)
    read -p "Enter HTTP port (default 8069): " ODOO_PORT
    ODOO_PORT="${ODOO_PORT:-8069}"

    if ! [[ "$ODOO_PORT" =~ ^[0-9]+$ ]] || [ "$ODOO_PORT" -lt 1024 ] || [ "$ODOO_PORT" -gt 65535 ]; then
        print_error "Port must be between 1024 and 65535."
    fi

    INSTANCE_DIR="$INSTALL_DIR/$INSTANCE_NAME"
    mkdir -p "$INSTANCE_DIR/config" "$INSTANCE_DIR/addons" "$INSTANCE_DIR/db-data" "$INSTANCE_DIR/filestore"

    # Generate random admin password
    ADMIN_PASS=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    echo "$(date '+%Y-%m-%d %H:%M:%S'): Instance '$INSTANCE_NAME' admin password: $ADMIN_PASS" >> "$SECRETS_FILE"
    chmod 600 "$SECRETS_FILE"
    print_info "Admin password saved to $SECRETS_FILE (accessible only by you)."

    # Generate docker-compose.yml
    cat > "$INSTANCE_DIR/docker-compose.yml" <<EOF
version: '3.8'
services:
  odoo:
    image: odoo:$ODOO_VERSION
    container_name: odoo-$INSTANCE_NAME
    depends_on:
      - db
    ports:
      - "$ODOO_PORT:8069"
    environment:
      - HOST=db
      - USER=odoo
      - PASSWORD=odoo
    volumes:
      - ./config:/etc/odoo
      - ./addons:/mnt/extra-addons
      - ./filestore:/var/lib/odoo/filestore
    restart: unless-stopped
    networks:
      - odoo-net

  db:
    image: postgres:15
    container_name: odoo-$INSTANCE_NAME-db
    environment:
      - POSTGRES_DB=odoo
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=odoo
    volumes:
      - ./db-/var/lib/postgresql/data
    restart: unless-stopped
    networks:
      - odoo-net

networks:
  odoo-net:
    driver: bridge
EOF

    # Generate odoo.conf
    cat > "$INSTANCE_DIR/config/odoo.conf" <<EOF
[options]
admin_passwd = $ADMIN_PASS
http_port = 8069
logfile = /var/log/odoo/odoo-server.log
addons_path = /mnt/extra-addons,/etc/odoo/addons
data_dir = /var/lib/odoo
EOF

    # Start services
    print_step "Starting Odoo instance '$INSTANCE_NAME'..."
    cd "$INSTANCE_DIR"
    docker compose up -d >> "$LOGFILE" 2>&1

    if ! docker inspect "odoo-$INSTANCE_NAME" &>/dev/null; then
        print_error "Failed to start Odoo container. Check $LOGFILE"
    fi

    # Get server IP safely
    SERVER_IP=$(hostname -I | awk '{print $1}')
    if [[ -z "$SERVER_IP" ]]; then
        SERVER_IP="127.0.0.1"
        print_warn "Could not detect public IP. Using localhost."
    fi

    print_info "✅ Odoo instance '$INSTANCE_NAME' is running!"
    echo
    echo "Instance Details:"
    echo "  - URL:          http://$SERVER_IP:$ODOO_PORT"
    echo "  - Admin Pass:   $ADMIN_PASS (also in $SECRETS_FILE)"
    echo "  - Config:       $INSTANCE_DIR/config/odoo.conf"
    echo "  - Addons:       $INSTANCE_DIR/addons"
    echo "  - DB Data:      $INSTANCE_DIR/db-data"
    echo "  - Filestore:    $INSTANCE_DIR/filestore"
    echo
    echo "To manage containers: cd $INSTANCE_DIR && docker compose [ps|logs|stop|rm]"
}

main "$@"
