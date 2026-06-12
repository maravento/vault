#!/bin/bash
# maravento.com
#
################################################################################
#
# DHCP Leases & ACL Manager (pydhcpd)
#
# DESCRIPTION:
#   DHCP lease management script for pydhcpd that:
#   - Parses and cleans /etc/pydhcp/pydhcpd.leases
#   - Detects unauthorized clients and adds them to the block list
#   - Dynamically rebuilds /etc/pydhcp/pydhcpd.conf based on ACL sources
#   - Applies static MAC→IP mappings from ACL files
#   - Removes duplicates and enforces consistency across data sources
#   - Safely restarts the pydhcpd service
#
# FEATURES:
#   - Locking mechanism to prevent concurrent executions (flock)
#   - Lease filtering and selective persistence
#   - Automatic cleanup and normalization of ACL files
#   - Duplicate detection with fail-safe abort
#   - First-run configuration via pyleases.env (auto-generated)
#   - All paths, ACL files and network settings read from pyleases.env
#
# REQUIREMENTS:
#   - pydhcpd installed and running
#   - ACL directories and files as defined in pyleases.env
#   - Root privileges
#   - python3 (for network calculations on first run)
#
# ACL FORMAT:
#       a;MAC;IP;HOSTNAME;
#
# NOTES:
#   - Designed for environments enforcing DHCP-based access control
#   - Incorrect ACL data may disrupt IP assignments
#   - On first run, pyleases.env is created with network/path configuration
#   - Delete pyleases.env to re-run setup
#
# WPAD/PAC OPTION (DHCP option 252)
# If you need WPAD/PAC for proxy auto-configuration:
# 1. Install and configure Apache2
# 2. Create virtual host on port 18100
# 3. Create wpad.pac file in Apache document root
# 4. Uncomment these two lines in /etc/pydhcp/pydhcpd.conf:
#    option wpad code 252 = text;
#    option wpad "http://<server_ip>:18100/wpad.pac";
#
################################################################################

echo "Leases Start. Wait..."
printf "\n"

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

LOG_FILE="/var/log/pyleases.log"
ulog() {
    local msg
    msg="$(date '+%Y-%m-%d %H:%M:%S') $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

echo "────────────────────────────────────────────────────────────────────────────────" >> "$LOG_FILE" 2>/dev/null || true
ulog "pyleases Start"

if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

TEMP_FILES_TO_CLEAN=()
cleanup_temp() {
    for f in "${TEMP_FILES_TO_CLEAN[@]}"; do
        rm -f "$f" 2>/dev/null
    done
    # Lockfile is NOT removed: deleting it creates a TOCTOU race
    # where two processes could flock different inodes of the same path.
}
trap cleanup_temp EXIT

local_user=""
local_user=$(who | awk '/\(:0\)/{print $1; exit}')
[ -z "$local_user" ] && local_user=$(logname 2>/dev/null || true)
[ -z "$local_user" ] && local_user="${SUDO_USER:-}"
[ -z "$local_user" ] && local_user=$(who | awk 'NR==1{print $1}')
if [ -z "$local_user" ] || ! id "$local_user" &>/dev/null; then
    echo "ERROR: Cannot determine a valid local user"
    exit 1
fi

setup_env() {
    local env_file="$1"

    validate_ip() {
        echo "$1" | grep -qE '^(([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
    }

    validate_mask() {
        echo "$1" | grep -qE '^(255|254|252|248|240|224|192|128|0)(\.(255|254|252|248|240|224|192|128|0)){3}$'
    }

    validate_dns() {
        echo "$1" | grep -qE '^(([0-9]{1,3}\.){3}[0-9]{1,3})(,(([0-9]{1,3}\.){3}[0-9]{1,3}))*$'
    }

    while true; do
        read -rp "DHCP server IP (e.g. 192.168.0.10): " SERV_DHCP
        validate_ip "$SERV_DHCP" && break || echo "Invalid IP, try again"
    done

    while true; do
        read -rp "Netmask [255.255.255.0]: " SERV_MASK
        SERV_MASK="${SERV_MASK:-255.255.255.0}"
        validate_mask "$SERV_MASK" && break || echo "Invalid netmask, try again"
    done

    SERV_SUBNET=$(python3 -c "
import ipaddress
net = ipaddress.IPv4Network('$SERV_DHCP/$SERV_MASK', strict=False)
print(net.network_address)
")
    SERV_BROADCAST=$(python3 -c "
import ipaddress
net = ipaddress.IPv4Network('$SERV_DHCP/$SERV_MASK', strict=False)
print(net.broadcast_address)
")
    echo "Subnet: $SERV_SUBNET"
    echo "Broadcast: $SERV_BROADCAST"

    NET_BASE="${SERV_DHCP%.*}"
    while true; do
        read -rp "Block pool start (last octet, e.g. 230): " POOL_START_OCT
        if [[ "$POOL_START_OCT" =~ ^[0-9]+$ ]] && (( POOL_START_OCT >= 1 && POOL_START_OCT <= 254 )); then
            SERV_INI_RANGE_BLOCK="${NET_BASE}.${POOL_START_OCT}"
            break
        fi
        echo "Invalid value, enter a number between 1 and 254"
    done

    while true; do
        read -rp "Block pool end (last octet, e.g. 235): " POOL_END_OCT
        if [[ "$POOL_END_OCT" =~ ^[0-9]+$ ]] && (( POOL_END_OCT > POOL_START_OCT && POOL_END_OCT <= 254 )); then
            SERV_END_RANGE_BLOCK="${NET_BASE}.${POOL_END_OCT}"
            break
        fi
        echo "Pool end must be greater than pool start ($POOL_START_OCT) and <= 254"
    done

    while true; do
        read -rp "DNS servers (e.g. 8.8.8.8,1.1.1.1): " SERV_DNS
        validate_dns "$SERV_DNS" && break || echo "Invalid DNS format, try again"
    done

    cat > "$env_file" <<EOF
# pyleases environment configuration
# Generated by pyleases.sh on $(date)
# Edit this file to change configuration. Delete it to re-run setup.

# Network
SERV_DHCP=$SERV_DHCP
SERV_SUBNET=$SERV_SUBNET
SERV_BROADCAST=$SERV_BROADCAST
SERV_MASK=$SERV_MASK
SERV_INI_RANGE_BLOCK=$SERV_INI_RANGE_BLOCK
SERV_END_RANGE_BLOCK=$SERV_END_RANGE_BLOCK
SERV_DNS=$SERV_DNS

# Paths
ACL_PATH=/etc/acl
ACL_MAC_PATH=/etc/acl/acl_mac
ACL_DHCP_PATH=/etc/acl/acl_dhcp

# ACL files
ACL_MAC_PROXY=/etc/acl/acl_mac/mac-proxy.txt
ACL_MAC_TRANSPARENT=/etc/acl/acl_mac/mac-transparent.txt
ACL_MAC_UNLIMITED=/etc/acl/acl_mac/mac-unlimited.txt
ACL_BLOCK_FILE=/etc/acl/acl_dhcp/blockdhcp.txt

# Lease cleanup interval in seconds (should be <= pool min-lease-time)
CLEANUP_INTERVAL=60
EOF
    chmod 640 "$env_file"
    chown root:pydhcpd "$env_file"
    echo "Configuration saved to $env_file"
}

ENV_FILE="$(dirname "$0")/pyleases.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "Configuration file not found. Running setup..."
    setup_env "$ENV_FILE"
fi
source "$ENV_FILE"

_notify() {
    local user="$1"; shift
    local uid
    uid=$(id -u "$user")
    local bus="unix:path=/run/user/${uid}/bus"
    local xdg_runtime="/run/user/${uid}"

    local session_type
    session_type=$(loginctl show-session \
        "$(loginctl show-user "$user" 2>/dev/null | awk -F'[= ]' '/^Sessions=/{print $2}')" \
        -p Type --value 2>/dev/null || echo "x11")

    if [[ "$session_type" == "wayland" ]]; then
        sudo -u "$user" \
            DBUS_SESSION_BUS_ADDRESS="$bus" \
            WAYLAND_DISPLAY=wayland-1 \
            XDG_RUNTIME_DIR="$xdg_runtime" \
            notify-send "$@" 2>/dev/null || true
    else
        sudo -u "$user" \
            DISPLAY=:0 \
            DBUS_SESSION_BUS_ADDRESS="$bus" \
            XDG_RUNTIME_DIR="$xdg_runtime" \
            notify-send "$@" 2>/dev/null || true
    fi
}

verify_dhcp_service() {
    if ! command -v python3 &>/dev/null; then
        echo "ERROR: pydhcpd is not installed"
        exit 1
    fi
    if ! systemctl is-active --quiet pydhcpd; then
        echo "ERROR: pydhcpd is not running"
        exit 1
    fi
}

verify_dhcp_files() {
    mkdir -p /etc/pydhcp
    chown root:pydhcpd /etc/pydhcp
    chmod 770 /etc/pydhcp
    if [ ! -f /etc/pydhcp/pydhcpd.leases ]; then
        touch /etc/pydhcp/pydhcpd.leases
    fi
    chown pydhcpd:pydhcpd /etc/pydhcp/pydhcpd.leases
    chmod 640 /etc/pydhcp/pydhcpd.leases
}

verify_dhcp_config() {
    if [ ! -f "/etc/pydhcp/pydhcpd.conf" ]; then
        echo "ERROR: /etc/pydhcp/pydhcpd.conf does not exist"
        exit 1
    fi
    chmod 640 "/etc/pydhcp/pydhcpd.conf"
    chown root:pydhcpd "/etc/pydhcp/pydhcpd.conf"
}

verify_directories() {
    for dir in "$ACL_MAC_PATH" "$ACL_DHCP_PATH"; do
        if [ ! -d "$dir" ]; then
            echo "ERROR: Directory $dir does not exist"
            exit 1
        fi
    done
}

initialize_empty_files() {
    if [ ! -f "$ACL_BLOCK_FILE" ]; then
        touch "$ACL_BLOCK_FILE"
        chmod 600 "$ACL_BLOCK_FILE"
        chown root:root "$ACL_BLOCK_FILE"
    fi
    for file in "$ACL_MAC_PROXY" "$ACL_MAC_TRANSPARENT" "$ACL_MAC_UNLIMITED"; do
        if [ ! -f "$file" ]; then
            touch "$file"
            chmod 600 "$file"
            chown root:root "$file"
        fi
    done
}

verify_dhcp_service
verify_dhcp_files
verify_dhcp_config
verify_directories
initialize_empty_files
ulog "Verification OK — pydhcpd active, paths valid"

function is_pydhcp() {
    dhcpd=/etc/pydhcp/pydhcpd.leases
    dhcp_conf="/etc/pydhcp/pydhcpd.conf"
    dhcp_conf_temp="/etc/pydhcp/pydhcpd.conf.temp"
    echo "" >"$dhcp_conf_temp"

    function read_leases() {
        local temp_leases
        temp_leases=$(mktemp)
        TEMP_FILES_TO_CLEAN+=("$temp_leases")

        while IFS= read -r line; do
            if echo "$line" | grep -qE '^lease [0-9,.]+ {$'; then
                current_lease="$line"
                lease_content="$line"$'\n'
                continue
            fi

            if [ -n "$current_lease" ]; then
                lease_content+="$line"$'\n'
            fi

            if echo "$line" | grep -q '^}$'; then
                if [ -n "$current_lease" ]; then
                    mac_address=$(echo "$lease_content" | grep -oE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -1)
                    ip_address=$(echo "$lease_content" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
                    host_candidate=$(echo "$lease_content" | grep -oE 'client-hostname "[^"]+"' | cut -d'"' -f2 | tr " " "_")
                    host="${host_candidate:-no_name_$(head -c100 /dev/urandom | sha1sum | head -c10)}"

                    if [[ -n "$mac_address" && -n "$ip_address" ]]; then
                        line_lease="a;$mac_address;$ip_address;$host;"

                        if ! grep -qi "^a;${mac_address};" "$ACL_MAC_PATH"/mac-* 2>/dev/null; then
                            if ! grep -qi "^a;${mac_address};" "$ACL_BLOCK_FILE" 2>/dev/null; then
                                ulog "read_leases: $mac_address → unknown → blockdhcp (ip=$ip_address host=$host)"
                                echo "$line_lease" >> "$ACL_BLOCK_FILE"
                                echo "$lease_content" >> "$temp_leases"
                            else
                                ulog "read_leases: $mac_address → blocked (lease discarded)"
                            fi
                        else
                            ulog "read_leases: $mac_address → authoritative (ip=$ip_address)"
                            echo "$lease_content" >> "$temp_leases"
                        fi
                    fi
                    current_lease=""
                    lease_content=""
                fi
            fi
        done < "$dhcpd"

        local leases_kept=0
        [[ -s "$temp_leases" ]] && { leases_kept=$(grep -c '^lease ' "$temp_leases" 2>/dev/null) || true; }
        ulog "read_leases: done (leases_kept=$leases_kept)"

        if [[ -s "$temp_leases" ]]; then
            mv -f "$temp_leases" "$dhcpd"
        else
            echo "" > "$dhcpd"
        fi
        chown pydhcpd:pydhcpd "$dhcpd"
        chmod 640 "$dhcpd"
    }

    function update_dhcp_conf {
        echo "# pydhcpd Configuration
authoritative;
cleanup-interval $CLEANUP_INTERVAL;
#option wpad code 252 = text;
server-identifier $SERV_DHCP;
deny duplicates;
one-lease-per-client true;
deny declines;
deny client-updates;
ping-check true;
ddns-update-style none;
        " >"$dhcp_conf_temp"

        shopt -s nullglob
        acl_files=("$ACL_MAC_PATH"/mac-*)
        shopt -u nullglob
        if [ ${#acl_files[@]} -gt 0 ]; then
            acl_sources=$(cat "${acl_files[@]}")
        else
            acl_sources=""
        fi

        while IFS= read -r line; do
            wcstatus=$(echo "$line" | cut -d ';' -f 1)
            macsource=$(echo "$line" | cut -d ';' -f 2)
            ipsource=$(echo "$line" | cut -d ';' -f 3)
            usersource=$(echo "$line" | cut -d ';' -f 4)
            if [[ $wcstatus == "a" ]]; then
                # Validate every field before writing it into the config so an
                # ACL entry cannot inject arbitrary dhcpd directives.
                if ! [[ $macsource =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
                    ulog "update_dhcp_conf: skipping entry, invalid MAC: $macsource"
                    continue
                fi
                if ! [[ $ipsource =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                    ulog "update_dhcp_conf: skipping entry, invalid IP: $ipsource"
                    continue
                fi
                if ! [[ $usersource =~ ^[A-Za-z0-9._-]{1,63}$ ]]; then
                    ulog "update_dhcp_conf: skipping entry, invalid hostname: $usersource"
                    continue
                fi
                echo "
    host $usersource {
    hardware ethernet $macsource;
    fixed-address $ipsource;
                }" >>"$dhcp_conf_temp"
            fi
        done <<< "$acl_sources"

        echo '
class "blockdhcp" {
     match pick-first-value (option dhcp-client-identifier, hardware);
        }' >>"$dhcp_conf_temp"

        while IFS= read -r line; do
            macs=$(echo "$line" | cut -d ';' -f 2)
            if echo "$macs" | grep -qE '^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$'; then
                echo '    subclass "blockdhcp" 1:'$macs';' >>"$dhcp_conf_temp"
            fi
        done < "$ACL_BLOCK_FILE"

        echo "" >>"$dhcp_conf_temp"

        echo "subnet $SERV_SUBNET netmask $SERV_MASK {
    #option wpad \"http://$SERV_DHCP:18100/wpad.pac\";
    option routers $SERV_DHCP;
    option subnet-mask $SERV_MASK;
    option broadcast-address $SERV_BROADCAST;
    #option domain-name \"example.org\";
    option domain-name-servers $SERV_DNS;
    min-lease-time 2592000;
    default-lease-time 2592000;
    max-lease-time 2592000;
    pool {
        min-lease-time 60;
        default-lease-time 60;
        max-lease-time 60;
        deny members of \"blockdhcp\";
        range $SERV_INI_RANGE_BLOCK $SERV_END_RANGE_BLOCK;
    }
}
        " >>"$dhcp_conf_temp"

        # Keep a backup of the previous config in case the new one is faulty.
        [ -f "$dhcp_conf" ] && cp -f "$dhcp_conf" "${dhcp_conf}.bak"
        mv -f "$dhcp_conf_temp" "$dhcp_conf"
        chown root:pydhcpd "$dhcp_conf"
        chmod 640 "$dhcp_conf"
    }

    function clean_block_list {
        local removed=0
        file_temp=$(mktemp)
        TEMP_FILES_TO_CLEAN+=("$file_temp")
        grep -hE ';[0-9a-f:]+;' "$ACL_MAC_PATH"/mac-* 2>/dev/null | cut -d ";" -f2 >"$file_temp"
        while read -r mac_actual; do
            if grep -qF ";${mac_actual};" "$ACL_BLOCK_FILE" 2>/dev/null; then
                ulog "clean_block_list: removing $mac_actual from blockdhcp (found in acl_mac)"
                (( removed++ )) || true
            fi
            grep -vF ";${mac_actual};" "$ACL_BLOCK_FILE" > "$ACL_BLOCK_FILE".tmp && mv "$ACL_BLOCK_FILE".tmp "$ACL_BLOCK_FILE"
        done <"$file_temp"
        rm -f "$file_temp"
        ulog "clean_block_list: done (removed=$removed)"
    }

    function clean_proxy_list {
        local file_temp removed=0
        file_temp=$(mktemp)
        TEMP_FILES_TO_CLEAN+=("$file_temp")
        while IFS= read -r line; do
            mac_actual=$(echo "$line" | cut -d ';' -f 2)
            if grep -qF ";${mac_actual};" "$ACL_MAC_PROXY" 2>/dev/null; then
                ulog "clean_proxy_list: removing $mac_actual from mac-proxy (found in mac-unlimited)"
                (( removed++ )) || true
            fi
            grep -vF ";${mac_actual};" "$ACL_MAC_PROXY" > "$file_temp" && mv "$file_temp" "$ACL_MAC_PROXY"
        done <"$ACL_MAC_UNLIMITED"
        rm -f "$file_temp"
        ulog "clean_proxy_list: done (removed=$removed)"
    }

    function clean_transparent_list {
        local file_temp removed=0
        file_temp=$(mktemp)
        TEMP_FILES_TO_CLEAN+=("$file_temp")
        while IFS= read -r line; do
            mac_actual=$(echo "$line" | cut -d ';' -f 2)
            if grep -qF ";${mac_actual};" "$ACL_MAC_TRANSPARENT" 2>/dev/null; then
                ulog "clean_transparent_list: removing $mac_actual from mac-transparent (found in mac-unlimited)"
                (( removed++ )) || true
            fi
            grep -vF ";${mac_actual};" "$ACL_MAC_TRANSPARENT" > "$file_temp" && mv "$file_temp" "$ACL_MAC_TRANSPARENT"
        done <"$ACL_MAC_UNLIMITED"
        rm -f "$file_temp"
        ulog "clean_transparent_list: done (removed=$removed)"
    }

    function clean_acl {
        ulog "clean_acl: removing empty lines from ACL files"
        sed '/^$/d' -i "$ACL_BLOCK_FILE"
        sed '/^$/d' -i "$ACL_MAC_PROXY"
        sed '/^$/d' -i "$ACL_MAC_TRANSPARENT"
        sed '/^$/d' -i "$ACL_MAC_UNLIMITED"
    }

    function order_files_acl {
        sort -V "$ACL_BLOCK_FILE" -o "$ACL_BLOCK_FILE"
    }

    clean_acl
    clean_block_list
    clean_proxy_list
    clean_transparent_list

    ulog "Stopping pydhcpd"
    systemctl stop pydhcpd
    trap 'systemctl is-active --quiet pydhcpd || systemctl start pydhcpd' EXIT
    ulog "Processing leases"
    read_leases
    ulog "Sorting ACL files"
    order_files_acl
    ulog "Rebuilding pydhcpd.conf"
    update_dhcp_conf
    ulog "Starting pydhcpd"
    systemctl start pydhcpd
    trap - EXIT
}

function duplicate() {
    aclall=$(for field in 2 3 4; do
        awk -F';' '/^a;/' "$ACL_MAC_PATH"/mac-* 2>/dev/null \
            | cut -d\; -f${field} | sort | uniq -d
    done)
    if [ "${aclall}" == "" ]; then
        ulog "Duplicate check: OK"
        is_pydhcp
    else
        ulog "ERROR: Duplicate data detected: $aclall"
        echo "Duplicate Data: $(date) $aclall" | tee -a /var/log/syslog
        _notify "$local_user" "Warning: Abort" "Duplicate: $aclall. $(date)" -i error
        exit 1
    fi
}
duplicate

_count() { local c; c=$(grep -c '^a;' "$1" 2>/dev/null) || true; echo "${c:-0}"; }
ulog "Summary: blockdhcp=$(_count "$ACL_BLOCK_FILE") | proxy=$(_count "$ACL_MAC_PROXY") | transparent=$(_count "$ACL_MAC_TRANSPARENT") | unlimited=$(_count "$ACL_MAC_UNLIMITED")"
ulog "Done"
