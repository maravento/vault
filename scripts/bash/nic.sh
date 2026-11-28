#!/bin/bash
# maravento.com
#
################################################################################
#
# nic -- NIC checks, NetworkManager/systemd-networkd switch and Webmin module
# FILE: nic.sh
#
# USAGE:
# COMMAND                         ACTION
# sudo bash nic.sh                Interactive menu
# sudo bash nic.sh --check        Check link, IPv4 and DNS
# sudo bash nic.sh --status       Show interfaces and renderer status
# sudo bash nic.sh --networkd     Switch to systemd-networkd
# sudo bash nic.sh --nm           Switch to NetworkManager
# sudo bash nic.sh --install      Install the Webmin module
# sudo bash nic.sh --uninstall    Uninstall the Webmin module
# sudo bash nic.sh -h             Show usage
# sudo bash nic.sh --help         Show usage
#
# --install offers to install Webmin when it is missing.
#
# RECOMMENDATIONS:
# Prefer NetworkManager for Wi-Fi profiles or roaming.
# Prefer systemd-networkd for Ethernet-only hosts managed through Netplan.
# The --networkd action configures only Ethernet interfaces.
#
# WARNING:
# --networkd and --nm may temporarily disconnect the network.
#
# BACKUP:
# Before switching to systemd-networkd, --networkd renames existing
# /etc/netplan YAML files with the .npswitch.bak suffix.
# When switching to NetworkManager, --nm restores those backups if present.
#
################################################################################

set -uo pipefail

# root check
if [ "$(id -u)" != "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# logging
log() {
    if [[ "$1" == ERROR:* ]]; then
        printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    else
        printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
    fi
}

# prevent overlapping runs
lock_changes() {
    local script_lock="/var/lock/$(basename "$0" .sh).lock"
    if ! (umask 077; : >> "$script_lock") || ! exec 200>"$script_lock"; then
        log "ERROR: cannot open $(basename "$script_lock") -abort"
        return 1
    fi
    if ! flock -n 200; then
        log "ERROR: $(basename "$0") is already running -abort"
        return 1
    fi
}

# dependencies
require_commands() {
    local command_name
    for command_name in "$@"; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            log "ERROR: missing command '$command_name' -abort"
            return 1
        fi
    done
}

require_webmin() {
    if [ ! -d /usr/share/webmin ] && [ ! -d /etc/webmin ]; then
        log "ERROR: Webmin is not installed on this system -abort"
        return 1
    fi
}

install_dependencies() {
    local package
    local -a missing=()
    for package in "$@"; do
        if [[ "$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null)" != *"ok installed"* ]]; then
            missing+=("$package")
        fi
    done
    (( ${#missing[@]} )) || return 0

    require_commands ip awk getent apt-get sleep || return 1
    check_ipv4_interfaces
    check_internet
    if ! apt-get update -qq; then
        log "ERROR: cannot update package lists -abort"
        return 1
    fi
    for package in "${missing[@]}"; do
        log "INFO: installing $package"
        if ! apt-get install -y "$package" >/dev/null 2>&1; then
            log "ERROR: cannot install $package -abort"
            return 1
        fi
    done
}

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
            log "INFO: waiting for internet..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    log "ERROR: no internet connection -abort"
    exit 1
}

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

mod_name="netplanmgr"
if ! [[ "$mod_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: mod_name contains invalid characters -abort" >&2
    exit 1
fi
mod_dir="/usr/share/webmin/$mod_name"
etc_dir="/etc/webmin/$mod_name"

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

query() {
    timeout -k 1s 3s "$@" </dev/null 2>/dev/null
}

check_interfaces() {
    local list="${1:-}" max_attempts="${2:-24}" attempt=1
    local iface state ready states

    [ -n "$list" ] || list="$(list_ifaces | awk '{print $1}' | paste -sd,)"

    while (( attempt <= max_attempts )); do
        ready=0
        states=()
        for iface in ${list//,/ }; do
            if [ "$(ip -br link show "$iface" 2>/dev/null | awk '{print $2}')" = "UP" ]; then
                state="UP"
                ready=1
            else
                state="DOWN"
            fi
            states+=("$iface=$state")
        done
        if [ "$attempt" -eq 1 ] || [ "$ready" -eq 1 ]; then
            for state in "${states[@]}"; do
                log "INFO: interface: $state"
            done
        fi
        if [ "$ready" -eq 1 ]; then
            return 0
        fi
        log "INFO: waiting for interfaces ($attempt/$max_attempts)"
        attempt=$((attempt + 1))
        sleep 5
    done

    return 1
}

keyfile_has_ipv4() {
    local file="$1" uuid="$2" cidr="$3"
    local line section='' saved_uuid='' method='' value key found=1
    [[ -f "$file" && ! -L "$file" && -r "$file" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            \[*\]) section="$line" ;;
            *=*)
                key="${line%%=*}"
                value="${line#*=}"
                case "$section:$key" in
                    '[connection]:uuid') saved_uuid="$value" ;;
                    '[ipv4]:method') method="$value" ;;
                    '[ipv4]:address'*)
                        if [[ "$key" =~ ^address[0-9]+$ && "${value%%,*}" == "$cidr" ]]; then
                            found=0
                        fi
                        ;;
                esac
                ;;
        esac
    done < "$file"
    [[ "$saved_uuid" == "$uuid" && ( "$method" == manual || "$method" == auto ) ]] &&
        return "$found"
    return 1
}

netplan_has_ipv4() {
    local id="$1" cidr="$2" uuid="${3:-}"
    local kind path entries key value runtime
    [[ "$id" =~ ^[[:alnum:]_-]+$ ]] || return 1
    for runtime in /run/netplan/*.yaml; do
        [[ ! -e "$runtime" && ! -L "$runtime" ]] || return 1
    done
    for kind in ethernets wifis bridges bonds vlans; do
        path="$kind.$id"
        entries=$(query netplan get "$path.addresses") || entries=
        while read -r key value; do
            if [[ "$key" == - && "${value//\"/}" == "$cidr" ]]; then
                return 0
            fi
        done <<< "$entries"

        [[ -n "$uuid" ]] || continue
        value=$(query netplan get "$path.networkmanager.uuid") || continue
        [[ "${value//\"/}" == "$uuid" ]] || continue
        entries=$(query netplan get "$path.networkmanager.passthrough") || continue
        while read -r key value; do
            value="${value//\"/}"
            if [[ "$key" =~ ^ipv4[.]address[0-9]+:$ && "${value%%,*}" == "$cidr" ]]; then
                return 0
            fi
        done <<< "$entries"
    done
    return 1
}

has_persistent_ipv4() {
    local iface="$1" cidr="$2" uuid addresses profiles key file status
    local -a configured
    uuid=$(query nmcli -g GENERAL.CON-UUID device show "$iface") || uuid=
    if [[ -n "$uuid" && "$uuid" != -- ]]; then
        addresses=$(query nmcli -g ipv4.addresses connection show uuid "$uuid") || return 1
        IFS=, read -r -a configured <<< "${addresses// /}"
        for key in "${configured[@]}"; do
            [[ "$key" != "$cidr" ]] || break
        done
        [[ "${key:-}" == "$cidr" ]] || return 1

        profiles=$(query nmcli -t --escape no -f UUID,FILENAME connection show) || return 1
        while IFS=: read -r key file; do
            [[ "$key" == "$uuid" ]] || continue
            case "$file" in
                /etc/NetworkManager/system-connections/*)
                    keyfile_has_ipv4 "$file" "$uuid" "$cidr"
                    return "$?"
                    ;;
                /run/NetworkManager/system-connections/netplan-*.nmconnection)
                    file="${file##*/netplan-}"
                    netplan_has_ipv4 "${file%.nmconnection}" "$cidr" "$uuid"
                    return "$?"
                    ;;
            esac
        done <<< "$profiles"
        return 1
    fi

    status=$(query networkctl --no-pager status "$iface") || return 1
    while read -r key file; do
        if [[ "$key $file" =~ ^Network\ File:\ /run/systemd/network/10-netplan-(.+)[.]network$ ]]; then
            netplan_has_ipv4 "${BASH_REMATCH[1]}" "$cidr"
            return "$?"
        fi
    done <<< "$status"
    return 1
}

check_global_ipv4() {
    local iface state addresses cidr flags condition
    local found=1
    while read -r iface state; do
        [[ "$state" == UP ]] || continue
        addresses=$(query ip -4 -o addr show dev "$iface" scope global) || continue
        [[ -n "$addresses" ]] || continue
        while read -r _ _ _ cidr flags; do
            [[ "$cidr" == */* ]] || continue
            found=0
            condition=unverified
            if [[ " $flags " == *" dynamic "* ]]; then
                condition=dynamic
            elif has_persistent_ipv4 "$iface" "$cidr"; then
                condition=static
            fi
            printf '%s %s %s\n' "$iface" "$cidr" "$condition"
        done <<< "$addresses"
    done < <(list_ifaces)
    return "$found"
}

check_network() (
    set -e
    export LC_ALL=C PAGER=cat SYSTEMD_PAGER=cat

    getent() {
        query getent "$@"
    }

    result=0
    printf '=== NIC UP ===\n'
    if ! check_interfaces '' 1; then
        log "ERROR: no interface is UP -abort"
        result=1
    fi

    printf '\n=== Global IPv4 ===\n'
    if ! check_global_ipv4; then
        log "ERROR: no UP interface has a global IPv4 -abort"
        result=1
    fi

    printf '\n=== Internet ===\n'
    if (check_internet); then
        printf 'DNS: www.google.com\n'
    else
        result=1
    fi
    exit "$result"
)

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
    local iface link_state type ip_addr line active_wifi=0

    while IFS= read -r line; do
        iface=$(echo "$line" | awk '{print $1}' | sed 's/@.*//')
        link_state=$(echo "$line" | awk '{print $2}')

        [[ "$iface" == "lo" ]] && continue
        type=$(classify_interface "$iface")
        [[ "$link_state" != "UP" ]] && continue

        ip_addr=$(ip -4 addr show dev "$iface" scope global 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)

        if [[ -z "$ip_addr" ]]; then
            continue
        fi

        [[ "$type" != wifi ]] || active_wifi=1

        printf ' %-18s [%-10s] %-14s %s\n' \
            "$iface" "$type" "UP/Active" "$ip_addr" >&2

    done < <(list_ifaces)

    echo "" >&2

    printf '%s\n' "$active_wifi"
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

    case "$(query systemctl show -p LoadState --value systemd-networkd.service)" in
        loaded|masked) ;;
        *)
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: systemd-networkd not installed -abort" >&2
            exit 1
            ;;
    esac

    if [ "$(detect_and_classify_interfaces)" = 1 ]; then
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
        read -r -p "Are you ABSOLUTELY SURE? (type 'I UNDERSTAND'): " confirm || confirm=''

        if [ "$confirm" != "I UNDERSTAND" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: aborted by user"
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: nic done"
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
        echo "To rollback: $0 --nm"
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

    detect_and_classify_interfaces >/dev/null

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

        # Block activation before stopping the service and its sockets.
        systemctl disable systemd-networkd.service 2>/dev/null || true
        if ! systemctl mask --now systemd-networkd.service; then
            log "ERROR: cannot stop and mask systemd-networkd -abort" >&2
            exit 1
        fi
        systemctl disable --now systemd-networkd.socket \
            systemd-networkd-wait-online.service 2>/dev/null || true
        systemctl stop systemd-networkd-varlink.socket \
            systemd-networkd-resolve-hook.socket 2>/dev/null || true

        if ! renderer_is_current NetworkManager; then
            log "ERROR: cannot verify NetworkManager renderer -abort" >&2
            exit 1
        fi
        log "INFO: systemd-networkd stopped and masked"

        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: switched to NetworkManager"
        echo "To verify: systemctl status NetworkManager"
        echo "To manage networks: nmtui or nmcli"
        echo "To switch back: $0 --networkd"
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

    detect_and_classify_interfaces >/dev/null

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

install_module() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Creating Netplan Manager module structure..."

    # Create directories
    mkdir -p "$mod_dir/images"
    mkdir -p "$mod_dir/lang"
    mkdir -p "$mod_dir/help"
    mkdir -p "$etc_dir"

    # Write index.cgi (main file)
    cat > "$mod_dir/index.cgi" <<'INDEXCGI'
#!/usr/bin/perl
# Netplan Manager - Main interface
use strict;
use warnings;
use Cwd qw(realpath);

# Load webmin libraries
do '../web-lib.pl';
do '../ui-lib.pl';
&init_config();
our (%in, %text, %config);
&ReadParse();

our $module_name = "netplanmgr";
&load_language($module_name);
&read_file("$ENV{'WEBMIN_CONFIG'}/$module_name/config", \%config);

# Helper subs
sub list_netplan_files {
    my $dir = $config{'netplan_path'} || "/etc/netplan";
    my @files;
    if (opendir(my $dh, $dir)) {
        @files = sort grep { -f "$dir/$_" && is_safe_netplan_file("$dir/$_") } readdir($dh);
        closedir($dh);
    }
    return map { "$dir/$_" } @files;
}

sub read_file_content {
    my ($f) = @_;
    return undef unless -f $f;
    if (open(my $fh, '<', $f)) {
        local $/;
        my $c = <$fh>;
        close($fh);
        return $c;
    }
    return undef;
}

sub backup_file {
    my ($file) = @_;
    local $SIG{'CHLD'} = 'DEFAULT';
    return system('cp', '-fT', '--remove-destination', '--', $file, "${file}.bak") == 0;
}

sub write_file_content {
    my ($f, $content) = @_;
    my $tmp = "$f.tmp.$$";
    open(my $fh, '>', $tmp) or return 0;
    unless (print $fh $content) { close($fh); unlink($tmp); return 0; }
    unless (close($fh)) { unlink($tmp); return 0; }
    if (my @st = stat($f)) {
        unless (chmod($st[2] & 07777, $tmp) && chown($st[4], $st[5], $tmp)) {
            unlink($tmp);
            return 0;
        }
    }
    unless (rename($tmp, $f)) { unlink($tmp); return 0; }
    return 1;
}

# Restrict all file operations to .yaml/.yml files that resolve inside the
# configured Netplan directory, preventing path traversal / arbitrary file
# read or write through the 'file' parameter.
sub is_safe_netplan_file {
    my ($f) = @_;
    return 0 unless $f;
    my $allowed_dir = $config{'netplan_path'} || "/etc/netplan";
    my $real_allowed = realpath($allowed_dir);
    return 0 unless $real_allowed;

    my ($base) = $f =~ m{([^/]+)$};
    return 0 unless $base && $base =~ /^[A-Za-z0-9._-]+\.ya?ml$/i;

    my $dir = $f;
    $dir =~ s{/[^/]*$}{};
    $dir = '.' if $dir eq '';
    my $real_dir = realpath($dir);
    return 0 unless $real_dir;

    return $real_dir eq $real_allowed && !-l $f;
}

# ============================================================
# PROCESS ACTIONS (before the header, to handle redirects)
# ============================================================

# Handle AJAX request for file content
if (defined $in{'ajax'} && $in{'ajax'} eq '1') {
    my $file = $in{'file'} || '';
    if ($file && is_safe_netplan_file($file) && -f $file) {
        my $content = read_file_content($file);
        print "Content-type: text/plain; charset=utf-8\r\n\r\n";
        print $content || '';
    } else {
        print "Content-type: text/plain\r\n\r\n";
        print "Error: File not found";
    }
    exit;
}

# Handle SAVE action
if (defined $in{'save'}) {
    my $file = $in{'file'} || '';
    my $content = $in{'content'} || '';
    if ($file && is_safe_netplan_file($file)
        && ($config{'netplan_backup'} // '1') eq '1' && -f $file) {
        unless (backup_file($file)) {
            &redirect("index.cgi?error=backup");
            exit;
        }
    }
    if ($file && is_safe_netplan_file($file) && write_file_content($file, $content)) {
        &redirect("index.cgi?saved=1&file=" . &urlize($file));
    } else {
        &redirect("index.cgi?error=save");
    }
    exit;
}

# Handle VALIDATE action
if (defined $in{'validate'}) {
    my $file = $in{'file'} || '';
    if ($file && is_safe_netplan_file($file) && -f $file) {
        my $tmpdir = `mktemp -d /tmp/netplan-test-XXXXXX`;
        chomp $tmpdir;
        my $tmpyaml = "$tmpdir/etc/netplan/validate-$$.yaml";
        system("mkdir -p \"$tmpdir/etc/netplan\"");
        my $content = read_file_content($file);
        if ($content && write_file_content($tmpyaml, $content)) {
            my $out = `netplan generate --root-dir="$tmpdir" 2>&1`;
            my $exit = $? >> 8;
            system("rm -rf \"$tmpdir\" 2>/dev/null");
            if ($exit == 0) {
                &redirect("index.cgi?validated=1&file=" . &urlize($file));
            } else {
                &redirect("index.cgi?validated=0&file=" . &urlize($file) . "&msg=" . &urlize($out));
            }
        } else {
            system("rm -rf \"$tmpdir\" 2>/dev/null");
            &redirect("index.cgi?error=validate");
        }
    } else {
        &redirect("index.cgi?error=file");
    }
    exit;
}

# Handle APPLY action
if (defined $in{'apply'}) {
    my $file = $in{'file'} || '';
    if ($file && is_safe_netplan_file($file)) {
        if (defined $in{'content'}) {
            if (($config{'netplan_backup'} // '1') eq '1' && -f $file) {
                unless (backup_file($file)) {
                    &redirect("index.cgi?error=backup");
                    exit;
                }
            }
            if (!write_file_content($file, $in{'content'})) {
                &redirect("index.cgi?error=save");
                exit;
            }
        }
        # Apply
        my $out = `netplan apply 2>&1`;
        my $exit = $? >> 8;
        if ($exit == 0) {
            &redirect("index.cgi?applied=1&file=" . &urlize($file));
        } else {
            &redirect("index.cgi?applied=0&file=" . &urlize($file) . "&msg=" . &urlize($out));
        }
    } else {
        &redirect("index.cgi?error=file");
    }
    exit;
}

# ============================================================
# UI OUTPUT (after processing actions)
# ============================================================

# Anti-cache headers
print "Cache-Control: no-cache, no-store, must-revalidate, max-age=0\r\n";
print "Pragma: no-cache\r\n";
print "Expires: Thu, 01 Jan 1970 00:00:00 GMT\r\n";

# Print header
&ui_print_header(undef, $text{'index_title'}, "", undef, 1, 1);

# CSS Responsive
print <<'CSS';
<style>
.netplan-container {
    max-width: 1200px;
    margin: 0 auto;
    padding: 20px;
}

.alert-success, .alert-error, .alert-warning, .info-box {
    padding: 12px 16px;
    border-radius: 6px;
    margin: 16px 0;
    font-weight: 500;
}

.alert-success {
    background-color: #d4edda;
    color: #155724;
    border-left: 4px solid #28a745;
}

.alert-error {
    background-color: #f8d7da;
    color: #721c24;
    border-left: 4px solid #dc3545;
}

.alert-warning {
    background-color: #fff3cd;
    color: #856404;
    border-left: 4px solid #ffc107;
}

.info-box {
    background-color: #d1ecf1;
    color: #0c5460;
    border-left: 4px solid #17a2b8;
}

.file-table {
    width: 100%;
    border-collapse: collapse;
    background: white;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    border-radius: 8px;
    overflow: hidden;
    margin: 20px 0;
}

.file-table thead {
    background: #f8f9fa;
    border-bottom: 2px solid #dee2e6;
}

.file-table th {
    padding: 12px 16px;
    text-align: left;
    font-weight: 600;
    color: #495057;
}

.file-table td {
    padding: 12px 16px;
    border-bottom: 1px solid #dee2e6;
}

.file-table tbody tr:hover {
    background-color: #f8f9fa;
}

.file-table code {
    background: #e9ecef;
    padding: 4px 8px;
    border-radius: 4px;
    font-family: 'Courier New', monospace;
}

.netplan-btn {
    padding: 6px 16px;
    border: 1px solid #ccc;
    border-radius: 4px;
    cursor: pointer;
    font-size: 13px;
    font-weight: 500;
    transition: all 0.2s;
    margin: 0;
    font-family: inherit;
    line-height: 1.5;
    text-align: center;
    white-space: nowrap;
}

.netplan-btn:hover {
    opacity: 0.85;
    border-color: #999;
}

.netplan-btn:active {
    transform: translateY(1px);
}

.netplan-btn-edit {
    background-color: #6c757d;
    color: white;
    border-color: #6c757d;
}

.netplan-btn-edit:hover {
    background-color: #5a6268;
    border-color: #545b62;
}

.netplan-btn-validate {
    background-color: #17a2b8;
    color: white;
    border-color: #17a2b8;
}

.netplan-btn-validate:hover {
    background-color: #138496;
    border-color: #117a8b;
}

.netplan-btn-apply {
    background-color: #28a745;
    color: white;
    border-color: #28a745;
}

.netplan-btn-apply:hover {
    background-color: #218838;
    border-color: #1e7e34;
}

.netplan-btn-cancel {
    background-color: #6c757d;
    color: white;
    border-color: #6c757d;
}

.netplan-btn-cancel:hover {
    background-color: #5a6268;
    border-color: #545b62;
}

.netplan-btn-save {
    background-color: #007bff;
    color: white;
    border-color: #007bff;
}

.netplan-btn-save:hover {
    background-color: #0056b3;
    border-color: #004085;
}

.btn-primary, .btn-secondary, .btn-success {
    padding: 8px 16px;
    border: none;
    border-radius: 4px;
    cursor: pointer;
    font-size: 14px;
    font-weight: 500;
    transition: all 0.2s;
    margin: 2px;
}

.btn-primary {
    background-color: #007bff;
    color: white;
}

.btn-primary:hover {
    background-color: #0056b3;
}

.btn-secondary {
    background-color: #6c757d;
    color: white;
}

.btn-secondary:hover {
    background-color: #545b62;
}

.btn-success {
    background-color: #28a745;
    color: white;
}

.btn-success:hover {
    background-color: #218838;
}

.button-group {
    display: flex;
    gap: 8px;
    align-items: center;
    flex-wrap: wrap;
}

.button-group form {
    margin: 0;
    display: inline-block;
}

.modal-overlay {
    display: none;
    position: fixed;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    background-color: rgba(0, 0, 0, 0.7);
    z-index: 9998;
    animation: fadeIn 0.2s;
}

.modal-overlay.active {
    display: block;
}

.modal-container {
    display: none;
    position: fixed;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    width: 90%;
    max-width: 1000px;
    max-height: 90vh;
    background: white;
    border-radius: 8px;
    box-shadow: 0 10px 40px rgba(0,0,0,0.3);
    z-index: 9999;
    overflow: hidden;
    animation: slideDown 0.3s;
}

.modal-container.active {
    display: flex;
    flex-direction: column;
}

.modal-header {
    padding: 16px 20px;
    background: #f8f9fa;
    border-bottom: 2px solid #dee2e6;
    display: flex;
    justify-content: space-between;
    align-items: center;
}

.modal-header h4 {
    margin: 0;
    color: #333;
    font-size: 18px;
}

.modal-close {
    background: none;
    border: none;
    font-size: 28px;
    color: #666;
    cursor: pointer;
    line-height: 1;
    padding: 0;
    width: 32px;
    height: 32px;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 4px;
    transition: all 0.2s;
}

.modal-close:hover {
    background: #e9ecef;
    color: #333;
}

.modal-body {
    padding: 20px;
    overflow-y: auto;
    flex: 1;
}

.modal-body textarea {
    width: 100%;
    font-family: 'Courier New', monospace;
    font-size: 13px;
    padding: 12px;
    border: 1px solid #ced4da;
    border-radius: 4px;
    box-sizing: border-box;
    resize: vertical;
    min-height: 400px;
}

.modal-footer {
    padding: 16px 20px;
    background: #f8f9fa;
    border-top: 1px solid #dee2e6;
    display: flex;
    justify-content: flex-end;
    gap: 10px;
}

@keyframes fadeIn {
    from { opacity: 0; }
    to { opacity: 1; }
}

@keyframes slideDown {
    from {
        opacity: 0;
        transform: translate(-50%, -55%);
    }
    to {
        opacity: 1;
        transform: translate(-50%, -50%);
    }
}

@media (max-width: 768px) {
    .netplan-container {
        padding: 10px;
    }

    .file-table {
        font-size: 14px;
    }

    .file-table th,
    .file-table td {
        padding: 8px;
    }

    .button-group {
        flex-direction: column;
        width: 100%;
    }

    .button-group button,
    .button-group form {
        width: 100%;
    }

    .netplan-btn {
        width: 100%;
        padding: 10px 16px;
    }

    .btn-primary, .btn-secondary, .btn-success {
        padding: 8px 12px;
        font-size: 13px;
        width: 100%;
    }

    .modal-container {
        width: 95%;
        max-height: 95vh;
    }

    .modal-body textarea {
        min-height: 300px;
        font-size: 12px;
    }
}

@media (max-width: 480px) {
    .file-table thead {
        display: none;
    }

    .file-table tr {
        display: block;
        margin-bottom: 16px;
        border: 1px solid #dee2e6;
        border-radius: 8px;
    }

    .file-table td {
        display: block;
        text-align: left;
        padding: 8px 12px;
        border-bottom: 1px solid #dee2e6;
    }

    .file-table td:last-child {
        border-bottom: none;
    }

    .file-table td:before {
        content: attr(data-label);
        font-weight: bold;
        display: block;
        margin-bottom: 4px;
        color: #495057;
    }

    .modal-container {
        width: 100%;
        max-height: 100vh;
        border-radius: 0;
    }
}
</style>
CSS

if (defined $in{'saved'}) {
    print "<div class='alert-success'> $text{'save_success'}</div>";
}

if (defined $in{'validated'}) {
    if ($in{'validated'} eq '1') {
        print "<div class='alert-success'> $text{'validate_success'}</div>";
    } else {
        print "<div class='alert-error'> $text{'validate_failed'}</div>";
        if (defined $in{'msg'}) {
            print "<pre style='background:#f8f9fa;padding:12px;border-radius:4px;overflow-x:auto;'>" . &html_escape($in{'msg'}) . "</pre>";
        }
    }
}

if (defined $in{'applied'}) {
    if ($in{'applied'} eq '1') {
        print "<div class='alert-success'> $text{'apply_success'}</div>";
    } else {
        print "<div class='alert-error'> $text{'apply_failed'}</div>";
        if (defined $in{'msg'}) {
            print "<pre style='background:#f8f9fa;padding:12px;border-radius:4px;overflow-x:auto;'>" . &html_escape($in{'msg'}) . "</pre>";
        }
    }
}

if (defined $in{'error'}) {
    my $message = $in{'error'} eq 'backup' ? 'Cannot create YAML backup' : $text{'file_error'};
    print "<div class='alert-error'> $message</div>";
}

print "<div class='netplan-container'>";
print "<h3> $text{'index_title'}</h3>";
print "<p>$text{'index_desc'}</p>";

my @files = list_netplan_files();

if (!@files) {
    print "<div class='alert-warning'>$text{'no_files'}</div>";
} else {
    print "<table class='file-table'>";
    print "<thead><tr><th>$text{'table_file'}</th><th>$text{'table_actions'}</th></tr></thead>";
    print "<tbody>";

    foreach my $f (@files) {
        my $basename = $f;
        $basename =~ s{.*/}{};
        my $escaped_file = &html_escape($f);
        my $escaped_basename = &html_escape($basename);

        print "<tr>";
        print "<td data-label='$text{\"table_file\"}'><code>$escaped_basename</code></td>";
        print "<td data-label='$text{\"table_actions\"}'>";
        print "<div class='button-group'>";

        print "<button type='button' class='netplan-btn netplan-btn-edit' data-file=\"$escaped_file\" data-name=\"$escaped_basename\" onclick='openEditModal(this.dataset.file, this.dataset.name)'>$text{'action_edit'}</button>";

        print "<form method='post' action='index.cgi' style='display:inline-block; margin:0;'>";
        print "<input type='hidden' name='file' value='$escaped_file'>";
        print "<input type='hidden' name='validate' value='1'>";
        print "<button type='submit' class='netplan-btn netplan-btn-validate'>$text{'action_validate'}</button>";
        print "</form>";

        print "<form method='post' action='index.cgi' style='display:inline-block; margin:0;'>";
        print "<input type='hidden' name='file' value='$escaped_file'>";
        print "<input type='hidden' name='apply' value='1'>";
        print "<button type='submit' class='netplan-btn netplan-btn-apply'>$text{'action_apply'}</button>";
        print "</form>";

        print "</div>";
        print "</td>";
        print "</tr>";
    }

    print "</tbody></table>";
}

print "</div>";

print <<"MODAL";
<div id="modalOverlay" class="modal-overlay" onclick="closeEditModal()"></div>

<div id="editModal" class="modal-container">
    <div class="modal-header">
        <h4 id="modalTitle">$text{'editing'}</h4>
        <button class="modal-close" onclick="closeEditModal()">&times;</button>
    </div>
    <div class="modal-body">
        <form id="editForm" method="post" action="index.cgi">
            <input type="hidden" name="file" id="modalFile" value="">
            <input type="hidden" name="save" value="1">
            <textarea name="content" id="modalContent" rows="20"></textarea>
        </form>
    </div>
    <div class="modal-footer">
        <button type="button" class="netplan-btn netplan-btn-cancel" onclick="closeEditModal()">$text{'action_cancel'}</button>
        <button type="button" class="netplan-btn netplan-btn-save" onclick="saveFile()">$text{'action_save'}</button>
    </div>
</div>

<script>
function openEditModal(filePath, fileName) {
    document.getElementById('modalContent').value = 'Loading...';
    document.getElementById('modalTitle').textContent = 'Editing: ' + fileName;
    document.getElementById('modalFile').value = filePath;

    document.getElementById('modalOverlay').classList.add('active');
    document.getElementById('editModal').classList.add('active');

    fetch('index.cgi?ajax=1&file=' + encodeURIComponent(filePath))
        .then(response => response.text())
        .then(content => {
            document.getElementById('modalContent').value = content;
            document.getElementById('modalContent').focus();
        })
        .catch(error => {
            document.getElementById('modalContent').value = 'Error loading file: ' + error;
        });
}

function closeEditModal() {
    document.getElementById('modalOverlay').classList.remove('active');
    document.getElementById('editModal').classList.remove('active');
    document.getElementById('modalContent').value = '';
}

function saveFile() {
    document.getElementById('editForm').submit();
}

document.addEventListener('keydown', function(event) {
    if (event.key === 'Escape') {
        closeEditModal();
    }
});
</script>
MODAL

&ui_print_footer("/", $text{'index'});
INDEXCGI

    chmod 755 "$mod_dir/index.cgi"

    # Write module.info (English)
    cat > "$mod_dir/module.info" <<'EOF'
desc=Netplan Manager
longdesc=View, edit and apply Netplan YAML configuration files
category=net
os_support=*-linux
version=1.2
depends=webmin
EOF

    # Write module.info.es (Spanish)
    cat > "$mod_dir/module.info.es" <<'EOF'
desc=Administrador de Netplan
longdesc=Ver, editar y aplicar archivos YAML de Netplan
category=net
os_support=*-linux
version=1.2
depends=webmin
EOF

    # Write lang/en (English strings)
    cat > "$mod_dir/lang/en" <<'EOF'
index_title=Netplan Manager
index_desc=Manage Netplan network configuration files under /etc/netplan
table_file=Configuration File
table_actions=Actions
action_edit=Edit
action_validate=Validate
action_apply=Apply
action_save=Save
action_cancel=Cancel
validate_success=YAML configuration is valid
validate_failed=Validation failed
save_success=File saved successfully
save_failed=Failed to save file
apply_success=Configuration applied successfully
apply_failed=Failed to apply configuration
file_error=File not specified or not found
editing=Editing
no_files=No Netplan YAML files found in /etc/netplan
applying=Applying configuration...
index=Webmin Index
EOF

    # Write lang/es (Spanish strings)
    cat > "$mod_dir/lang/es" <<'EOF'
index_title=Administrador de Netplan
index_desc=Gestiona los archivos de configuracion Netplan en /etc/netplan
table_file=Archivo de Configuracion
table_actions=Acciones
action_edit=Editar
action_validate=Validar
action_apply=Aplicar
action_save=Guardar
action_cancel=Cancelar
validate_success=La configuracion YAML es valida
validate_failed=La validacion fallo
save_success=Archivo guardado exitosamente
save_failed=Fallo al guardar el archivo
apply_success=Configuracion aplicada con exito
apply_failed=Fallo al aplicar la configuracion
file_error=Archivo no especificado o no encontrado
editing=Editando
no_files=No se encontraron archivos YAML de Netplan en /etc/netplan
applying=Aplicando configuracion...
index=Indice de Webmin
EOF

    # Write config.info (Configuration options - English)
    cat > "$mod_dir/config.info" <<'EOF'
netplan_path=Netplan configuration directory,0
netplan_backup=Create backup before overwriting,1,1-Yes,0-No
EOF

    # Write config.info.es (Configuration options - Spanish)
    cat > "$mod_dir/config.info.es" <<'EOF'
netplan_path=Directorio de configuracion Netplan,0
netplan_backup=Crear respaldo antes de sobrescribir,1,1-Si,0-No
EOF

    # Write defaultconfig (Default configuration values)
    cat > "$mod_dir/defaultconfig" <<'EOF'
netplan_path=/etc/netplan
netplan_backup=1
EOF

    # Write config (Initial configuration - same as defaults)
    cat > "$etc_dir/config" <<'EOF'
netplan_path=/etc/netplan
netplan_backup=1
EOF

    # Write install_check.pl
    cat > "$mod_dir/install_check.pl" <<'EOF'
#!/usr/bin/perl
# Check if netplan is available

do '../web-lib.pl';

sub module_install_check {
    if (!&has_command("netplan")) {
        return "netplan command not found - Netplan is required for this module";
    }
    return undef;
}
EOF

    chmod 755 "$mod_dir/install_check.pl"

    # Write help/intro.html
    cat > "$mod_dir/help/intro.html" <<'EOF'
<header>Netplan Manager</header>

<h3>Introduction</h3>
<p>The Netplan Manager module allows you to view, edit and apply Netplan YAML files located in /etc/netplan. Use Validate before Apply to avoid applying broken configuration.</p>

<h3>Usage</h3>
<ul>
<li><strong>Edit:</strong> Opens the YAML file in an editor. After editing, press Save.</li>
<li><strong>Validate:</strong> Checks YAML syntax using netplan generate.</li>
<li><strong>Apply:</strong> Runs <code>netplan apply</code> to activate the configuration.</li>
</ul>

<h3>Workflow</h3>
<ol>
<li>Click <strong>Edit</strong> to modify a configuration file</li>
<li>Make your changes and click <strong>Save</strong></li>
<li>Click <strong>Validate</strong> to check for errors</li>
<li>If validation passes, click <strong>Apply</strong> to activate</li>
</ol>

<footer>
EOF

    # Write help/intro.es.html
    cat > "$mod_dir/help/intro.es.html" <<'EOF'
<header>Administrador de Netplan</header>

<h3>Introduccion</h3>
<p>El modulo Administrador de Netplan permite ver, editar y aplicar archivos YAML de Netplan ubicados en /etc/netplan. Use Validar antes de Aplicar para evitar aplicar configuraciones erroneas.</p>

<h3>Uso</h3>
<ul>
<li><strong>Editar:</strong> Abre el archivo YAML en un editor. Despues de editar, presione Guardar.</li>
<li><strong>Validar:</strong> Verifica la sintaxis YAML usando netplan generate.</li>
<li><strong>Aplicar:</strong> Ejecuta <code>netplan apply</code> para activar la configuracion.</li>
</ul>

<h3>Flujo de trabajo</h3>
<ol>
<li>Haga clic en <strong>Editar</strong> para modificar un archivo de configuracion</li>
<li>Realice sus cambios y haga clic en <strong>Guardar</strong></li>
<li>Haga clic en <strong>Validar</strong> para verificar errores</li>
<li>Si la validacion pasa, haga clic en <strong>Aplicar</strong> para activar</li>
</ol>

<footer>
EOF

    # Write CHANGELOG
    cat > "$mod_dir/CHANGELOG" <<'EOF'
Version 1.2 (2025)
- Added modal popup editor for better UX with long file lists
- Added AJAX file loading for instant editing
- Added configuration option (backup)
- Added Spanish configuration translations
- Improved user experience with floating editor

Version 1.1 (2025)
- Fixed button functionality with proper redirects
- Added responsive CSS design
- Improved mobile experience
- Better error handling and user feedback
- Enhanced UI with modern styling

Version 1.0 (2025)
- Initial Netplan Manager release
- View, edit, validate and apply Netplan YAML files
- Multi-language (en/es)
EOF

    # Create icon.gif
    icon_b64=$(mktemp)
    cat > "$icon_b64" << 'ICONEOF'
R0lGODlhMAAwAPAAAAAAAAAAACH5BAEAAAAALAAAAAAwADAAAAKrhI+py+0Po5wqJEszCpyf7mkUiAGkOJJqiUKr2krvGS/zDdYGzusmj6vdLjPfynb0/XIVmnLZQTKfsOZU95I6W8NNUQj8yq5hcWRbzk62xOA5BIX/Pj0XML6rP9JuvJ3v4cTGAChncpFR+JSXtshIlgSm5mWWWPlYJdLVFqmxSdlpOQmayRU6isXnGHfnqEhVyBITazgbuxiFWXKlxFJ6uGpVGywsS3yMHFMAADs=
ICONEOF

    base64 -d "$icon_b64" > "$mod_dir/images/icon.gif" || true
    rm -f "$icon_b64"

    # Set permissions
    if ! chown -R root:root "$mod_dir" "$etc_dir"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot set netplanmgr owner and group -abort" >&2
        exit 1
    fi
    if ! chmod -R 755 "$mod_dir"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot set netplanmgr permissions -abort" >&2
        exit 1
    fi
    chmod 644 "$mod_dir"/*.info* "$mod_dir/lang/"* "$mod_dir/help/"* "$mod_dir/CHANGELOG" 2>/dev/null || true
    chmod 755 "$mod_dir"/*.cgi "$mod_dir"/*.pl 2>/dev/null || true
    chmod 644 "$mod_dir/images/"* 2>/dev/null || true

    # Register in Webmin ACL
    if [ -f /etc/webmin/webmin.acl ]; then
        if ! grep -qE "^root:.*\b${mod_name}\b" /etc/webmin/webmin.acl 2>/dev/null; then
            sed -i.bak 's/\(^root:.*\)/\1 '"$mod_name"'/' /etc/webmin/webmin.acl
            rm -f /etc/webmin/webmin.acl.bak
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: module added to webmin.acl"
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: webmin.acl not found, ACL not updated -alert"
    fi

    # Clear cache
    rm -f /var/webmin/module.infos.cache

    # Restart Webmin
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Restarting Webmin service..."
    systemctl restart webmin.service 2>/dev/null || /etc/webmin/restart 2>/dev/null || true

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Netplan Manager installed"
    echo "Module location: $mod_dir"
    echo "Config location: $etc_dir"
    echo ""
    echo "Please refresh your browser to see module"
    echo "Find it under 'Network' category"
    echo ""
}

# Install the Webmin platform only after explicit confirmation.
webmin_usable() {
    [ -f /usr/share/webmin/web-lib.pl ] &&
        [ -f /usr/share/webmin/ui-lib.pl ] &&
        [ -d /etc/webmin ]
}

install_webmin() (
    local repo_url="https://raw.githubusercontent.com/webmin/webmin/master"
    local setup_script

    require_commands ip awk getent apt-get mktemp rm sh sleep || return 1
    check_ipv4_interfaces
    check_internet

    if ! command -v curl >/dev/null 2>&1; then
        if ! apt-get update -qq || ! apt-get install -y curl; then
            log "ERROR: cannot install curl for Webmin -abort"
            return 1
        fi
    fi

    setup_script=$(mktemp) || {
        log "ERROR: cannot create Webmin setup file -abort"
        return 1
    }
    trap 'rm -f -- "$setup_script"' EXIT

    if ! curl --fail --silent --show-error --location --retry 3 \
        --connect-timeout 10 --max-time 90 -o "$setup_script" \
        "$repo_url/webmin-setup-repo.sh"; then
        log "ERROR: cannot download Webmin repository setup -abort"
        return 1
    fi
    if ! sh "$setup_script" --force --install-packages=webmin </dev/null; then
        log "ERROR: cannot configure the Webmin APT repository -abort"
        return 1
    fi
    if ! apt-get install -y --install-recommends webmin; then
        log "ERROR: cannot install Webmin -abort"
        return 1
    fi
    if ! webmin_usable; then
        log "ERROR: Webmin installation files are incomplete -abort"
        return 1
    fi
)

# Uninstall the Webmin module
uninstall_module() {
    if [ ! -d "$mod_dir" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: module not installed -skip"
        return 0
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Removing module files..."
    rm -rf "$mod_dir"
    rm -rf "$etc_dir"

    # Remove from ACL
    if [ -f /etc/webmin/webmin.acl ]; then
        if grep -q "$mod_name" /etc/webmin/webmin.acl 2>/dev/null; then
            sed -i.bak 's/ '"$mod_name"'//g' /etc/webmin/webmin.acl
            rm -f /etc/webmin/webmin.acl.bak
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: module removed from webmin.acl"
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: webmin.acl not found, ACL not updated -alert"
    fi

    # Clear cache
    rm -f /var/webmin/module.infos.cache
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: module cache cleared"

    # Restart Webmin
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Restarting Webmin service..."
    systemctl restart webmin.service 2>/dev/null || /etc/webmin/restart 2>/dev/null || true

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Netplan Manager uninstalled"
}

confirm_switch() {
    local target="$1" answer
    printf 'Switch to %s\n' "$target"
    if [ "$target" = systemd-networkd ]; then
        echo -e "----------------------------------------------"
        echo "This will:"
        echo "1. Deactivate ALL existing YAML files (rename to .npswitch.bak)"
        echo "2. Create new 00-networkd.yaml config"
        echo "3. Disable NetworkManager"
        echo "4. Enable systemd-networkd"
        echo "5. Apply changes (may disconnect SSH!)"
        echo ""
    else
        echo -e "----------------------------------------------"
        echo "This will:"
        echo "1. Remove 00-networkd.yaml file"
        echo "2. Restore ALL previous YAML files (from .npswitch.bak)"
        echo "3. Force renderer to NetworkManager"
        echo "4. Disable systemd-networkd"
        echo "5. Enable NetworkManager"
        echo "6. Apply changes (may disconnect SSH!)"
        echo ""
    fi
    read -r -p 'Continue? [y/N]: ' answer || return 1
    [[ "$answer" == y || "$answer" == Y ]]
}

show_help() {
    cat <<EOF
Usage: $0 [OPTION]

Without arguments, opens the interactive menu.

  --check      Check link, global IPv4 and DNS; report IPv4 configuration
  --status     Show interfaces, services and Netplan renderer
  --networkd   Switch to systemd-networkd after confirmation
  --nm         Switch to NetworkManager after confirmation
  --install    Install Netplan Manager for Webmin
  --uninstall  Uninstall Netplan Manager for Webmin
  -h, --help   Show help
EOF
}

renderer_is_current() {
    local target="$1" service other configured other_state renderer
    case "$target" in
        systemd-networkd) renderer=networkd; service=systemd-networkd.service; other=NetworkManager.service ;;
        NetworkManager) renderer=NetworkManager; service=NetworkManager.service; other=systemd-networkd.service ;;
        *) return 1 ;;
    esac

    configured=$(query netplan get renderer) || return 1
    [ "$configured" = "$renderer" ] || return 1
    query systemctl is-active --quiet "$service" || return 1
    other_state=$(query systemctl show -p ActiveState --value "$other") || return 1
    [[ "$other_state" == inactive || "$other_state" == failed ]]
}

run_action() {
    local action="$1" target
    if [[ "$action" == --help ]]; then
        show_help
        return
    fi
    case "$action" in
        --check)
            require_commands ip awk paste grep getent timeout sleep date || return 1
            check_network
            ;;
        --status)
            require_commands ip awk grep sed head systemctl || return 1
            show_status
            ;;
        --networkd|--nm)
            target=NetworkManager
            [[ "$action" != --networkd ]] || target=systemd-networkd
            if renderer_is_current "$target"; then
                log "INFO: $target is already active -skip"
                return 0
            fi
            if ! confirm_switch "$target"; then
                log "INFO: aborted by user"
                return 0
            fi
            require_commands flock dpkg-query || return 1
            lock_changes || return 1
            if renderer_is_current "$target"; then
                log "INFO: $target is already active -skip"
                return 0
            fi
            install_dependencies netplan.io iproute2 systemd network-manager \
                util-linux libc-bin coreutils grep sed || return 1
            require_commands ip awk netplan nmcli systemctl grep sed find || return 1
            if [[ "$action" == --networkd ]]; then
                switch_to_networkd
            else
                switch_to_nm
            fi
            ;;
        --install)
            local answer
            require_commands flock dpkg-query || return 1
            lock_changes || return 1
            if ! webmin_usable; then
                if [ "$(dpkg-query -W -f='${Status}' webmin 2>/dev/null)" = "install ok installed" ]; then
                    log "ERROR: Webmin installation files are incomplete -abort"
                    return 1
                fi
                if ! read -r -p 'Add the official APT repository and install Webmin? [y/N]: ' answer ||
                    [[ "$answer" != y && "$answer" != Y ]]; then
                    log "INFO: aborted by user"
                    return 0
                fi
                install_webmin || return 1
            fi
            install_dependencies coreutils systemd util-linux iproute2 libc-bin \
                grep sed netplan.io || return 1
            install_module
            ;;
        --uninstall)
            require_webmin || return 1
            require_commands flock systemctl rm sed grep || return 1
            lock_changes || return 1
            uninstall_module
            ;;
    esac
}

show_menu() {
    local choice
    while true; do
        echo ""
        cat <<'MENU'
==== NIC Manager ====
1) Check network
2) Show status
3) To systemd-networkd
4) To NetworkManager
5) Install Netplan Manager for Webmin
6) Uninstall Netplan Manager for Webmin
7) Help
8) Exit
MENU
        read -r -p 'Select [1-8] [8]: ' choice || return 1
        echo ""
        case "${choice:-8}" in
            1) run_action --check; return $? ;;
            2) run_action --status; return $? ;;
            3) run_action --networkd; return $? ;;
            4) run_action --nm; return $? ;;
            5) run_action --install; return $? ;;
            6) run_action --uninstall; return $? ;;
            7) run_action --help; return $? ;;
            8) return 0 ;;
            *) log "INFO: invalid option -retry" ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

case "$#:${1:-}" in
    0:) show_menu ;;
    1:--check|1:--status|1:--networkd|1:--nm|1:--install|1:--uninstall|1:--help)
        run_action "$1"
        ;;
    1:-h) show_help ;;
    *)
        log "ERROR: invalid option -abort"
        show_help >&2
        exit 1
        ;;
esac
