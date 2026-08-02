#!/bin/bash
################################################################################
# Odoo Multi-Instance Installation Script - Professional Edition
# Author: Ibrahim Aljuhani
# Version: 3.0.3
# Supports: Ubuntu 22.04+
# Architecture: Configuration-First Pattern (Gather → Validate → Execute)
# Modes: Interactive | Non-Interactive | Dry-Run
################################################################################
set -euo pipefail
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

trap 'echo -e "${RED}[FATAL]${NC} Script aborted unexpectedly at line $LINENO — check the output above." >&2' ERR

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
    echo "║                        Version 3.0.3                            ║"
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
INSTALL_WKHTMLTOPDF="False"
INSTALL_QUEUE_JOB="False"
OE_SUPERADMIN=""
NGINX_ACCESS_URL=""

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

# Poll until the given systemd service becomes active, or give up after ~60s.
# Shared by step_start_service (initial boot) and step_configure_nginx (the
# restart after appending proxy_mode) so both wait-and-verify the same way
# instead of firing systemctl restart and silently trusting it worked.
wait_for_service_active() {
    local service="$1"
    for i in $(seq 1 20); do
        sleep 3
        if sudo systemctl is-active --quiet "$service"; then
            print_info "Service '$service' is running ($((i * 3))s)."
            return 0
        fi
        print_warn "Not ready yet... ($((i * 3))s elapsed)"
    done
    return 1
}

# Strict check: only returns true if ALL FOUR artifacts created by this script's
# own install flow are present. Mirrors delete_odoo.sh's is_odoo_instance() —
# used to gate any destructive action (userdel/rm -rf) so a name collision with
# an unrelated system user (e.g. 'backup', 'deploy') can never trigger deletion.
is_odoo_instance() {
    local user="$1"
    [ -f "/etc/${user}-server.conf" ]                        &&
    [ -f "/etc/systemd/system/${user}-server.service" ]      &&
    [ -d "/$user/${user}-server" ]                           &&
    [ -f "/$user/${user}-server/odoo-bin" ]
}

# This script's Nginx setup deliberately restricts UFW to allow ports 80/443
# ONLY from Cloudflare's published IP ranges (see step_configure_nginx) — this
# is an intentional security requirement, not optional. But if the domain is
# not actually proxied through Cloudflare (orange-cloud DNS), the site becomes
# completely unreachable with no error anywhere. This check turns that silent
# failure into a loud, explicit warning before the firewall rule is applied.
# Requires $CF_IPV4_LIST / $CF_IPV6_LIST to already be populated by the caller.
warn_if_domain_not_behind_cloudflare() {
    local domain="$1"

    if [[ "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ "$domain" == *:* ]]; then
        print_warn "Domain is set to a raw IP address ('$domain'), not a hostname."
        print_warn "Cloudflare proxying only applies to actual domain names — a raw IP"
        print_warn "can NEVER be behind Cloudflare. The firewall will only allow port"
        print_warn "80/443 from Cloudflare IPs, so this site will be UNREACHABLE from"
        print_warn "the public internet after setup (SSH on port 22 is unaffected)."
        _cf_confirm_continue
        return
    fi

    local resolved_ip
    resolved_ip=$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | head -1)
    if [[ -z "$resolved_ip" ]]; then
        print_warn "Could not resolve '$domain' to an IP address right now."
        print_warn "If you just created the DNS record, this may just be propagation"
        print_warn "delay — but if it doesn't resolve, or doesn't resolve through"
        print_warn "Cloudflare (orange-cloud enabled), the site will be UNREACHABLE"
        print_warn "after setup, since UFW only allows Cloudflare IPs on port 80/443."
        _cf_confirm_continue
        return
    fi

    if command -v python3 &>/dev/null && python3 - "$resolved_ip" <<PYEOF
import ipaddress, sys
ip = ipaddress.ip_address(sys.argv[1])
ranges = """$CF_IPV4_LIST
$CF_IPV6_LIST""".strip().splitlines()
for r in ranges:
    r = r.strip()
    if not r:
        continue
    try:
        if ip in ipaddress.ip_network(r, strict=False):
            sys.exit(0)
    except ValueError:
        continue
sys.exit(1)
PYEOF
    then
        print_info "Domain '$domain' resolves to $resolved_ip — confirmed behind Cloudflare."
    else
        print_warn "Domain '$domain' resolves to $resolved_ip, which is NOT a Cloudflare IP."
        print_warn "This script's firewall only allows port 80/443 from Cloudflare — unless"
        print_warn "you enable the Cloudflare proxy (orange cloud) for this DNS record, the"
        print_warn "site will be COMPLETELY UNREACHABLE after this setup completes."
        _cf_confirm_continue
    fi
}

_cf_confirm_continue() {
    if [[ "$CONFIG_MODE" != "interactive" ]]; then
        print_warn "Continuing anyway (non-interactive mode) — review the warning above."
        return
    fi
    read -rp "  Continue anyway? (y/N): " _CF_CHOICE
    _CF_CHOICE=$(echo "$_CF_CHOICE" | tr '[:upper:]' '[:lower:]')
    if [[ "$_CF_CHOICE" != "y" && "$_CF_CHOICE" != "yes" ]]; then
        print_error "Aborted. Fix DNS/Cloudflare proxying for the domain and re-run."
    fi
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
            --wkhtmltopdf)      INSTALL_WKHTMLTOPDF="True"; shift ;;
            --queue-job)        INSTALL_QUEUE_JOB="True"; shift ;;
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
    echo "      [--nginx] [--domain <domain>] [--ssl] [--email <email>] \\"
    echo "      [--wkhtmltopdf] [--queue-job]"
    echo ""
    echo "  Dry-Run (simulate only):"
    echo "    sudo ./install_odoo.sh --dry-run --instance test --version 18.0 --port 8069"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    printf "  %-22s %s\n" "--instance"      "Instance name (e.g., odoo-prod)"
    printf "  %-22s %s\n" "--version"       "Odoo version: 19.0 | 18.0 | 17.0"
    printf "  %-22s %s\n" "--port"          "HTTP port (default: 8069)"
    printf "  %-22s %s\n" "--nginx"         "Enable Nginx reverse proxy"
    printf "  %-22s %s\n" "--domain"        "Domain name for Nginx"
    printf "  %-22s %s\n" "--ssl"           "Enable Let's Encrypt SSL"
    printf "  %-22s %s\n" "--email"         "Email for SSL notifications"
    printf "  %-22s %s\n" "--wkhtmltopdf"   "Attempt wkhtmltopdf install (official pkg: Ubuntu 22.04/Jammy only)"
    printf "  %-22s %s\n" "--queue-job"     "Install OCA queue_job and enable it as a server-wide module"
    printf "  %-22s %s\n" "--dry-run"       "Simulate without making changes"
    printf "  %-22s %s\n" "--help, -h"      "Show this help message"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Handle Existing Instance (with optional backup)
# ─────────────────────────────────────────────────────────────────────────────
handle_existing_instance() {
    local user="$1"

    # Defense in depth: never delete anything unless this is confirmed to be a
    # real Odoo instance created by this script (see is_odoo_instance()). The
    # caller already gates on this, but this function must never trust that
    # alone — a future caller or copy-paste elsewhere must not be able to turn
    # this into a generic "delete any system user" primitive.
    if ! is_odoo_instance "$user"; then
        print_error "'$user' is an existing system user/service but does not look like an Odoo instance created by this script (missing config, systemd unit, source dir, or odoo-bin). Refusing to delete it — choose a different instance name."
    fi

    echo -e "${RED}"
    echo "  ┌─────────────────────────────────────────────────────────┐"
    echo "  │  ⚠  WARNING: This action is IRREVERSIBLE!               │"
    echo "  │     All files, logs, configs, and data will be lost.    │"
    echo "  └─────────────────────────────────────────────────────────┘"
    echo -e "${NC}"

    # Offer backup before deletion
    read -rp "  Create automatic backup before deletion? (y/N): " BACKUP_CHOICE
    BACKUP_CHOICE=$(echo "$BACKUP_CHOICE" | tr '[:upper:]' '[:lower:]')
    if [[ "$BACKUP_CHOICE" == "y" || "$BACKUP_CHOICE" == "yes" ]]; then
        sudo mkdir -p "$BACKUP_DIR"
        local BACKUP_FILE="$BACKUP_DIR/${user}_$(date +%Y%m%d_%H%M%S).tar.gz"
        local DB_BACKUP="$BACKUP_DIR/${user}_db_$(date +%Y%m%d_%H%M%S).sql"

        print_step "Creating filesystem backup: $BACKUP_FILE"
        sudo tar -czf "$BACKUP_FILE" \
            "/$user" \
            "/etc/${user}-server.conf" \
            "/var/log/$user" 2>/dev/null \
            || print_warn "Filesystem backup may be incomplete."

        print_step "Creating PostgreSQL backup: $DB_BACKUP"
        sudo -u postgres pg_dump "$user" > "$DB_BACKUP" 2>/dev/null \
            || print_warn "Database backup may have failed."

        print_info "Full backup saved to: $BACKUP_DIR"
    fi

    # Ask about PostgreSQL separately
    read -rp "  Also delete the PostgreSQL database and user? (y/N): " DROP_DB_CHOICE
    local DROP_POSTGRES=false
    [[ "$(echo "$DROP_DB_CHOICE" | tr '[:upper:]' '[:lower:]')" =~ ^(y|yes)$ ]] && DROP_POSTGRES=true

    # Read port BEFORE removing config file (needed for UFW cleanup later)
    local oe_port
    oe_port=$(grep "^http_port" "/etc/${user}-server.conf" 2>/dev/null \
              | awk -F'=' '{print $2}' | tr -d ' ' || true)

    print_step "Stopping Odoo service and killing related processes..."
    sudo systemctl stop "${user}-server" 2>/dev/null || true
    for i in $(seq 1 5); do
        sleep 2
        sudo systemctl is-active --quiet "${user}-server" 2>/dev/null || break
    done
    sudo systemctl kill --signal=SIGKILL "${user}-server" 2>/dev/null || true
    sleep 1
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

    # Remove Nginx config if present and reload
    sudo rm -f "/etc/nginx/sites-available/$user"
    sudo rm -f "/etc/nginx/sites-enabled/$user"
    if command -v nginx &>/dev/null && sudo nginx -t >/dev/null 2>&1; then
        sudo systemctl reload nginx 2>/dev/null || true
        print_info "Nginx reloaded."
    fi

    # Remove Nginx static cache
    sudo rm -rf "/var/cache/nginx/odoo_static_${user}"
    print_info "Nginx static cache removed."

    # Remove logrotate config
    sudo rm -f "/etc/logrotate.d/${user}-odoo"
    print_info "Logrotate config removed."

    # Remove manifest JSON files (mirrors delete_odoo.sh's step_remove_manifests)
    local _manifests
    _manifests=$(ls "$MANIFEST_DIR/${user}_"*"_manifest.json" 2>/dev/null || true)
    if [ -n "$_manifests" ]; then
        while IFS= read -r _mf; do
            [[ -z "$_mf" ]] && continue
            sudo rm -f "$_mf"
        done <<< "$_manifests"
        print_info "Manifest JSON files removed."
    fi

    # Remove UFW deny rule added by Nginx setup
    if [[ -n "$oe_port" ]]; then
        sudo ufw delete deny "$oe_port" 2>/dev/null || true
        print_info "UFW rule for port $oe_port cleaned up."
    fi

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
        read -rp "  Instance name (e.g., odoo-prod): " OE_USER
        if ! validate_instance_name "$OE_USER"; then
            print_warn "Invalid name. Must start with a lowercase letter and contain only: a-z 0-9 - _"
            OE_USER=""
            continue
        fi
        if check_instance_exists "$OE_USER"; then
            echo ""
            if is_odoo_instance "$OE_USER"; then
                print_warn "Instance '$OE_USER' already exists!"
                echo "  What would you like to do?"
                echo "    1) Delete the existing instance and reinstall"
                echo "    2) Enter a different instance name"
                read -rp "  Choice (1/2): " CONFLICT_CHOICE
                case $CONFLICT_CHOICE in
                    1) handle_existing_instance "$OE_USER"; break ;;
                    2) OE_USER=""; continue ;;
                    *) print_warn "Invalid choice. Please enter 1 or 2." ;;
                esac
            else
                # A system user/service with this name exists but it is NOT a valid
                # Odoo instance created by this script — never offer to delete it.
                print_warn "'$OE_USER' is already in use by an existing system user or service that does not appear to be an Odoo instance. For safety, this name cannot be reused or auto-deleted."
                OE_USER=""
                continue
            fi
        else
            break
        fi
    done

    # ── Odoo Version ───────────────────────────────────────────────────────
    print_section "Odoo Version"
    echo "    1) 19.0  — Latest"
    echo "    2) 18.0  — Stable (recommended)"
    echo "    3) 17.0  — LTS"
    echo ""
    while true; do
        read -rp "  Select version (1-3): " VER_CHOICE
        case $VER_CHOICE in
            1) OE_VERSION="19.0"; break ;;
            2) OE_VERSION="18.0"; break ;;
            3) OE_VERSION="17.0"; break ;;
            *) print_warn "Please select 1, 2, or 3." ;;
        esac
    done
    print_info "Selected Odoo version: $OE_VERSION"

    # ── HTTP Port ──────────────────────────────────────────────────────────
    print_section "Port Configuration"
    while true; do
        read -rp "  HTTP port [default: 8069]: " OE_PORT
        OE_PORT="${OE_PORT:-8069}"
        if ! validate_port_range "$OE_PORT"; then
            print_warn "Port must be between 1024 and 65535."
            continue
        fi
        if check_port_in_use "$OE_PORT"; then
            print_warn "Port $OE_PORT is already in use!"
            read -rp "  Enter a different port: " OE_PORT
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
    read -rp "  Configure Nginx for this instance? (y/N): " NGINX_CHOICE
    NGINX_CHOICE=$(echo "$NGINX_CHOICE" | tr '[:upper:]' '[:lower:]')

    if [[ "$NGINX_CHOICE" == "y" || "$NGINX_CHOICE" == "yes" ]]; then
        read -rp "  Domain name [default: $SERVER_IP]: " NGINX_DOMAIN
        NGINX_DOMAIN="${NGINX_DOMAIN:-$SERVER_IP}"

        read -rp "  Enable Let's Encrypt SSL? (y/N): " SSL_CHOICE
        SSL_CHOICE=$(echo "$SSL_CHOICE" | tr '[:upper:]' '[:lower:]')

        if [[ "$SSL_CHOICE" == "y" || "$SSL_CHOICE" == "yes" ]]; then
            while true; do
                read -rp "  Email for SSL notifications: " LETSENCRYPT_EMAIL
                if [[ "$LETSENCRYPT_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
                    break
                fi
                print_warn "Please enter a valid email address (e.g., user@example.com)."
            done
        fi
    fi

    # ── wkhtmltopdf ────────────────────────────────────────────────────────
    print_section "PDF Rendering (wkhtmltopdf)"
    echo "  Odoo includes a built-in PDF renderer that works out of the box."
    echo "  wkhtmltopdf is an optional tool that may improve PDF quality"
    echo "  for complex reports, but it is deprecated (last release: 2023)."
    echo ""
    local _WK_CODENAME _WK_ARCH
    _WK_CODENAME=$(lsb_release -cs 2>/dev/null || echo "unknown")
    _WK_ARCH=$(dpkg --print-architecture 2>/dev/null || echo "amd64")

    if [[ "${_WK_CODENAME}_${_WK_ARCH}" =~ ^jammy_(amd64|arm64)$ ]]; then
        # ── Supported system ──
        read -rp "  Install wkhtmltopdf? (y/N): " WKHTML_CHOICE
        WKHTML_CHOICE=$(echo "$WKHTML_CHOICE" | tr '[:upper:]' '[:lower:]')
        if [[ "$WKHTML_CHOICE" =~ ^(y|yes)$ ]]; then
            INSTALL_WKHTMLTOPDF="True"
            print_info "wkhtmltopdf will be installed."
        else
            INSTALL_WKHTMLTOPDF="False"
            print_info "Skipping wkhtmltopdf — Odoo built-in PDF renderer will be used."
        fi
    else
        # ── Unsupported system — show detailed warning ──
        echo "  ┌──────────────────────────────────────────────────────────────┐"
        echo "  │  ⚠️  WARNING: No Official Package for Your System            │"
        echo "  ├──────────────────────────────────────────────────────────────┤"
        printf "  │  %-62s│\n" "  Detected: Ubuntu ${_WK_CODENAME} (${_WK_ARCH})"
        echo "  │  Official packages exist only for Ubuntu 22.04 (Jammy).     │"
        echo "  │                                                              │"
        echo "  │  • Project archived — no updates since May 2023.            │"
        echo "  │  • Installing on this system may cause dependency errors.   │"
        echo "  │  • Odoo works perfectly without it (built-in renderer).     │"
        echo "  └──────────────────────────────────────────────────────────────┘"
        echo ""
        read -rp "  Continue installing wkhtmltopdf at your own risk? (y/N): " WKHTML_CHOICE
        WKHTML_CHOICE=$(echo "$WKHTML_CHOICE" | tr '[:upper:]' '[:lower:]')
        if [[ "$WKHTML_CHOICE" =~ ^(y|yes)$ ]]; then
            INSTALL_WKHTMLTOPDF="True"
            print_warn "wkhtmltopdf installation will be attempted at your own risk."
        else
            INSTALL_WKHTMLTOPDF="False"
            print_info "Skipping wkhtmltopdf — Odoo built-in PDF renderer will be used."
        fi
    fi

    # ── queue_job (OCA) ───────────────────────────────────────────────────
    print_section "Background Job Queue (OCA queue_job)"
    echo "  queue_job (OCA) lets Odoo modules run methods asynchronously via"
    echo "  .with_delay() instead of blocking the request. Optional — only"
    echo "  needed if a module you plan to install actually uses it."
    echo ""
    read -rp "  Install and enable OCA queue_job? (y/N): " QJ_CHOICE
    QJ_CHOICE=$(echo "$QJ_CHOICE" | tr '[:upper:]' '[:lower:]')
    if [[ "$QJ_CHOICE" =~ ^(y|yes)$ ]]; then
        INSTALL_QUEUE_JOB="True"
        print_info "queue_job will be installed and enabled as a server-wide module."
    else
        INSTALL_QUEUE_JOB="False"
        print_info "Skipping queue_job."
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
    local _nginx_disp="No"; [[ "$NGINX_CHOICE" =~ ^(y|yes)$ ]] && _nginx_disp="Yes"
    printf  "${BLUE}║${NC}  %-22s : %-40s ${BLUE}║${NC}\n" "Nginx"             "$_nginx_disp"
    if [[ "$NGINX_CHOICE" =~ ^(y|yes)$ ]]; then
        printf "${BLUE}║${NC}  %-22s : %-40s ${BLUE}║${NC}\n" "Domain"           "$NGINX_DOMAIN"
        if [[ "$SSL_CHOICE" =~ ^(y|yes)$ ]]; then
            printf "${BLUE}║${NC}  %-22s : %-40s ${BLUE}║${NC}\n" "SSL"           "Let's Encrypt"
            printf "${BLUE}║${NC}  %-22s : %-40s ${BLUE}║${NC}\n" "SSL Email"     "$LETSENCRYPT_EMAIL"
        else
            printf "${BLUE}║${NC}  %-22s : %-40s ${BLUE}║${NC}\n" "SSL"           "None"
        fi
    fi
    local _wk_disp="No (built-in renderer)"; [[ "$INSTALL_WKHTMLTOPDF" == "True" ]] && _wk_disp="Yes (if supported)"
    printf  "${BLUE}║${NC}  %-22s : %-40s ${BLUE}║${NC}\n" "wkhtmltopdf"      "$_wk_disp"
    local _qj_disp="No"; [[ "$INSTALL_QUEUE_JOB" == "True" ]] && _qj_disp="Yes"
    printf  "${BLUE}║${NC}  %-22s : %-40s ${BLUE}║${NC}\n" "queue_job"        "$_qj_disp"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [[ "$CONFIG_MODE" == "non-interactive" ]]; then
        print_info "Non-interactive mode — proceeding automatically."
        return 0
    fi

    read -rp "Proceed with installation? (y/N): " CONFIRM
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
    for cmd in wget git gpg curl lsb_release; do
        command -v "$cmd" &>/dev/null || print_error "'$cmd' is required but not installed."
    done
    print_info "All required tools are present."
}

step_check_ubuntu() {
    UBUNTU_VERSION=$(lsb_release -r -s 2>/dev/null || echo "unknown")
    [[ "$UBUNTU_VERSION" == "unknown" ]] && print_error "Cannot detect Ubuntu version."
    local major minor
    IFS='.' read -r major minor _ <<< "$UBUNTU_VERSION"
    if (( major > 22 || (major == 22 && minor >= 4) )); then
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
        lsb-release
    print_info "System packages installed."
}

step_install_nodejs() {
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - \
        || print_error "Failed to add NodeSource repository."
    sudo apt install -y nodejs || print_error "Failed to install Node.js 20."
    sudo npm install -g rtlcss || print_error "Failed to install rtlcss."
    print_info "Node.js 20 LTS and rtlcss installed."
}

step_install_wkhtmltopdf() {
    if [[ "$INSTALL_WKHTMLTOPDF" != "True" ]]; then
        print_info "wkhtmltopdf skipped — Odoo built-in PDF renderer will be used."
        return
    fi

    local CODENAME ARCH WKHTML_URL WKHTML_DEB
    CODENAME=$(lsb_release -cs 2>/dev/null || echo "unknown")
    ARCH=$(dpkg --print-architecture 2>/dev/null || echo "amd64")
    WKHTML_DEB="/tmp/wkhtmltox_${OE_USER}.deb"
    local BASE_URL="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3"

    case "${CODENAME}_${ARCH}" in
        jammy_amd64)
            WKHTML_URL="${BASE_URL}/wkhtmltox_0.12.6.1-3.jammy_amd64.deb"
            ;;
        jammy_arm64)
            WKHTML_URL="${BASE_URL}/wkhtmltox_0.12.6.1-3.jammy_arm64.deb"
            ;;
        *_amd64)
            # User chose to proceed at own risk on unsupported amd64 system
            print_warn "No official package for '${CODENAME}'. Attempting jammy_amd64 build at your own risk..."
            WKHTML_URL="${BASE_URL}/wkhtmltox_0.12.6.1-3.jammy_amd64.deb"
            ;;
        *_arm64)
            # User chose to proceed at own risk on unsupported arm64 system
            print_warn "No official package for '${CODENAME}'. Attempting jammy_arm64 build at your own risk..."
            WKHTML_URL="${BASE_URL}/wkhtmltox_0.12.6.1-3.jammy_arm64.deb"
            ;;
        *)
            print_warn "wkhtmltopdf: unsupported architecture '${ARCH}'. Skipping."
            print_warn "Odoo built-in PDF renderer will be used instead."
            return
            ;;
    esac

    # Ensure gdebi is available before attempting installation
    if ! command -v gdebi &>/dev/null; then
        print_step "Installing gdebi-core (required for .deb installation)..."
        sudo apt-get install -y -q gdebi-core \
            || { print_warn "Could not install gdebi-core. Skipping wkhtmltopdf."; return; }
    fi

    print_step "Downloading wkhtmltopdf for Ubuntu ${CODENAME} / ${ARCH}..."
    if ! wget -q "$WKHTML_URL" -O "$WKHTML_DEB"; then
        print_warn "Failed to download wkhtmltopdf. Skipping — built-in PDF renderer will be used."
        rm -f "$WKHTML_DEB"
        return
    fi

    if ! sudo gdebi -n "$WKHTML_DEB"; then
        print_warn "Failed to install wkhtmltopdf (dependency error likely). Skipping — built-in PDF renderer will be used."
        rm -f "$WKHTML_DEB"
        return
    fi

    rm -f "$WKHTML_DEB"

    if command -v wkhtmltopdf &>/dev/null; then
        print_info "wkhtmltopdf installed: $(wkhtmltopdf --version 2>/dev/null | head -n1)"
    else
        print_warn "wkhtmltopdf package applied but binary not found in PATH. Check manually."
    fi
}

step_setup_postgresql() {
    if dpkg -l postgresql-16 2>/dev/null | grep -q "^ii"; then
        print_info "PostgreSQL 16 is already installed."
        sudo systemctl is-active --quiet postgresql || {
            sudo systemctl start postgresql
            sudo systemctl enable postgresql
        }
    else
        curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
            | gpg --dearmor \
            | sudo tee /usr/share/keyrings/postgresql.gpg > /dev/null \
            || print_error "Failed to import PostgreSQL GPG key. Check network and try again."
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
        sudo -u postgres createuser --createdb "$OE_USER"
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

    # Configure automatic log rotation
    sudo tee "/etc/logrotate.d/${OE_USER}-odoo" > /dev/null <<EOF
/var/log/${OE_USER}/${OE_USER}-server.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    copytruncate
}
EOF
    print_info "Log rotation configured: /etc/logrotate.d/${OE_USER}-odoo"
}

step_clone_odoo() {
    local OE_HOME_EXT="/$OE_USER/${OE_USER}-server"
    if [ -d "$OE_HOME_EXT" ]; then
        print_warn "Odoo source directory exists. Skipping clone."
    else
        [[ "$OE_VERSION" == "19.0" ]] && \
            print_warn "Odoo 19.0 is a development branch — may be unstable or not yet available."
        sudo -u "$OE_USER" git clone --depth 1 --branch "$OE_VERSION" \
            https://github.com/odoo/odoo "$OE_HOME_EXT" \
            || print_error "Failed to clone Odoo $OE_VERSION. The branch may not exist yet."
        print_info "Odoo $OE_VERSION cloned."
    fi
}

step_create_addons_dir() {
    sudo -u "$OE_USER" mkdir -p "/$OE_USER/custom/addons"
    print_info "Custom addons directory: /$OE_USER/custom/addons"
}

step_install_queue_job() {
    if [[ "$INSTALL_QUEUE_JOB" != "True" ]]; then
        print_info "queue_job skipped."
        return
    fi

    local ADDONS_DIR="/$OE_USER/custom/addons"
    local QJ_DIR="$ADDONS_DIR/queue_job"
    local TMP_CLONE="/tmp/oca_queue_${OE_USER}"

    if [ -d "$QJ_DIR" ]; then
        print_warn "queue_job already present at $QJ_DIR — skipping clone."
        return
    fi

    print_step "Cloning OCA queue_job (branch $OE_VERSION)..."
    rm -rf "$TMP_CLONE"
    if sudo -u "$OE_USER" git clone --depth 1 --branch "$OE_VERSION" \
            https://github.com/OCA/queue "$TMP_CLONE" 2>/dev/null; then
        sudo -u "$OE_USER" cp -r "$TMP_CLONE/queue_job" "$QJ_DIR"
        rm -rf "$TMP_CLONE"
        print_info "queue_job installed to $QJ_DIR"
    else
        print_warn "Could not clone OCA queue_job for branch '$OE_VERSION' (the branch may not exist yet for this Odoo version). Skipping — install it manually later if needed."
        rm -rf "$TMP_CLONE"
        # Prevent step_create_config from enabling server_wide_modules for a
        # module that was never actually installed - that would crash Odoo on boot.
        INSTALL_QUEUE_JOB="False"
    fi
}

step_set_permissions() {
    sudo chown -R "$OE_USER:$OE_USER" "/$OE_USER"
    print_info "Permissions set for /$OE_USER"
}

step_create_venv() {
    local VENV_PATH="/$OE_USER/venv"
    sudo -u "$OE_USER" python3 -m venv "$VENV_PATH"

    print_info "Upgrading pip, setuptools, and wheel..."
    sudo -u "$OE_USER" "$VENV_PATH/bin/pip" install --upgrade pip setuptools wheel

    print_info "Installing extra required packages..."
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
    print_info "cbor2 version unpinned to >=5.4.6 (fixes Python 3.10 build failure)"

    # Fix known gevent compatibility issue on Odoo 17.x and 18.x
    if [[ "$OE_VERSION" =~ ^1[7-8]\.0$ ]]; then
        print_warn "Detected Odoo $OE_VERSION -- pinning gevent to 23.9.1 for compatibility."
        sed -i '/gevent/d' "$REQ_FILE"
        sudo -u "$OE_USER" "$VENV_PATH/bin/pip" install -r "$REQ_FILE" \
            || print_error "Failed to install Python dependencies. Check the output above."
        sudo -u "$OE_USER" "$VENV_PATH/bin/pip" install "gevent==23.9.1"
    else
        sudo -u "$OE_USER" "$VENV_PATH/bin/pip" install -r "$REQ_FILE" \
            || print_error "Failed to install Python dependencies. Check the output above."
    fi

    rm -f "$REQ_FILE"
    print_info "Python dependencies installed."
}

step_create_config() {
    local OE_HOME_EXT="/$OE_USER/${OE_USER}-server"
    local VENV_PATH="/$OE_USER/venv"
    local CONFIG_FILE="/etc/${OE_USER}-server.conf"

    local _raw_pass
    _raw_pass=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9')
    OE_SUPERADMIN="${_raw_pass:0:20}"
    [ ${#OE_SUPERADMIN} -lt 16 ] && print_error "Failed to generate a secure admin password. Check openssl."
    [ ! -f "$SECRETS_FILE" ] && install -m 600 /dev/null "$SECRETS_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S')  instance='$OE_USER'  master_password='$OE_SUPERADMIN'" \
        >> "$SECRETS_FILE"
    chmod 600 "$SECRETS_FILE"

    sudo install -m 640 -o "$OE_USER" -g "$OE_USER" /dev/null "$CONFIG_FILE"

    sudo tee "$CONFIG_FILE" > /dev/null <<EOF
[options]
admin_passwd       = ${OE_SUPERADMIN}
http_port          = ${OE_PORT}
longpolling_port   = ${LONGPOLLING_PORT}
logfile            = /var/log/${OE_USER}/${OE_USER}-server.log
addons_path        = ${OE_HOME_EXT}/addons,/$OE_USER/custom/addons
EOF

    if [[ "$INSTALL_QUEUE_JOB" == "True" ]]; then
        # queue_job's jobrunner thread only starts if it is loaded as a server-wide
        # module (imported at process boot, before any per-database install state
        # is checked) - see step_install_queue_job for where the addon is cloned.
        echo "server_wide_modules = web,queue_job" | sudo tee -a "$CONFIG_FILE" > /dev/null
        print_info "server_wide_modules = web,queue_job added to config."
    fi

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
LimitNOFILE=65536
PrivateTmp=yes
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "${OE_USER}-server"
    print_info "Systemd service: ${OE_USER}-server"
}

step_start_service() {
    sudo systemctl start "${OE_USER}-server"
    print_step "Waiting for Odoo service to become active (up to 60s)..."
    wait_for_service_active "${OE_USER}-server" \
        || print_error "Odoo service did not start within 60 seconds. Run: journalctl -u ${OE_USER}-server -n 50"
}

step_configure_nginx() {
    if ! check_nginx_installed; then
        print_step "Installing Nginx..."
        sudo apt install -y nginx || print_error "Failed to install Nginx."
        print_info "Nginx installed."
    else
        print_info "Nginx is already installed."
    fi

    # ── UFW: Enable (if inactive) + Allow HTTP/HTTPS from Cloudflare only ─
    print_step "Configuring UFW firewall..."
    if ! sudo ufw status | grep -q "Status: active"; then
        print_warn "UFW is inactive — enabling it now (port 22/SSH will be allowed first)."
        sudo ufw allow 22/tcp 2>/dev/null || true
        sudo ufw --force enable
        print_security "UFW enabled."
    fi

    print_step "Fetching current Cloudflare IP ranges..."
    CF_IPV4_LIST=$(curl -fsSL --max-time 10 https://www.cloudflare.com/ips-v4 2>/dev/null) || {
        print_warn "Could not fetch Cloudflare IPs — using built-in fallback list."
        CF_IPV4_LIST="173.245.48.0/20
103.21.244.0/22
103.22.200.0/22
103.31.4.0/22
141.101.64.0/18
108.162.192.0/18
190.93.240.0/20
188.114.96.0/20
197.234.240.0/22
198.41.128.0/17
162.158.0.0/15
104.16.0.0/13
104.24.0.0/14
172.64.0.0/13
131.0.72.0/22"
    }

    CF_IPV6_LIST=$(curl -fsSL --max-time 10 https://www.cloudflare.com/ips-v6 2>/dev/null) || {
        print_warn "Could not fetch Cloudflare IPv6 IPs — skipping IPv6 rules."
        CF_IPV6_LIST=""
    }

    print_step "Verifying domain is proxied through Cloudflare..."
    warn_if_domain_not_behind_cloudflare "$NGINX_DOMAIN"

    sudo ufw delete allow 'Nginx Full'  2>/dev/null || true
    sudo ufw delete allow 'Nginx HTTP'  2>/dev/null || true
    sudo ufw delete allow 'Nginx HTTPS' 2>/dev/null || true
    sudo ufw delete allow 80/tcp        2>/dev/null || true
    sudo ufw delete allow 443/tcp       2>/dev/null || true
    while IFS= read -r cfip; do
        [[ -z "$cfip" ]] && continue
        sudo ufw allow from "$cfip" to any port 80  proto tcp 2>/dev/null || true
        sudo ufw allow from "$cfip" to any port 443 proto tcp 2>/dev/null || true
    done <<< "$CF_IPV4_LIST"
    while IFS= read -r cfip; do
        [[ -z "$cfip" ]] && continue
        sudo ufw allow from "$cfip" to any port 80  proto tcp 2>/dev/null || true
        sudo ufw allow from "$cfip" to any port 443 proto tcp 2>/dev/null || true
    done <<< "$CF_IPV6_LIST"
    print_security "UFW: HTTP/HTTPS allowed from Cloudflare IPs only (IPv4 + IPv6)."

    # Ensure www-data exists
    id www-data &>/dev/null || print_error "Nginx user 'www-data' not found."

    # Global: client_max_body_size
    if ! grep -q "client_max_body_size 1G;" /etc/nginx/nginx.conf; then
        sudo sed -i '/http {/a \    client_max_body_size 1G;' /etc/nginx/nginx.conf
        print_info "Set global client_max_body_size = 1G"
    fi

    # Global: server_tokens off
    if ! grep -q "server_tokens off;" /etc/nginx/nginx.conf; then
        sudo sed -i '/http {/a \    server_tokens off;' /etc/nginx/nginx.conf
        print_info "server_tokens off — Nginx version hidden."
    fi

    # ── Default server block: reject direct IP access ────────────────────
    if [ ! -f /etc/nginx/ssl/dummy.crt ]; then
        print_step "Creating dummy SSL certificate for default block..."
        sudo mkdir -p /etc/nginx/ssl
        sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout /etc/nginx/ssl/dummy.key \
            -out    /etc/nginx/ssl/dummy.crt \
            -subj "/CN=localhost" 2>/dev/null
        print_security "Dummy certificate created."
    fi
    # Remove Nginx default site (conflicts with our default block)
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo rm -f /etc/nginx/sites-available/default

    if [ ! -f /etc/nginx/sites-available/000-default-block ]; then
        sudo tee /etc/nginx/sites-available/000-default-block > /dev/null <<'DEFAULTEOF'
# Block all direct IP access — return 444 (no response)
server {
    listen 80  default_server;
    listen [::]:80  default_server;
    listen 443 ssl  default_server;
    listen [::]:443 ssl default_server;
    ssl_certificate     /etc/nginx/ssl/dummy.crt;
    ssl_certificate_key /etc/nginx/ssl/dummy.key;
    server_name _;
    return 444;
}
DEFAULTEOF
        sudo ln -sf /etc/nginx/sites-available/000-default-block \
                    /etc/nginx/sites-enabled/000-default-block
        print_security "Default block: direct IP access will return 444."
    fi

    # WebSocket global map (in conf.d)
    if ! grep -rq 'map $http_upgrade $connection_upgrade' \
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
# Domain: ${NGINX_DOMAIN}
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

# ── HTTPS ──────────────────────────────────────────────────────────────────
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${NGINX_DOMAIN};
    charset utf-8;

    # ── SSL ─────────────────────────────────────────────────────────────
    # Certbot will replace these two paths automatically when SSL is enabled.
    # Until then, a self-signed dummy certificate is used so nginx -t passes.
    ssl_certificate     /etc/nginx/ssl/dummy.crt;
    ssl_certificate_key /etc/nginx/ssl/dummy.key;

    # ── Security ────────────────────────────────────────────────────────
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    # HSTS is added automatically after a valid SSL certificate is installed.

    # ── Reject requests not matching domain (block direct IP access) ─────
    if (\$host != "${NGINX_DOMAIN}") {
        return 444;
    }

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

    # ── Block Sensitive Files ────────────────────────────────────────────
    location ~* \.(env|git|svn|htaccess|htpasswd|ini|log|sh|sql|conf|bak)\$ {
        deny all;
        return 404;
    }

    # ── Static Assets (cached) ──────────────────────────────────────────
    location /web/static/ {
        proxy_pass http://${UPSTREAM_MAIN};
        proxy_cache ${CACHE_ZONE};
        proxy_cache_valid 200 7d;
        proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
        proxy_ignore_headers Cache-Control Expires;
        # Re-declare security headers — Nginx child blocks do NOT inherit
        # add_header from the parent server block when they define their own.
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header X-Cache-Status \$upstream_cache_status;
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
        proxy_send_timeout 3600;
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
        proxy_send_timeout 3600;
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
        proxy_hide_header X-Powered-By;
        proxy_hide_header Server;
    }

    access_log /var/log/nginx/${OE_USER}_access.log;
    error_log  /var/log/nginx/${OE_USER}_error.log warn;
}

# ── HTTP ────────────────────────────────────────────────────────────────────
# Without SSL: proxies directly to Odoo over HTTP.
# With SSL:    Certbot (--redirect) converts this block to an HTTPS redirect.
server {
    listen 80;
    listen [::]:80;
    server_name ${NGINX_DOMAIN};

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

    location / {
        proxy_pass http://${UPSTREAM_MAIN};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 60;
        proxy_send_timeout 300;
        proxy_read_timeout 600;
    }
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
        print_step "Waiting for Odoo to come back up after enabling proxy_mode (up to 60s)..."
        wait_for_service_active "${OE_USER}-server" \
            || print_error "Odoo did not come back up after enabling proxy_mode. Run: journalctl -u ${OE_USER}-server -n 50"
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
            # Add HSTS now that a valid certificate is in place
            local NGINX_SITE_SSL="/etc/nginx/sites-available/${OE_USER}"
            if ! grep -q "Strict-Transport-Security" "$NGINX_SITE_SSL"; then
                sudo sed -i \
                    '/add_header Referrer-Policy/a\    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;' \
                    "$NGINX_SITE_SSL"
                # Verify HSTS was actually injected (sed silently skips if anchor not found)
                if ! grep -q "Strict-Transport-Security" "$NGINX_SITE_SSL"; then
                    print_warn "HSTS injection failed — anchor line not found. Add it manually to $NGINX_SITE_SSL"
                elif sudo nginx -t >/dev/null 2>&1; then
                    sudo systemctl reload nginx
                    print_security "HSTS enabled (max-age=1 year, includeSubDomains)."
                else
                    print_warn "nginx -t failed after HSTS injection — HSTS not applied. Check config manually."
                fi
            fi
            NGINX_ACCESS_URL="https://${NGINX_DOMAIN}"
        else
            print_warn "SSL certificate request failed. Site accessible via HTTP only."
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
    local QJ_EN="false"
    [[ "$NGINX_CHOICE" =~ ^(y|yes)$ ]] && NGINX_EN="true"
    [[ "$SSL_CHOICE"   =~ ^(y|yes)$ ]] && SSL_EN="true"
    [[ "$INSTALL_QUEUE_JOB" == "True" ]] && QJ_EN="true"

    cat > "$MANIFEST_FILE" <<EOF
{
  "instance_name":    "$OE_USER",
  "odoo_version":     "$OE_VERSION",
  "http_port":        $OE_PORT,
  "longpolling_port": $LONGPOLLING_PORT,
  "nginx_enabled":    $NGINX_EN,
  "domain":           "$NGINX_DOMAIN",
  "ssl_enabled":      $SSL_EN,
  "queue_job_enabled":$QJ_EN,
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
    execute_step "Installing queue_job"      step_install_queue_job
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
    if [[ "$NGINX_CHOICE" =~ ^(y|yes)$ ]]; then
        echo "  [✓] Database manager blocked via Nginx (HTTP + HTTPS)"
        echo "      location ~* ^/web/database { deny all; return 403; }"
    else
        echo "  [!] Database manager NOT blocked — Nginx not configured."
        echo "      Add to Odoo config:  list_db = False"
        echo "      Then:  sudo systemctl restart ${OE_USER}-server"
    fi
    echo ""
    echo "  [ ] Optional: Extra hardening via Odoo config (recommended for production):"
    echo "        sudo nano /etc/${OE_USER}-server.conf"
    echo "        # Add:  list_db = False"
    echo "        #        dbfilter = ^${OE_USER}\$"
    echo "        sudo systemctl restart ${OE_USER}-server"
    echo ""
    echo "  [ ] Review UFW firewall rules:   sudo ufw status"
    echo "  [ ] Enable automatic OS updates: sudo dpkg-reconfigure unattended-upgrades"
    echo "  [✓] Log rotation configured:     /etc/logrotate.d/${OE_USER}-odoo"
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
    local _qj_final="No"; [[ "$INSTALL_QUEUE_JOB" == "True" ]] && _qj_final="Yes (server-wide)"
    printf "║  %-22s : %-40s║\n" "queue_job"         "$_qj_final"
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
        case "$OE_VERSION" in
            17.0|18.0|19.0) ;;
            *) print_error "Invalid version: '$OE_VERSION'. Supported: 17.0 | 18.0 | 19.0" ;;
        esac
        if [[ "$SSL_CHOICE" =~ ^(y|yes)$ ]] && ! [[ "$NGINX_CHOICE" =~ ^(y|yes)$ ]]; then
            print_error "--ssl requires --nginx. SSL works only through Nginx reverse proxy."
        fi
        if [[ "$SSL_CHOICE" =~ ^(y|yes)$ ]] && [[ -z "$LETSENCRYPT_EMAIL" ]]; then
            print_error "--email is required when --ssl is enabled."
        fi
        if [[ "$NGINX_CHOICE" =~ ^(y|yes)$ ]] && [[ -z "$NGINX_DOMAIN" ]]; then
            NGINX_DOMAIN="$SERVER_IP"
            print_warn "No --domain specified. Using server IP: $SERVER_IP"
        fi
        LONGPOLLING_PORT=$((OE_PORT + 3))
        if check_port_in_use "$LONGPOLLING_PORT"; then
            print_warn "Longpolling port $LONGPOLLING_PORT is already in use. Live features may not work."
        fi
    fi

    validate_configuration
    execute_installation
}

main "$@"
