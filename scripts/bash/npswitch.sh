#!/bin/bash
# maravento.com
################################################################################
# npswitch.sh
# 
# Intelligent Network Renderer Switcher for Ubuntu/Debian Netplan
# Safely switches between NetworkManager and systemd-networkd
#
# Author: Your Name
# License: GPL-3.0 https://www.gnu.org/licenses/gpl.txt
# Version: 1.0
#
################################################################################
#
# DESCRIPTION:
#   This script provides an intelligent way to switch network management 
#   between NetworkManager and systemd-networkd on systems using Netplan.
#   It automatically detects your network setup (WiFi, Ethernet, virtual 
#   interfaces) and recommends the best renderer for your use case.
#
# FEATURES:
#   • Automatic interface detection and classification
#   • Smart recommendations based on your hardware
#   • Safe backup/restore of Netplan configurations
#   • Proper service management (stop, disable, mask)
#   • Virtual interface exclusion (Docker, libvirt, bridges)
#   • WiFi detection and warnings
#   • Interactive or command-line usage
#
# WHEN TO USE NetworkManager:
#   ✓ Laptops and workstations with WiFi
#   ✓ Systems that need GUI network management (nmtui/nmcli)
#   ✓ Frequent network switching (home/office/mobile)
#   ✓ Desktop environments (GNOME, KDE, etc.)
#
# WHEN TO USE systemd-networkd:
#   ✓ Servers with only Ethernet connections
#   ✓ Headless systems and VMs
#   ✓ Minimal installations (lower resource usage)
#   ✓ Systems that need faster boot times
#   ✓ Container hosts and cloud instances
#
# USAGE:
#   Interactive menu:
#     sudo ./npswitch.sh
#
#   Command-line options:
#     sudo ./npswitch.sh --status        # Show current config
#     sudo ./npswitch.sh --to-networkd   # Switch to networkd
#     sudo ./npswitch.sh --to-nm         # Switch to NetworkManager
#     sudo ./npswitch.sh --help          # Show help
#
# QUICK START:
#   1. Make executable:
#      chmod +x npswitch.sh
#
#   2. Check your current setup:
#      sudo ./npswitch.sh --status
#
#   3. Switch renderer (the script will guide you):
#      sudo ./npswitch.sh --to-nm
#      # or
#      sudo ./npswitch.sh --to-networkd
#
# SAFETY FEATURES:
#   • Automatic backup of all YAML files before changes (.bak extension)
#   • Configuration validation before applying changes
#   • Rollback capability if errors occur
#   • Warning prompts for risky operations (WiFi systems)
#   • No modification of virtual interfaces (Docker, libvirt, etc.)
#
# REQUIREMENTS:
#   • Ubuntu 18.04+ or Debian-based system with Netplan
#   • Root/sudo privileges
#   • netplan, systemctl, and ip commands available
#
# FILES MODIFIED:
#   • /etc/netplan/*.yaml (backed up as *.yaml.bak)
#   • Creates /etc/netplan/00-networkd.yaml when switching to networkd
#   • Restores original YAML files when switching to NetworkManager
#
# TROUBLESHOOTING:
#   If something goes wrong:
#   1. Check service status:
#      sudo systemctl status NetworkManager
#      sudo systemctl status systemd-networkd
#
#   2. Restore backups manually:
#      cd /etc/netplan
#      sudo mv *.yaml.bak *.yaml (remove .bak extension)
#      sudo netplan apply
#
#   3. View network interfaces:
#      ip addr show
#      sudo netplan status
#
# NOTES:
#   ⚠ This script may temporarily disconnect your network connection
#   ⚠ Use with caution on remote SSH sessions
#   ⚠ Virtual interfaces (docker0, virbr0, etc.) are intentionally excluded
#   ⚠ WiFi requires NetworkManager for easy management
#
################################################################################

# check root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# checking script execution
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Paths
NETPLAN_DIR="/etc/netplan"
NETWORKD_FILE="$NETPLAN_DIR/00-networkd.yaml"

# Check root
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}Error: This script must be run as root${NC}" 1>&2
    exit 1
fi

# Check dependencies
check_dependencies() {
    if ! command -v netplan &>/dev/null; then
        echo -e "${RED}Error: netplan command not found${NC}"
        exit 1
    fi
    
    if ! command -v ip &>/dev/null; then
        echo -e "${RED}Error: ip command not found${NC}"
        exit 1
    fi
}

# Detect current renderer
detect_current_renderer() {
    local renderer="unknown"
    
    # Check all yaml files
    for yaml_file in "$NETPLAN_DIR"/*.yaml; do
        [ -f "$yaml_file" ] || continue
        if grep -q "renderer.*networkd" "$yaml_file" 2>/dev/null; then
            renderer="networkd"
            break
        elif grep -q "renderer.*NetworkManager" "$yaml_file" 2>/dev/null; then
            renderer="NetworkManager"
            break
        fi
    done
    
    echo "$renderer"
}

# Classify interface type
classify_interface() {
    local iface="$1"
    local type="unknown"
    
    # Virtual interfaces (Docker, libvirt, etc.)
    if [[ "$iface" =~ ^(docker|br-|virbr|veth|tap|tun) ]]; then
        type="virtual"
    # Loopback
    elif [[ "$iface" == "lo" ]]; then
        type="loopback"
    # Wireless
    elif [[ "$iface" =~ ^wl ]]; then
        type="wifi"
    # Ethernet
    elif [[ "$iface" =~ ^(eth|en|eno|enp|ens) ]]; then
        type="ethernet"
    # Bridge
    elif ip link show "$iface" 2>/dev/null | grep -q "bridge"; then
        type="bridge"
    # Bond
    elif ip link show "$iface" 2>/dev/null | grep -q "bond"; then
        type="bond"
    else
        type="other"
    fi
    
    echo "$type"
}

# Detect and classify all interfaces
detect_and_classify_interfaces() {
    declare -A iface_data
    local has_wifi=0
    local has_ethernet=0
    local has_virtual=0
    local active_wifi=0
    
    echo -e "${BLUE}Analyzing network interfaces...${NC}" >&2
    
    while IFS= read -r line; do
        iface=$(echo "$line" | awk '{print $1}' | sed 's/@.*//')
        link_state=$(echo "$line" | awk '{print $2}')
        
        [[ "$iface" == "lo" ]] && continue
        [[ "$link_state" != "UP" ]] && continue

        ip_addr=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        type=$(classify_interface "$iface")
        
        if [[ -z "$ip_addr" ]]; then
            continue
        fi

        case "$type" in
            wifi)
                has_wifi=1
                active_wifi=1
                ;;
            ethernet)
                has_ethernet=1
                ;;
            virtual|bridge|bond)
                has_virtual=1
                ;;
        esac
        
        local icon color state_display="${GREEN}UP/Active${NC}"
        
        case "$type" in
            wifi) icon="📡" color="$MAGENTA" ;;
            ethernet) icon="🔌" color="$GREEN" ;;
            virtual) icon="🐳" color="$CYAN" ;;
            bridge) icon="🌉" color="$YELLOW" ;;
            bond) icon="🔗" color="$BLUE" ;;
            *) icon="❓" color="$NC" ;;
        esac
        
        printf "${color}${icon} %-18s${NC} [%-10s] %-14s %s\n" \
            "$iface" "$type" "$state_display" "$ip_addr" >&2
            
    done < <(ip -br link show | grep -v "^lo")
    
    echo "" >&2

    echo "$has_wifi|$has_ethernet|$has_virtual|$active_wifi"
}

# Get recommendation based on interface analysis
# Returns: 0 for normal recommendation, 1 for WiFi warning
get_renderer_recommendation() {
    local analysis="$1"
    local has_wifi=$(echo "$analysis" | cut -d'|' -f1)
    local has_ethernet=$(echo "$analysis" | cut -d'|' -f2)
    local has_virtual=$(echo "$analysis" | cut -d'|' -f3)
    local active_wifi=$(echo "$analysis" | cut -d'|' -f4)
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  RENDERER RECOMMENDATION${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if [ "$active_wifi" == "1" ]; then
        echo -e "${YELLOW}⚠   Active WiFi detected${NC}"
        echo ""
        echo -e "${GREEN}✓ Recommended: NetworkManager${NC}"
        echo "  Reasons:"
        echo "  • Easy WiFi management (nmtui/nmcli/GUI)"
        echo "  • Automatic connection switching"
        echo "  • Better laptop/workstation support"
        echo ""
        echo -e "${RED}✗ NOT Recommended: systemd-networkd${NC}"
        echo "  Limitations:"
        echo "  • Requires manual wpa_supplicant configuration"
        echo "  • No GUI for WiFi management"
        echo "  • Harder to switch between networks"
        echo ""
        return 1  # Return 1 to indicate WiFi warning
    elif [ "$has_wifi" == "1" ] && [ "$active_wifi" == "0" ]; then
        echo -e "${YELLOW}⚠   WiFi interface present (but inactive)${NC}"
        echo ""
        echo -e "${CYAN}⚖  Either renderer works, but:${NC}"
        echo ""
        echo -e "  ${GREEN}NetworkManager:${NC} Better if you plan to use WiFi"
        echo -e "  ${GREEN}systemd-networkd:${NC} OK for server with Ethernet only"
        echo ""
        return 0
    else
        echo -e "${GREEN}✓ Server profile detected (Ethernet only)${NC}"
        echo ""
        echo -e "${GREEN}✓ Recommended: systemd-networkd${NC}"
        echo "  Benefits:"
        echo "  • Faster and lighter (less RAM)"
        echo "  • Better for servers"
        echo "  • Excellent performance"
        echo "  • Native systemd integration"
        echo ""
        echo -e "${CYAN}○ Alternative: NetworkManager${NC}"
        echo "  • More features (may not need them)"
        echo "  • GUI management (nmtui)"
        echo "  • Better for mixed environments"
        echo ""
        return 0
    fi
}

# Get interfaces suitable for networkd
get_networkd_interfaces() {
    local -n result=$1
    
    while IFS= read -r line; do
        iface=$(echo "$line" | awk '{print $1}')
        state=$(echo "$line" | awk '{print $2}')
        
        type=$(classify_interface "$iface")
        
        if [[ "$type" == "ethernet" && "$state" == "UP" ]]; then
            result+=("$iface")
        fi
    done < <(ip -br link show | grep -v "^lo")
}

# Get interface IP info
get_interface_info() {
    local iface="$1"
    local ip_addr=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    local has_dhcp="unknown"
    
    if [ -n "$ip_addr" ]; then
        if ip addr show "$iface" | grep -q "dynamic"; then
            has_dhcp="yes"
        else
            has_dhcp="maybe"
        fi
    fi
    
    echo "$ip_addr|$has_dhcp"
}

# Deactivate all YAML files (rename with .bak extension)
deactivate_all_yaml_files() {
    echo -e "${BLUE}Deactivating all existing YAML files...${NC}"
    local count
    count=$(find "$NETPLAN_DIR" -maxdepth 1 -type f -name '*.yaml' -not -name '*.yaml.bak' -print | wc -l)
    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}  No active YAML files found${NC}"
    else
        find "$NETPLAN_DIR" -maxdepth 1 -type f -name '*.yaml' -not -name '*.yaml.bak' -exec mv -- {} {}.bak \; > /dev/null 2>&1
        echo -e "${GREEN}✓ Deactivated $count YAML file(s)${NC}"
    fi
    echo ""
}

# Restore all backup YAML files
restore_all_yaml_files() {
    echo -e "${BLUE}Restoring all previous YAML files...${NC}"
    local count
    count=$(find "$NETPLAN_DIR" -maxdepth 1 -type f -name '*.yaml.bak' -print | wc -l)
    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}  No backup YAML files found to restore${NC}"
    else
        find "$NETPLAN_DIR" -maxdepth 1 -type f -name '*.yaml.bak' -exec sh -c 'mv "$1" "${1%.bak}"' sh {} \; > /dev/null 2>&1
        echo -e "${GREEN}✓ Restored $count YAML file(s)${NC}"
    fi
    echo ""
}

# Generate networkd configuration
generate_networkd_config() {
    local interfaces=("$@")
    
    if [ ${#interfaces[@]} -eq 0 ]; then
        echo -e "${RED}Error: No suitable interfaces for systemd-networkd${NC}"
        echo "Only Ethernet interfaces in UP state are included."
        exit 1
    fi
    
    cat > "$NETWORKD_FILE" <<EOF
# Generated by netplan-renderer-switcher
# $(date)
# Only physical Ethernet interfaces included
# Virtual interfaces (docker, virbr, veth) managed separately
network:
  version: 2
  renderer: networkd
  ethernets:
EOF

    for iface in "${interfaces[@]}"; do
        echo "    $iface:" >> "$NETWORKD_FILE"
        echo "      dhcp4: true" >> "$NETWORKD_FILE"
        echo "      dhcp6: false" >> "$NETWORKD_FILE"
    done
    
    chown root:root "$NETWORKD_FILE"
    chmod 600 "$NETWORKD_FILE"
    
    echo -e "${GREEN}✓ Created: $NETWORKD_FILE${NC}"
}

# Switch to networkd
switch_to_networkd() {
    echo ""
    echo -e "${YELLOW}================================================${NC}"
    echo -e "${YELLOW}  Switching to systemd-networkd${NC}"
    echo -e "${YELLOW}================================================${NC}"
    echo ""
    
    if ! systemctl list-unit-files | grep -q "systemd-networkd.service"; then
        echo -e "${RED}Error: systemd-networkd is not installed${NC}"
        exit 1
    fi
    
    analysis=$(detect_and_classify_interfaces)
    echo ""
    
    get_renderer_recommendation "$analysis"
    rec_result=$?
    echo ""
    
    if [ $rec_result -eq 1 ]; then
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED}  STRONG WARNING${NC}"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo "You have ACTIVE WiFi connections!"
        echo "Switching to systemd-networkd will:"
        echo ""
        echo "  ${RED}✗${NC} Disconnect all WiFi connections"
        echo "  ${RED}✗${NC} Require manual wpa_supplicant setup"
        echo "  ${RED}✗${NC} Remove GUI management"
        echo ""
        echo "This is NOT recommended for systems with WiFi."
        echo ""
        read -p "Are you ABSOLUTELY SURE? (type 'I UNDERSTAND'): " confirm
        
        if [ "$confirm" != "I UNDERSTAND" ]; then
            echo "Aborted. Good choice!"
            exit 0
        fi
    fi
    
    declare -a suitable_ifaces
    get_networkd_interfaces suitable_ifaces
    
    if [ ${#suitable_ifaces[@]} -eq 0 ]; then
        echo -e "${RED}Error: No suitable Ethernet interfaces found${NC}"
        echo "systemd-networkd configuration requires at least one UP Ethernet interface."
        exit 1
    fi
    
    echo -e "${GREEN}Interfaces to be configured with networkd:${NC}"
    for iface in "${suitable_ifaces[@]}"; do
        info=$(get_interface_info "$iface")
        ip_addr=$(echo "$info" | cut -d'|' -f1)
        echo "  🔌 $iface: ${ip_addr:-no IP}"
    done
    echo ""
    
    echo -e "${YELLOW}NOTE: Virtual interfaces (docker0, virbr0, veth*, br-*) will NOT be included.${NC}"
    echo -e "${YELLOW}They are managed by their respective services.${NC}"
    echo ""
    
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "This will:"
    echo "  1. Deactivate ALL existing YAML files (rename to .bak)"
    echo "  2. Create new 00-networkd.yaml config"
    echo "  3. Disable NetworkManager"
    echo "  4. Enable systemd-networkd"
    echo "  5. Apply changes (may disconnect SSH!)"
    echo ""
    read -p "Continue? (y/n): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    
    deactivate_all_yaml_files
    
    echo -e "${BLUE}Generating networkd configuration...${NC}"
    generate_networkd_config "${suitable_ifaces[@]}"
    
    echo ""
    echo -e "${BLUE}Generated configuration:${NC}"
    cat "$NETWORKD_FILE"
    echo ""
    
    echo -e "${BLUE}Validating configuration...${NC}"
    if netplan generate 2>&1 | grep -qi error; then
        echo -e "${RED}Error: Configuration validation failed${NC}"
        echo "Restoring backup..."
        restore_all_yaml_files
        rm -f "$NETWORKD_FILE"
        exit 1
    fi
    echo -e "${GREEN}✓ Configuration is valid${NC}"
    echo ""
    
    echo -e "${BLUE}Unmasking NetworkManager (if masked)...${NC}"
    systemctl unmask NetworkManager.service 2>/dev/null || true
    
    echo -e "${BLUE}Stopping and disabling NetworkManager...${NC}"
    systemctl stop NetworkManager.service 2>/dev/null || true
    systemctl disable NetworkManager.service 2>/dev/null || true
    echo -e "${GREEN}✓ NetworkManager stopped${NC}"

    echo -e "${BLUE}Enabling systemd-networkd...${NC}"
    systemctl unmask systemd-networkd.service 2>/dev/null || true
    systemctl enable systemd-networkd.service 2>/dev/null || true
    systemctl start systemd-networkd.service 2>/dev/null || true
    echo -e "${GREEN}✓ systemd-networkd started${NC}"
    
    echo ""
    echo -e "${BLUE}Applying netplan configuration...${NC}"
    if netplan apply; then
        echo ""
        echo -e "${GREEN}================================================${NC}"
        echo -e "${GREEN}✓ Successfully switched to systemd-networkd${NC}"
        echo -e "${GREEN}================================================${NC}"
        echo ""
        echo "To verify: systemctl status systemd-networkd"
        echo "To rollback: $0 --to-nm"
    else
        echo -e "${RED}Error applying configuration!${NC}"
        echo "Attempting rollback..."
        restore_all_yaml_files
        rm -f "$NETWORKD_FILE"
        netplan apply
        exit 1
    fi
}

# Switch to NetworkManager
switch_to_nm() {
    echo ""
    echo -e "${YELLOW}================================================${NC}"
    echo -e "${YELLOW}  Switching to NetworkManager${NC}"
    echo -e "${YELLOW}================================================${NC}"
    echo ""
    
    if ! command -v nmcli &>/dev/null; then
        echo -e "${RED}Error: NetworkManager is not installed${NC}"
        echo "Install it with: apt install network-manager"
        exit 1
    fi
    
    analysis=$(detect_and_classify_interfaces)
    echo ""
    
    get_renderer_recommendation "$analysis"
    echo ""
    
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "This will:"
    echo "  1. Remove 00-networkd.yaml file"
    echo "  2. Restore ALL previous YAML files (from .bak)"
    echo "  3. Force renderer to NetworkManager"
    echo "  4. Disable systemd-networkd"
    echo "  5. Enable NetworkManager"
    echo "  6. Apply changes (may disconnect SSH!)"
    echo ""
    read -p "Continue? (y/n): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    
    echo -e "${BLUE}Removing networkd configuration file...${NC}"
    if [ -f "$NETWORKD_FILE" ]; then
        rm -f "$NETWORKD_FILE"
        echo -e "${GREEN}✓ Removed: $NETWORKD_FILE${NC}"
    else
        echo -e "${YELLOW}  File not found: $NETWORKD_FILE${NC}"
    fi
    echo ""
    
    restore_all_yaml_files
    
    echo -e "${BLUE}Forcing all YAML files to use NetworkManager renderer...${NC}"
    for yaml in "$NETPLAN_DIR"/*.yaml; do
        [ -f "$yaml" ] || continue
        sed -i 's/renderer: networkd/renderer: NetworkManager/g' "$yaml"
    done
    echo -e "${GREEN}✓ Updated renderer in YAML files${NC}"
    echo ""
    
    echo -e "${BLUE}Unmasking systemd-networkd temporarily (for netplan apply)...${NC}"
    systemctl unmask systemd-networkd.service 2>/dev/null || true
    systemctl unmask systemd-networkd.socket 2>/dev/null || true
    echo -e "${GREEN}✓ Unmasked systemd-networkd${NC}"
    echo ""
    
    echo -e "${BLUE}Unmasking NetworkManager (if masked)...${NC}"
    systemctl unmask NetworkManager.service 2>/dev/null || true
    
    echo -e "${BLUE}Enabling and starting NetworkManager...${NC}"
    systemctl enable NetworkManager.service 2>/dev/null || true
    systemctl start NetworkManager.service 2>/dev/null || true
    echo -e "${GREEN}✓ NetworkManager is running${NC}"
    echo ""
    
    echo -e "${BLUE}Applying netplan configuration...${NC}"
    if netplan apply; then
        echo ""
        echo -e "${GREEN}✓ Netplan configuration applied successfully${NC}"
        echo ""
        
        # NOW stop and mask systemd-networkd AFTER netplan apply succeeded
        echo -e "${BLUE}Stopping systemd-networkd services...${NC}"
        systemctl stop systemd-networkd.socket 2>/dev/null || true
        systemctl stop systemd-networkd-wait-online.service 2>/dev/null || true
        systemctl stop systemd-networkd.service 2>/dev/null || true
        
        # Verify they stopped
        sleep 1
        if systemctl is-active --quiet systemd-networkd.service; then
            echo -e "${YELLOW}  Force killing systemd-networkd...${NC}"
            systemctl kill systemd-networkd.service 2>/dev/null || true
            sleep 1
        fi
        echo -e "${GREEN}✓ Stopped systemd-networkd services${NC}"
        
        echo -e "${BLUE}Disabling systemd-networkd services...${NC}"
        systemctl disable systemd-networkd.service 2>/dev/null || true
        systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true
        systemctl disable systemd-networkd.socket 2>/dev/null || true
        echo -e "${GREEN}✓ Disabled systemd-networkd services${NC}"
        
        echo -e "${BLUE}Masking systemd-networkd...${NC}"
        systemctl mask systemd-networkd.service 2>/dev/null || true
        echo -e "${GREEN}✓ Masked systemd-networkd${NC}"
        echo ""
        
        echo -e "${GREEN}================================================${NC}"
        echo -e "${GREEN}✓ Successfully switched to NetworkManager${NC}"
        echo -e "${GREEN}================================================${NC}"
        echo ""
        echo "To verify: systemctl status NetworkManager"
        echo "To manage networks: nmtui or nmcli"
        echo "To switch back: $0 --to-networkd"
    else
        echo -e "${RED}Error applying configuration!${NC}"
        echo "Manual intervention may be required."
        exit 1
    fi
}

# Show current status with detailed analysis
show_status() {
    echo ""
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}  Current Network Configuration${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo ""
    
    current_renderer=$(detect_current_renderer)
    echo -e "Current renderer: ${GREEN}$current_renderer${NC}"
    echo ""
    
    echo -e "${BLUE}Active netplan files:${NC}"
    if ls "$NETPLAN_DIR"/*.yaml &>/dev/null; then
        for yaml in "$NETPLAN_DIR"/*.yaml; do
            [[ "$yaml" == *.yaml.bak ]] && continue
            echo "  - $(basename "$yaml")"
        done
    else
        echo "  None found"
    fi
    echo ""
    
    echo -e "${BLUE}Deactivated netplan files:${NC}"
    if ls "$NETPLAN_DIR"/*.yaml.bak* &>/dev/null; then
        for yaml in "$NETPLAN_DIR"/*.yaml.bak*; do
            echo "  - $(basename "$yaml")"
        done
    else
        echo "  None found"
    fi
    echo ""
    
    analysis=$(detect_and_classify_interfaces | tail -1)
    echo ""
    
    get_renderer_recommendation "$analysis"
    echo ""
    
    echo -e "${BLUE}Service status:${NC}"
    if systemctl is-active NetworkManager.service &>/dev/null; then
        echo -e "  NetworkManager: ${GREEN}active${NC}"
    else
        echo -e "  NetworkManager: ${RED}inactive${NC}"
    fi
    
    if systemctl is-active systemd-networkd.service &>/dev/null; then
        echo -e "  systemd-networkd: ${GREEN}active${NC}"
    else
        echo -e "  systemd-networkd: ${RED}inactive${NC}"
    fi
    echo ""
}

# Show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Network Renderer Switcher for Netplan
Intelligently switches between NetworkManager and systemd-networkd

Options:
  --status              Show current configuration and recommendations
  --to-networkd         Switch to systemd-networkd renderer
  --to-nm               Switch to NetworkManager renderer
  -h, --help            Show this help message

Features:
  • Intelligent interface detection (WiFi, Ethernet, Virtual)
  • Automatic renderer recommendations
  • Safe exclusion of virtual interfaces from networkd config
  • Automatic file protection via .bak extension

Examples:
  $0 --status           # Analyze and get recommendations
  $0 --to-networkd      # Switch to systemd-networkd (servers)
  $0 --to-nm            # Switch to NetworkManager (WiFi/desktop)

EOF
}

# Main menu
show_menu() {
    while true; do
        clear
        current_renderer=$(detect_current_renderer)
        
        echo -e "${BLUE}============================================================${NC}"
        echo -e "${BLUE}          NETPLAN RENDERER SWITCHER${NC}"
        echo -e "${BLUE}        Intelligent Network Configuration Tool${NC}"
        echo -e "${BLUE}============================================================${NC}"
        echo ""
        echo -e "Current renderer: ${GREEN}$current_renderer${NC}"
        echo ""
        echo "  1) Show detailed status & recommendations"
        echo "  2) Switch to systemd-networkd"
        echo "  3) Switch to NetworkManager"
        echo "  4) Exit"
        echo ""
        echo -n "Select an option [1-4]: "
        read -r option
        
        case $option in
            1)
                show_status
                read -p "Press Enter to continue..."
                ;;
            2)
                switch_to_networkd
                read -p "Press Enter to continue..."
                ;;
            3)
                switch_to_nm
                read -p "Press Enter to continue..."
                ;;
            4)
                echo ""
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo ""
                echo -e "${RED}Invalid option${NC}"
                sleep 2
                ;;
        esac
    done
}

# Main execution
check_dependencies

if [ $# -eq 0 ]; then
    show_menu
else
    case "$1" in
        --status)
            show_status
            ;;
        --to-networkd)
            switch_to_networkd
            ;;
        --to-nm)
            switch_to_nm
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo -e "${RED}Error: Invalid option '$1'${NC}"
            echo ""
            show_help
            exit 1
            ;;
    esac
fi
