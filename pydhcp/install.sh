#!/bin/bash
# maravento.com
#
################################################################################
#
# Installer / Uninstaller for pydhcpd
# Deploys all files to their correct system paths
# or removes them cleanly from the system.
#
# Usage:
#   sudo bash install.sh           # install
#   sudo bash install.sh --remove  # uninstall
#
################################################################################

set -euo pipefail

INSTALL_DIR="/etc/pydhcp"
SERVICE_FILE="/etc/systemd/system/pydhcpd.service"
INIT_FILE="/etc/init.d/pydhcpd"
SYSTEM_USER="pydhcpd"
LOG_FILE="/var/log/pydhcpd.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ─── Root check ─────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root (use sudo)"
fi

# ─── Source directory (where this script lives) ──────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── UNINSTALL ───────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--remove" ]]; then
    info "Stopping and disabling pydhcpd service..."
    systemctl stop pydhcpd 2>/dev/null || true
    systemctl disable pydhcpd 2>/dev/null || true

    info "Removing system files..."
    rm -f "$SERVICE_FILE"
    rm -f "$INIT_FILE"
    rm -f "$LOG_FILE"

    info "Removing $INSTALL_DIR ..."
    [[ "$INSTALL_DIR" == "/etc/pydhcp" ]] || error "Unexpected install dir: $INSTALL_DIR"
    rm -rf "$INSTALL_DIR"

    info "Removing system user and group $SYSTEM_USER ..."
    userdel "$SYSTEM_USER" 2>/dev/null || warn "User $SYSTEM_USER not found or already removed"
    groupdel "$SYSTEM_USER" 2>/dev/null || true

    systemctl daemon-reload

    success "pydhcpd has been removed from the system."
    exit 0
fi

# ─── INSTALL ─────────────────────────────────────────────────────────────────

# Detect and select network interface
echo ""
info "Available network interfaces:"
mapfile -t IFACES < <(ip -br link show | awk '$1 != "lo" {print $1}')
if [[ ${#IFACES[@]} -eq 0 ]]; then
    error "No network interfaces found"
fi
for i in "${!IFACES[@]}"; do
    STATE=$(ip -br link show "${IFACES[$i]}" | awk '{print $2}')
    printf "  [%d] %s (%s)\n" "$((i+1))" "${IFACES[$i]}" "$STATE"
done
echo ""
while true; do
    read -rp "  Select interface number [1-${#IFACES[@]}]: " SEL
    if [[ "$SEL" =~ ^[0-9]+$ ]] && (( SEL >= 1 && SEL <= ${#IFACES[@]} )); then
        IFACE="${IFACES[$((SEL-1))]}"
        break
    fi
    warn "Invalid selection, try again"
done
info "Using interface: $IFACE"

# DHCP server IP
echo ""
while true; do
    read -rp "  Enter DHCP server IP address (e.g. 192.168.0.1): " SERVER_IP
    SERVER_IP=$(echo "$SERVER_IP" | xargs)
    if [[ "$SERVER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        break
    fi
    warn "Invalid IP address, try again"
done
info "Server IP: $SERVER_IP"

# Network base
echo ""
read -rp "  Enter network base (default: 192.168.0): " NET_BASE
NET_BASE=$(echo "$NET_BASE" | xargs)
[[ -z "$NET_BASE" ]] && NET_BASE="192.168.0"
info "Network base: $NET_BASE"

# Pool range
echo ""
while true; do
    read -rp "  Enter pool start (last octet, default: 220): " POOL_START
    POOL_START=$(echo "$POOL_START" | xargs)
    [[ -z "$POOL_START" ]] && POOL_START="220"
    if [[ "$POOL_START" =~ ^[0-9]+$ ]] && (( POOL_START >= 1 && POOL_START <= 254 )); then
        break
    fi
    warn "Invalid value, enter a number between 1 and 254"
done
while true; do
    read -rp "  Enter pool end   (last octet, default: 235): " POOL_END
    POOL_END=$(echo "$POOL_END" | xargs)
    [[ -z "$POOL_END" ]] && POOL_END="235"
    if [[ "$POOL_END" =~ ^[0-9]+$ ]] && (( POOL_END > POOL_START && POOL_END <= 254 )); then
        break
    fi
    warn "Pool end must be greater than pool start ($POOL_START) and <= 254"
done
info "Pool range: ${NET_BASE}.${POOL_START} → ${NET_BASE}.${POOL_END}"

# Verify source files exist
for f in pydhcpd.py pydhcpd.conf pydhcpd.defaults pydhcpd.service pydhcpd.init; do
    [ -f "$SCRIPT_DIR/$f" ] || error "Missing source file: $f (run from the project directory)"
done

# Create system group and user
if ! getent group "$SYSTEM_USER" &>/dev/null; then
    info "Creating system group: $SYSTEM_USER"
    groupadd --system "$SYSTEM_USER"
else
    warn "Group $SYSTEM_USER already exists, skipping"
fi

if ! id "$SYSTEM_USER" &>/dev/null; then
    info "Creating system user: $SYSTEM_USER"
    useradd --system --no-create-home --shell /bin/false --gid "$SYSTEM_USER" --comment "Python DHCP Daemon" "$SYSTEM_USER"
else
    warn "User $SYSTEM_USER already exists, skipping"
fi

# Create install directory
info "Creating $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
chown root:"$SYSTEM_USER" "$INSTALL_DIR"
chmod 750 "$INSTALL_DIR"

# Deploy daemon and config files
info "Deploying pydhcpd.py ..."
cp "$SCRIPT_DIR/pydhcpd.py" "$INSTALL_DIR/pydhcpd.py"
chown root:root "$INSTALL_DIR/pydhcpd.py"
chmod 755 "$INSTALL_DIR/pydhcpd.py"

for f in pydhcpd.conf pydhcpd.defaults; do
    if [ -f "$INSTALL_DIR/$f" ]; then
        warn "$f already exists in $INSTALL_DIR — skipping (not overwritten)"
    else
        info "Deploying $f ..."
        cp "$SCRIPT_DIR/$f" "$INSTALL_DIR/$f"
    fi
    chown root:"$SYSTEM_USER" "$INSTALL_DIR/$f"
    chmod 640 "$INSTALL_DIR/$f"
done

# Apply detected interface to defaults file
sed -i "s/^INTERFACESv4=.*/INTERFACESv4=\"$IFACE\"/" "$INSTALL_DIR/pydhcpd.defaults"
info "Interface set in pydhcpd.defaults: $IFACE"

# Apply network parameters to pydhcpd.conf
NETMASK="255.255.255.0"
BROADCAST="${NET_BASE}.255"
SUBNET="${NET_BASE}.0"

sed -i "s/^server-identifier .*/server-identifier ${SERVER_IP};/" "$INSTALL_DIR/pydhcpd.conf"
sed -i "s|subnet [0-9.]* netmask|subnet ${SUBNET} netmask|" "$INSTALL_DIR/pydhcpd.conf"
sed -i "s|option routers .*;|option routers ${SERVER_IP};|" "$INSTALL_DIR/pydhcpd.conf"
sed -i "s|option subnet-mask .*;|option subnet-mask ${NETMASK};|" "$INSTALL_DIR/pydhcpd.conf"
sed -i "s|option broadcast-address .*;|option broadcast-address ${BROADCAST};|" "$INSTALL_DIR/pydhcpd.conf"
sed -i "s|range [0-9.]* [0-9.]*;|range ${NET_BASE}.${POOL_START} ${NET_BASE}.${POOL_END};|" "$INSTALL_DIR/pydhcpd.conf"
sed -i "s|SERVER_IP|${SERVER_IP}|g" "$INSTALL_DIR/pydhcpd.conf"
info "Network parameters set in pydhcpd.conf"

# Initialize empty leases file if not present
if [ ! -f "$INSTALL_DIR/pydhcpd.leases" ]; then
    info "Creating empty pydhcpd.leases ..."
    touch "$INSTALL_DIR/pydhcpd.leases"
    chown "$SYSTEM_USER":"$SYSTEM_USER" "$INSTALL_DIR/pydhcpd.leases"
    chmod 640 "$INSTALL_DIR/pydhcpd.leases"
fi

# Deploy systemd service
info "Deploying systemd unit ..."
cp "$SCRIPT_DIR/pydhcpd.service" "$SERVICE_FILE"
chown root:root "$SERVICE_FILE"
chmod 644 "$SERVICE_FILE"

# Deploy init.d wrapper
info "Deploying init.d wrapper ..."
cp "$SCRIPT_DIR/pydhcpd.init" "$INIT_FILE"
chown root:root "$INIT_FILE"
chmod 755 "$INIT_FILE"

# Create log file only if it does not exist
if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
    chown "$SYSTEM_USER":"$SYSTEM_USER" "$LOG_FILE"
    chmod 640 "$LOG_FILE"
fi

# Enable and start service
info "Enabling and starting pydhcpd ..."
systemctl daemon-reload
systemctl enable --force pydhcpd
if ! systemctl start pydhcpd; then
    error "pydhcpd failed to start. Check logs with: journalctl -u pydhcpd -n 50"
fi

echo ""
success "pydhcpd installed and running."
echo ""
info "Configuration : $INSTALL_DIR/pydhcpd.conf"
info "Interface     : $(grep INTERFACESv4 "$INSTALL_DIR/pydhcpd.defaults" | cut -d= -f2 | tr -d '"')"
info "Leases        : $INSTALL_DIR/pydhcpd.leases"
info "Logs          : journalctl -u pydhcpd -f"
echo ""
info "To remove     : sudo bash install.sh --remove"
