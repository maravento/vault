#!/bin/bash
# maravento.com
#
# =============================================================================
# Network Bridge Manager Script
# 
# Description: This script creates and manages a network bridge (br0) using
#              NetworkManager. It automatically detects the active Ethernet
#              interface, creates a bridge with DHCP configuration, and 
#              restores the original network configuration when disabled.
#
# Primary Use Cases:
#   - Virtualization (KVM/QEMU, virt-manager, Virtual Machine Manager)
#   - Container networking (LXC/LXD, Docker custom networks)
#   - Development labs and network testing environments
#   - Service isolation (web servers, game servers, VoIP services)
#   - Home lab setups and self-hosted services
#   - Network security (DMZ, isolated environments)
#
# Features:
#   - Automatic Ethernet interface detection
#   - Prevents execution if WiFi is active
#   - Creates bridge with DHCP (IPv4/IPv6)
#   - Preserves original network configuration
#   - No duplicate connections created
#   - Robust interface linking and verification
#   - Clean restoration of original network state
#
# Usage: sudo ./bridge.sh [on|off|status|clean]
# =============================================================================

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# checking root
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# checking script execution
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

# VARIABLES
BRIDGE_NAME="br0"
BRIDGE_SLAVE="${BRIDGE_NAME}-slave"

# Function definitions
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
    # Check if WiFi is active
    local wifi_interfaces=$(nmcli -t -f DEVICE,TYPE device status | grep -E ":wifi$" | cut -d: -f1)
    local active_wifi=""
    
    for wifi in $wifi_interfaces; do
        if nmcli -t -f DEVICE,STATE device status | grep -q "^${wifi}:connected"; then
            active_wifi="$wifi"
            echo "✗ WiFi interface '$active_wifi' is active. Please disable WiFi before creating a bridge." >&2
            echo "   Run: nmcli radio wifi off" >&2
            return 1
        fi
    done
    
    # Find active Ethernet interfaces with IP addresses
    local ethernet_interfaces=$(nmcli -t -f DEVICE,TYPE device status | grep -E ":ethernet$" | cut -d: -f1)
    local candidate_interface=""
    
    for eth in $ethernet_interfaces; do
        # Check if interface is connected and has an IP address
        if nmcli -t -f DEVICE,STATE device status | grep -q "^${eth}:connected"; then
            if ip addr show "$eth" 2>/dev/null | grep -q "inet "; then
                candidate_interface="$eth"
                break
            fi
        fi
    done
    
    if [ -z "$candidate_interface" ]; then
        echo "✗ No active Ethernet interface found with IP address." >&2
        echo "   Please ensure an Ethernet cable is connected and you have network connectivity." >&2
        return 1
    fi
    
    echo "$candidate_interface"
}

get_ethernet_interface_for_status() {
    # Simplified version for status command that doesn't check WiFi or exit on error
    local ethernet_interfaces=$(nmcli -t -f DEVICE,TYPE device status | grep -E ":ethernet$" | cut -d: -f1)
    
    for eth in $ethernet_interfaces; do
        if nmcli -t -f DEVICE,STATE device status | grep -q "^${eth}:connected"; then
            echo "$eth"
            return 0
        fi
    done
    
    # If no connected interface found, try to find any Ethernet interface
    if [ -n "$ethernet_interfaces" ]; then
        echo "$(echo "$ethernet_interfaces" | head -1)"
        return 0
    fi
    
    echo "unknown"
}

get_original_connection_name() {
    # Get the original connection name for the physical interface
    local interface="$1"
    if [ "$interface" != "unknown" ]; then
        # Find connections that are NOT bridge-related and are for this interface
        nmcli -g NAME,UUID connection show | while IFS=: read -r conn_name uuid; do
            if nmcli connection show "$conn_name" 2>/dev/null | grep -q "connection.interface-name:\s*${interface}" && \
               [[ "$conn_name" != "$BRIDGE_SLAVE" ]] && \
               [[ "$conn_name" != *"bridge"* ]] && \
               [[ "$conn_name" != *"slave"* ]] && \
               [[ ! "$conn_name" =~ ^[a-z]+[0-9]+[a-z]*[0-9]*$ ]]; then
                echo "$conn_name"
                return 0
            fi
        done
    fi
}

bridge_exists() {
    # Check if bridge exists at system level or NetworkManager
    ip link show "$BRIDGE_NAME" 2>/dev/null >/dev/null || \
    nmcli connection show "$BRIDGE_NAME" 2>/dev/null >/dev/null || \
    nmcli connection show "$BRIDGE_SLAVE" 2>/dev/null >/dev/null
}

show_restored_status() {
    echo ""
    echo "=== RESTORED STATUS ==="
    local original_conn=$(get_original_connection_name "$INTERFACE")
    if [ -n "$original_conn" ]; then
        echo "✓ Original connection reactivated: $original_conn"
        nmcli connection show "$original_conn" | grep -E "GENERAL.STATE|IP4.ADDRESS" | head -2
    else
        ip addr show "$INTERFACE" 2>/dev/null | grep -E "inet|ether" | head -2 || echo "  Interface not available"
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
        
        # Show preserved original connection
        local original_conn=$(get_original_connection_name "$INTERFACE")
        if [ -n "$original_conn" ]; then
            echo "✓ Original connection '$original_conn' preserved (inactive)"
        fi
    else
        echo "✗ Bridge is not active"
        restore_normal_network
        exit 1
    fi
}

cleanup_all_connections() {
    echo "Cleaning up all bridge connections..."
    
    # Delete only the bridge connections we created
    nmcli connection delete "$BRIDGE_SLAVE" 2>/dev/null || true
    nmcli connection delete "$BRIDGE_NAME" 2>/dev/null || true
    
    # Clean up bridge at system level
    ip link set dev "$BRIDGE_NAME" down 2>/dev/null || true
    ip link delete "$BRIDGE_NAME" type bridge 2>/dev/null || true
    
    # Clean up physical interface but DO NOT delete its original connection
    if [ "$INTERFACE" != "unknown" ]; then
        ip addr flush dev "$INTERFACE" 2>/dev/null || true
        ip link set dev "$INTERFACE" up 2>/dev/null || true
    fi
    
    sleep 2
}

create_bridge_connection() {
    echo "Creating bridge configuration..."
    
    # Get original connection for reference
    local original_conn=$(get_original_connection_name "$INTERFACE")
    if [ -n "$original_conn" ]; then
        echo "Original connection detected: $original_conn"
    fi
    
    # Step 1: Create the bridge with robust configuration
    if ! nmcli connection add type bridge con-name "$BRIDGE_NAME" ifname "$BRIDGE_NAME" \
        ipv4.method auto ipv6.method auto \
        ipv4.dhcp-timeout 30 ipv6.dhcp-timeout 30 \
        bridge.stp no \
        connection.autoconnect no 2>&1; then
        echo "✗ Error creating bridge"
        return 1
    fi
    
    # Step 2: Configure bridge-slave
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
    
    # Method 1: Use bridge command
    ip link set dev "$INTERFACE" down 2>/dev/null || true
    sleep 1
    ip link set dev "$INTERFACE" master "$BRIDGE_NAME" 2>/dev/null || true
    sleep 1
    ip link set dev "$INTERFACE" up 2>/dev/null || true
    sleep 2
    
    # Method 2: Verify and retry
    if ! bridge link show dev "$INTERFACE" 2>/dev/null | grep -q "$BRIDGE_NAME"; then
        echo "Retrying link..."
        ip link set dev "$INTERFACE" nomaster 2>/dev/null || true
        sleep 1
        ip link set dev "$INTERFACE" master "$BRIDGE_NAME" 2>/dev/null || true
        sleep 2
    fi
    
    # Method 3: Use brctl if available
    if command -v brctl &> /dev/null; then
        echo "Using brctl to force link..."
        brctl addif "$BRIDGE_NAME" "$INTERFACE" 2>/dev/null || true
        sleep 2
    fi
}

activate_bridge() {
    echo "Activating bridge..."
    
    # First ensure physical interface is available and clean
    ip link set dev "$INTERFACE" down 2>/dev/null || true
    ip addr flush dev "$INTERFACE" 2>/dev/null || true
    ip link set dev "$INTERFACE" up 2>/dev/null || true
    sleep 2
    
    # Deactivate any active connection on the physical interface
    local active_conn=$(get_original_connection_name "$INTERFACE")
    if [ -n "$active_conn" ]; then
        echo "Deactivating active connection: $active_conn"
        nmcli connection down "$active_conn" 2>/dev/null || true
        sleep 2
    fi
    
    # Activate bridge FIRST
    echo "Activating bridge first..."
    if ! nmcli connection up "$BRIDGE_NAME" 2>&1; then
        echo "✗ Error activating bridge"
        return 1
    fi
    sleep 3
    
    # Force physical link BEFORE activating slave
    force_interface_to_bridge
    
    # Now activate slave
    echo "Activating slave..."
    if ! nmcli connection up "$BRIDGE_SLAVE" 2>&1; then
        echo "⚠ Problem activating slave, but continuing..."
    fi
    sleep 3
    
    # Final link verification
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
        
        # Force DHCP renew every 2 attempts
        if [ $((attempt % 2)) -eq 0 ]; then
            echo "Forcing DHCP renewal..."
            nmcli connection up "$BRIDGE_NAME" 2>/dev/null || true
        fi
        
        sleep 5
    done
    
    echo "⚠ No IP address obtained via DHCP"
    return 1
}

restore_normal_network() {
    echo "Restoring normal network configuration..."
    
    # Deactivate bridge connections
    nmcli connection down "$BRIDGE_SLAVE" 2>/dev/null || true
    nmcli connection down "$BRIDGE_NAME" 2>/dev/null || true
    sleep 2
    
    # Delete only the bridge connections we created
    nmcli connection delete "$BRIDGE_SLAVE" 2>/dev/null || true
    nmcli connection delete "$BRIDGE_NAME" 2>/dev/null || true
    sleep 1
    
    # Clean up bridge at system level
    ip link set dev "$BRIDGE_NAME" down 2>/dev/null || true
    ip link delete "$BRIDGE_NAME" type bridge 2>/dev/null || true
    
    # Clean up and reactivate physical interface
    if [ "$INTERFACE" != "unknown" ]; then
        ip addr flush dev "$INTERFACE" 2>/dev/null || true
        ip link set dev "$INTERFACE" up 2>/dev/null || true
    fi
    
    # Find and reactivate the ORIGINAL connection
    local original_conn=$(get_original_connection_name "$INTERFACE")
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

# Main execution starts here
case "$1" in
    on)
        echo "Verifying dependencies..."
        check_dependencies || exit 1
        
        echo "Scanning for active Ethernet interface..."
        INTERFACE=$(detect_ethernet_interface)
        if [ $? -ne 0 ]; then
            exit 1
        fi
        
        echo "✓ Found active Ethernet interface: $INTERFACE"
        
        # Verify if bridge already exists
        if bridge_exists; then
            echo "✗ Bridge $BRIDGE_NAME is already active or exists"
            echo "   Use '$0 off' to deactivate it first"
            echo "   Use '$0 status' to check current status"
            exit 1
        fi
        
        echo "Activating bridge ${BRIDGE_NAME} on ${INTERFACE}..."
        
        # Initial complete cleanup
        cleanup_all_connections
        
        # Create configuration
        if ! create_bridge_connection; then
            echo "✗ Error in bridge configuration"
            restore_normal_network
            exit 1
        fi
        
        # Activate bridge
        if ! activate_bridge; then
            echo "✗ Error activating bridge - interface linking failed"
            restore_normal_network
            exit 1
        fi
        
        # Wait for DHCP
        wait_for_dhcp
        
        # Final verification
        show_final_status
        ;;
    
    off)
        # For off command, detect interface
        INTERFACE=$(get_ethernet_interface_for_status)
        
        # Verify if bridge exists before trying to deactivate
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
        # For status command, detect interface
        INTERFACE=$(get_ethernet_interface_for_status)
        
        echo "=== CONNECTION STATUS ==="
        nmcli connection show | grep -E "(${BRIDGE_NAME}|${BRIDGE_SLAVE})" || echo "No active bridge connections"
        
        original_conn=$(get_original_connection_name "$INTERFACE")
        if [ -n "$original_conn" ]; then
            echo "Original connection: $original_conn"
        fi
        
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
        # For clean command, detect interface
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
