#!/bin/bash
################################################################################
# Odoo Instance Deletion Script - Professional Edition
# Author: Ibrahim Aljuhani
# Compatible with: install_odoo.sh v3.0.0
# Features: Safe detection, Dry-run, Non-interactive, Backup, Full cleanup
################################################################################
set -e

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

print_info()    { echo -e "${GREEN}[✔ DONE ]${NC} $1"; }
print_warn()    { echo -e "${YELLOW}[⚠ WARN ]${NC} $1"; }
print_error()   { echo -e "${RED}[✖ ERROR]${NC} $1"; exit 1; }
print_step()    { echo -e "${CYAN}[  ==>  ]${NC} $1"; }
print_danger()  { echo -e "${RED}[🔥 WARN ]${NC} $1"; }

print_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║         Odoo Instance Deletion Tool - Professional Edition       ║"
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
#  Configuration
# ─────────────────────────────────────────────────────────────────────────────
DRY_RUN=false
FORCE=false
BACKUP=false
OE_USER=""

BACKUP_DIR="/root/odoo-backups"
MANIFEST_DIR="/root/odoo-installs"
LOG_FILE="/root/odoo-deletion-log.txt"
TEMP_REPORT=""

# ─────────────────────────────────────────────────────────────────────────────
#  Help
# ─────────────────────────────────────────────────────────────────────────────
show_help() {
    print_banner
    echo -e "${BOLD}Usage:${NC}"
    echo ""
    echo "  Interactive (default):"
    echo "    sudo ./delete_odoo.sh"
    echo ""
    echo "  Non-Interactive:"
    echo "    sudo ./delete_odoo.sh --instance <name> [--backup] [--force] [--dry-run]"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    printf "  %-20s %s\n" "--instance <name>"  "Instance name to delete"
    printf "  %-20s %s\n" "--backup"           "Create full backup before deletion"
    printf "  %-20s %s\n" "--force"            "Skip confirmation prompt"
    printf "  %-20s %s\n" "--dry-run"          "Simulate deletion without making changes"
    printf "  %-20s %s\n" "--help, -h"         "Show this help message"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  sudo ./delete_odoo.sh"
    echo "  sudo ./delete_odoo.sh --instance prod --backup --force"
    echo "  sudo ./delete_odoo.sh --instance test --dry-run"
    exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
#  Instance Detection
#  Validates all artifacts created by install_odoo.sh v3.0.0
# ─────────────────────────────────────────────────────────────────────────────
is_odoo_instance() {
    local user="$1"
    # All four artifacts must exist to qualify as a valid instance
    [ -f "/etc/${user}-server.conf" ]                        &&
    [ -f "/etc/systemd/system/${user}-server.service" ]      &&
    [ -d "/$user/${user}-server" ]                           &&
    [ -f "/$user/${user}-server/odoo-bin" ]
}

detect_instances() {
    local instances=()
    while IFS= read -r user; do
        if [[ "$user" =~ ^[a-z][a-z0-9_-]*$ ]] && id -u "$user" &>/dev/null; then
            if is_odoo_instance "$user"; then
                instances+=("$user")
            fi
        fi
    done < <(cut -d: -f1 /etc/passwd | sort)
    echo "${instances[@]}"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Instance Info Summary
# ─────────────────────────────────────────────────────────────────────────────
show_instance_info() {
    local user="$1"
    local port=""
    local lp_port=""
    local nginx_domain=""
    local has_nginx="No"
    local has_ssl="No"
    local has_manifest="No"
    local has_cache="No"

    # Read port from config
    if [ -f "/etc/${user}-server.conf" ]; then
        port=$(grep "^http_port" "/etc/${user}-server.conf" 2>/dev/null \
               | awk -F'=' '{print $2}' | tr -d ' ' || echo "N/A")
        lp_port=$(grep "^longpolling_port" "/etc/${user}-server.conf" 2>/dev/null \
                  | awk -F'=' '{print $2}' | tr -d ' ' || echo "N/A")
    fi

    # Check Nginx
    if [ -f "/etc/nginx/sites-available/${user}" ]; then
        has_nginx="Yes"
        nginx_domain=$(grep "server_name" "/etc/nginx/sites-available/${user}" 2>/dev/null \
                       | awk '{print $2}' | tr -d ';' | head -1 || echo "N/A")
        grep -q "ssl_certificate" "/etc/nginx/sites-available/${user}" 2>/dev/null \
            && has_ssl="Yes"
    fi

    # Check manifest files
    ls "$MANIFEST_DIR/${user}_"*"_manifest.json" &>/dev/null 2>&1 \
        && has_manifest="Yes"

    # Check Nginx cache
    [ -d "/var/cache/nginx/odoo_static_${user}" ] && has_cache="Yes"

    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                     Instance Information                         ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════════╣${NC}"
    printf  "${BLUE}║${NC}  %-22s : %-40s ${BLUE}║${NC}\n" "Instance Name"    "$user"
    printf  "${BLUE}║${NC}  %-22s : %-40s ${BLUE}║${NC}\n" "HTTP Port"        "${port:-N/A}"
    printf  "${BLUE}║${NC}  %-22s : %-40s ${BLUE}║${NC}\n" "Longpolling Port" "${lp_port:-N/A}"
    printf  "${BLUE}║${NC}  %-22s : %-40s ${BLUE}║${NC}\n" "Nginx Configured" "$has_nginx"
    printf  "${BLUE}║${NC}  %-22s : %-40s ${BLUE}║${NC}\n" "Domain"           "${nginx_domain:-N/A}"
    printf  "${BLUE}║${NC}  %-22s : %-40s ${BLUE}║${NC}\n" "SSL Enabled"      "$has_ssl"
    printf  "${BLUE}║${NC}  %-22s : %-40s ${BLUE}║${NC}\n" "Manifest Files"   "$has_manifest"
    printf  "${BLUE}║${NC}  %-22s : %-40s ${BLUE}║${NC}\n" "Nginx Cache"      "$has_cache"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
#  Report Helper
# ─────────────────────────────────────────────────────────────────────────────
report() {
    echo "  $1" >> "$TEMP_REPORT"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Backup
# ─────────────────────────────────────────────────────────────────────────────
backup_instance() {
    local user="$1"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/${user}_${timestamp}"

    print_step "Creating backup at: $backup_path"
    sudo mkdir -p "$backup_path"

    # Home directory
    if [ -d "/$user" ]; then
        print_step "Compressing home directory..."
        sudo tar -czf "$backup_path/home.tar.gz" "/$user" 2>/dev/null || true
        report "✓ Home directory backed up → $backup_path/home.tar.gz"
    fi

    # Config file
    if [ -f "/etc/${user}-server.conf" ]; then
        sudo cp "/etc/${user}-server.conf" "$backup_path/" 2>/dev/null || true
        report "✓ Config file backed up"
    fi

    # Systemd service
    if [ -f "/etc/systemd/system/${user}-server.service" ]; then
        sudo cp "/etc/systemd/system/${user}-server.service" "$backup_path/" 2>/dev/null || true
        report "✓ Systemd service file backed up"
    fi

    # PostgreSQL database
    if sudo -u postgres psql -lqt 2>/dev/null | cut -d'|' -f1 | grep -qw "$user"; then
        print_step "Dumping PostgreSQL database..."
        sudo -u postgres pg_dump "$user" > "$backup_path/db.sql" 2>/dev/null || true
        report "✓ PostgreSQL database backed up → $backup_path/db.sql"
    fi

    # Nginx config
    if [ -f "/etc/nginx/sites-available/$user" ]; then
        sudo cp "/etc/nginx/sites-available/$user" "$backup_path/nginx_${user}" 2>/dev/null || true
        report "✓ Nginx config backed up"
    fi

    # Manifest files (new in install_odoo.sh v3.0.0)
    local manifests
    manifests=$(ls "$MANIFEST_DIR/${user}_"*"_manifest.json" 2>/dev/null || true)
    if [ -n "$manifests" ]; then
        sudo cp $manifests "$backup_path/" 2>/dev/null || true
        report "✓ Manifest JSON files backed up"
    fi

    sudo chmod -R 600 "$backup_path"
    print_info "Backup complete: $backup_path"
    report ""
}

# ─────────────────────────────────────────────────────────────────────────────
#  Deletion Steps (each is an isolated function — no eval)
# ─────────────────────────────────────────────────────────────────────────────

step_stop_service() {
    if $DRY_RUN; then
        print_info "[DRY RUN] Would stop: ${OE_USER}-server"
        report "[DRY RUN] Stop service ${OE_USER}-server"
        return
    fi
    sudo systemctl stop "${OE_USER}-server"  2>/dev/null || true
    sudo systemctl kill --signal=SIGKILL "${OE_USER}-server" 2>/dev/null || true
    sleep 2
    sudo pkill -9 -u "$OE_USER" 2>/dev/null || true
    report "✓ Service stopped and processes killed"
    print_info "Service stopped."
}

step_remove_service_files() {
    if $DRY_RUN; then
        print_info "[DRY RUN] Would remove: /etc/systemd/system/${OE_USER}-server.service"
        report "[DRY RUN] Remove service file and config"
        return
    fi
    sudo systemctl disable --quiet "${OE_USER}-server" 2>/dev/null || true
    sudo rm -f "/etc/systemd/system/${OE_USER}-server.service"
    sudo rm -f "/etc/${OE_USER}-server.conf"
    sudo systemctl daemon-reload
    report "✓ Systemd service file removed"
    report "✓ Odoo config file removed"
    report "✓ Systemd daemon reloaded"
    print_info "Service files removed."
}

step_remove_user_and_dirs() {
    if $DRY_RUN; then
        print_info "[DRY RUN] Would remove: system user '$OE_USER', /$OE_USER, /var/log/$OE_USER"
        report "[DRY RUN] Remove user, home dir, log dir"
        return
    fi
    sudo userdel -r "$OE_USER" 2>/dev/null || true
    sudo rm -rf "/$OE_USER"
    sudo rm -rf "/var/log/$OE_USER"
    report "✓ System user '$OE_USER' deleted"
    report "✓ Home directory /$OE_USER removed"
    report "✓ Log directory /var/log/$OE_USER removed"
    print_info "User and directories removed."
}

step_remove_postgresql() {
    if ! sudo -u postgres psql -lqt 2>/dev/null | cut -d'|' -f1 | grep -qw "$OE_USER"; then
        print_warn "Database '$OE_USER' not found — skipping."
        report "⚠ PostgreSQL database '$OE_USER' not found — skipped"
        return
    fi

    if $DRY_RUN; then
        print_info "[DRY RUN] Would drop PostgreSQL DB and user: '$OE_USER'"
        report "[DRY RUN] Drop PostgreSQL database and user '$OE_USER'"
        return
    fi

    # Terminate active connections first
    sudo -u postgres psql -d postgres -c \
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$OE_USER';" \
        >/dev/null 2>&1 || true

    sudo -u postgres psql -d postgres -c \
        "DROP DATABASE IF EXISTS \"$OE_USER\";" >/dev/null 2>&1 || true

    sudo -u postgres psql -d postgres -c \
        "DROP USER IF EXISTS \"$OE_USER\";" >/dev/null 2>&1 || true

    report "✓ PostgreSQL database '$OE_USER' dropped"
    report "✓ PostgreSQL user '$OE_USER' dropped"
    print_info "PostgreSQL database and user removed."
}

step_remove_nginx() {
    local has_site=false
    [ -f "/etc/nginx/sites-available/$OE_USER" ] && has_site=true
    [ -f "/etc/nginx/sites-enabled/$OE_USER" ]   && has_site=true

    if ! $has_site; then
        print_warn "No Nginx config found for '$OE_USER' — skipping."
        report "⚠ No Nginx config found — skipped"
        return
    fi

    if $DRY_RUN; then
        print_info "[DRY RUN] Would remove Nginx config for '$OE_USER'"
        report "[DRY RUN] Remove Nginx site config"
        return
    fi

    sudo rm -f "/etc/nginx/sites-available/$OE_USER"
    sudo rm -f "/etc/nginx/sites-enabled/$OE_USER"
    report "✓ Nginx site config removed"

    if command -v nginx &>/dev/null; then
        if sudo nginx -t >/dev/null 2>&1; then
            sudo systemctl reload nginx 2>/dev/null || true
            report "✓ Nginx reloaded"
            print_info "Nginx config removed and reloaded."
        else
            report "⚠ Nginx config test failed after removal — manual review needed"
            print_warn "Nginx config test failed — manual review recommended."
        fi
    fi
}

# NEW: Remove Nginx static cache (created by install_odoo.sh v3.0.0)
step_remove_nginx_cache() {
    local cache_dir="/var/cache/nginx/odoo_static_${OE_USER}"

    if [ ! -d "$cache_dir" ]; then
        print_warn "No Nginx cache found for '$OE_USER' — skipping."
        report "⚠ No Nginx cache directory found — skipped"
        return
    fi

    if $DRY_RUN; then
        print_info "[DRY RUN] Would remove Nginx cache: $cache_dir"
        report "[DRY RUN] Remove Nginx cache: $cache_dir"
        return
    fi

    sudo rm -rf "$cache_dir"
    report "✓ Nginx static cache removed: $cache_dir"
    print_info "Nginx cache removed."
}

# NEW: Remove manifest JSON files (created by install_odoo.sh v3.0.0)
step_remove_manifests() {
    local found=false
    local manifests
    manifests=$(ls "$MANIFEST_DIR/${OE_USER}_"*"_manifest.json" 2>/dev/null || true)

    if [ -z "$manifests" ]; then
        print_warn "No manifest files found for '$OE_USER' — skipping."
        report "⚠ No manifest files found — skipped"
        return
    fi

    if $DRY_RUN; then
        print_info "[DRY RUN] Would remove manifest files in $MANIFEST_DIR"
        report "[DRY RUN] Remove manifest JSON files"
        return
    fi

    local count=0
    for f in $manifests; do
        sudo rm -f "$f"
        count=$((count + 1))
    done

    report "✓ Removed $count manifest file(s) from $MANIFEST_DIR"
    print_info "Manifest files removed ($count file(s))."
}

# NEW: Remove shared WebSocket map if this is the last Odoo instance
step_cleanup_shared_nginx_conf() {
    local ws_map="/etc/nginx/conf.d/ws_upgrade_map.conf"

    [ -f "$ws_map" ] || return 0

    # Count remaining active Odoo Nginx sites after this deletion
    local remaining
    remaining=$(ls /etc/nginx/sites-enabled/ 2>/dev/null \
                | grep -v "^$OE_USER$" \
                | while read -r site; do
                    grep -l "odoo_" "/etc/nginx/sites-available/$site" 2>/dev/null || true
                  done \
                | wc -l)

    if [ "$remaining" -gt 0 ]; then
        print_warn "Other Odoo instances still use Nginx — keeping ws_upgrade_map.conf."
        report "⚠ WebSocket map kept (other Odoo instances still active)"
        return
    fi

    if $DRY_RUN; then
        print_info "[DRY RUN] Would remove shared WebSocket map: $ws_map"
        report "[DRY RUN] Remove shared WebSocket map (last Odoo instance)"
        return
    fi

    sudo rm -f "$ws_map"
    report "✓ Shared WebSocket map removed (no remaining Odoo instances)"
    print_info "Shared WebSocket map removed."
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

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --instance) OE_USER="$2"; shift 2 ;;
            --force)    FORCE=true; shift ;;
            --backup)   BACKUP=true; shift ;;
            --dry-run)  DRY_RUN=true; FORCE=true; shift ;;
            --help|-h)  show_help ;;
            *)          shift ;;
        esac
    done

    clear
    print_banner

    if $DRY_RUN; then
        echo -e "${YELLOW}  ┌─────────────────────────────────────────────────────────┐${NC}"
        echo -e "${YELLOW}  │  🔍  DRY-RUN MODE — No changes will be made             │${NC}"
        echo -e "${YELLOW}  └─────────────────────────────────────────────────────────┘${NC}"
        echo ""
    fi

    # ── Detect instances ────────────────────────────────────────────────────
    print_section "Scanning for Odoo Instances"
    INSTANCES=($(detect_instances))

    if [ ${#INSTANCES[@]} -eq 0 ]; then
        print_info "No Odoo instances found on this server."
        exit 0
    fi

    # ── Select instance ─────────────────────────────────────────────────────
    if [[ -z "$OE_USER" ]]; then
        echo -e "  ${CYAN}Found ${#INSTANCES[@]} instance(s):${NC}"
        echo ""
        for i in "${!INSTANCES[@]}"; do
            printf "    %s) %s\n" "$((i+1))" "${INSTANCES[i]}"
        done
        echo ""
        read -p "  Select instance number to DELETE (0 to cancel): " CHOICE

        if [[ "$CHOICE" == "0" || -z "$CHOICE" ]]; then
            print_info "Operation cancelled."
            exit 0
        fi

        if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || \
           [ "$CHOICE" -lt 1 ] || \
           [ "$CHOICE" -gt ${#INSTANCES[@]} ]; then
            print_error "Invalid choice."
        fi

        OE_USER="${INSTANCES[$((CHOICE-1))]}"
    fi

    # ── Validate ────────────────────────────────────────────────────────────
    if ! is_odoo_instance "$OE_USER"; then
        print_error "Instance '$OE_USER' is not a valid Odoo instance or does not exist."
    fi

    # ── Show instance info ──────────────────────────────────────────────────
    print_section "Instance Details"
    show_instance_info "$OE_USER"

    # ── Backup ──────────────────────────────────────────────────────────────
    if $BACKUP && ! $DRY_RUN; then
        print_section "Creating Backup"
        TEMP_REPORT=$(mktemp)
        backup_instance "$OE_USER"
    else
        TEMP_REPORT=$(mktemp)
    fi

    # Initialize report
    cat > "$TEMP_REPORT" <<EOF
Odoo Instance Deletion Report
══════════════════════════════════════════════════════════════════
Instance  : $OE_USER
Timestamp : $(date '+%Y-%m-%d %H:%M:%S')
Mode      : $($DRY_RUN && echo 'DRY RUN (simulation only)' || echo 'REAL DELETION')
Backup    : $($BACKUP && echo "YES → $BACKUP_DIR/${OE_USER}_*" || echo 'NO')
══════════════════════════════════════════════════════════════════

Actions performed:
EOF

    # ── Confirmation ────────────────────────────────────────────────────────
    if ! $FORCE && ! $DRY_RUN; then
        echo -e "${RED}"
        echo "  ┌─────────────────────────────────────────────────────────┐"
        echo "  │  ⚠  WARNING — THIS ACTION IS IRREVERSIBLE!              │"
        echo "  │                                                         │"
        echo "  │  The following will be PERMANENTLY deleted:             │"
        echo "  │    • Odoo source code and custom addons                 │"
        echo "  │    • Config file and systemd service                    │"
        echo "  │    • PostgreSQL database and user                       │"
        echo "  │    • Nginx config and static cache                      │"
        echo "  │    • Log files and manifest JSON files                  │"
        echo "  └─────────────────────────────────────────────────────────┘"
        echo -e "${NC}"
        read -p "  Type the instance name '${OE_USER}' to confirm: " CONFIRM
        if [ "$CONFIRM" != "$OE_USER" ]; then
            print_error "Confirmation did not match. Aborting."
        fi
        echo ""
    fi

    # ── Execute deletion ────────────────────────────────────────────────────
    print_section "Running Deletion Steps"

    print_step "Stopping service..."
    step_stop_service

    print_step "Removing service and config files..."
    step_remove_service_files

    print_step "Removing system user and directories..."
    step_remove_user_and_dirs

    print_step "Removing PostgreSQL database and user..."
    step_remove_postgresql

    print_step "Removing Nginx configuration..."
    step_remove_nginx

    print_step "Removing Nginx static cache..."
    step_remove_nginx_cache

    print_step "Removing manifest JSON files..."
    step_remove_manifests

    print_step "Cleaning up shared Nginx config..."
    step_cleanup_shared_nginx_conf

    # ── Finalize ────────────────────────────────────────────────────────────
    echo "" >> "$TEMP_REPORT"
    if $DRY_RUN; then
        echo "Result: DRY RUN complete — no changes were made." >> "$TEMP_REPORT"
    else
        echo "Result: Instance deleted successfully." >> "$TEMP_REPORT"
        # Append to master log
        echo "$(date '+%Y-%m-%d %H:%M:%S')  DELETED instance='$OE_USER'  dry_run=false  backup=$BACKUP" \
            >> "$LOG_FILE"
    fi

    # ── Final Report ────────────────────────────────────────────────────────
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
    if $DRY_RUN; then
        echo -e "${BLUE}║             🔍  DRY RUN COMPLETE — No changes made              ║${NC}"
    else
        echo -e "${BLUE}║                    ✅  Deletion Complete                         ║${NC}"
    fi
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    cat "$TEMP_REPORT"
    echo ""

    if ! $DRY_RUN; then
        print_info "Instance '$OE_USER' has been completely and permanently deleted."
        print_info "Deletion log: $LOG_FILE"
    else
        print_info "Simulation complete. No changes were made to the system."
    fi

    rm -f "$TEMP_REPORT"
}

main "$@"
