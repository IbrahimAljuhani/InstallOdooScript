#!/bin/bash
################################################################################
# Odoo Instance Deletion Script (Full Cleanup)
# Author: Ibrahim Aljuhani
# Deletes: system user, home dir, config, service, logs, and PostgreSQL DB
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

print_info()  { echo -e "${GREEN}[✔]${NC} $1"; }
print_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✖]${NC} $1"; exit 1; }
print_step()  { echo -e "${CYAN}==> $1${NC}"; }
print_danger() { echo -e "${RED}🔥 $1${NC}"; }

#-------------------------------#
#     Detect Existing Instances #
#-------------------------------#
detect_instances() {
  local instances=()
  while IFS= read -r user; do
    # Check if it's an Odoo-like user (home in root dir, e.g., /odoo-prod)
    if [[ "$user" =~ ^[a-z][a-z0-9_-]*$ ]] && [ -d "/$user" ]; then
      if id "$user" &>/dev/null && systemctl list-unit-files --type=service | grep -q "^${user}-server\\.service"; then
        instances+=("$user")
      fi
    fi
  done < <(cut -d: -f1 /etc/passwd)

  echo "${instances[@]}"
}

#-------------------------------#
#     Main Script               #
#-------------------------------#
print_step "Scanning for existing Odoo instances..."

INSTANCES=($(detect_instances))

if [ ${#INSTANCES[@]} -eq 0 ]; then
  print_info "No Odoo instances found on this server."
  exit 0
fi

echo -e "${CYAN}Found ${#INSTANCES[@]} instance(s):${NC}"
for i in "${!INSTANCES[@]}"; do
  echo "  $((i+1))) ${INSTANCES[i]}"
done

echo
read -p "Enter the number of the instance to DELETE (or 0 to cancel): " CHOICE

if [ "$CHOICE" == "0" ] || [ -z "$CHOICE" ]; then
  print_info "Operation cancelled."
  exit 0
fi

if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt ${#INSTANCES[@]} ]; then
  print_error "Invalid choice."
fi

OE_USER="${INSTANCES[$((CHOICE-1))]}"
print_danger "You are about to DELETE the instance: '$OE_USER'"
echo -e "${RED}────────────────────────────────────────────────────${NC}"
echo -e "${RED}⚠  THIS ACTION IS IRREVERSIBLE!${NC}"
echo -e "${RED}   - All files, logs, configs, and PostgreSQL database will be PERMANENTLY DELETED.${NC}"
echo -e "${RED}────────────────────────────────────────────────────${NC}"

read -p "Type the instance name '$OE_USER' to confirm deletion: " CONFIRM
if [ "$CONFIRM" != "$OE_USER" ]; then
  print_error "Confirmation failed. Aborting."
fi

#-------------------------------#
#     Perform Full Deletion     #
#-------------------------------#
print_step "Stopping and disabling service..."
sudo systemctl stop "${OE_USER}-server" 2>/dev/null || true
sudo systemctl disable --quiet "${OE_USER}-server" 2>/dev/null || true

print_step "Killing any remaining processes..."
sudo pkill -9 -u "$OE_USER" 2>/dev/null || true
sleep 2

print_step "Removing systemd service and config..."
sudo rm -f "/etc/systemd/system/${OE_USER}-server.service"
sudo rm -f "/etc/${OE_USER}-server.conf"
sudo systemctl daemon-reload

print_step "Deleting system user and home directory..."
sudo userdel -r "$OE_USER" 2>/dev/null || true
sudo rm -rf "/$OE_USER"

print_step "Deleting log directory..."
sudo rm -rf "/var/log/$OE_USER"

print_step "Dropping PostgreSQL database and user..."
sudo -u postgres psql -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$OE_USER';" >/dev/null 2>&1 || true
sudo -u postgres psql -d postgres -c "DROP DATABASE IF EXISTS \"$OE_USER\";" >/dev/null 2>&1 || true
sudo -u postgres psql -d postgres -c "DROP USER IF EXISTS \"$OE_USER\";" >/dev/null 2>&1 || true

print_step "Removing Nginx site (if exists)..."
sudo rm -f "/etc/nginx/sites-available/$OE_USER"
sudo rm -f "/etc/nginx/sites-enabled/$OE_USER"
if command -v nginx &>/dev/null; then
  sudo nginx -t >/dev/null 2>&1 && sudo systemctl reload nginx 2>/dev/null || true
fi

# Optional: Log deletion
echo "$(date '+%Y-%m-%d %H:%M:%S'): FULL DELETION of Odoo instance '$OE_USER'" >> /root/odoo-deletion-log.txt

print_info "✅ Instance '$OE_USER' has been COMPLETELY and PERMANENTLY deleted."