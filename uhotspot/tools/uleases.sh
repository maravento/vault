#!/bin/bash
# maravento.com
#
################################################################################
#
# uleases — DHCP Leases & ACL Manager for pydhcpd (UniFi Hotspot edition)
#
# Reimplementation of pyleases.sh with extended directives and built-in
# UniFi Hotspot integration. Operates exclusively with pydhcpd as backend.
# Not compatible with isc-dhcp-server or any other DHCP daemon.
#
# DESCRIPTION:
#   Runs from /etc/uhotspot/tools/ and operates on pydhcpd
#   data located in /etc/pydhcp (which must exist).
#
#   This script:
#   - Drains the lease removal queue written by uhotspot.sh
#   - Parses and cleans /etc/pydhcp/pydhcpd.leases
#   - Detects unauthorized clients and adds them to block lists
#   - Dynamically rebuilds /etc/pydhcp/pydhcpd.conf based on ACL sources
#   - Applies static mappings (MAC → IP) from ACL files
#   - Removes duplicates and enforces consistency across data sources
#   - Safely restarts the pydhcpd service
#
# FEATURES:
#   - Locking mechanism to prevent concurrent executions (flock)
#   - Concurrency guard: aborts if uhotspot.sh is running (standalone mode only)
#   - Lease filtering and selective persistence
#   - Automatic cleanup and normalization of ACL files
#   - Duplicate detection with fail-safe abort
#   - First-run configuration via uleases.env (auto-generated)
#   - All paths, ACL files and network settings read from uleases.env
#   - Optional WPAD/PAC support (see WPAD/PAC OPTION below)
#   - UniFi Hotspot integration (default: true; set false in uleases.env for test)
#   - Grace period for unknown MACs before blocking (hotspot mode only)
#   - Lease removal queue: drains /etc/uhotspot/leases-remove-queue.txt
#     (written by uhotspot.sh) during the safe stop→modify→start cycle
#
# LOCATION:
#   Installed at /etc/uhotspot/tools/uleases.sh
#   Requires /etc/pydhcp to exist (pydhcpd backend)
#   Configuration stored in /etc/uhotspot/tools/uleases.env
#
# REQUIREMENTS:
#   - pydhcpd installed and running (/etc/pydhcp must exist)
#   - ACL directories and files as defined in uleases.env
#   - Root privileges
#   - python3 (for network calculations on first run)
#
# ACL FORMATS:
#   Standard (mac-*.txt, blockdhcp.txt):
#       a;MAC;IP;HOSTNAME;
#
#   Hotspot voucher (mac-hotspot.txt):
#       a;MAC;IP;HOSTNAME;END_TIME_EPOCH;
#
#   Grace (gracedhcp.txt, hotspot mode only):
#       a;MAC;IP;HOSTNAME;FIRST_SEEN_EPOCH;
#
# NOTES:
#   - Designed for environments enforcing DHCP-based access control
#   - Incorrect ACL data may disrupt IP assignments
#   - On first run, uleases.env is created with network/path configuration
#   - Delete uleases.env to re-run setup
#
# UNIFI HOTSPOT MODULE:
#   Integration layer that:
#   - Imports hotspot client data (mac-hotspot, guest-pending) as authoritative
#     exclusion lists during lease classification
#   - Extends DHCP reservations for hotspot users
#   - Synchronizes hotspot-related ACL entries
#   - Provides a grace period (BLOCKDHCP_GRACE_SECONDS) during which a previously
#     unseen MAC receives leases but is NOT yet listed in blockdhcp.txt
#
# USAGE:
#   - Controlled via UNIFI_HOTSPOT_ENABLED in uleases.env
#   - Can be safely disabled without affecting core DHCP logic
#
# WPAD/PAC OPTION (option 252)
# If you need WPAD/PAC for proxy auto-configuration:
# 1. Install and configure Apache2
# 2. Create virtual host on port 18100
# 3. Create wpad.pac file in Apache document root
# 4. Set WPAD_ENABLED=true in /etc/uhotspot/tools/uleases.env
#
################################################################################

echo "Leases Start. Wait..."
printf "\n"

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

LOG_FILE="/var/log/uleases.log"
ulog() {
    local msg
    msg="$(date '+%Y-%m-%d %H:%M:%S') $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

echo "────────────────────────────────────────────────────────────────────────────────" >> "$LOG_FILE" 2>/dev/null || true
ulog "uleases Start"

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

if [[ -z "${UHOTSPOT_RELOAD_ACTIVE:-}" ]] && [ -f /var/lock/uhotspot.lock ]; then
    if fuser /var/lock/uhotspot.lock &>/dev/null; then
        echo "ERROR: uhotspot.sh is currently running. Try again later."
        exit 1
    fi
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
# uleases environment configuration
# Generated by uleases.sh on $(date)
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
HOTSPOT_PATH=/etc/uhotspot

# ACL files
ACL_MAC_PROXY=/etc/acl/acl_mac/mac-proxy.txt
ACL_MAC_TRANSPARENT=/etc/acl/acl_mac/mac-transparent.txt
ACL_MAC_UNLIMITED=/etc/acl/acl_mac/mac-unlimited.txt
ACL_MAC_HOTSPOT=/etc/uhotspot/mac-hotspot.txt
ACL_GUEST_PENDING=/etc/uhotspot/guest-pending.txt
ACL_BLOCK_FILE=/etc/acl/acl_dhcp/blockdhcp.txt

# Hotspot grace file
ACL_GRACE_FILE=/etc/acl/acl_dhcp/gracedhcp.txt
# Grace period in seconds (24h default = 86400)
BLOCKDHCP_GRACE_SECONDS=86400

# UniFi Hotspot integration. 
# Set to false only for testing/debugging without a UniFi controller.
UNIFI_HOTSPOT_ENABLED=true

# Lease cleanup interval in seconds (should be <= pool min-lease-time)
CLEANUP_INTERVAL=40

# DHCP timing (seconds) (min-lease|default-lease|max-lease -time)
AUTHORIZED_LEASE_TIME=2592000

# WPAD/PAC support (requires Apache2 on port 18100 with wpad.pac)
WPAD_ENABLED=false

# Ping check: pydhcpd pings each IP before OFFER to detect conflicts.
# Set to false in environments with strict ICMP firewall rules.
PING_CHECK_ENABLED=true
EOF
    chmod 640 "$env_file"
    chown root:root "$env_file"
    echo "Configuration saved to $env_file"
}

ENV_FILE="$(dirname "$(readlink -f "$0")")/uleases.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "Configuration file not found. Running setup..."
    setup_env "$ENV_FILE"
fi
source "$ENV_FILE"

ACL_GRACE_FILE="${ACL_GRACE_FILE:-/etc/acl/acl_dhcp/gracedhcp.txt}"
LEASE_REMOVE_QUEUE="/etc/uhotspot/leases-remove-queue.txt"

if [[ "${WPAD_ENABLED:-false}" == "true" ]]; then
    wpad_header="option wpad code 252 = text;"
    wpad_subnet="option wpad \"http://$SERV_DHCP:18100/wpad.pac\";"
else
    wpad_header="#option wpad code 252 = text;"
    wpad_subnet="#option wpad \"http://$SERV_DHCP:18100/wpad.pac\";"
fi

if [[ "${PING_CHECK_ENABLED:-true}" == "true" ]]; then
    ping_check_line="ping-check true;"
else
    ping_check_line="ping-check false;"
fi

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
    if [ ! -d /etc/pydhcp ]; then
        echo "ERROR: /etc/pydhcp does not exist. Is pydhcpd installed?"
        exit 1
    fi
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
    if [[ "${UNIFI_HOTSPOT_ENABLED:-true}" == "true" ]]; then
        if [ ! -d "$HOTSPOT_PATH" ]; then
            echo "ERROR: Directory $HOTSPOT_PATH does not exist"
            exit 1
        fi
    fi
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
    if [[ "${UNIFI_HOTSPOT_ENABLED:-true}" == "true" ]]; then
        if [ ! -f "$ACL_MAC_HOTSPOT" ]; then
            touch "$ACL_MAC_HOTSPOT"
            chmod 600 "$ACL_MAC_HOTSPOT"
            chown root:root "$ACL_MAC_HOTSPOT"
        fi
        if [ ! -f "$ACL_GUEST_PENDING" ]; then
            touch "$ACL_GUEST_PENDING"
            chmod 600 "$ACL_GUEST_PENDING"
            chown root:root "$ACL_GUEST_PENDING"
        fi
        if [ ! -f "$ACL_GRACE_FILE" ]; then
            touch "$ACL_GRACE_FILE"
            chmod 600 "$ACL_GRACE_FILE"
            chown root:root "$ACL_GRACE_FILE"
        fi
    fi
}

verify_dhcp_service
verify_dhcp_files
verify_dhcp_config
verify_directories
initialize_empty_files
ulog "Verification OK — pydhcpd active, paths valid, HOTSPOT_ENABLED=${UNIFI_HOTSPOT_ENABLED:-true}"

function guest_pending_fixed() {
    while IFS= read -r line; do
        macsource=$(echo "$line" | cut -d ';' -f 2)
        ipsource=$(echo "$line" | cut -d ';' -f 3)
        usersource=$(echo "$line" | cut -d ';' -f 4)
        if ! [[ $macsource =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
            ulog "guest_pending_fixed: skipping entry, invalid MAC: $macsource"
            continue
        fi
        if ! [[ $ipsource =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            ulog "guest_pending_fixed: skipping entry, invalid IP: $ipsource"
            continue
        fi
        if ! [[ $usersource =~ ^[A-Za-z0-9._-]{1,63}$ ]]; then
            ulog "guest_pending_fixed: skipping entry, invalid hostname: $usersource"
            continue
        fi
        echo "
    host pending_${usersource} {
    hardware ethernet ${macsource};
    fixed-address ${ipsource};
                }" >>"$dhcp_conf_temp"
    done < "$ACL_GUEST_PENDING" 2>/dev/null || true
}

function clean_hotspot_list() {
    local removed=0 patterns
    patterns=$(mktemp)
    awk -F';' 'NF>=2 && $2!="" {print ";"$2";"}' "$ACL_MAC_UNLIMITED" | sort -u > "$patterns"

    while IFS= read -r pat; do
        local mac_actual="${pat//;/}"
        if grep -qF "$pat" "$ACL_MAC_HOTSPOT" 2>/dev/null; then
            ulog "clean_hotspot_list: removing $mac_actual from mac-hotspot (found in mac-unlimited)"
            (( removed++ )) || true
        fi
    done < "$patterns"

    if (( removed > 0 )); then
        grep -vFf "$patterns" "$ACL_MAC_HOTSPOT" > "$ACL_MAC_HOTSPOT".tmp \
            && mv "$ACL_MAC_HOTSPOT".tmp "$ACL_MAC_HOTSPOT"
    fi
    rm -f "$patterns"
    ulog "clean_hotspot_list: done (removed=$removed)"
}

function clean_grace_list() {
    [ ! -f "$ACL_GRACE_FILE" ] && return
    local file_temp patterns
    file_temp=$(mktemp)
    patterns=$(mktemp)

    {
        grep -h '^a;' "$ACL_MAC_PATH"/mac-* 2>/dev/null
        grep -h '^a;' "$ACL_MAC_HOTSPOT" 2>/dev/null
        grep -h '^a;' "$ACL_GUEST_PENDING" 2>/dev/null
    } | awk -F';' '{print tolower($2)}' | sort -u > "$file_temp"

    local removed=0
    while IFS= read -r mac_actual; do
        [ -z "$mac_actual" ] && continue
        if grep -qi "^a;${mac_actual};" "$ACL_GRACE_FILE" 2>/dev/null; then
            local found_in=""
            grep -qhi "^a;${mac_actual};" "$ACL_MAC_PATH"/mac-* 2>/dev/null && found_in="acl_mac"
            grep -qi "^a;${mac_actual};" "$ACL_MAC_HOTSPOT" 2>/dev/null && found_in="${found_in:+$found_in/}hotspot"
            grep -qi "^a;${mac_actual};" "$ACL_GUEST_PENDING" 2>/dev/null && found_in="${found_in:+$found_in/}pending"
            ulog "clean_grace_list: removing $mac_actual from gracedhcp (found in ${found_in:-unknown}, date=$(date))"
            printf '^a;%s;\n' "$mac_actual" >> "$patterns"
            (( removed++ )) || true
        fi
    done < "$file_temp"

    if (( removed > 0 )); then
        grep -vif "$patterns" "$ACL_GRACE_FILE" > "$ACL_GRACE_FILE.tmp" \
            && mv "$ACL_GRACE_FILE.tmp" "$ACL_GRACE_FILE"
    fi
    rm -f "$file_temp" "$patterns"
}

function expire_grace_entries() {
    [ ! -f "$ACL_GRACE_FILE" ] && return
    local file_temp now_epoch age
    file_temp=$(mktemp)
    now_epoch=$(date +%s)
    local grace_count
    grace_count=$(grep -c '^a;' "$ACL_GRACE_FILE" 2>/dev/null) || true
    grace_count=${grace_count:-0}
    ulog "expire_grace_entries: processing $grace_count entries (now=$now_epoch, grace=${BLOCKDHCP_GRACE_SECONDS}s)"

    while IFS=';' read -r status mac ip hostname epoch _; do
        if [[ "$status" != "a" || -z "$mac" || -z "$epoch" || ! "$epoch" =~ ^[0-9]+$ ]]; then
            ulog "expire_grace_entries: skipping malformed line (status=$status mac=$mac epoch=$epoch)"
            continue
        fi
        age=$(( now_epoch - epoch ))
        if (( age >= BLOCKDHCP_GRACE_SECONDS )); then
            ulog "expire_grace_entries: expired $mac (age=${age}s) → blockdhcp"
            echo "a;${mac};${ip};${hostname};" >> "$ACL_BLOCK_FILE"
        else
            ulog "expire_grace_entries: keeping $mac (age=${age}s, remaining=$(( BLOCKDHCP_GRACE_SECONDS - age ))s)"
            echo "a;${mac};${ip};${hostname};${epoch};" >> "$file_temp"
        fi
    done < "$ACL_GRACE_FILE"

    mv "$file_temp" "$ACL_GRACE_FILE"
    chmod 600 "$ACL_GRACE_FILE"
    chown root:root "$ACL_GRACE_FILE"
}

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
            if echo "$line" | grep -qE '^lease ((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?) \{$'; then
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

                        if [[ "${UNIFI_HOTSPOT_ENABLED:-true}" == "true" ]]; then
                            mac_authoritative=""
                            if grep -qi "^a;${mac_address};" "$ACL_MAC_PATH"/mac-* 2>/dev/null; then
                                mac_authoritative="yes"
                            elif grep -qi "^a;${mac_address};" "$ACL_MAC_HOTSPOT" 2>/dev/null; then
                                mac_authoritative="yes"
                            elif grep -qi "^a;${mac_address};" "$ACL_GUEST_PENDING" 2>/dev/null; then
                                mac_authoritative="yes"
                            fi

                            if [[ -n "$mac_authoritative" ]]; then
                                ulog "read_leases: $mac_address → authoritative (ip=$ip_address)"
                                echo "$lease_content" >> "$temp_leases"
                            elif grep -qi "^a;${mac_address};" "$ACL_BLOCK_FILE" 2>/dev/null; then
                                ulog "read_leases: $mac_address → blocked (lease discarded)"
                                :
                            elif grep -qi "^a;${mac_address};" "$ACL_GRACE_FILE" 2>/dev/null; then
                                ulog "read_leases: $mac_address → already in gracedhcp (lease managed by daemon)"
                                :
                            else
                                ulog "read_leases: $mac_address → new unknown → gracedhcp (ip=$ip_address host=$host epoch=$(date +%s) date=$(date))"
                                echo "a;${mac_address};${ip_address};${host};$(date +%s);" >> "$ACL_GRACE_FILE"
                                :
                            fi
                        else
                            if ! grep -qi "^a;${mac_address};" "$ACL_MAC_PATH"/mac-* 2>/dev/null; then
                                if ! grep -qi "^a;${mac_address};" "$ACL_BLOCK_FILE" 2>/dev/null; then
                                    ulog "read_leases: $mac_address → unknown (no hotspot) → blockdhcp (ip=$ip_address)"
                                    echo "$line_lease" >> "$ACL_BLOCK_FILE"
                                    echo "$lease_content" >> "$temp_leases"
                                fi
                            else
                                ulog "read_leases: $mac_address → authoritative (ip=$ip_address)"
                                echo "$lease_content" >> "$temp_leases"
                            fi
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
$wpad_header
server-identifier $SERV_DHCP;
deny duplicates;
one-lease-per-client true;
deny declines;
deny client-updates;
$ping_check_line
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

        if [[ "${UNIFI_HOTSPOT_ENABLED:-true}" == "true" ]]; then
            hotspot_normalized=$(awk -F';' 'NF>=5 && $2!="" && $3!=""{print $1";"$2";"$3";"$4";"}' \
                "$ACL_MAC_HOTSPOT" 2>/dev/null || true)
            all_sources=$(printf '%s\n' "$acl_sources" "$hotspot_normalized" | sort -u)
        else
            all_sources=$acl_sources
        fi

        while IFS= read -r line; do
            wcstatus=$(echo "$line" | cut -d ';' -f 1)
            macsource=$(echo "$line" | cut -d ';' -f 2)
            ipsource=$(echo "$line" | cut -d ';' -f 3)
            usersource=$(echo "$line" | cut -d ';' -f 4)
            if [[ $wcstatus == "a" ]]; then
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
        done <<< "$all_sources"

        if [[ "${UNIFI_HOTSPOT_ENABLED:-true}" == "true" ]]; then
            guest_pending_fixed
        fi
        
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
    $wpad_subnet
    option routers $SERV_DHCP;
    option subnet-mask $SERV_MASK;
    option broadcast-address $SERV_BROADCAST;
    #option domain-name \"example.org\";
    option domain-name-servers $SERV_DNS;
    min-lease-time $AUTHORIZED_LEASE_TIME;
    default-lease-time $AUTHORIZED_LEASE_TIME;
    max-lease-time $AUTHORIZED_LEASE_TIME;
    pool {
        min-lease-time $CLEANUP_INTERVAL;
        default-lease-time $CLEANUP_INTERVAL;
        max-lease-time $CLEANUP_INTERVAL;
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
        local removed=0 file_temp patterns
        file_temp=$(mktemp)
        patterns=$(mktemp)
        grep -hE ';[0-9a-f:]+;' "$ACL_MAC_PATH"/mac-* 2>/dev/null | cut -d ";" -f2 | sort -u >"$file_temp"

        while read -r mac_actual; do
            [ -z "$mac_actual" ] && continue
            if grep -qF ";${mac_actual};" "$ACL_BLOCK_FILE" 2>/dev/null; then
                ulog "clean_block_list: removing $mac_actual from blockdhcp (found in acl_mac, date=$(date))"
                printf ';%s;\n' "$mac_actual" >> "$patterns"
                (( removed++ )) || true
            fi
        done <"$file_temp"

        if (( removed > 0 )); then
            grep -vFf "$patterns" "$ACL_BLOCK_FILE" > "$ACL_BLOCK_FILE".tmp \
                && mv "$ACL_BLOCK_FILE".tmp "$ACL_BLOCK_FILE"
        fi
        rm -f "$file_temp" "$patterns"
        ulog "clean_block_list: done (removed=$removed)"
    }

    function clean_proxy_list {
        local removed=0 patterns
        patterns=$(mktemp)
        awk -F';' 'NF>=2 && $2!="" {print ";"$2";"}' "$ACL_MAC_UNLIMITED" | sort -u > "$patterns"

        while IFS= read -r pat; do
            local mac_actual="${pat//;/}"
            if grep -qF "$pat" "$ACL_MAC_PROXY" 2>/dev/null; then
                ulog "clean_proxy_list: removing $mac_actual from mac-proxy (found in mac-unlimited)"
                (( removed++ )) || true
            fi
        done < "$patterns"

        if (( removed > 0 )); then
            local file_temp
            file_temp=$(mktemp)
            grep -vFf "$patterns" "$ACL_MAC_PROXY" > "$file_temp" \
                && mv "$file_temp" "$ACL_MAC_PROXY"
            rm -f "$file_temp"
        fi
        rm -f "$patterns"
        ulog "clean_proxy_list: done (removed=$removed)"
    }

    function clean_transparent_list {
        local removed=0 patterns
        patterns=$(mktemp)
        awk -F';' 'NF>=2 && $2!="" {print ";"$2";"}' "$ACL_MAC_UNLIMITED" | sort -u > "$patterns"

        while IFS= read -r pat; do
            local mac_actual="${pat//;/}"
            if grep -qF "$pat" "$ACL_MAC_TRANSPARENT" 2>/dev/null; then
                ulog "clean_transparent_list: removing $mac_actual from mac-transparent (found in mac-unlimited)"
                (( removed++ )) || true
            fi
        done < "$patterns"

        if (( removed > 0 )); then
            local file_temp
            file_temp=$(mktemp)
            grep -vFf "$patterns" "$ACL_MAC_TRANSPARENT" > "$file_temp" \
                && mv "$file_temp" "$ACL_MAC_TRANSPARENT"
            rm -f "$file_temp"
        fi
        rm -f "$patterns"
        ulog "clean_transparent_list: done (removed=$removed)"
    }

    function clean_acl {
        ulog "clean_acl: removing empty lines from ACL files"
        sed '/^$/d' -i "$ACL_BLOCK_FILE"
        sed '/^$/d' -i "$ACL_MAC_PROXY"
        sed '/^$/d' -i "$ACL_MAC_TRANSPARENT"
        sed '/^$/d' -i "$ACL_MAC_UNLIMITED"
        if [[ "${UNIFI_HOTSPOT_ENABLED:-true}" == "true" ]]; then
            sed '/^$/d' -i "$ACL_MAC_HOTSPOT"
            sed '/^$/d' -i "$ACL_GRACE_FILE"
        fi
    }

    function order_files_acl {
        sort -V "$ACL_BLOCK_FILE" -o "$ACL_BLOCK_FILE"
        if [[ "${UNIFI_HOTSPOT_ENABLED:-true}" == "true" ]]; then
            sort -t';' -k3,3V "$ACL_MAC_HOTSPOT" -o "$ACL_MAC_HOTSPOT"
            sort -V "$ACL_GRACE_FILE" -o "$ACL_GRACE_FILE"
        fi
    }

    if [[ "${UNIFI_HOTSPOT_ENABLED:-true}" == "true" ]]; then
        ulog "--- gracedhcp state BEFORE processing ---"
        if [[ -s "$ACL_GRACE_FILE" ]]; then
            while IFS= read -r _line; do ulog "  $_line"; done < "$ACL_GRACE_FILE"
        else
            ulog "  (empty)"
        fi
        clean_grace_list
        expire_grace_entries
        ulog "--- gracedhcp state AFTER clean+expire ---"
        if [[ -s "$ACL_GRACE_FILE" ]]; then
            while IFS= read -r _line; do ulog "  $_line"; done < "$ACL_GRACE_FILE"
        else
            ulog "  (empty)"
        fi
    fi

    clean_acl
    clean_block_list
    clean_proxy_list
    if [[ "${UNIFI_HOTSPOT_ENABLED:-true}" == "true" ]]; then
        clean_hotspot_list
    fi
    clean_transparent_list
    ulog "Stopping pydhcpd"
    systemctl stop pydhcpd
    trap 'systemctl is-active --quiet pydhcpd || systemctl start pydhcpd' EXIT
    drain_lease_queue
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

drain_lease_queue() {
    [[ ! -s "$LEASE_REMOVE_QUEUE" ]] && return
    local dhcpd_leases="/etc/pydhcp/pydhcpd.leases"
    [[ ! -f "$dhcpd_leases" ]] && { : > "$LEASE_REMOVE_QUEUE"; return; }

    local tmp removed=0
    tmp=$(mktemp)
    local queue_macs
    queue_macs=$(tr '[:upper:]' '[:lower:]' < "$LEASE_REMOVE_QUEUE" | sort -u)

    local in_block=0 block=""
    while IFS= read -r line; do
        if echo "$line" | grep -qE '^lease ((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?) \{$'; then
            in_block=1; block="$line"$'\n'; continue
        fi
        if [[ $in_block -eq 1 ]]; then
            block+="$line"$'\n'
            if echo "$line" | grep -q '^}$'; then
                in_block=0
                local lmac
                lmac=$(echo "$block" | grep -oiE '([0-9a-f]{2}:){5}[0-9a-f]{2}' | head -1 | tr '[:upper:]' '[:lower:]')
                if [[ -n "$lmac" ]] && echo "$queue_macs" | grep -qxF "$lmac"; then
                    ulog "drain_lease_queue: removing $lmac from leases (date=$(date))"
                    (( removed++ )) || true
                else
                    printf '%s' "$block" >> "$tmp"
                fi
                block=""
            fi
            continue
        fi
        echo "$line" >> "$tmp"
    done < "$dhcpd_leases"

    mv "$tmp" "$dhcpd_leases"
    chown pydhcpd:pydhcpd "$dhcpd_leases"
    chmod 640 "$dhcpd_leases"
    : > "$LEASE_REMOVE_QUEUE"

    if (( removed > 0 )); then
        ulog "drain_lease_queue: removed $removed lease(s)"
    fi
}

function duplicate() {
    if [[ "${UNIFI_HOTSPOT_ENABLED:-true}" == "true" ]]; then
        aclall=$(for field in 2 3 4; do
            awk -F';' '/^a;/' "$ACL_MAC_PATH"/mac-* "$ACL_MAC_HOTSPOT" 2>/dev/null \
                | cut -d\; -f${field} | sort | uniq -d
        done)
    else
        aclall=$(for field in 2 3 4; do
            awk -F';' '/^a;/' "$ACL_MAC_PATH"/mac-* 2>/dev/null \
                | cut -d\; -f${field} | sort | uniq -d
        done)
    fi

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

# Final summary
_count() { local c; c=$(grep -c '^a;' "$1" 2>/dev/null) || true; echo "${c:-0}"; }
ulog "Summary: blockdhcp=$(_count "$ACL_BLOCK_FILE") | proxy=$(_count "$ACL_MAC_PROXY") | transparent=$(_count "$ACL_MAC_TRANSPARENT") | unlimited=$(_count "$ACL_MAC_UNLIMITED")$(
    [[ "${UNIFI_HOTSPOT_ENABLED:-true}" == "true" ]] && echo " | hotspot=$(_count "$ACL_MAC_HOTSPOT") | gracedhcp=$(_count "$ACL_GRACE_FILE") | pending=$(_count "$ACL_GUEST_PENDING")"
)"
ulog "Done"
