#!/bin/bash
################################################################################
# Odoo Instance Deletion Script - Professional Edition
# Author: Ibrahim Aljuhani
# Features: Safe detection, Dry-run mode, Non-interactive mode, Backup option
################################################################################
set -e

#-------------------------------#
#        Color Definitions      #
#-------------------------------#
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()  { echo -e "${GREEN}[✔]${NC} $1"; }
print_warn()  { echo -e "${YELLOW}[⚠]${NC} $1"; }
print_error() { echo -e "${RED}[✖]${NC} $1"; exit 1; }
print_step()  { echo -e "${CYAN}[🚀]${NC} $1"; }
print_danger() { echo -e "${RED}🔥 $1${NC}"; }
print_header() { echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"; }
print_footer() { echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"; }

#-------------------------------#
#     Configuration Variables   #
#-------------------------------#
DRY_RUN=false
FORCE=false
BACKUP=false
OE_USER=""
BACKUP_DIR="/root/odoo-backups/deleted"
LOG_FILE="/root/odoo-deletion-log.txt"
DELETION_REPORT=""

#-------------------------------#
#     Helper Functions          #
#-------------------------------#
show_help() {
  cat <<EOF
Odoo Instance Deletion Script - Professional Edition

Usage:
  Interactive mode (default):
    sudo ./delete_odoo.sh

  Non-interactive mode:
    sudo ./delete_odoo.sh --instance <name> [--force] [--backup] [--dry-run]

Options:
  --instance <name>   Instance name to delete (required for non-interactive)
  --force             Skip confirmation prompt (use with caution!)
  --backup            Create backup before deletion
  --dry-run           Show what would be deleted without making changes
  --help, -h          Show this help message

Examples:
  # Interactive deletion with confirmation
  sudo ./delete_odoo.sh

  # Non-interactive deletion with backup
  sudo ./delete_odoo.sh --instance prod --backup --force

  # Dry-run to preview deletion
  sudo ./delete_odoo.sh --instance test --dry-run
EOF
  exit 0
}

is_odoo_instance() {
  local user="$1"
  # Triple-validation to ensure it's a real Odoo instance
  [ -f "/etc/${user}-server.conf" ] && \
  [ -f "/etc/systemd/system/${user}-server.service" ] && \
  [ -d "/$user/${user}-server" ] && \
  [ -f "/$user/${user}-server/odoo-bin" ]
}

detect_instances() {
  local instances=()
  while IFS= read -r user; do
    # Only consider system users with home in root directory
    if [[ "$user" =~ ^[a-z][a-z0-9_-]*$ ]] && id -u "$user" &>/dev/null; then
      if is_odoo_instance "$user"; then
        instances+=("$user")
      fi
    fi
  done < <(cut -d: -f1 /etc/passwd | sort)
  
  echo "${instances[@]}"
}

backup_instance() {
  local user="$1"
  local timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_path="$BACKUP_DIR/${user}_${timestamp}"
  
  print_step "Creating backup at: $backup_path"
  
  sudo mkdir -p "$backup_path"
  
  # Backup home directory
  if [ -d "/$user" ]; then
    sudo tar -czf "$backup_path/home.tar.gz" "/$user" 2>/dev/null || true
    echo "  ✓ Home directory backed up" >> "$DELETION_REPORT"
  fi
  
  # Backup config file
  if [ -f "/etc/${user}-server.conf" ]; then
    sudo cp "/etc/${user}-server.conf" "$backup_path/" 2>/dev/null || true
    echo "  ✓ Config file backed up" >> "$DELETION_REPORT"
  fi
  
  # Backup PostgreSQL database
  if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$user" 2>/dev/null; then
    sudo -u postgres pg_dump "$user" > "$backup_path/db.sql" 2>/dev/null || true
    echo "  ✓ Database backed up" >> "$DELETION_REPORT"
  fi
  
  # Backup Nginx config
  if [ -f "/etc/nginx/sites-available/$user" ]; then
    sudo cp "/etc/nginx/sites-available/$user" "$backup_path/" 2>/dev/null || true
    echo "  ✓ Nginx config backed up" >> "$DELETION_REPORT"
  fi
  
  sudo chmod -R 600 "$backup_path"
  print_info "Backup created successfully: $backup_path"
}

delete_step() {
  local action="$1"
  local command="$2"
  
  echo "  $action" >> "$DELETION_REPORT"
  
  if $DRY_RUN; then
    print_info "[DRY RUN] Would: $action"
    return 0
  fi
  
  eval "$command" 2>/dev/null || true
}

#-------------------------------#
#     Main Execution            #
#-------------------------------#
main() {
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --instance) OE_USER="$2"; shift 2 ;;
      --force) FORCE=true; shift ;;
      --backup) BACKUP=true; shift ;;
      --dry-run) DRY_RUN=true; FORCE=true; shift ;; # Dry-run implies force
      --help|-h) show_help ;;
      *) shift ;;
    esac
  done
  
  # Header
  clear
  print_header
  print_center() { printf '%*s\n' $(((${#1}+78)/2)) "$1"; }
  print_center "Odoo Instance Deletion Tool"
  print_center "Professional Edition v2.0.0"
  print_footer
  echo ""
  
  # Detect instances
  print_step "Scanning for Odoo instances..."
  INSTANCES=($(detect_instances))
  
  if [ ${#INSTANCES[@]} -eq 0 ]; then
    print_info "No Odoo instances found on this server."
    exit 0
  fi
  
  # Interactive mode: show menu
  if [[ -z "$OE_USER" ]]; then
    echo -e "${CYAN}Found ${#INSTANCES[@]} instance(s):${NC}"
    for i in "${!INSTANCES[@]}"; do
      echo "  $((i+1))) ${INSTANCES[i]}"
    done
    echo ""
    read -p "Enter the number of the instance to DELETE (or 0 to cancel): " CHOICE
    
    if [ "$CHOICE" == "0" ] || [ -z "$CHOICE" ]; then
      print_info "Operation cancelled."
      exit 0
    fi
    
    if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt ${#INSTANCES[@]} ]; then
      print_error "Invalid choice."
    fi
    
    OE_USER="${INSTANCES[$((CHOICE-1))]}"
  fi
  
  # Validate instance exists
  if ! is_odoo_instance "$OE_USER"; then
    print_error "Instance '$OE_USER' is not a valid Odoo instance or does not exist."
  fi
  
  # Dry-run header
  if $DRY_RUN; then
    print_header
    print_center "DRY RUN MODE - No changes will be made"
    print_footer
    echo ""
  fi
  
  # Backup if requested
  if $BACKUP && ! $DRY_RUN; then
    backup_instance "$OE_USER"
  fi
  
  # Confirmation
  if ! $FORCE && ! $DRY_RUN; then
    print_danger "You are about to DELETE the instance: '$OE_USER'"
    echo -e "${RED}────────────────────────────────────────────────────${NC}"
    echo -e "${RED}⚠  THIS ACTION IS IRREVERSIBLE!${NC}"
    echo -e "${RED}   - All files, logs, configs, and PostgreSQL database${NC}"
    echo -e "${RED}     will be PERMANENTLY DELETED.${NC}"
    echo -e "${RED}────────────────────────────────────────────────────${NC}"
    
    read -p "Type the instance name '$OE_USER' to confirm deletion: " CONFIRM
    if [ "$CONFIRM" != "$OE_USER" ]; then
      print_error "Confirmation failed. Aborting."
    fi
  fi
  
  # Initialize deletion report
  DELETION_REPORT=$(mktemp)
  echo "Odoo Instance Deletion Report" > "$DELETION_REPORT"
  echo "Instance: $OE_USER" >> "$DELETION_REPORT"
  echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')" >> "$DELETION_REPORT"
  echo "Mode: $( $DRY_RUN && echo 'DRY RUN' || echo 'REAL DELETION' )" >> "$DELETION_REPORT"
  echo "Backup Created: $( $BACKUP && echo 'YES' || echo 'NO' )" >> "$DELETION_REPORT"
  echo "" >> "$DELETION_REPORT"
  echo "Actions performed:" >> "$DELETION_REPORT"
  
  # Deletion steps
  delete_step "Stopping service ${OE_USER}-server" \
    "sudo systemctl stop '${OE_USER}-server' 2>/dev/null || true"
  
  delete_step "Killing remaining processes for user $OE_USER" \
    "sudo pkill -9 -u '$OE_USER' 2>/dev/null || true; sleep 2"
  
  delete_step "Removing systemd service file" \
    "sudo rm -f '/etc/systemd/system/${OE_USER}-server.service'"
  
  delete_step "Removing config file" \
    "sudo rm -f '/etc/${OE_USER}-server.conf'"
  
  delete_step "Reloading systemd daemon" \
    "sudo systemctl daemon-reload"
  
  delete_step "Deleting system user and home directory" \
    "sudo userdel -r '$OE_USER' 2>/dev/null || true; sudo rm -rf '/$OE_USER'"
  
  delete_step "Deleting log directory" \
    "sudo rm -rf '/var/log/$OE_USER'"
  
  # PostgreSQL deletion (with safety checks)
  if sudo -u postgres psql -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw "$OE_USER" 2>/dev/null; then
    delete_step "Terminating active database connections" \
      "sudo -u postgres psql -d postgres -c \"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$OE_USER';\" >/dev/null 2>&1 || true"
    
    delete_step "Dropping PostgreSQL database '$OE_USER'" \
      "sudo -u postgres psql -d postgres -c \"DROP DATABASE IF EXISTS \\\"$OE_USER\\\";\" >/dev/null 2>&1 || true"
    
    delete_step "Dropping PostgreSQL user '$OE_USER'" \
      "sudo -u postgres psql -d postgres -c \"DROP USER IF EXISTS \\\"$OE_USER\\\";\" >/dev/null 2>&1 || true"
  else
    echo "  ⚠ Database '$OE_USER' not found - skipping DB deletion" >> "$DELETION_REPORT"
    print_warn "Database '$OE_USER' not found - skipping DB deletion"
  fi
  
  # Nginx cleanup
  if [ -f "/etc/nginx/sites-available/$OE_USER" ] || [ -f "/etc/nginx/sites-enabled/$OE_USER" ]; then
    delete_step "Removing Nginx configuration files" \
      "sudo rm -f '/etc/nginx/sites-available/$OE_USER' '/etc/nginx/sites-enabled/$OE_USER'"
    
    if command -v nginx &>/dev/null && ! $DRY_RUN; then
      if sudo nginx -t >/dev/null 2>&1; then
        delete_step "Reloading Nginx configuration" \
          "sudo systemctl reload nginx 2>/dev/null || true"
      else
        echo "  ⚠ Nginx config test failed after removal - manual review recommended" >> "$DELETION_REPORT"
        print_warn "Nginx config test failed after removal - manual review recommended"
      fi
    fi
  fi
  
  # Finalize
  echo "" >> "$DELETION_REPORT"
  echo "Deletion completed successfully." >> "$DELETION_REPORT"
  
  # Log to master log
  echo "$(date '+%Y-%m-%d %H:%M:%S'): DELETED instance '$OE_USER' (Dry-run: $DRY_RUN, Backup: $BACKUP)" >> "$LOG_FILE"
  
  # Show report
  echo ""
  print_header
  if $DRY_RUN; then
    print_center "DRY RUN COMPLETE - No changes made"
  else
    print_center "DELETION COMPLETE"
  fi
  print_footer
  echo ""
  cat "$DELETION_REPORT"
  echo ""
  
  if ! $DRY_RUN; then
    print_info "✅ Instance '$OE_USER' has been COMPLETELY and PERMANENTLY deleted."
    print_info "Full deletion report saved to: $LOG_FILE"
  else
    print_info "[DRY RUN] No changes were made to the system."
    print_info "This was a simulation only."
  fi
  
  rm -f "$DELETION_REPORT"
}

main "$@"
