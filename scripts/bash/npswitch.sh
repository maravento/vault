#!/bin/bash
# maravento.com
#
################################################################################
# npswitch.sh -- Netplan Renderer Switcher
#
# Safely switches between NetworkManager and systemd-networkd on
# Ubuntu/Debian systems using Netplan. Detects your interfaces (WiFi,
# Ethernet, virtual) and recommends the best renderer.
#
# USAGE:
# sudo ./npswitch.sh # interactive menu
# sudo ./npswitch.sh --status # show current config
# sudo ./npswitch.sh --to-networkd # switch to systemd-networkd
# sudo ./npswitch.sh --to-nm # switch to NetworkManager
# sudo ./npswitch.sh --help # show help
#
# NOTES:
# May temporarily disconnect your network -- use with caution over SSH
# YAML files are backed up (.bak) before any change
# Virtual interfaces (docker0, virbr0, etc.) are excluded
################################################################################

set -uo pipefail

# root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root -- abort"
    exit 1
fi

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock")
exec 200>"$script_lock"
if ! flock -n 200; then
    echo "ERROR: script $(basename "$0") is already running -- abort"
    exit 1
fi

# dependencies
for dep in netplan.io iproute2 systemd network-manager util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "ERROR: dependency '$dep' is not installed -- abort" >&2
        exit 1
    fi
done

# Colors
color_red='\033[0;31m'
color_green='\033[0;32m'
color_yellow='\033[1;33m'
color_blue='\033[0;34m'
color_cyan='\033[0;36m'
color_magenta='\033[0;35m'
color_reset='\033[0m' # No Color

# Paths
netplan_dir="/etc/netplan"
networkd_file="$netplan_dir/00-networkd.yaml"
nm_file="$netplan_dir/99-networkmanager.yaml"

# Detect current renderer
detect_current_renderer() {
    local renderer="unknown"

    # Check all yaml files
    for yaml_file in "$netplan_dir"/*.yaml; do
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

    echo -e "${color_blue}Analyzing network interfaces...${color_reset}" >&2

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

        local icon color state_display="${color_green}UP/Active${color_reset}"

        case "$type" in
            wifi) icon=" " color="$color_magenta" ;;
            ethernet) icon=" " color="$color_green" ;;
            virtual) icon=" " color="$color_cyan" ;;
            bridge) icon=" " color="$color_yellow" ;;
            bond) icon=" " color="$color_blue" ;;
            *) icon=" " color="$color_reset" ;;
        esac

        printf "${color}${icon} %-18s${color_reset} [%-10s] %-14s %s\n" \
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

    echo -e "${color_blue}----------------------------------------------${color_reset}"
    echo -e "${color_blue} RENDERER RECOMMENDATION${color_reset}"
    echo -e "${color_blue}----------------------------------------------${color_reset}"
    echo ""

    if [ "$active_wifi" == "1" ]; then
        echo -e "${color_yellow} Active WiFi detected${color_reset}"
        echo ""
        echo -e "${color_green} Recommended: NetworkManager${color_reset}"
        echo "Reasons:"
        echo "* Easy WiFi management (nmtui/nmcli/GUI)"
        echo "* Automatic connection switching"
        echo "* Better laptop/workstation support"
        echo ""
        echo -e "${color_red} NOT Recommended: systemd-networkd${color_reset}"
        echo "Limitations:"
        echo "* Requires manual wpa_supplicant configuration"
        echo "* No GUI for WiFi management"
        echo "* Harder to switch between networks"
        echo ""
        return 1 # Return 1 to indicate WiFi warning
    elif [ "$has_wifi" == "1" ] && [ "$active_wifi" == "0" ]; then
        echo -e "${color_yellow} WiFi interface present (but inactive)${color_reset}"
        echo ""
        echo -e "${color_cyan} Either renderer works, but:${color_reset}"
        echo ""
        echo -e " ${color_green}NetworkManager:${color_reset} Better if you plan to use WiFi"
        echo -e " ${color_green}systemd-networkd:${color_reset} OK for server with Ethernet only"
        echo ""
        return 0
    else
        echo -e "${color_green} Server profile detected (Ethernet only)${color_reset}"
        echo ""
        echo -e "${color_green} Recommended: systemd-networkd${color_reset}"
        echo "Benefits:"
        echo "* Faster and lighter (less RAM)"
        echo "* Better for servers"
        echo "* Excellent performance"
        echo "* Native systemd integration"
        echo ""
        echo -e "${color_cyan} Alternative: NetworkManager${color_reset}"
        echo "* More features (may not need them)"
        echo "* GUI management (nmtui)"
        echo "* Better for mixed environments"
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
    echo -e "${color_blue}Deactivating all existing YAML files...${color_reset}"
    local count
    count=$(find "$netplan_dir" -maxdepth 1 -type f -name '*.yaml' -not -name '*.yaml.bak' -print | wc -l)
    if [ "$count" -eq 0 ]; then
        echo -e "${color_yellow} No active YAML files found${color_reset}"
    else
        find "$netplan_dir" -maxdepth 1 -type f -name '*.yaml' -not -name '*.yaml.bak' -exec mv -- {} {}.bak \; 2>/dev/null
        echo -e "${color_green} Deactivated $count YAML file(s)${color_reset}"
    fi
    echo ""
}

# Restore all backup YAML files
restore_all_yaml_files() {
    echo -e "${color_blue}Restoring all previous YAML files...${color_reset}"
    local count
    count=$(find "$netplan_dir" -maxdepth 1 -type f -name '*.yaml.bak' -print | wc -l)
    if [ "$count" -eq 0 ]; then
        echo -e "${color_yellow} No backup YAML files found to restore${color_reset}"
    else
        find "$netplan_dir" -maxdepth 1 -type f -name '*.yaml.bak' -exec sh -c 'mv "$1" "${1%.bak}"' sh {} \; 2>/dev/null
        echo -e "${color_green} Restored $count YAML file(s)${color_reset}"
    fi
    echo ""
}

# Generate networkd configuration
generate_networkd_config() {
    local interfaces=("$@")

    if [ ${#interfaces[@]} -eq 0 ]; then
        echo -e "${color_red}Error: No suitable interfaces for systemd-networkd${color_reset}"
        echo "Only Ethernet interfaces in UP state are included."
        exit 1
    fi

    cat > "$networkd_file" <<EOF
# Generated by netplan-renderer-switcher
# $(date '+%Y-%m-%d %H:%M:%S')
# Only physical Ethernet interfaces included
# Virtual interfaces (docker, virbr, veth) managed separately
network:
  version: 2
  renderer: networkd
  ethernets:
EOF

    for iface in "${interfaces[@]}"; do
        echo "    $iface:" >> "$networkd_file"
        echo "      dhcp4: true" >> "$networkd_file"
        echo "      dhcp6: false" >> "$networkd_file"
    done

    chown root:root "$networkd_file"
    chmod 600 "$networkd_file"

    echo -e "${color_green} Created: $networkd_file${color_reset}"
}

# Switch to networkd
switch_to_networkd() {
    echo ""
    echo -e "${color_yellow}================================================${color_reset}"
    echo -e "${color_yellow} Switching to systemd-networkd${color_reset}"
    echo -e "${color_yellow}================================================${color_reset}"
    echo ""

    if ! systemctl list-unit-files | grep -q "systemd-networkd.service"; then
        echo -e "${color_red}Error: systemd-networkd is not installed${color_reset}"
        exit 1
    fi

    analysis=$(detect_and_classify_interfaces)
    echo ""

    rec_result=0
    get_renderer_recommendation "$analysis" || rec_result=$?
    echo ""

    if [ $rec_result -eq 1 ]; then
        echo -e "${color_red}----------------------------------------------${color_reset}"
        echo -e "${color_red} STRONG WARNING${color_reset}"
        echo -e "${color_red}----------------------------------------------${color_reset}"
        echo ""
        echo "You have ACTIVE WiFi connections!"
        echo "Switching to systemd-networkd will:"
        echo ""
        echo "${color_red} ${color_reset} Disconnect all WiFi connections"
        echo "${color_red} ${color_reset} Require manual wpa_supplicant setup"
        echo "${color_red} ${color_reset} Remove GUI management"
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
        echo -e "${color_red}Error: No suitable Ethernet interfaces found${color_reset}"
        echo "systemd-networkd configuration requires at least one UP Ethernet interface."
        exit 1
    fi

    echo -e "${color_green}Interfaces to be configured with networkd:${color_reset}"
    for iface in "${suitable_ifaces[@]}"; do
        info=$(get_interface_info "$iface")
        ip_addr=$(echo "$info" | cut -d'|' -f1)
        echo "$iface: ${ip_addr:-no IP}"
    done
    echo ""

    echo -e "${color_yellow}NOTE: Virtual interfaces (docker0, virbr0, veth*, br-*) will NOT be included.${color_reset}"
    echo -e "${color_yellow}They are managed by their respective services.${color_reset}"
    echo ""

    echo -e "${color_yellow}----------------------------------------------${color_reset}"
    echo "This will:"
    echo "1. Deactivate ALL existing YAML files (rename to .bak)"
    echo "2. Create new 00-networkd.yaml config"
    echo "3. Disable NetworkManager"
    echo "4. Enable systemd-networkd"
    echo "5. Apply changes (may disconnect SSH!)"
    echo ""
    read -p "Continue? (y/n): " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi

    deactivate_all_yaml_files

    echo -e "${color_blue}Generating networkd configuration...${color_reset}"
    generate_networkd_config "${suitable_ifaces[@]}"

    echo ""
    echo -e "${color_blue}Generated configuration:${color_reset}"
    cat "$networkd_file"
    echo ""

    echo -e "${color_blue}Validating configuration...${color_reset}"
    if netplan generate 2>&1 | grep -qi error; then
        echo -e "${color_red}Error: Configuration validation failed${color_reset}"
        echo "Restoring backup..."
        restore_all_yaml_files
        rm -f "$networkd_file"
        exit 1
    fi
    echo -e "${color_green} Configuration is valid${color_reset}"
    echo ""

    echo -e "${color_blue}Unmasking NetworkManager (if masked)...${color_reset}"
    systemctl unmask NetworkManager.service 2>/dev/null || true

    echo -e "${color_blue}Stopping and disabling NetworkManager...${color_reset}"
    systemctl stop NetworkManager.service 2>/dev/null || true
    systemctl disable NetworkManager.service 2>/dev/null || true
    echo -e "${color_green} NetworkManager stopped${color_reset}"

    echo -e "${color_blue}Enabling systemd-networkd...${color_reset}"
    systemctl unmask systemd-networkd.service 2>/dev/null || true
    systemctl enable systemd-networkd.service 2>/dev/null || true
    systemctl start systemd-networkd.service 2>/dev/null || true
    echo -e "${color_green} systemd-networkd started${color_reset}"

    echo ""
    echo -e "${color_blue}Applying netplan configuration...${color_reset}"
    if netplan apply; then
        echo ""
        echo -e "${color_green}================================================${color_reset}"
        echo -e "${color_green} Successfully switched to systemd-networkd${color_reset}"
        echo -e "${color_green}================================================${color_reset}"
        echo ""
        echo "To verify: systemctl status systemd-networkd"
        echo "To rollback: $0 --to-nm"
    else
        echo -e "${color_red}Error applying configuration!${color_reset}"
        echo "Attempting rollback..."
        restore_all_yaml_files
        rm -f "$networkd_file"
        netplan apply
        exit 1
    fi
}

# Switch to NetworkManager
switch_to_nm() {
    echo ""
    echo -e "${color_yellow}================================================${color_reset}"
    echo -e "${color_yellow} Switching to NetworkManager${color_reset}"
    echo -e "${color_yellow}================================================${color_reset}"
    echo ""

    analysis=$(detect_and_classify_interfaces)
    echo ""

    get_renderer_recommendation "$analysis" || true
    echo ""

    echo -e "${color_yellow}----------------------------------------------${color_reset}"
    echo "This will:"
    echo "1. Remove 00-networkd.yaml file"
    echo "2. Restore ALL previous YAML files (from .bak)"
    echo "3. Force renderer to NetworkManager"
    echo "4. Disable systemd-networkd"
    echo "5. Enable NetworkManager"
    echo "6. Apply changes (may disconnect SSH!)"
    echo ""
    read -p "Continue? (y/n): " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi

    echo -e "${color_blue}Removing networkd configuration file...${color_reset}"
    if [ -f "$networkd_file" ]; then
        rm -f "$networkd_file"
        echo -e "${color_green} Removed: $networkd_file${color_reset}"
    else
        echo -e "${color_yellow} File not found: $networkd_file${color_reset}"
    fi
    echo ""

    restore_all_yaml_files

    echo -e "${color_blue}Forcing all YAML files to use NetworkManager renderer...${color_reset}"
    cat > "$nm_file" <<EOF
# Generated by netplan-renderer-switcher
# $(date '+%Y-%m-%d %H:%M:%S')
# Highest-numbered file wins, so this sets the renderer for every other file
network:
  version: 2
  renderer: NetworkManager
EOF
    chown root:root "$nm_file"
    chmod 600 "$nm_file"
    echo -e "${color_green} Created: $nm_file${color_reset}"
    echo ""

    echo -e "${color_blue}Unmasking systemd-networkd temporarily (for netplan apply)...${color_reset}"
    systemctl unmask systemd-networkd.service 2>/dev/null || true
    systemctl unmask systemd-networkd.socket 2>/dev/null || true
    echo -e "${color_green} Unmasked systemd-networkd${color_reset}"
    echo ""

    echo -e "${color_blue}Unmasking NetworkManager (if masked)...${color_reset}"
    systemctl unmask NetworkManager.service 2>/dev/null || true

    echo -e "${color_blue}Enabling and starting NetworkManager...${color_reset}"
    systemctl enable NetworkManager.service 2>/dev/null || true
    systemctl start NetworkManager.service 2>/dev/null || true
    echo -e "${color_green} NetworkManager is running${color_reset}"
    echo ""

    echo -e "${color_blue}Applying netplan configuration...${color_reset}"
    if netplan apply; then
        echo ""
        echo -e "${color_green} Netplan configuration applied successfully${color_reset}"
        echo ""

        echo -e "${color_blue}Stopping systemd-networkd services...${color_reset}"
        systemctl stop systemd-networkd.socket 2>/dev/null || true
        systemctl stop systemd-networkd-wait-online.service 2>/dev/null || true
        systemctl stop systemd-networkd.service 2>/dev/null || true

        sleep 1
        if systemctl is-active --quiet systemd-networkd.service; then
            echo -e "${color_yellow} Force killing systemd-networkd...${color_reset}"
            systemctl kill systemd-networkd.service 2>/dev/null || true
            sleep 1
        fi
        echo -e "${color_green} Stopped systemd-networkd services${color_reset}"

        echo -e "${color_blue}Disabling systemd-networkd services...${color_reset}"
        systemctl disable systemd-networkd.service 2>/dev/null || true
        systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true
        systemctl disable systemd-networkd.socket 2>/dev/null || true
        echo -e "${color_green} Disabled systemd-networkd services${color_reset}"

        echo -e "${color_blue}Masking systemd-networkd...${color_reset}"
        systemctl mask systemd-networkd.service 2>/dev/null || true
        echo -e "${color_green} Masked systemd-networkd${color_reset}"
        echo ""

        echo -e "${color_green}================================================${color_reset}"
        echo -e "${color_green} Successfully switched to NetworkManager${color_reset}"
        echo -e "${color_green}================================================${color_reset}"
        echo ""
        echo "To verify: systemctl status NetworkManager"
        echo "To manage networks: nmtui or nmcli"
        echo "To switch back: $0 --to-networkd"
    else
        echo -e "${color_red}Error applying configuration!${color_reset}"
        echo "Manual intervention may be required."
        exit 1
    fi
}

# Show current status with detailed analysis
show_status() {
    echo ""
    echo -e "${color_blue}================================================${color_reset}"
    echo -e "${color_blue} Current Network Configuration${color_reset}"
    echo -e "${color_blue}================================================${color_reset}"
    echo ""

    current_renderer=$(detect_current_renderer)
    echo -e "Current renderer: ${color_green}$current_renderer${color_reset}"
    echo ""

    echo -e "${color_blue}Active netplan files:${color_reset}"
    if ls "$netplan_dir"/*.yaml &>/dev/null; then
        for yaml in "$netplan_dir"/*.yaml; do
            [[ "$yaml" == *.yaml.bak ]] && continue
            echo "- $(basename "$yaml")"
        done
    else
        echo "None found"
    fi
    echo ""

    echo -e "${color_blue}Deactivated netplan files:${color_reset}"
    if ls "$netplan_dir"/*.yaml.bak* &>/dev/null; then
        for yaml in "$netplan_dir"/*.yaml.bak*; do
            echo "- $(basename "$yaml")"
        done
    else
        echo "None found"
    fi
    echo ""

    analysis=$(detect_and_classify_interfaces)
    echo ""

    get_renderer_recommendation "$analysis" || true
    echo ""

    echo -e "${color_blue}Service status:${color_reset}"
    if systemctl is-active NetworkManager.service &>/dev/null; then
        echo -e " NetworkManager: ${color_green}active${color_reset}"
    else
        echo -e " NetworkManager: ${color_red}inactive${color_reset}"
    fi

    if systemctl is-active systemd-networkd.service &>/dev/null; then
        echo -e " systemd-networkd: ${color_green}active${color_reset}"
    else
        echo -e " systemd-networkd: ${color_red}inactive${color_reset}"
    fi
    echo ""
}

# Show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Switches between NetworkManager and systemd-networkd on Netplan systems.

Options:
  --status Show current configuration and recommendations
  --to-networkd Switch to systemd-networkd
  --to-nm Switch to NetworkManager
  -h, --help Show this help message

EOF
}

# Main menu
show_menu() {
    while true; do
        clear
        current_renderer=$(detect_current_renderer)

        echo -e "${color_blue}Netplan Renderer Switcher${color_reset} -- current: ${color_green}$current_renderer${color_reset}"
        echo ""
        echo "1) Status"
        echo "2) Switch to systemd-networkd"
        echo "3) Switch to NetworkManager"
        echo "4) Exit"
        echo ""
        echo -n "Select [1-4]: "
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
                echo -e "${color_red}Invalid option${color_reset}"
                sleep 2
                ;;
        esac
    done
}

# Main execution
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
            echo -e "${color_red}Error: Invalid option '$1'${color_reset}"
            echo ""
            show_help
            exit 1
            ;;
    esac
fi
