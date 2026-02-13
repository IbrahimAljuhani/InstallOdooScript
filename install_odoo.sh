#!/bin/bash
################################################################################
# Odoo Multi-Instance Installation Script - Professional Edition
# Author: Ibrahim Aljuhani
# Version: 2.0.0
# Architecture: Configuration-First Pattern (Gather → Validate → Execute)
# Features: Interactive mode, Non-interactive mode, Dry-run mode
################################################################################
set -e
export DEBIAN_FRONTEND=noninteractive

#-------------------------------#
#        Color Definitions      #
#-------------------------------#
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

print_info()  { echo -e "${GREEN}[✔]${NC} $1"; }
print_warn()  { echo -e "${YELLOW}[⚠]${NC} $1"; }
print_error() { echo -e "${RED}[✖]${NC} $1"; exit 1; }
print_step()  { echo -e "${CYAN}[🚀]${NC} $1"; }
print_header() { echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"; }
print_footer() { echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"; }
print_divider() { echo -e "${BLUE}╠════════════════════════════════════════════════════════════╣${NC}"; }
print_center() { printf '%*s\n' $(((${#1}+78)/2)) "$1"; }

#-------------------------------#
#     Configuration Variables   #
#-------------------------------#
CONFIG_MODE="interactive"  # interactive, non-interactive, dry-run
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
SERVER_IP=$(hostname -I | awk '{print $1}')
DRY_RUN=false
MANIFEST_DIR="/root/odoo-installs"
SECRETS_FILE="/root/odoo-secrets.txt"

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
#     Argument Parsing          #
#-------------------------------#
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --non-interactive) CONFIG_MODE="non-interactive"; shift ;;
            --dry-run) DRY_RUN=true; CONFIG_MODE="non-interactive"; shift ;;
            --instance) OE_USER="$2"; shift 2 ;;
            --version) OE_VERSION="$2"; shift 2 ;;
            --port) OE_PORT="$2"; shift 2 ;;
            --nginx) NGINX_CHOICE="y"; shift ;;
            --domain) NGINX_DOMAIN="$2"; shift 2 ;;
            --ssl) SSL_CHOICE="y"; shift ;;
            --email) LETSENCRYPT_EMAIL="$2"; shift 2 ;;
            --help|-h) show_help; exit 0 ;;
            *) shift ;;
        esac
    done
}

show_help() {
    echo "Odoo Multi-Instance Installer - Professional Edition"
    echo ""
    echo "Usage:"
    echo "  Interactive mode (default):"
    echo "    sudo ./install_odoo.sh"
    echo ""
    echo "  Non-interactive mode:"
    echo "    sudo ./install_odoo.sh --non-interactive \\"
    echo "      --instance <name> \\"
    echo "      --version <19.0|18.0|17.0|16.0> \\"
    echo "      --port <number> \\"
    echo "      [--nginx] [--domain <domain>] [--ssl] [--email <email>]"
    echo ""
    echo "  Dry-run mode (simulation only):"
    echo "    sudo ./install_odoo.sh --dry-run --instance test --version 18.0 --port 8069"
    echo ""
    echo "Options:"
    echo "  --instance    Instance name (e.g., odoo-prod)"
    echo "  --version     Odoo version (19.0, 18.0, 17.0, 16.0)"
    echo "  --port        HTTP port (default: 8069)"
    echo "  --nginx       Enable Nginx reverse proxy"
    echo "  --domain      Domain name for Nginx"
    echo "  --ssl         Enable Let's Encrypt SSL"
    echo "  --email       Email for SSL notifications"
    echo "  --dry-run     Simulate installation without making changes"
    echo "  --help, -h    Show this help message"
    echo ""
    echo "Examples:"
    echo "  # Interactive installation"
    echo "  sudo ./install_odoo.sh"
    echo ""
    echo "  # Non-interactive installation with Nginx and SSL"
    echo "  sudo ./install_odoo.sh --non-interactive \\"
    echo "    --instance prod --version 18.0 --port 8069 \\"
    echo "    --nginx --domain example.com --ssl --email admin@example.com"
}

#-------------------------------#
#     Phase 1: Gather Inputs    #
#-------------------------------#
gather_inputs() {
    clear
    print_header
    print_center "Odoo Multi-Instance Installer"
    print_center "Professional Edition v2.0.0"
    print_divider
    print_center "Configuration Wizard"
    print_footer
    echo ""

    # Instance Name
    if [[ -z "$OE_USER" ]]; then
        while true; do
            read -p "Instance name (e.g., odoo-prod): " OE_USER
            if [[ ! "$OE_USER" =~ ^[a-z][a-z0-9_-]*$ ]]; then
                print_error "Invalid instance name. Must start with lowercase letter, and contain only letters, digits, hyphens, or underscores."
            elif check_instance_exists "$OE_USER"; then
                print_warn "Instance '$OE_USER' already exists!"
                read -p "Delete existing instance and proceed? (y/N): " DELETE_CHOICE
                if [[ "$DELETE_CHOICE" == "y" || "$DELETE_CHOICE" == "yes" ]]; then
                    handle_existing_instance "$OE_USER"
                else
                    OE_USER=""
                    continue
                fi
            fi
            break
        done
    fi

    # Odoo Version
    if [[ -z "$OE_VERSION" ]]; then
        echo -e "\n${CYAN}Odoo version:${NC}"
        echo "  1) 19.0 (Latest)"
        echo "  2) 18.0 (Stable)"
        echo "  3) 17.0 (LTS)"
        echo "  4) 16.0 (Legacy)"
        while true; do
            read -p "Choice (1-4): " VER_CHOICE
            case $VER_CHOICE in
                1) OE_VERSION="19.0"; break ;;
                2) OE_VERSION="18.0"; break ;;
                3) OE_VERSION="17.0"; break ;;
                4) OE_VERSION="16.0"; break ;;
                *) print_error "Invalid choice. Please select 1, 2, 3, or 4." ;;
            esac
        done
    fi

    # HTTP Port
    if [[ -z "$OE_PORT" ]]; then
        while true; do
            read -p "HTTP port (default 8069): " OE_PORT
            OE_PORT="${OE_PORT:-8069}"
            
            if ! [[ "$OE_PORT" =~ ^[0-9]+$ ]] || [ "$OE_PORT" -lt 1024 ] || [ "$OE_PORT" -gt 65535 ]; then
                print_error "Port must be a number between 1024 and 65535."
            fi
            
            if check_port_in_use "$OE_PORT"; then
                print_warn "Port $OE_PORT is already in use."
                read -p "Continue anyway? (y/N): " CONTINUE_CHOICE
                if [[ "$CONTINUE_CHOICE" == "y" || "$CONTINUE_CHOICE" == "yes" ]]; then
                    break
                fi
                continue
            fi
            
            break
        done
    fi
    LONGPOLLING_PORT=$((OE_PORT + 3))

    # Nginx Configuration
    if [[ -z "$NGINX_CHOICE" || "$NGINX_CHOICE" == "n" ]]; then
        read -p "Configure Nginx reverse proxy? (y/N): " NGINX_CHOICE
        NGINX_CHOICE=$(echo "$NGINX_CHOICE" | tr '[:upper:]' '[:lower:]')
    fi

    if [[ "$NGINX_CHOICE" == "y" || "$NGINX_CHOICE" == "yes" ]]; then
        if [[ -z "$NGINX_DOMAIN" ]]; then
            read -p "Domain name (or press Enter for IP $SERVER_IP): " NGINX_DOMAIN
            NGINX_DOMAIN="${NGINX_DOMAIN:-$SERVER_IP}"
        fi
        
        if [[ -z "$SSL_CHOICE" || "$SSL_CHOICE" == "n" ]]; then
            read -p "Enable Let's Encrypt SSL? (y/N): " SSL_CHOICE
            SSL_CHOICE=$(echo "$SSL_CHOICE" | tr '[:upper:]' '[:lower:]')
        fi
        
        if [[ "$SSL_CHOICE" == "y" || "$SSL_CHOICE" == "yes" ]]; then
            if [[ -z "$LETSENCRYPT_EMAIL" ]]; then
                while true; do
                    read -p "Email for SSL notifications: " LETSENCRYPT_EMAIL
                    if [[ -z "$LETSENCRYPT_EMAIL" ]]; then
                        print_error "Email is required for Let's Encrypt."
                    fi
                    break
                done
            fi
        fi
    fi
}

handle_existing_instance() {
    local user="$1"
    print_warn "Instance '$user' already exists. Deleting..."
    
    # Stop service
    sudo systemctl stop "${user}-server" 2>/dev/null || true
    sudo systemctl disable --quiet "${user}-server" 2>/dev/null || true
    
    # Remove service file
    sudo rm -f "/etc/systemd/system/${user}-server.service"
    sudo systemctl daemon-reload
    
    # Remove config file
    sudo rm -f "/etc/${user}-server.conf"
    
    # Remove user and home directory
    sudo userdel -r "$user" 2>/dev/null || true
    sudo rm -rf "/$user"
    sudo rm -rf "/var/log/$user"
    
    # Remove PostgreSQL database and user
    sudo -u postgres psql -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$user';" >/dev/null 2>&1 || true
    sudo -u postgres psql -d postgres -c "DROP DATABASE IF EXISTS \"$user\";" >/dev/null 2>&1 || true
    sudo -u postgres psql -d postgres -c "DROP USER IF EXISTS \"$user\";" >/dev/null 2>&1 || true
    
    # Remove Nginx configuration
    sudo rm -f "/etc/nginx/sites-available/$user"
    sudo rm -f "/etc/nginx/sites-enabled/$user"
    
    print_info "Instance '$user' has been deleted."
}

#-------------------------------#
#     Phase 2: Validation       #
#-------------------------------#
validate_configuration() {
    print_header
    print_center "Installation Summary"
    print_divider
    
    printf "║ %-20s : %-45s ║\n" "Instance Name" "$OE_USER"
    printf "║ %-20s : %-45s ║\n" "Odoo Version" "$OE_VERSION"
    printf "║ %-20s : %-45s ║\n" "HTTP Port" "$OE_PORT"
    printf "║ %-20s : %-45s ║\n" "Longpolling Port" "$LONGPOLLING_PORT"
    printf "║ %-20s : %-45s ║\n" "Nginx" "${NGINX_CHOICE:-no}"
    
    if [[ "$NGINX_CHOICE" == "y" || "$NGINX_CHOICE" == "yes" ]]; then
        printf "║ %-20s : %-45s ║\n" "Domain" "$NGINX_DOMAIN"
        if [[ "$SSL_CHOICE" == "y" || "$SSL_CHOICE" == "yes" ]]; then
            printf "║ %-20s : %-45s ║\n" "SSL Certificate" "Let's Encrypt"
            printf "║ %-20s : %-45s ║\n" "SSL Email" "$LETSENCRYPT_EMAIL"
        else
            printf "║ %-20s : %-45s ║\n" "SSL Certificate" "No"
        fi
    fi
    
    print_footer
    echo ""
    
    if [[ "$CONFIG_MODE" == "non-interactive" ]]; then
        print_info "Running in non-interactive mode. Proceeding with installation..."
        return 0
    fi
    
    read -p "Proceed with installation? (y/N): " CONFIRM
    CONFIRM=$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "yes" ]]; then
        print_info "Installation cancelled by user."
        exit 0
    fi
}

#-------------------------------#
#     Phase 3: Execution        #
#-------------------------------#
execute_installation() {
    local start_time=$(date +%s)
    
    print_header
    print_center "Starting Installation"
    print_footer
    echo ""
    
    # Create manifest directory
    if ! $DRY_RUN; then
        sudo mkdir -p "$MANIFEST_DIR"
    fi
    
    # Step 1: System Preparation
    execute_step "Checking required tools" check_required_tools
    execute_step "Checking Ubuntu version" check_ubuntu_version
    execute_step "Updating system packages" update_system_packages
    
    # Step 2: Install Dependencies
    execute_step "Installing system packages" install_system_packages
    execute_step "Installing Node.js 20 LTS" install_nodejs
    execute_step "Installing wkhtmltopdf" install_wkhtmltopdf
    
    # Step 3: PostgreSQL Setup
    execute_step "Setting up PostgreSQL 15" setup_postgresql
    execute_step "Creating PostgreSQL user" create_postgres_user
    
    # Step 4: System User and Directories
    execute_step "Creating system user" create_system_user
    execute_step "Setting up log directory" setup_log_directory
    
    # Step 5: Odoo Installation
    execute_step "Cloning Odoo source code" clone_odoo_source
    execute_step "Creating custom addons directory" create_addons_directory
    execute_step "Setting permissions" set_permissions
    execute_step "Creating Python virtual environment" create_venv
    execute_step "Installing Python dependencies" install_python_deps
    
    # Step 6: Configuration
    execute_step "Creating Odoo configuration file" create_odoo_config
    execute_step "Creating systemd service" create_systemd_service
    execute_step "Starting Odoo service" start_odoo_service
    
    # Step 7: Nginx Setup (if requested)
    if [[ "$NGINX_CHOICE" == "y" || "$NGINX_CHOICE" == "yes" ]]; then
        execute_step "Configuring Nginx" configure_nginx
    fi
    
    # Step 8: Finalization
    execute_step "Generating installation manifest" generate_manifest
    execute_step "Cleaning temporary files" cleanup_temp_files
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    print_header
    print_center "Installation Complete!"
    print_divider
    
    printf "║ %-20s : %-45s ║\n" "Instance Name" "$OE_USER"
    printf "║ %-20s : %-45s ║\n" "Service Name" "${OE_USER}-server"
    printf "║ %-20s : %-45s ║\n" "HTTP Port" "$OE_PORT"
    printf "║ %-20s : %-45s ║\n" "Longpolling Port" "$LONGPOLLING_PORT"
    
    if [[ "$NGINX_CHOICE" == "y" || "$NGINX_CHOICE" == "yes" ]]; then
        if [[ "$SSL_CHOICE" == "y" || "$SSL_CHOICE" == "yes" ]]; then
            printf "║ %-20s : %-45s ║\n" "Access URL" "https://$NGINX_DOMAIN"
        else
            printf "║ %-20s : %-45s ║\n" "Access URL" "http://$NGINX_DOMAIN"
        fi
    else
        printf "║ %-20s : %-45s ║\n" "Access URL" "http://$SERVER_IP:$OE_PORT"
    fi
    
    printf "║ %-20s : %-45s ║\n" "Configuration File" "/etc/${OE_USER}-server.conf"
    printf "║ %-20s : %-45s ║\n" "Log File" "/var/log/$OE_USER/${OE_USER}-server.log"
    printf "║ %-20s : %-45s ║\n" "Code Location" "/$OE_USER/${OE_USER}-server"
    printf "║ %-20s : %-45s ║\n" "Installation Time" "$((duration / 60)) min $((duration % 60)) sec"
    
    print_footer
    echo ""
    
    print_info "Admin password saved to: $SECRETS_FILE"
    print_info "Installation manifest saved to: $MANIFEST_DIR/${OE_USER}_$(date +%Y%m%d_%H%M%S)_manifest.json"

        echo ""
    print_info "To access your Odoo instance, open: http://$SERVER_IP:$OE_PORT"
    if [[ "$NGINX_CHOICE" == "y" || "$NGINX_CHOICE" == "yes" ]]; then
        print_info "Or via domain: http://$NGINX_DOMAIN"
    fi
    
    echo ""
    print_header
    print_center "🔒 CRITICAL SECURITY RECOMMENDATION"
    print_divider
    echo -e "${RED}⚠️  PRODUCTION ENVIRONMENTS: Disable Database Manager!${NC}"
    echo ""
    echo "The database manager interface (/web/database/manager) allows:"
    echo "  • Creating new databases"
    echo "  • Dropping existing databases"
    echo "  • Changing master passwords"
    echo ""
    echo "This is a SEVERE SECURITY RISK in production environments."
    echo ""
    echo "✅ Recommended actions:"
    echo ""
    echo "Option 1 (Nginx - RECOMMENDED):"
    echo "  sudo nano /etc/nginx/sites-available/${OE_USER}"
    echo "  → Ensure this block exists:"
    echo "     location ~* /web/database {"
    echo "         deny all;"
    echo "         return 403;"
    echo "     }"
    echo "  → Then reload Nginx:"
    echo "     sudo nginx -t && sudo systemctl reload nginx"
    echo ""
    echo "Option 2 (Odoo config):"
    echo "  sudo nano /etc/${OE_USER}-server.conf"
    echo "  → Add these lines:"
    echo "     list_db = False"
    echo "     dbfilter = ^${OE_USER}$"
    echo "  → Then restart Odoo:"
    echo "     sudo systemctl restart ${OE_USER}-server"
    echo ""
    echo "💡 Why this matters:"
    echo "  • Prevents unauthorized database creation/deletion"
    echo "  • Blocks brute-force attacks on master password"
    echo "  • Required by PCI-DSS and ISO 27001 compliance"
    echo "  • Recommended by Odoo Security Best Practices"
    print_footer
    echo ""
    
    print_info "✅ Installation complete! Review security recommendations above before going live."
}

execute_step() {
    local step_name="$1"
    local step_function="$2"
    
    print_step "$step_name"
    
    if $DRY_RUN; then
        print_info "[DRY RUN] Would execute: $step_function"
        return 0
    fi
    
    $step_function
}

#-------------------------------#
#     Helper Functions          #
#-------------------------------#
check_required_tools() {
    for cmd in wget git gpg curl bc; do
        if ! command -v "$cmd" &> /dev/null; then
            print_error "$cmd is required but not installed."
        fi
    done
    print_info "All required tools are installed."
}

check_ubuntu_version() {
    UBUNTU_VERSION=$(lsb_release -r -s 2>/dev/null || echo "unknown")
    if [[ "$UBUNTU_VERSION" == "unknown" ]]; then
        print_error "Unable to detect Ubuntu version. Make sure 'lsb-release' is installed."
    fi
    
    if (( $(echo "$UBUNTU_VERSION >= 22.04" | bc -l) )); then
        print_info "Ubuntu version $UBUNTU_VERSION is supported."
    else
        print_error "This script requires Ubuntu 22.04 or newer. Detected version: $UBUNTU_VERSION"
    fi
}

update_system_packages() {
    if $DRY_RUN; then
        print_info "[DRY RUN] Would update system packages"
        return 0
    fi
    
    sudo apt update -y
    sudo apt full-upgrade -y
    sudo apt autoremove -y
    sudo apt autoclean -y
    print_info "System packages updated."
}

install_system_packages() {
    if $DRY_RUN; then
        print_info "[DRY RUN] Would install system packages"
        return 0
    fi
    
    sudo apt install -y curl wget gnupg apt-transport-https git build-essential \
        libxslt-dev libzip-dev libldap2-dev libsasl2-dev libjpeg-dev libpng-dev \
        gdebi libpq-dev fonts-dejavu-core fonts-font-awesome fonts-roboto-unhinted \
        adduser lsb-base vim python3 python3-dev python3-venv python3-wheel lsb-release bc
    
    print_info "System packages installed."
}

install_nodejs() {
    if $DRY_RUN; then
        print_info "[DRY RUN] Would install Node.js 20 LTS"
        return 0
    fi
    
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - || print_error "Failed to add NodeSource repo"
    sudo apt install -y nodejs || print_error "Failed to install Node.js 20"
    sudo npm install -g rtlcss
    print_info "Node.js 20 LTS and rtlcss installed."
}

install_wkhtmltopdf() {
    if $DRY_RUN; then
        print_info "[DRY RUN] Would install wkhtmltopdf"
        return 0
    fi
    
    WKHTML_DEB="/tmp/wkhtmltox_${OE_USER}.deb"
    WKHTML_URL="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb"
    
    wget -q "$WKHTML_URL" -O "$WKHTML_DEB" || print_error "Failed to download wkhtmltopdf"
    sudo gdebi -n "$WKHTML_DEB" || print_error "Failed to install wkhtmltopdf"
    rm -f "$WKHTML_DEB"
    
    print_info "wkhtmltopdf installed from official .deb (0.12.6.1-3)"
}

setup_postgresql() {
    if $DRY_RUN; then
        print_info "[DRY RUN] Would setup PostgreSQL 15"
        return 0
    fi
    
    if dpkg -l | grep -q "postgresql-15"; then
        print_info "PostgreSQL 15 is already installed."
        if ! systemctl is-active --quiet postgresql; then
            sudo systemctl start postgresql
            sudo systemctl enable postgresql
        fi
    else
        curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | \
            sudo tee /usr/share/keyrings/postgresql.gpg > /dev/null
        echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" | \
            sudo tee /etc/apt/sources.list.d/pgdg.list > /dev/null
        sudo apt update -y
        sudo apt install -y postgresql-15 || print_error "Failed to install PostgreSQL 15"
        print_info "PostgreSQL 15 installed successfully."
    fi
}

create_postgres_user() {
    if $DRY_RUN; then
        print_info "[DRY RUN] Would create PostgreSQL user '$OE_USER'"
        return 0
    fi
    
    if ! sudo -u postgres psql -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='$OE_USER'" 2>/dev/null | grep -q 1; then
        sudo -u postgres createuser -s "$OE_USER"
        print_info "PostgreSQL user '$OE_USER' created."
    else
        print_warn "PostgreSQL user '$OE_USER' already exists."
    fi
}

create_system_user() {
    if $DRY_RUN; then
        print_info "[DRY RUN] Would create system user '$OE_USER'"
        return 0
    fi
    
    if id "$OE_USER" &>/dev/null; then
        print_warn "User '$OE_USER' already exists."
    else
        sudo adduser --system --quiet --shell=/bin/bash --home="/$OE_USER" --gecos 'ODOO' --group "$OE_USER"
        print_info "User '$OE_USER' created."
    fi
}

setup_log_directory() {
    if $DRY_RUN; then
        print_info "[DRY RUN] Would create log directory"
        return 0
    fi
    
    sudo mkdir -p /var/log/$OE_USER
    sudo chown $OE_USER:$OE_USER /var/log/$OE_USER
    print_info "Log directory created."
}

clone_odoo_source() {
    if $DRY_RUN; then
        print_info "[DRY RUN] Would clone Odoo $OE_VERSION"
        return 0
    fi
    
    OE_HOME="/$OE_USER"
    OE_HOME_EXT="${OE_HOME}/${OE_USER}-server"
    
    if [ -d "$OE_HOME_EXT" ]; then
        print_warn "Odoo directory exists. Skipping clone."
    else
        sudo -u "$OE_USER" git clone --depth 1 --branch "$OE_VERSION" https://github.com/odoo/odoo "$OE_HOME_EXT"
        print_info "Odoo source cloned."
    fi
}

create_addons_directory() {
    if $DRY_RUN; then
        print_info "[DRY RUN] Would create custom addons directory"
        return 0
    fi
    
    OE_HOME="/$OE_USER"
    sudo -u "$OE_USER" mkdir -p "${OE_HOME}/custom/addons"
    print_info "Custom addons directory created."
}

set_permissions() {
    if $DRY_RUN; then
        print_info "[DRY RUN] Would set permissions"
        return 0
    fi
    
    OE_HOME="/$OE_USER"
    sudo chown -R "$OE_USER":"$OE_USER" "$OE_HOME"
    print_info "Permissions set."
}

create_venv() {
    if $DRY_RUN; then
        print_info "[DRY RUN] Would create Python virtual environment"
        return 0
    fi
    
    OE_HOME="/$OE_USER"
    VENV_PATH="$OE_HOME/venv"
    
    sudo -u "$OE_USER" python3 -m venv "$VENV_PATH"
    sudo -u "$OE_USER" "$VENV_PATH/bin/pip" install --upgrade pip
    print_info "Python virtual environment created."
}

install_python_deps() {
    if $DRY_RUN; then
        print_info "[DRY RUN] Would install Python dependencies"
        return 0
    fi
    
    OE_HOME="/$OE_USER"
    VENV_PATH="$OE_HOME/venv"
    REQUIREMENTS_FILE="/tmp/odoo_reqs_${OE_USER}.txt"
    REQUIREMENTS_URL="https://github.com/odoo/odoo/raw/${OE_VERSION}/requirements.txt"
    
    wget -q "$REQUIREMENTS_URL" -O "$REQUIREMENTS_FILE" || print_error "Failed to download requirements.txt"
    
    if [[ "$OE_VERSION" =~ ^1[6-8]\.0$ ]]; then
        sed -i '/gevent/d' "$REQUIREMENTS_FILE"
        sudo -u "$OE_USER" "$VENV_PATH/bin/pip" install -r "$REQUIREMENTS_FILE" || print_warn "Some packages failed"
        sudo -u "$OE_USER" "$VENV_PATH/bin/pip" install "gevent==23.9.1"
    else
        sudo -u "$OE_USER" "$VENV_PATH/bin/pip" install -r "$REQUIREMENTS_FILE" || print_warn "Some packages failed"
    fi
    
    rm -f "$REQUIREMENTS_FILE"
    print_info "Odoo Python dependencies installed."
}

create_odoo_config() {
    if $DRY_RUN; then
        print_info "[DRY RUN] Would create Odoo configuration file"
        return 0
    fi
    
    OE_HOME="/$OE_USER"
    VENV_PATH="$OE_HOME/venv"
    CONFIG_FILE="/etc/${OE_USER}-server.conf"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        sudo touch "$CONFIG_FILE"
        sudo chmod 640 "$CONFIG_FILE"
        sudo chown "$OE_USER":"$OE_USER" "$CONFIG_FILE"
    fi
    
    if [ "$GENERATE_RANDOM_PASSWORD" == "True" ]; then
        OE_SUPERADMIN=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Instance '$OE_USER' admin password: $OE_SUPERADMIN" >> "$SECRETS_FILE"
        sudo chmod 600 "$SECRETS_FILE"
        print_info "Admin password saved to $SECRETS_FILE"
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
}

create_systemd_service() {
    if $DRY_RUN; then
        print_info "[DRY RUN] Would create systemd service"
        return 0
    fi
    
    OE_HOME="/$OE_USER"
    OE_HOME_EXT="${OE_HOME}/${OE_USER}-server"
    VENV_PATH="$OE_HOME/venv"
    SERVICE_FILE="/etc/systemd/system/${OE_USER}-server.service"
    
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
    print_info "Systemd service created."
}

start_odoo_service() {
    if $DRY_RUN; then
        print_info "[DRY RUN] Would start Odoo service"
        return 0
    fi
    
    sudo systemctl start "${OE_USER}-server"
    
    if ! sudo systemctl is-active --quiet "${OE_USER}-server"; then
        print_error "Odoo service failed to start. Check logs with: journalctl -u ${OE_USER}-server"
    fi
    
    print_info "Odoo service started and enabled."
}

configure_nginx() {
    if $DRY_RUN; then
        print_info "[DRY RUN] Would configure Nginx"
        return 0
    fi
    
    if ! check_nginx_installed; then
        print_step "Installing Nginx..."
        sudo apt install -y nginx || print_error "Failed to install Nginx"
        sudo ufw allow 'Nginx Full' 2>/dev/null || true
        print_info "Nginx installed."
    else
        print_info "Nginx is already installed."
    fi
    
    # Ensure nginx directory structure exists
    sudo mkdir -p /etc/nginx/conf.d /etc/nginx/sites-available /etc/nginx/sites-enabled
    sudo chown -R root:root /etc/nginx
    sudo chmod -R 755 /etc/nginx
    
    # Configure WebSocket map
    if ! grep -q 'map \$http_upgrade \$connection_upgrade' /etc/nginx/nginx.conf /etc/nginx/conf.d/* 2>/dev/null; then
        sudo tee /etc/nginx/conf.d/websocket_map.conf > /dev/null <<'MAP_EOF'
# WebSocket upgrade mapping (required for Odoo bus, live chat, POS, IoT)
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
MAP_EOF
        print_info "WebSocket map configured globally."
    fi
    
    # Set global client_max_body_size
    if ! grep -q "client_max_body_size 1G;" /etc/nginx/nginx.conf; then
        sudo sed -i '/http {/a \    client_max_body_size 1G;' /etc/nginx/nginx.conf
    fi
    
    # Create ACME challenge directory
    sudo mkdir -p /var/www/certbot/.well-known/acme-challenge
    sudo chown -R www-data:www-data /var/www/certbot
    
    # Create Nginx configuration
    NGINX_SITE="/etc/nginx/sites-available/${OE_USER}"
    NGINX_ENABLED="/etc/nginx/sites-enabled/${OE_USER}"
    
    UPSTREAM_BACKEND="odoo_backend_${OE_USER}"
    UPSTREAM_LONGPOLLING="odoo_longpolling_${OE_USER}"
    CACHE_ZONE="odoo_static_${OE_USER}"
    
    sudo mkdir -p "/var/cache/nginx/odoo_static_${OE_USER}"
    sudo chown -R www-data:www-data /var/cache/nginx
    sudo chmod -R 755 /var/cache/nginx
    
    sudo tee "$NGINX_SITE" > /dev/null <<EOF
# Odoo Nginx Baseline Configuration
# Instance: ${OE_USER}

map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

upstream ${UPSTREAM_BACKEND} {
    server 127.0.0.1:${OE_PORT};
    keepalive 32;
}

upstream ${UPSTREAM_LONGPOLLING} {
    server 127.0.0.1:${LONGPOLLING_PORT};
    keepalive 32;
}

proxy_cache_path /var/cache/nginx/odoo_static_${OE_USER}
    levels=1:2
    keys_zone=${CACHE_ZONE}:100m
    inactive=60m
    max_size=1g;

server {
    server_name ${NGINX_DOMAIN};
    charset utf-8;
    listen 80;
    listen [::]:80;

    location ^~ /.well-known/acme-challenge/ {
        allow all;
        root /var/www/certbot;
        default_type "text/plain";
        try_files \$uri =404;
    }

    location ~* /web/database {
        deny all;
        return 403;
    }

    location /web/static/ {
        proxy_pass http://${UPSTREAM_BACKEND};
        proxy_cache ${CACHE_ZONE};
        proxy_cache_valid 200 7d;
        proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
        proxy_ignore_headers Cache-Control Expires;
        expires 7d;
        add_header Cache-Control "public, max-age=604800" always;
    }

    location /websocket {
        proxy_pass http://${UPSTREAM_BACKEND};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 3600;
        proxy_buffering off;
        proxy_request_buffering off;
    }

    location /longpolling {
        proxy_pass http://${UPSTREAM_LONGPOLLING};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 3600;
        proxy_buffering off;
    }

    location / {
        proxy_pass http://${UPSTREAM_BACKEND};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_connect_timeout 60;
        proxy_send_timeout 60;
        proxy_read_timeout 300;
        client_max_body_size 128M;
    }

    access_log /var/log/nginx/${OE_USER}_access.log;
    error_log /var/log/nginx/${OE_USER}_error.log warn;
}
EOF
    
    sudo ln -sf "$NGINX_SITE" "$NGINX_ENABLED"
    
    if ! sudo nginx -t; then
        print_error "Nginx configuration test failed!"
    fi
    
    sudo systemctl reload nginx
    
    # Enable proxy_mode
    CONFIG_FILE="/etc/${OE_USER}-server.conf"
    if ! grep -q "^proxy_mode" "$CONFIG_FILE"; then
        echo "proxy_mode = True" | sudo tee -a "$CONFIG_FILE" > /dev/null
        sudo systemctl restart "${OE_USER}-server"
    fi
    
    print_info "Nginx configured successfully."
    
    # SSL Configuration
    if [[ "$SSL_CHOICE" == "y" || "$SSL_CHOICE" == "yes" ]]; then
        print_step "Configuring Let's Encrypt SSL..."
        
        sudo apt install -y certbot python3-certbot-nginx || print_error "Failed to install Certbot"
        
        if sudo certbot --nginx --non-interactive --agree-tos --email "$LETSENCRYPT_EMAIL" --domains "$NGINX_DOMAIN" --redirect 2>/dev/null; then
            print_info "SSL certificate installed successfully!"
            sudo ufw deny "$OE_PORT" 2>/dev/null || true
        else
            print_warn "Failed to obtain SSL certificate. HTTP fallback enabled."
        fi
    else
        sudo ufw deny "$OE_PORT" 2>/dev/null || true
    fi
}

generate_manifest() {
    if $DRY_RUN; then
        print_info "[DRY RUN] Would generate installation manifest"
        return 0
    fi
    
    MANIFEST_FILE="$MANIFEST_DIR/${OE_USER}_$(date +%Y%m%d_%H%M%S)_manifest.json"
    
    cat > "$MANIFEST_FILE" <<EOF
{
  "instance_name": "$OE_USER",
  "odoo_version": "$OE_VERSION",
  "http_port": $OE_PORT,
  "longpolling_port": $LONGPOLLING_PORT,
  "nginx_enabled": $([ "$NGINX_CHOICE" == "y" ] && echo "true" || echo "false"),
  "domain": "$NGINX_DOMAIN",
  "ssl_enabled": $([ "$SSL_CHOICE" == "y" ] && echo "true" || echo "false"),
  "ssl_email": "$LETSENCRYPT_EMAIL",
  "installation_date": "$(date -Iseconds)",
  "master_password": "$OE_SUPERADMIN",
  "server_ip": "$SERVER_IP",
  "installation_duration_seconds": $(( $(date +%s) - start_time ))
}
EOF
    
    sudo chmod 600 "$MANIFEST_FILE"
    print_info "Installation manifest generated: $MANIFEST_FILE"
    print_warn "⚠️  Master password stored in manifest (permissions: 600). Keep this file secure!"
}

cleanup_temp_files() {
    if $DRY_RUN; then
        print_info "[DRY RUN] Would clean temporary files"
        return 0
    fi
    
    rm -f "/tmp/odoo_reqs_${OE_USER}.txt" "/tmp/wkhtmltox_${OE_USER}.deb" 2>/dev/null || true
    print_info "Temporary files cleaned."
}

#-------------------------------#
#     Main Execution            #
#-------------------------------#
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Phase 1: Gather Inputs
    if [[ "$CONFIG_MODE" == "interactive" ]]; then
        gather_inputs
    fi
    
    # Phase 2: Validation
    validate_configuration
    
    # Phase 3: Execution
    execute_installation
}

# Run main function
main "$@"
