#!/bin/bash
# maravento.com
#
################################################################################
#
# Network Bridge Manager Script
# FILE: bridge.sh
#
# DESCRIPTION: Detects the active Ethernet interface and turns it into a
# NetworkManager bridge, so a virtual machine can reach the LAN directly.
# Waits for DHCP on the bridge, and restores the original connection on off.
#
# USAGE:
# COMMAND                       ACTION
# sudo bash bridge.sh --on      Enable bridge
# sudo bash bridge.sh --off     Disable bridge
# sudo bash bridge.sh --status  Show status
# sudo bash bridge.sh --clean   Clean bridge configuration
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# path for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# root check
if [ "$(id -u)" != "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock") || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot open $(basename "$script_lock") -abort" >&2
    exit 1
}
exec 200>"$script_lock"
if ! flock -n 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: script $(basename "$0") is already running -abort" >&2
    exit 1
fi

# check ipv4 interfaces
list_ifaces() {
    ip -br link show 2>/dev/null | awk '$1 != "lo" {sub(/@.*/, "", $1); printf "%s %s\n", $1, ($2 == "UP") ? "UP" : "DOWN"}'
}

list_ipv4_ifaces() {
    local iface state
    while read -r iface state; do
        [ "$state" = UP ] || continue
        if ip -4 -o addr show dev "$iface" scope global 2>/dev/null \
            | awk '$4 != "" {found=1} END {exit !found}'; then
            printf '%s\n' "$iface"
        fi
    done < <(list_ifaces)
}

check_ipv4_interfaces() {
    local max_attempts=24 attempt=1

    while (( attempt <= max_attempts )); do
        if [ -n "$(list_ipv4_ifaces)" ]; then
            return 0
        fi
        if (( attempt == 1 )); then
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: waiting for an interface with IPv4..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no interface with IPv4 -abort" >&2
    exit 1
}

# check internet
check_internet() {
    local max_attempts=24 attempt=1

    while (( attempt <= max_attempts )); do
        if getent hosts www.google.com >/dev/null 2>&1; then
            return 0
        fi
        if (( attempt == 1 )); then
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: waiting for internet..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no internet connection -abort" >&2
    exit 1
}

# dependencies
net_checked=0
for dep in iproute2 bridge-utils util-linux network-manager libc-bin; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep" 2>/dev/null)" != *"ok installed"* ]]; then
        if [ "$net_checked" -eq 0 ]; then
            if ! command -v ip >/dev/null 2>&1; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: installing iproute2"
                apt-get install -y iproute2 >/dev/null 2>&1 || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install iproute2 -abort" >&2; exit 1; }
            fi
            check_ipv4_interfaces
            check_internet
            apt-get update -qq || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot update package lists -abort" >&2; exit 1; }
            net_checked=1
        fi
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: installing $dep"
        if ! apt-get install -y "$dep" >/dev/null 2>&1; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install $dep -abort" >&2
            exit 1
        fi
    fi
done

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

# Declare the configuration values used by this script
BRIDGE_NAME="br0"
BRIDGE_SLAVE="${BRIDGE_NAME}-slave"
INTERFACE=""

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

detect_ethernet_interface() {
    local wifi_interfaces
    wifi_interfaces=$(nmcli -t -f DEVICE,TYPE device status | grep -E ":wifi$" | cut -d: -f1)
    for wifi in $wifi_interfaces; do
        if nmcli -t -f DEVICE,STATE device status | grep -q "^${wifi}:connected"; then
            echo "WiFi interface '$wifi' is active. Please disable WiFi before creating a bridge." >&2
            echo "Run: nmcli radio wifi off" >&2
            return 1
        fi
    done

    local ethernet_interfaces
    ethernet_interfaces=$(nmcli -t -f DEVICE,TYPE device status | grep -E ":ethernet$" | cut -d: -f1)

    for eth in $ethernet_interfaces; do
        if nmcli -t -f DEVICE,STATE device status | grep -q "^${eth}:connected"; then
            if ip addr show "$eth" 2>/dev/null | grep -q "inet "; then
                echo "$eth"
                return 0
            fi
        fi
    done

    echo "No active Ethernet interface found with IP address." >&2
    return 1
}

get_ethernet_interface_for_status() {
    local ethernet_interfaces
    ethernet_interfaces=$(nmcli -t -f DEVICE,TYPE device status | grep -E ":ethernet$" | cut -d: -f1)

    for eth in $ethernet_interfaces; do
        if nmcli -t -f DEVICE,STATE device status | grep -q "^${eth}:connected"; then
            echo "$eth"
            return 0
        fi
    done

    if [ -n "$ethernet_interfaces" ]; then
        echo "$ethernet_interfaces" | head -1
        return 0
    fi

    echo "unknown"
}

get_original_connection_name() {
    # NM default connection names like enp2s0, eth0, ens33.
    local interface="$1"
    [ "$interface" = "unknown" ] && return 1

    while IFS=: read -r conn_name uuid; do
        # Skip bridge-related connections
        [[ "$conn_name" == "$BRIDGE_SLAVE" ]] && continue
        [[ "$conn_name" == *"bridge"* ]] && continue
        [[ "$conn_name" == *"slave"* ]] && continue

        if nmcli connection show "$conn_name" 2>/dev/null \
            | grep -qE "connection\.interface-name:\s*${interface}"; then
            echo "$conn_name"
            return 0
        fi
    done < <(nmcli -g NAME,UUID connection show)

    return 1
}

bridge_exists() {
    ip link show "$BRIDGE_NAME" &>/dev/null || \
    nmcli connection show "$BRIDGE_NAME" &>/dev/null || \
    nmcli connection show "$BRIDGE_SLAVE" &>/dev/null
}

show_restored_status() {
    echo ""
    echo "=== RESTORED STATUS ==="
    local original_conn
    original_conn=$(get_original_connection_name "$INTERFACE")
    if [ -n "$original_conn" ]; then
        echo "Original connection reactivated: $original_conn"
        nmcli connection show "$original_conn" | grep -E "GENERAL.STATE|IP4.ADDRESS" | head -2
    else
        ip addr show "$INTERFACE" 2>/dev/null | grep -E "inet|ether" | head -2 \
            || echo " Interface not available"
    fi
}

show_final_status() {
    echo ""
    echo "=== FINAL STATUS ==="
    if ip link show "$BRIDGE_NAME" 2>/dev/null | grep -q "state UP"; then
        echo "Bridge ${BRIDGE_NAME} activated successfully"
        echo ""
        ip -br addr show "$BRIDGE_NAME"
        echo ""
        if bridge link show dev "$INTERFACE" 2>/dev/null | grep -q "$BRIDGE_NAME"; then
            echo "${INTERFACE} successfully linked to bridge"
        else
            echo "${INTERFACE} NOT linked to bridge"
        fi
        local original_conn
        original_conn=$(get_original_connection_name "$INTERFACE")
        [ -n "$original_conn" ] && echo "Original connection '$original_conn' preserved (inactive)"
    else
        echo "Bridge is not active"
        restore_normal_network
        exit 1
    fi
}

cleanup_all_connections() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Cleaning up all bridge connections..."
    nmcli connection delete "$BRIDGE_SLAVE" 2>/dev/null || true
    nmcli connection delete "$BRIDGE_NAME" 2>/dev/null || true
    ip link set dev "$BRIDGE_NAME" down 2>/dev/null || true
    ip link delete "$BRIDGE_NAME" type bridge 2>/dev/null || true
    if [ -n "$INTERFACE" ] && [ "$INTERFACE" != "unknown" ]; then
        ip addr flush dev "$INTERFACE" 2>/dev/null || true
        ip link set dev "$INTERFACE" up 2>/dev/null || true
    fi
    sleep 2
}

create_bridge_connection() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Creating bridge configuration..."
    local original_conn
    original_conn=$(get_original_connection_name "$INTERFACE")
    [ -n "$original_conn" ] && echo "Original connection detected: $original_conn"

    if ! nmcli connection add type bridge con-name "$BRIDGE_NAME" ifname "$BRIDGE_NAME" \
        ipv4.method auto ipv6.method auto \
        ipv4.dhcp-timeout 30 ipv6.dhcp-timeout 30 \
        bridge.stp no \
        connection.autoconnect no 2>&1; then
        echo "Error creating bridge"
        return 1
    fi

    if ! nmcli connection add type bridge-slave con-name "$BRIDGE_SLAVE" ifname "$INTERFACE" \
        master "$BRIDGE_NAME" connection.autoconnect no 2>&1; then
        echo "Error creating bridge-slave"
        nmcli connection delete "$BRIDGE_NAME" 2>/dev/null || true
        return 1
    fi

    sleep 2
    return 0
}

force_interface_to_bridge() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Forcing link of $INTERFACE to $BRIDGE_NAME..."

    ip link set dev "$INTERFACE" down 2>/dev/null || true
    sleep 1
    ip link set dev "$INTERFACE" master "$BRIDGE_NAME" 2>/dev/null || true
    sleep 1
    ip link set dev "$INTERFACE" up 2>/dev/null || true
    sleep 2

    if ! bridge link show dev "$INTERFACE" 2>/dev/null | grep -q "$BRIDGE_NAME"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Retrying link..."
        ip link set dev "$INTERFACE" nomaster 2>/dev/null || true
        sleep 1
        ip link set dev "$INTERFACE" master "$BRIDGE_NAME" 2>/dev/null || true
        sleep 2
    fi
}

activate_bridge() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Activating bridge..."

    ip link set dev "$INTERFACE" down 2>/dev/null || true
    ip addr flush dev "$INTERFACE" 2>/dev/null || true
    ip link set dev "$INTERFACE" up 2>/dev/null || true
    sleep 2

    local active_conn
    active_conn=$(get_original_connection_name "$INTERFACE")
    if [ -n "$active_conn" ]; then
        echo "Deactivating active connection: $active_conn"
        nmcli connection down "$active_conn" 2>/dev/null || true
        sleep 2
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Activating bridge first..."
    if ! nmcli connection up "$BRIDGE_NAME" 2>&1; then
        echo "Error activating bridge"
        return 1
    fi
    sleep 3

    force_interface_to_bridge

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Activating slave..."
    if ! nmcli connection up "$BRIDGE_SLAVE" 2>&1; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Problem activating slave, but continuing..."
    fi
    sleep 3

    if bridge link show dev "$INTERFACE" 2>/dev/null | grep -q "$BRIDGE_NAME"; then
        echo "$INTERFACE successfully linked to $BRIDGE_NAME"
        return 0
    else
        echo "Failed to link $INTERFACE to bridge $BRIDGE_NAME"
        return 1
    fi
}

wait_for_dhcp() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Waiting for DHCP configuration..."
    local max_attempts=6
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if ip addr show "$BRIDGE_NAME" | grep -q "inet "; then
            echo "IP address obtained via DHCP"
            return 0
        fi

        attempt=$((attempt + 1))
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Attempt $attempt/$max_attempts..."

        if [ $((attempt % 2)) -eq 0 ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Forcing DHCP renewal..."
            nmcli device reapply "$BRIDGE_NAME" 2>/dev/null || true
        fi

        sleep 5
    done

    echo "No IP address obtained via DHCP"
    return 1
}

restore_normal_network() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Restoring normal network configuration..."
    nmcli connection down "$BRIDGE_SLAVE" 2>/dev/null || true
    nmcli connection down "$BRIDGE_NAME" 2>/dev/null || true
    sleep 2
    nmcli connection delete "$BRIDGE_SLAVE" 2>/dev/null || true
    nmcli connection delete "$BRIDGE_NAME" 2>/dev/null || true
    sleep 1
    ip link set dev "$BRIDGE_NAME" down 2>/dev/null || true
    ip link delete "$BRIDGE_NAME" type bridge 2>/dev/null || true

    if [ -n "$INTERFACE" ] && [ "$INTERFACE" != "unknown" ]; then
        ip addr flush dev "$INTERFACE" 2>/dev/null || true
        ip link set dev "$INTERFACE" up 2>/dev/null || true
    fi

    local original_conn
    original_conn=$(get_original_connection_name "$INTERFACE")
    if [ -n "$original_conn" ]; then
        echo "Reactivating original connection: $original_conn"
        nmcli connection up "$original_conn" 2>/dev/null || true
    else
        echo "No original connection found for $INTERFACE"
        echo "Network should auto-connect or you may need to manually activate a connection"
    fi

    sleep 3
    echo "Normal configuration restored"
}

# ------------------------------------------------------------------------------
# ACTIONS
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: bridge start..."

# Main
case "${1:-}" in
    --on)
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Scanning for active Ethernet interface..."
        INTERFACE=$(detect_ethernet_interface) || exit 1
        echo "Found active Ethernet interface: $INTERFACE"

        if bridge_exists; then
            echo "Bridge $BRIDGE_NAME is already active or exists"
            echo "Use '$0 --off' to deactivate it first"
            exit 1
        fi

        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Activating bridge ${BRIDGE_NAME} on ${INTERFACE}..."
        cleanup_all_connections

        if ! create_bridge_connection; then
            echo "Error in bridge configuration"
            restore_normal_network
            exit 1
        fi

        if ! activate_bridge; then
            echo "Error activating bridge - interface linking failed"
            restore_normal_network
            exit 1
        fi

        if ! wait_for_dhcp; then
            echo "Error obtaining an IP address on the bridge"
            restore_normal_network
            exit 1
        fi
        show_final_status
        ;;

    --off)
        INTERFACE=$(get_ethernet_interface_for_status)
        if bridge_exists; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Deactivating bridge, restoring normal config..."
            cleanup_all_connections
            restore_normal_network
            show_restored_status
        else
            echo "Bridge $BRIDGE_NAME is not active, nothing to do"
        fi
        ;;

    --status)
        INTERFACE=$(get_ethernet_interface_for_status)
        echo "=== CONNECTION STATUS ==="
        nmcli connection show | grep -E "(${BRIDGE_NAME}|${BRIDGE_SLAVE})" \
            || echo "No active bridge connections"
        original_conn=$(get_original_connection_name "$INTERFACE")
        [ -n "$original_conn" ] && echo "Original connection: $original_conn"

        echo ""
        echo "=== INTERFACE STATUS ==="
        echo "Bridge ${BRIDGE_NAME}:"
        if ip link show "$BRIDGE_NAME" 2>/dev/null; then
            ip -br addr show "$BRIDGE_NAME"
            if bridge link show dev "$INTERFACE" 2>/dev/null | grep -q "$BRIDGE_NAME"; then
                echo "${INTERFACE} linked to bridge"
            else
                echo "${INTERFACE} NOT linked to bridge"
            fi
        else
            echo "Does not exist"
        fi

        echo ""
        if [ "$INTERFACE" != "unknown" ]; then
            echo "Physical interface ${INTERFACE}:"
            ip -br addr show "$INTERFACE" 2>/dev/null || echo " No IP address"
        else
            echo "Physical interface: No Ethernet interface detected"
        fi
        ;;

    --clean)
        INTERFACE=$(get_ethernet_interface_for_status)
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Complete cleanup of bridge connections..."
        cleanup_all_connections
        echo "Cleanup completed"
        ;;

    *)
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: invalid option -abort" >&2
        echo "Usage: sudo $0 [--on|--off|--status|--clean]"
        echo ""
        echo "Options:"
        echo "--on - Activate bridge ${BRIDGE_NAME}"
        echo "--off - Deactivate bridge and restore original configuration"
        echo "--status - Check detailed status"
        echo "--clean - Clean up bridge connections"
        exit 1
        ;;
esac

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: bridge done"

exit 0
