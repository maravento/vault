#!/bin/bash
# maravento.com
#
################################################################################
#
# npswitch -- NetworkManager / systemd-networkd renderer switch
# FILE: npswitch.sh
#
# DESCRIPTION:
# Switches between NetworkManager and systemd-networkd on Netplan-based
# systems. Detects network interfaces and recommends the best renderer.
#
# USAGE:
# COMMAND                              ACTION
# sudo bash npswitch.sh                Interactive menu
# sudo bash npswitch.sh --status       Show status
# sudo bash npswitch.sh --to-networkd  Switch to networkd
# sudo bash npswitch.sh --to-nm        Switch to NetworkManager
# sudo bash npswitch.sh -h             Show usage
# sudo bash npswitch.sh --help         Show usage
#
# Without arguments, shows an interactive menu.
#
# WARNING:
# May temporarily disconnect the network -- use with caution over SSH
# Netplan YAML files under /etc/netplan are backed up (.npswitch.bak) before changes
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# awk is a command, not a package: check it before its first use
command -v awk >/dev/null 2>&1 || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: awk not found -abort" >&2; exit 1; }

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
for dep in netplan.io iproute2 systemd network-manager util-linux libc-bin coreutils grep sed; do
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

# Paths
netplan_dir="/etc/netplan"
networkd_file="$netplan_dir/00-networkd.yaml"
nm_file="$netplan_dir/99-networkmanager.yaml"

# validation - one variable per thing validated; use directly with =~
UH_IPV4='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'
UH_CIDR='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])/(3[0-2]|[12][0-9]|[0-9])$'

# Current IPv4 configuration of each interface, read from NetworkManager
declare -A ipv4_mode=() ipv4_addresses=() ipv4_gateway=() ipv4_dns=()

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

# Detect current renderer
detect_current_renderer() {
    local renderer="unknown" value

    # Ask netplan instead of parsing the yaml. It merges every file under
    # /etc/netplan and resolves the precedence itself, and the dotted key
    # returns the global renderer only, never a per-device one. An unset
    # key returns 'null' and a missing config fails, both left as unknown.
    value=$(netplan get renderer 2>/dev/null)
    case "$value" in
        networkd|NetworkManager) renderer="$value" ;;
    esac

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


    while IFS= read -r line; do
        iface=$(echo "$line" | awk '{print $1}' | sed 's/@.*//')
        link_state=$(echo "$line" | awk '{print $2}')

        [[ "$iface" == "lo" ]] && continue
        [[ "$link_state" != "UP" ]] && continue

        ip_addr=$(ip -4 addr show dev "$iface" scope global 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
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

        printf ' %-18s [%-10s] %-14s %s\n' \
            "$iface" "$type" "UP/Active" "$ip_addr" >&2

    done < <(list_ifaces)

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

    echo -e "----------------------------------------------"
    echo -e " RENDERER RECOMMENDATION"
    echo -e "----------------------------------------------"
    echo ""

    if [ "$active_wifi" == "1" ]; then
        echo -e " Active WiFi detected"
        echo ""
        echo -e " Recommended: NetworkManager"
        echo "Reasons:"
        echo "* Easy WiFi management (nmtui/nmcli/GUI)"
        echo "* Automatic connection switching"
        echo "* Better laptop/workstation support"
        echo ""
        echo -e " NOT Recommended: systemd-networkd"
        echo "Limitations:"
        echo "* Requires manual wpa_supplicant configuration"
        echo "* No GUI for WiFi management"
        echo "* Harder to switch between networks"
        echo ""
        return 1 # Return 1 to indicate WiFi warning
    elif [ "$has_wifi" == "1" ] && [ "$active_wifi" == "0" ]; then
        echo -e " WiFi interface present (but inactive)"
        echo ""
        echo -e " Either renderer works, but:"
        echo ""
        echo -e " NetworkManager: Better if you plan to use WiFi"
        echo -e " systemd-networkd: OK for server with Ethernet only"
        echo ""
        return 0
    else
        echo -e " Server profile detected (Ethernet only)"
        echo ""
        echo -e " Recommended: systemd-networkd"
        echo "Benefits:"
        echo "* Faster and lighter (less RAM)"
        echo "* Better for servers"
        echo "* Excellent performance"
        echo "* Native systemd integration"
        echo ""
        echo -e " Alternative: NetworkManager"
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
    done < <(list_ifaces)
}

# IPV4 CONFIGURATION
# Read the IPv4 method, addresses, gateway and DNS of an interface from
# NetworkManager, so a static address survives the switch to networkd
read_ipv4_config() {
    local iface="$1" uuid method value item
    uuid=$(nmcli -g GENERAL.CON-UUID device show "$iface" 2>/dev/null) || return 1
    [ -n "$uuid" ] && [ "$uuid" != "--" ] || return 1
    method=$(nmcli -g ipv4.method connection show "$uuid" 2>/dev/null) || return 1
    case "$method" in
        auto)
            ipv4_mode[$iface]=dhcp
            ;;
        manual)
            ipv4_mode[$iface]=static
            value=$(nmcli -g ipv4.addresses connection show "$uuid" 2>/dev/null) || return 1
            value="${value// /}"
            [ -n "$value" ] || return 1
            for item in ${value//,/ }; do
                [[ "$item" =~ $UH_CIDR ]] || return 1
            done
            ipv4_addresses[$iface]="${value//,/, }"
            value=$(nmcli -g ipv4.gateway connection show "$uuid" 2>/dev/null) || return 1
            value="${value// /}"
            if [ -n "$value" ] && [ "$value" != "--" ]; then
                [[ "$value" =~ $UH_IPV4 ]] || return 1
                ipv4_gateway[$iface]="$value"
            fi
            value=$(nmcli -g ipv4.dns connection show "$uuid" 2>/dev/null) || return 1
            value="${value// /}"
            if [ -n "$value" ] && [ "$value" != "--" ]; then
                for item in ${value//,/ }; do
                    [[ "$item" =~ $UH_IPV4 ]] || return 1
                done
                ipv4_dns[$iface]="${value//,/, }"
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

# Deactivate all YAML files (rename with .npswitch.bak extension)
deactivate_all_yaml_files() {
    local count
    count=$(find "$netplan_dir" -maxdepth 1 -type f -name '*.yaml' -not -name '*.yaml.bak' -print | wc -l)
    if [ "$count" -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: no active YAML files -skip"
    else
        if ! find "$netplan_dir" -maxdepth 1 -type f -name '*.yaml' -not -name '*.yaml.bak' \
            -exec sh -c 'for f in "$@"; do mv -- "$f" "$f.npswitch.bak" || exit 1; done' sh {} + 2>/dev/null; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot deactivate YAML files -abort" >&2
            exit 1
        fi
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: deactivated $count YAML file(s)"
    fi
}

# Restore all backup YAML files
restore_all_yaml_files() {
    local count
    count=$(find "$netplan_dir" -maxdepth 1 -type f -name '*.yaml.npswitch.bak' -print | wc -l)
    if [ "$count" -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: no YAML backups to restore -skip"
    else
        if ! find "$netplan_dir" -maxdepth 1 -type f -name '*.yaml.npswitch.bak' \
            -exec sh -c 'rc=0; for f in "$@"; do mv -- "$f" "${f%.npswitch.bak}" || rc=1; done; exit $rc' sh {} + 2>/dev/null; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: some YAML files not restored -alert"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: restored $count YAML file(s)"
        fi
    fi
}

# Generate networkd configuration
generate_networkd_config() {
    local interfaces=("$@")

    if [ ${#interfaces[@]} -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no Ethernet interface UP for systemd-networkd -abort" >&2
        exit 1
    fi

    if ! cat > "$networkd_file" <<EOF
# Generated by netplan-renderer-switcher
# $(date '+%Y-%m-%d %H:%M:%S')
# Only physical Ethernet interfaces included
# Virtual interfaces (docker, virbr, veth) managed separately
network:
  version: 2
  renderer: networkd
  ethernets:
EOF
    then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot write $networkd_file -abort" >&2
        exit 1
    fi

    for iface in "${interfaces[@]}"; do
        if [ "${ipv4_mode[$iface]:-dhcp}" = static ]; then
            {
                echo "    $iface:"
                echo "      dhcp4: false"
                echo "      dhcp6: false"
                echo "      addresses: [${ipv4_addresses[$iface]}]"
                if [ -n "${ipv4_gateway[$iface]:-}" ]; then
                    echo "      routes:"
                    echo "        - to: default"
                    echo "          via: ${ipv4_gateway[$iface]}"
                fi
                if [ -n "${ipv4_dns[$iface]:-}" ]; then
                    echo "      nameservers:"
                    echo "        addresses: [${ipv4_dns[$iface]}]"
                fi
            } >> "$networkd_file"
        else
            {
                echo "    $iface:"
                echo "      dhcp4: true"
                echo "      dhcp6: false"
            } >> "$networkd_file"
        fi || {
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot write $networkd_file -abort" >&2
            exit 1
        }
    done

    if ! chown root:root "$networkd_file"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot set owner/group: $(basename "$networkd_file") -abort" >&2
        exit 1
    fi
    if ! chmod 600 "$networkd_file"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot set $(basename "$networkd_file") permissions -abort" >&2
        exit 1
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: created $networkd_file"
}

# Put a unit back to its saved enabled/active state
restore_unit() {
    local unit="$1" active="$2" enabled="$3"
    if [ "$active" = active ]; then
        systemctl start "$unit" 2>/dev/null
    else
        systemctl stop "$unit" 2>/dev/null
    fi
    case "$enabled" in
        enabled) systemctl enable "$unit" 2>/dev/null ;;
        disabled) systemctl disable "$unit" 2>/dev/null ;;
        masked) systemctl disable "$unit" 2>/dev/null; systemctl mask "$unit" 2>/dev/null ;;
    esac
    return 0
}

# Switch to networkd
switch_to_networkd() {
    echo ""
    echo -e "================================================"
    echo -e " Switching to systemd-networkd"
    echo -e "================================================"
    echo ""

    if ! systemctl list-unit-files | grep -q "systemd-networkd.service"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: systemd-networkd not installed -abort" >&2
        exit 1
    fi

    analysis=$(detect_and_classify_interfaces)
    echo ""

    rec_result=0
    get_renderer_recommendation "$analysis" || rec_result=$?
    echo ""

    if [ $rec_result -eq 1 ]; then
        echo -e "----------------------------------------------"
        echo -e " STRONG WARNING"
        echo -e "----------------------------------------------"
        echo ""
        echo "You have ACTIVE WiFi connections!"
        echo "Switching to systemd-networkd will:"
        echo ""
        echo -e "  Disconnect all WiFi connections"
        echo -e "  Require manual wpa_supplicant setup"
        echo -e "  Remove GUI management"
        echo ""
        echo "This is NOT recommended for systems with WiFi"
        echo ""
        read -p "Are you ABSOLUTELY SURE? (type 'I UNDERSTAND'): " confirm

        if [ "$confirm" != "I UNDERSTAND" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: aborted by user"
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: npswitch done"
            exit 0
        fi
    fi

    declare -a suitable_ifaces
    get_networkd_interfaces suitable_ifaces

    if [ ${#suitable_ifaces[@]} -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no Ethernet interface UP -abort" >&2
        exit 1
    fi

    for iface in "${suitable_ifaces[@]}"; do
        if ! read_ipv4_config "$iface"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: [1/2] $iface: cannot read IPv4 configuration" >&2
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: [2/2] switch aborted, network unchanged -abort" >&2
            exit 1
        fi
    done

    echo -e "Interfaces to be configured with networkd:"
    for iface in "${suitable_ifaces[@]}"; do
        if [ "${ipv4_mode[$iface]}" = static ]; then
            echo "$iface: ${ipv4_addresses[$iface]} (static)"
        else
            echo "$iface: DHCP (dynamic)"
        fi
    done
    echo ""

    echo -e "NOTE: Virtual interfaces (docker0, virbr0, veth*, br-*) will NOT be included."
    echo -e "They are managed by their respective services."
    echo ""

    echo -e "----------------------------------------------"
    echo "This will:"
    echo "1. Deactivate ALL existing YAML files (rename to .npswitch.bak)"
    echo "2. Create new 00-networkd.yaml config"
    echo "3. Disable NetworkManager"
    echo "4. Enable systemd-networkd"
    echo "5. Apply changes (may disconnect SSH!)"
    echo ""
    read -p "Continue? (y/n): " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: aborted by user"
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: npswitch done"
        exit 0
    fi

    deactivate_all_yaml_files

    generate_networkd_config "${suitable_ifaces[@]}"

    echo ""
    echo -e "Generated configuration:"
    cat "$networkd_file"
    echo ""

    if ! netplan generate >/dev/null 2>&1; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: [1/2] configuration not valid" >&2
        restore_all_yaml_files
        rm -f "$networkd_file"
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: [2/2] backup restored -abort" >&2
        exit 1
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: configuration valid"

    # Saved for the rollback below
    nm_active=$(systemctl is-active NetworkManager.service 2>/dev/null)
    nm_enabled=$(systemctl is-enabled NetworkManager.service 2>/dev/null)
    nd_active=$(systemctl is-active systemd-networkd.service 2>/dev/null)
    nd_enabled=$(systemctl is-enabled systemd-networkd.service 2>/dev/null)

    systemctl unmask NetworkManager.service 2>/dev/null || true
    systemctl stop NetworkManager.service 2>/dev/null || true
    systemctl disable NetworkManager.service 2>/dev/null || true
    if systemctl is-active --quiet NetworkManager.service \
        || systemctl is-enabled --quiet NetworkManager.service; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: NetworkManager still active or enabled -alert"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: NetworkManager stopped and disabled"
    fi

    systemctl unmask systemd-networkd.service 2>/dev/null || true
    systemctl enable systemd-networkd.service 2>/dev/null || true
    systemctl start systemd-networkd.service 2>/dev/null || true
    if systemctl is-active --quiet systemd-networkd.service; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: systemd-networkd enabled and started"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: systemd-networkd not started -alert"
    fi

    if netplan apply; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: switched to systemd-networkd"
        echo "To verify: systemctl status systemd-networkd"
        echo "To rollback: $0 --to-nm"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: [1/2] cannot apply configuration" >&2
        restore_all_yaml_files
        rm -f "$networkd_file"
        restore_unit systemd-networkd.service "$nd_active" "$nd_enabled"
        restore_unit NetworkManager.service "$nm_active" "$nm_enabled"
        netplan apply
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: [2/2] previous network restored -abort" >&2
        exit 1
    fi
}

# Switch to NetworkManager
switch_to_nm() {
    echo ""
    echo -e "================================================"
    echo -e " Switching to NetworkManager"
    echo -e "================================================"
    echo ""

    analysis=$(detect_and_classify_interfaces)
    echo ""

    get_renderer_recommendation "$analysis" || true
    echo ""

    echo -e "----------------------------------------------"
    echo "This will:"
    echo "1. Remove 00-networkd.yaml file"
    echo "2. Restore ALL previous YAML files (from .npswitch.bak)"
    echo "3. Force renderer to NetworkManager"
    echo "4. Disable systemd-networkd"
    echo "5. Enable NetworkManager"
    echo "6. Apply changes (may disconnect SSH!)"
    echo ""
    read -p "Continue? (y/n): " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: aborted by user"
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: npswitch done"
        exit 0
    fi

    if [ -f "$networkd_file" ]; then
        if ! rm -f "$networkd_file"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot remove $networkd_file -abort" >&2
            exit 1
        fi
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: removed $networkd_file"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: $networkd_file not found -skip"
    fi

    restore_all_yaml_files

    if ! cat > "$nm_file" <<EOF
# Generated by netplan-renderer-switcher
# $(date '+%Y-%m-%d %H:%M:%S')
# Highest-numbered file wins, so this sets the renderer for every other file
network:
  version: 2
  renderer: NetworkManager
EOF
    then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot write $nm_file -abort" >&2
        exit 1
    fi
    if ! chown root:root "$nm_file"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot set owner/group: $(basename "$nm_file") -abort" >&2
        exit 1
    fi
    if ! chmod 600 "$nm_file"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot set $(basename "$nm_file") permissions -abort" >&2
        exit 1
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: created $nm_file"

    systemctl unmask systemd-networkd.service 2>/dev/null || true
    systemctl unmask systemd-networkd.socket 2>/dev/null || true
    if [ "$(systemctl is-enabled systemd-networkd.service 2>/dev/null)" = masked ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: systemd-networkd still masked -alert"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: systemd-networkd unmasked for netplan apply"
    fi

    systemctl unmask NetworkManager.service 2>/dev/null || true
    systemctl enable NetworkManager.service 2>/dev/null || true
    systemctl start NetworkManager.service 2>/dev/null || true
    if systemctl is-active --quiet NetworkManager.service; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: NetworkManager enabled and started"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: NetworkManager not started -alert"
    fi

    if netplan apply; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: netplan configuration applied"

        systemctl stop systemd-networkd.socket 2>/dev/null || true
        systemctl stop systemd-networkd-wait-online.service 2>/dev/null || true
        systemctl stop systemd-networkd.service 2>/dev/null || true

        sleep 1
        if systemctl is-active --quiet systemd-networkd.service; then
            systemctl kill systemd-networkd.service 2>/dev/null || true
            sleep 1
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: systemd-networkd killed"
        fi
        if systemctl is-active --quiet systemd-networkd.service; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: systemd-networkd still active -alert"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: systemd-networkd stopped"
        fi

        systemctl disable systemd-networkd.service 2>/dev/null || true
        systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true
        systemctl disable systemd-networkd.socket 2>/dev/null || true
        systemctl mask systemd-networkd.service 2>/dev/null || true
        if [ "$(systemctl is-enabled systemd-networkd.service 2>/dev/null)" = masked ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: systemd-networkd disabled and masked"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: systemd-networkd not masked -alert"
        fi

        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: switched to NetworkManager"
        echo "To verify: systemctl status NetworkManager"
        echo "To manage networks: nmtui or nmcli"
        echo "To switch back: $0 --to-networkd"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot apply configuration; fix it manually -abort" >&2
        exit 1
    fi
}

# Show current status with detailed analysis
show_status() {
    echo ""
    echo -e "================================================"
    echo -e " Current Network Configuration"
    echo -e "================================================"
    echo ""

    current_renderer=$(detect_current_renderer)
    echo -e "Current renderer: $current_renderer"
    echo ""

    echo -e "Active netplan files:"
    if ls "$netplan_dir"/*.yaml &>/dev/null; then
        for yaml in "$netplan_dir"/*.yaml; do
            [[ "$yaml" == *.yaml.bak ]] && continue
            echo "- $(basename "$yaml")"
        done
    else
        echo "None found"
    fi
    echo ""

    echo -e "Deactivated netplan files:"
    if ls "$netplan_dir"/*.yaml.npswitch.bak &>/dev/null; then
        for yaml in "$netplan_dir"/*.yaml.npswitch.bak; do
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

    echo -e "Service status:"
    if systemctl is-active NetworkManager.service &>/dev/null; then
        echo -e " NetworkManager: active"
    else
        echo -e " NetworkManager: inactive"
    fi

    if systemctl is-active systemd-networkd.service &>/dev/null; then
        echo -e " systemd-networkd: active"
    else
        echo -e " systemd-networkd: inactive"
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

        echo -e "Netplan Renderer Switcher -- current: $current_renderer"
        echo ""
        echo "1) Status"
        echo "2) Switch to systemd-networkd"
        echo "3) Switch to NetworkManager"
        echo "4) Exit"
        echo ""
        echo -n "Select [1-4] [4]: "
        read -r option || return 1
        option="${option:-4}"

        case $option in
            1)
                show_status
                break
                ;;
            2)
                switch_to_networkd
                break
                ;;
            3)
                switch_to_nm
                break
                ;;
            4)
                break
                ;;
            *)
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: invalid option -retry"
                sleep 2
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# ACTIONS
# ------------------------------------------------------------------------------

# Main execution
case "${1:-}" in
    -h|--help) show_help; exit 0 ;;
esac
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: npswitch start..."
if [ $# -eq 0 ]; then
    show_menu || exit 1
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
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: invalid option -abort" >&2
            echo ""
            show_help
            exit 1
            ;;
    esac
fi

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: npswitch done"
