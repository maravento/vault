#!/bin/bash
# maravento.com
#
# =============================================================================
# Network Bridge Manager Script
#
# Usage: sudo ./bridge.sh [on|off|status|clean]
# =============================================================================

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

# VARIABLES
BRIDGE_NAME="br0"
BRIDGE_SLAVE="${BRIDGE_NAME}-slave"
INTERFACE=""

check_dependencies() {
    local missing=0
    if ! command -v nmcli &> /dev/null; then
        echo "✗ NetworkManager is not installed" >&2
        missing=1
    fi
    if ! command -v ip &> /dev/null; then
        echo "✗ iproute2 is not installed" >&2
        missing=1
    fi
    if [ $missing -eq 1 ]; then
        echo "" >&2
        echo "Install dependencies with:" >&2
        echo "  sudo apt-get install network-manager iproute2" >&2
        return 1
    fi
    echo "✓ All dependencies are installed"
    return 0
}

detect_ethernet_interface() {
    local wifi_interfaces
    wifi_interfaces=$(nmcli -t -f DEVICE,TYPE device status | grep -E ":wifi$" | cut -d: -f1)
    for wifi in $wifi_interfaces; do
        if nmcli -t -f DEVICE,STATE device status | grep -q "^${wifi}:connected"; then
            echo "✗ WiFi interface '$wifi' is active. Please disable WiFi before creating a bridge." >&2
            echo "   Run: nmcli radio wifi off" >&2
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

    echo "✗ No active Ethernet interface found with IP address." >&2
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
        echo "✓ Original connection reactivated: $original_conn"
        nmcli connection show "$original_conn" | grep -E "GENERAL.STATE|IP4.ADDRESS" | head -2
    else
        ip addr show "$INTERFACE" 2>/dev/null | grep -E "inet|ether" | head -2 \
            || echo "  Interface not available"
    fi
}

show_final_status() {
    echo ""
    echo "=== FINAL STATUS ==="
    if ip link show "$BRIDGE_NAME" 2>/dev/null | grep -q "state UP"; then
        echo "✓ Bridge ${BRIDGE_NAME} activated successfully"
        echo ""
        ip -br addr show "$BRIDGE_NAME"
        echo ""
        if bridge link show dev "$INTERFACE" 2>/dev/null | grep -q "$BRIDGE_NAME"; then
            echo "✓ ${INTERFACE} successfully linked to bridge"
        else
            echo "✗ ${INTERFACE} NOT linked to bridge"
        fi
        local original_conn
        original_conn=$(get_original_connection_name "$INTERFACE")
        [ -n "$original_conn" ] && echo "✓ Original connection '$original_conn' preserved (inactive)"
    else
        echo "✗ Bridge is not active"
        restore_normal_network
        exit 1
    fi
}

cleanup_all_connections() {
    echo "Cleaning up all bridge connections..."
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
    echo "Creating bridge configuration..."
    local original_conn
    original_conn=$(get_original_connection_name "$INTERFACE")
    [ -n "$original_conn" ] && echo "Original connection detected: $original_conn"

    if ! nmcli connection add type bridge con-name "$BRIDGE_NAME" ifname "$BRIDGE_NAME" \
        ipv4.method auto ipv6.method auto \
        ipv4.dhcp-timeout 30 ipv6.dhcp-timeout 30 \
        bridge.stp no \
        connection.autoconnect no 2>&1; then
        echo "✗ Error creating bridge"
        return 1
    fi

    if ! nmcli connection add type bridge-slave con-name "$BRIDGE_SLAVE" ifname "$INTERFACE" \
        master "$BRIDGE_NAME" connection.autoconnect no 2>&1; then
        echo "✗ Error creating bridge-slave"
        nmcli connection delete "$BRIDGE_NAME" 2>/dev/null || true
        return 1
    fi

    sleep 2
    return 0
}

force_interface_to_bridge() {
    echo "Forcing link of $INTERFACE to $BRIDGE_NAME..."

    ip link set dev "$INTERFACE" down 2>/dev/null || true
    sleep 1
    ip link set dev "$INTERFACE" master "$BRIDGE_NAME" 2>/dev/null || true
    sleep 1
    ip link set dev "$INTERFACE" up 2>/dev/null || true
    sleep 2

    if ! bridge link show dev "$INTERFACE" 2>/dev/null | grep -q "$BRIDGE_NAME"; then
        echo "Retrying link..."
        ip link set dev "$INTERFACE" nomaster 2>/dev/null || true
        sleep 1
        ip link set dev "$INTERFACE" master "$BRIDGE_NAME" 2>/dev/null || true
        sleep 2
    fi
}

activate_bridge() {
    echo "Activating bridge..."

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

    echo "Activating bridge first..."
    if ! nmcli connection up "$BRIDGE_NAME" 2>&1; then
        echo "✗ Error activating bridge"
        return 1
    fi
    sleep 3

    force_interface_to_bridge

    echo "Activating slave..."
    if ! nmcli connection up "$BRIDGE_SLAVE" 2>&1; then
        echo "⚠ Problem activating slave, but continuing..."
    fi
    sleep 3

    if bridge link show dev "$INTERFACE" 2>/dev/null | grep -q "$BRIDGE_NAME"; then
        echo "✓ $INTERFACE successfully linked to $BRIDGE_NAME"
        return 0
    else
        echo "✗ Failed to link $INTERFACE to bridge $BRIDGE_NAME"
        return 1
    fi
}

wait_for_dhcp() {
    echo "Waiting for DHCP configuration..."
    local max_attempts=6
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if ip addr show "$BRIDGE_NAME" | grep -q "inet "; then
            echo "✓ IP address obtained via DHCP"
            return 0
        fi

        attempt=$((attempt + 1))
        echo "Attempt $attempt/$max_attempts..."

        if [ $((attempt % 2)) -eq 0 ]; then
            echo "Forcing DHCP renewal..."
            nmcli device reapply "$BRIDGE_NAME" 2>/dev/null || true
        fi

        sleep 5
    done

    echo "⚠ No IP address obtained via DHCP"
    return 1
}

restore_normal_network() {
    echo "Restoring normal network configuration..."
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
    echo "✓ Normal configuration restored"
}

# Main
case "$1" in
    on)
        echo "Verifying dependencies..."
        check_dependencies || exit 1

        echo "Scanning for active Ethernet interface..."
        INTERFACE=$(detect_ethernet_interface) || exit 1
        echo "✓ Found active Ethernet interface: $INTERFACE"

        if bridge_exists; then
            echo "✗ Bridge $BRIDGE_NAME is already active or exists"
            echo "   Use '$0 off' to deactivate it first"
            exit 1
        fi

        echo "Activating bridge ${BRIDGE_NAME} on ${INTERFACE}..."
        cleanup_all_connections

        if ! create_bridge_connection; then
            echo "✗ Error in bridge configuration"
            restore_normal_network
            exit 1
        fi

        if ! activate_bridge; then
            echo "✗ Error activating bridge - interface linking failed"
            restore_normal_network
            exit 1
        fi

        wait_for_dhcp
        show_final_status
        ;;

    off)
        INTERFACE=$(get_ethernet_interface_for_status)
        if ! bridge_exists; then
            echo "✓ Bridge $BRIDGE_NAME is not active, nothing to do"
            exit 0
        fi
        echo "Deactivating bridge and restoring normal configuration..."
        cleanup_all_connections
        restore_normal_network
        show_restored_status
        ;;

    status)
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
                echo "  ✓ ${INTERFACE} linked to bridge"
            else
                echo "  ✗ ${INTERFACE} NOT linked to bridge"
            fi
        else
            echo "  Does not exist"
        fi

        echo ""
        if [ "$INTERFACE" != "unknown" ]; then
            echo "Physical interface ${INTERFACE}:"
            ip -br addr show "$INTERFACE" 2>/dev/null || echo "  No IP address"
        else
            echo "Physical interface: No Ethernet interface detected"
        fi
        ;;

    clean)
        INTERFACE=$(get_ethernet_interface_for_status)
        echo "Complete cleanup of bridge connections..."
        cleanup_all_connections
        echo "✓ Cleanup completed"
        ;;

    *)
        echo "Usage: sudo $0 [on|off|status|clean]"
        echo ""
        echo "Options:"
        echo "  on     - Activate bridge ${BRIDGE_NAME}"
        echo "  off    - Deactivate bridge and restore original configuration"
        echo "  status - Check detailed status"
        echo "  clean  - Clean up bridge connections"
        exit 1
        ;;
esac

exit 0
