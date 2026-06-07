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
#   sudo bash pyinstall.sh           # install
#   sudo bash pyinstall.sh --update  # update code only (preserves user config, backs up replaced files to /etc/pydhcp.bak/)
#   sudo bash pyinstall.sh --remove  # uninstall
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
    rm -f /etc/logrotate.d/pydhcpd

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

# ─── UPDATE ──────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--update" ]]; then
    if [ ! -d "$INSTALL_DIR" ]; then
        error "No existing installation found in $INSTALL_DIR. Run without --update to install first."
    fi

    BACKUP_DIR="/etc/pydhcp.bak/$(date +%Y%m%d_%H%M%S)"
    info "Creating backup in $BACKUP_DIR ..."
    mkdir -p "$BACKUP_DIR/tools" "$BACKUP_DIR/init.d"
    for f in pydhcpd.py tools/pyleases.sh tools/pywebmin.sh; do
        [ -f "$INSTALL_DIR/$f" ] && cp "$INSTALL_DIR/$f" "$BACKUP_DIR/$f"
    done
    [ -f "$SERVICE_FILE" ]                   && cp "$SERVICE_FILE"                   "$BACKUP_DIR/pydhcpd.service"
    [ -f "$INIT_FILE" ]                      && cp "$INIT_FILE"                      "$BACKUP_DIR/init.d/pydhcpd"

    info "Stopping pydhcpd service..."
    systemctl stop pydhcpd 2>/dev/null || true

    info "Updating pydhcpd.py ..."
    cp "$SCRIPT_DIR/pydhcpd.py" "$INSTALL_DIR/pydhcpd.py"
    chown root:root "$INSTALL_DIR/pydhcpd.py"
    chmod 755 "$INSTALL_DIR/pydhcpd.py"

    info "Updating systemd unit ..."
    cp "$SCRIPT_DIR/pydhcpd.service" "$SERVICE_FILE"
    chown root:root "$SERVICE_FILE"
    chmod 644 "$SERVICE_FILE"

    info "Updating init.d wrapper ..."
    cp "$SCRIPT_DIR/init.d/pydhcpd" "$INIT_FILE"
    chown root:root "$INIT_FILE"
    chmod 755 "$INIT_FILE"

    if [ -f "$SCRIPT_DIR/tools/pyleases.sh" ]; then
        info "Updating tools/pyleases.sh ..."
        cp "$SCRIPT_DIR/tools/pyleases.sh" "$INSTALL_DIR/tools/pyleases.sh"
        chown root:root "$INSTALL_DIR/tools/pyleases.sh"
        chmod 755 "$INSTALL_DIR/tools/pyleases.sh"
    fi

    if [ -f "$SCRIPT_DIR/tools/pywebmin.sh" ]; then
        info "Updating tools/pywebmin.sh ..."
        cp "$SCRIPT_DIR/tools/pywebmin.sh" "$INSTALL_DIR/tools/pywebmin.sh"
        chown root:root "$INSTALL_DIR/tools/pywebmin.sh"
        chmod 755 "$INSTALL_DIR/tools/pywebmin.sh"
    fi

    systemctl daemon-reload
    if ! systemctl start pydhcpd; then
        error "pydhcpd failed to start after update. Check logs with: journalctl -u pydhcpd -n 50"
    fi

    echo ""
    success "pydhcpd updated. Backup saved in $BACKUP_DIR"
    info "  $INSTALL_DIR/pydhcpd.conf    — unchanged"
    info "  $INSTALL_DIR/default/pydhcpd  — unchanged"
    info "  $INSTALL_DIR/pydhcpd.leases  — unchanged"
    info "  $INSTALL_DIR/pydhcpd.env     — unchanged"
    echo ""
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
    read -rp "  Enter DHCP server IP address (e.g. 192.168.0.10): " SERVER_IP
    SERVER_IP=$(echo "$SERVER_IP" | xargs)
    if [[ "$SERVER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        break
    fi
    warn "Invalid IP address, try again"
done
info "Server IP: $SERVER_IP"

# Netmask
echo ""
while true; do
    read -rp "  Enter netmask [255.255.255.0]: " NETMASK
    NETMASK=$(echo "$NETMASK" | xargs)
    [[ -z "$NETMASK" ]] && NETMASK="255.255.255.0"
    if [[ "$NETMASK" =~ ^(255|254|252|248|240|224|192|128|0)(\.(255|254|252|248|240|224|192|128|0)){3}$ ]]; then
        break
    fi
    warn "Invalid netmask, try again"
done
info "Netmask: $NETMASK"

# Calculate network values from SERVER_IP and NETMASK
NET_BASE=$(echo "$SERVER_IP" | cut -d. -f1-3)
SUBNET="${NET_BASE}.0"
BROADCAST=$(python3 -c "
import ipaddress
net = ipaddress.IPv4Network('$SERVER_IP/$NETMASK', strict=False)
print(net.broadcast_address)
")
info "Network base: $NET_BASE"
info "Subnet: $SUBNET"
info "Broadcast: $BROADCAST"

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
for f in pydhcpd.py pydhcpd.conf pydhcpd.service init.d/pydhcpd; do
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
# 770 (not 750) so the unprivileged pydhcpd group can create the .tmp file
# used by the atomic write of pydhcpd.leases after systemd drops privileges.
chmod 770 "$INSTALL_DIR"

# Deploy daemon and config files
info "Deploying pydhcpd.py ..."
cp "$SCRIPT_DIR/pydhcpd.py" "$INSTALL_DIR/pydhcpd.py"
chown root:root "$INSTALL_DIR/pydhcpd.py"
chmod 755 "$INSTALL_DIR/pydhcpd.py"

# Deploy pydhcpd.conf (preserved on update — never overwritten)
if [ -f "$INSTALL_DIR/pydhcpd.conf" ]; then
    warn "pydhcpd.conf already exists in $INSTALL_DIR — skipping (not overwritten)"
else
    info "Deploying pydhcpd.conf ..."
    cp "$SCRIPT_DIR/pydhcpd.conf" "$INSTALL_DIR/pydhcpd.conf"
fi
chown root:"$SYSTEM_USER" "$INSTALL_DIR/pydhcpd.conf"
chmod 640 "$INSTALL_DIR/pydhcpd.conf"

# Create default/pydhcpd (preserved on update — never overwritten)
mkdir -p "$INSTALL_DIR/default"
chown root:"$SYSTEM_USER" "$INSTALL_DIR/default"
chmod 750 "$INSTALL_DIR/default"

if [ -f "$INSTALL_DIR/default/pydhcpd" ]; then
    warn "default/pydhcpd already exists in $INSTALL_DIR — skipping (not overwritten)"
else
    info "Creating default/pydhcpd ..."
    cat > "$INSTALL_DIR/default/pydhcpd" <<DEFEOF
# /etc/pydhcp/default/pydhcpd
# Configuration defaults for pydhcpd
# Generated by pyinstall.sh on $(date)
# Read by pydhcpd.py at startup and by /etc/init.d/pydhcpd

# Path to pydhcpd config file
# Used by pydhcpd.py to locate pydhcpd.conf at startup
DHCPDv4_CONF=/etc/pydhcp/pydhcpd.conf

# Path to pydhcpd PID file
# Used by pydhcpd.py to write its PID and by init.d to stop the daemon
DHCPDv4_PID=/etc/pydhcp/pydhcpd.pid

# Network interface to listen on (IPv4 only, single interface)
INTERFACESv4="$IFACE"

# System user and group under which pydhcpd runs.
# Created automatically by pyinstall.sh — change only if you renamed them.
DAEMON_USER="pydhcpd"
DAEMON_GROUP="pydhcpd"
DEFEOF
fi
chown root:"$SYSTEM_USER" "$INSTALL_DIR/default/pydhcpd"
chmod 640 "$INSTALL_DIR/default/pydhcpd"
info "Interface set in default/pydhcpd: $IFACE"

# Apply network parameters to pydhcpd.conf
sed -i "s/^server-identifier .*/server-identifier ${SERVER_IP};/" "$INSTALL_DIR/pydhcpd.conf"
sed -i "s|subnet [0-9.]* netmask|subnet ${SUBNET} netmask|" "$INSTALL_DIR/pydhcpd.conf"
sed -i "s|option routers .*;|option routers ${SERVER_IP};|" "$INSTALL_DIR/pydhcpd.conf"
sed -i "s|option subnet-mask .*;|option subnet-mask ${NETMASK};|" "$INSTALL_DIR/pydhcpd.conf"
sed -i "s|option broadcast-address .*;|option broadcast-address ${BROADCAST};|" "$INSTALL_DIR/pydhcpd.conf"
sed -i "s|range [0-9.]* [0-9.]*;|range ${NET_BASE}.${POOL_START} ${NET_BASE}.${POOL_END};|" "$INSTALL_DIR/pydhcpd.conf"
sed -i "s|SERVER_IP|${SERVER_IP}|g" "$INSTALL_DIR/pydhcpd.conf"
info "Network parameters set in pydhcpd.conf"

# Re-apply permissions after sed edits
chown root:"$SYSTEM_USER" "$INSTALL_DIR/pydhcpd.conf"
chmod 640 "$INSTALL_DIR/pydhcpd.conf"

# Create pydhcpd.env
info "Creating pydhcpd.env ..."
cat > "$INSTALL_DIR/pydhcpd.env" <<EOF
# pydhcpd environment configuration
# Generated by install.sh on $(date)
# Do not edit manually unless you know what you are doing.

# Network
IFACE=$IFACE
SERVER_IP=$SERVER_IP
NETMASK=$NETMASK
NET_BASE=$NET_BASE
SUBNET=$SUBNET
BROADCAST=$BROADCAST
POOL_START=${NET_BASE}.${POOL_START}
POOL_END=${NET_BASE}.${POOL_END}

# Paths
INSTALL_DIR=$INSTALL_DIR
LOG_FILE=$LOG_FILE
EOF
chown root:"$SYSTEM_USER" "$INSTALL_DIR/pydhcpd.env"
chmod 640 "$INSTALL_DIR/pydhcpd.env"
info "pydhcpd.env created"

# Initialize empty leases file if not present
if [ ! -f "$INSTALL_DIR/pydhcpd.leases" ]; then
    info "Creating empty pydhcpd.leases ..."
    touch "$INSTALL_DIR/pydhcpd.leases"
    chown "$SYSTEM_USER":"$SYSTEM_USER" "$INSTALL_DIR/pydhcpd.leases"
    chmod 640 "$INSTALL_DIR/pydhcpd.leases"
fi

# Pre-create pid file with correct permissions
touch "$INSTALL_DIR/pydhcpd.pid"
chown "$SYSTEM_USER":"$SYSTEM_USER" "$INSTALL_DIR/pydhcpd.pid"
chmod 640 "$INSTALL_DIR/pydhcpd.pid"

# Deploy tools
info "Creating $INSTALL_DIR/tools ..."
mkdir -p "$INSTALL_DIR/tools"
chown root:root "$INSTALL_DIR/tools"
chmod 755 "$INSTALL_DIR/tools"

for tool in pyleases.sh pywebmin.sh; do
    if [ -f "$SCRIPT_DIR/tools/$tool" ]; then
        info "Deploying tools/$tool ..."
        cp "$SCRIPT_DIR/tools/$tool" "$INSTALL_DIR/tools/$tool"
        chown root:root "$INSTALL_DIR/tools/$tool"
        chmod 755 "$INSTALL_DIR/tools/$tool"
    fi
done

# Deploy systemd service
info "Deploying systemd unit ..."
cp "$SCRIPT_DIR/pydhcpd.service" "$SERVICE_FILE"
chown root:root "$SERVICE_FILE"
chmod 644 "$SERVICE_FILE"

# Deploy init.d wrapper
info "Deploying init.d wrapper ..."
cp "$SCRIPT_DIR/init.d/pydhcpd" "$INIT_FILE"
chown root:root "$INIT_FILE"
chmod 755 "$INIT_FILE"

# Create log file only if it does not exist
if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
    chown "$SYSTEM_USER":"$SYSTEM_USER" "$LOG_FILE"
    chmod 640 "$LOG_FILE"
fi

# Deploy logrotate config
info "Deploying logrotate config ..."
cat > /etc/logrotate.d/pydhcpd << 'EOF'
/var/log/pydhcpd.log {
    su pydhcpd pydhcpd
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 640 pydhcpd pydhcpd
    postrotate
        systemctl reload pydhcpd > /dev/null 2>&1 || true
    endscript
}
EOF
chmod 644 /etc/logrotate.d/pydhcpd

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
info "Interface     : $(grep INTERFACESv4 "$INSTALL_DIR/default/pydhcpd" | cut -d= -f2 | tr -d '"')"
info "Leases        : $INSTALL_DIR/pydhcpd.leases"
info "Logs          : journalctl -u pydhcpd -f"
echo ""
info "To remove     : sudo bash pyinstall.sh --remove"
