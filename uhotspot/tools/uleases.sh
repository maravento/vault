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
#   - Drains the lease removal queue written by uhotspotd
#   - Parses and cleans /etc/pydhcp/pydhcpd.leases
#   - Detects unauthorized clients and adds them to block lists
#   - Dynamically rebuilds /etc/pydhcp/pydhcpd.conf based on ACL sources
#   - Applies static mappings (MAC → IP) from ACL files
#   - Removes duplicates and enforces consistency across data sources
#   - Safely restarts the pydhcpd service
#
# FEATURES:
#   - Locking mechanism to prevent concurrent executions (flock)
#   - Concurrency guard: aborts if uhotspotd is running (standalone mode only)
#   - Lease filtering and selective persistence
#   - Automatic cleanup and normalization of ACL files
#   - Duplicate detection with fail-safe abort
#   - Configuration read from /etc/uhotspot/uhotspot.conf (managed by usetup.sh)
#   - All paths, ACL files and network settings read from uhotspot.conf
#   - Optional WPAD/PAC support (see WPAD/PAC OPTION below)
#   - UniFi Hotspot integration (default: true; set false in uhotspot.conf for test)
#   - Grace period for unknown MACs before blocking (hotspot mode only)
#   - Lease removal queue: drains /etc/uhotspot/leases-remove-queue.txt
#     (written by uhotspotd) during the safe stop→modify→start cycle
#
# LOCATION:
#   Installed at /etc/uhotspot/tools/uleases.sh
#   Requires /etc/pydhcp to exist (pydhcpd backend)
#   Configuration stored in /etc/uhotspot/uhotspot.conf
#
# REQUIREMENTS:
#   - pydhcpd installed and running (/etc/pydhcp must exist)
#   - ACL directories and files as defined in uhotspot.conf
#   - Root privileges
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
#   - Configuration managed by usetup.sh — run usetup.sh to reconfigure
#
# UNIFI HOTSPOT MODULE:
#   Integration layer that:
#   - Classifies pydhcpd.leases entries: managed (mac-proxy.txt, mac-unlimited.txt),
#     voucher-authorized (mac-hotspot), blocked (blockdhcp), grace-period
#     (gracedhcp), or new
#   - New and gracedhcp clients keep their pydhcpd pool lease (no fixed-address
#     injection). Only mac-hotspot clients receive a fixed hotspot-range IP.
#   - Grace period (BLOCKDHCP_GRACE_SECONDS): any MAC detected in pydhcpd.leases
#     that is not in an authoritative ACL is added to gracedhcp.txt with a
#     timestamp. Regardless of reconnections, once the timer expires the MAC
#     moves permanently to blockdhcp.txt. The only exit is manual removal or
#     addition to mac-*.
#
# USAGE:
#   - Controlled via UNIFI_HOTSPOT_ENABLED in uhotspot.conf
#   - Can be safely disabled without affecting core DHCP logic
#
# WPAD/PAC OPTION (option 252)
# If you need WPAD/PAC for proxy auto-configuration:
# 1. Install and configure Apache2
# 2. Create virtual host on port 18100
# 3. Create wpad.pac file in Apache document root
# 4. Set WPAD_ENABLED=true in /etc/uhotspot/uhotspot.conf
#
################################################################################


export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

set -euo pipefail


LOG_FILE="/var/log/uhotspot.log"
ulog() {
    local msg
    msg="$(date '+%Y-%m-%d %H:%M:%S') $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

# Ensure log file exists with correct permissions.
if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    chown root:adm "$LOG_FILE" 2>/dev/null || chown root:root "$LOG_FILE"
fi

# Ensure logrotate config exists so the log does not grow unbounded.
_logrotate_conf="/etc/logrotate.d/uhotspot"
if [ ! -f "$_logrotate_conf" ]; then
    cat > "$_logrotate_conf" <<'EOF'
/var/log/uhotspot.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 640 root adm
}
EOF
    chmod 644 "$_logrotate_conf"
    chown root:root "$_logrotate_conf"
fi
unset _logrotate_conf

ulog "uleases start..."

if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -w 60 200; then
    echo "Script $(basename "$0") is already running — waited 60s, giving up"
    exit 1
fi

# When triggered by the daemon (UHOTSPOT_RELOAD_ACTIVE set), the daemon
# already holds CYCLE_LOCK for the duration of its run_cycle — this script
# runs synchronously as its child, so no additional check is needed here
# (and attempting to flock the same lock from a child of the lock holder
# would deadlock).
#
# When triggered by the @hourly cron (UHOTSPOT_RELOAD_ACTIVE unset), acquire
# CYCLE_LOCK before doing any real work, waiting briefly for the daemon to
# finish its current cycle if one is in progress. The daemon only holds this
# lock for the ~1-3s of active ACL mutation within run_cycle, not its entire
# process lifetime, so this wait is short in practice — unlike a check against
# the daemon's singleton lock (held for as long as the service is up), which
# would skip almost every time. The lock is held for the rest of this
# script's execution (through the stop→modify→start pydhcpd cycle) and is
# released automatically when the process exits.
if [[ -z "${UHOTSPOT_RELOAD_ACTIVE:-}" ]]; then
    CYCLE_LOCK="/var/lock/uhotspotd-cycle.lock"
    exec 201>"$CYCLE_LOCK"
    if ! flock -w 10 201; then
        ulog "INFO: uhotspotd cycle in progress — skipping cron-triggered reload (will retry next run)"
        ulog "uleases done (skipped)"
        exit 0
    fi
fi

TEMP_FILES_TO_CLEAN=()
cleanup_temp() {
    local f
    for f in "${TEMP_FILES_TO_CLEAN[@]+"${TEMP_FILES_TO_CLEAN[@]}"}"; do
        rm -f "$f" 2>/dev/null
    done
    # Lockfile is NOT removed: deleting it creates a TOCTOU race
    # where two processes could flock different inodes of the same path.
}
trap cleanup_temp EXIT

local_user=""

ENV_FILE="/etc/uhotspot/uhotspot.conf"
if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: $ENV_FILE not found. Run usetup.sh first."
    exit 1
fi

# Load only known KEY=VALUE pairs from ENV_FILE instead of sourcing it,
# so a tampered or maliciously replaced env file cannot execute code.
load_env_file() {
    local file="$1" line key value
    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        key="${line%%=*}"
        value="${line#*=}"
        if [[ "$value" == \"*\" && "$value" == *\" && ${#value} -ge 2 ]]; then
            value="${value:1:$((${#value}-2))}"
        fi
        case "$key" in
            SERV_DHCP|SERV_SUBNET|SERV_BROADCAST|SERV_MASK|SERV_INI_RANGE_BLOCK|SERV_END_RANGE_BLOCK|SERV_DNS|\
            ACL_PATH|ACL_MAC_PATH|ACL_DHCP_PATH|HOTSPOT_PATH|\
            ACL_MAC_PROXY|ACL_MAC_UNLIMITED|ACL_MAC_HOTSPOT|ACL_BLOCK_FILE|\
            ACL_GRACE_FILE|BLOCKDHCP_GRACE_SECONDS|UNIFI_HOTSPOT_ENABLED|\
            CLEANUP_INTERVAL|AUTHORIZED_LEASE_TIME|WPAD_ENABLED|PING_CHECK_ENABLED|\
            LOCAL_USER|SERVER_IP|HOTSPOT_IP_RANGE|HOTSPOT_RANGE_START|HOTSPOT_RANGE_END|POLL_INTERVAL)
                printf -v "$key" '%s' "$value"
                ;;
            *)
                ;;
        esac
    done < "$file"
}
load_env_file "$ENV_FILE"

# Determine local user: prefer LOCAL_USER from uhotspot.conf (the only reliable
# source when running from systemd without a TTY), then fall back to session detection.
local_user="${LOCAL_USER:-}"
if [ -z "$local_user" ] || ! id "$local_user" &>/dev/null 2>/dev/null; then
    local_user=$(who | awk '/\(:0\)/{print $1; exit}')
    [ -z "$local_user" ] && local_user=$(logname 2>/dev/null || true)
    [ -z "$local_user" ] && local_user="${SUDO_USER:-}"
    [ -z "$local_user" ] && local_user=$(who | awk 'NR==1{print $1}')
fi
if [ -z "$local_user" ] || ! id "$local_user" &>/dev/null; then
    echo "ERROR: Cannot determine a valid local user. Set LOCAL_USER in $ENV_FILE."
    exit 1
fi

# Compatibility: uhotspot.conf uses SERVER_IP; uleases.sh uses SERV_DHCP
: "${SERV_DHCP:=${SERVER_IP:-}}"

# Defaults for variables that may not exist in older uhotspot.conf installations.
# These match the values previously generated by uleases.env setup.
: "${SERV_MASK:=255.255.255.0}"
: "${SERV_DNS:=8.8.8.8,1.1.1.1}"
: "${ACL_PATH:=/etc/acl}"
: "${ACL_MAC_PATH:=/etc/acl/acl_mac}"
: "${ACL_DHCP_PATH:=/etc/acl/acl_dhcp}"
: "${HOTSPOT_PATH:=/etc/uhotspot}"
: "${ACL_MAC_PROXY:=/etc/acl/acl_mac/mac-proxy.txt}"
: "${ACL_MAC_UNLIMITED:=/etc/acl/acl_mac/mac-unlimited.txt}"
: "${ACL_MAC_HOTSPOT:=/etc/uhotspot/mac-hotspot.txt}"
: "${ACL_BLOCK_FILE:=/etc/acl/acl_dhcp/blockdhcp.txt}"
: "${BLOCKDHCP_GRACE_SECONDS:=86400}"
: "${UNIFI_HOTSPOT_ENABLED:=true}"
: "${CLEANUP_INTERVAL:=20}"
: "${AUTHORIZED_LEASE_TIME:=2592000}"
: "${WPAD_ENABLED:=false}"
: "${PING_CHECK_ENABLED:=true}"

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
        echo "ERROR: python3 is not installed (required by pydhcpd / uleases.sh)"
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
    for file in "$ACL_MAC_PROXY" "$ACL_MAC_UNLIMITED"; do
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

function clean_hotspot_list() {
    local removed=0 patterns
    patterns=$(mktemp)
    TEMP_FILES_TO_CLEAN+=("${patterns}")
    awk -F';' 'NF>=2 && $2!="" {print ";"$2";"}' "$ACL_MAC_UNLIMITED" | sort -u > "$patterns"

    while IFS= read -r pat; do
        local mac_actual="${pat//;/}"
        if grep -qF "$pat" "$ACL_MAC_HOTSPOT" 2>/dev/null; then
            ulog "clean_hotspot_list: removing $mac_actual from mac-hotspot (found in mac-unlimited)"
            (( removed++ )) || true
        fi
    done < "$patterns"

    if (( removed > 0 )); then
        local _grep_rc=0
        grep -vFf "$patterns" "$ACL_MAC_HOTSPOT" > "$ACL_MAC_HOTSPOT".tmp || _grep_rc=$?
        if (( _grep_rc > 1 )); then
            ulog "ERROR: clean_hotspot_list: grep failed (rc=$_grep_rc) — skipping update of mac-hotspot"
            rm -f "$ACL_MAC_HOTSPOT".tmp
        else
            chmod 600 "$ACL_MAC_HOTSPOT".tmp
            TEMP_FILES_TO_CLEAN+=("${ACL_MAC_HOTSPOT}.tmp")
            mv "$ACL_MAC_HOTSPOT".tmp "$ACL_MAC_HOTSPOT"
        fi
    fi
    rm -f "$patterns"
    if (( removed > 0 )); then
        ulog "clean_hotspot_list: done (removed=$removed)"
    fi
}

function clean_grace_list() {
    [ ! -f "$ACL_GRACE_FILE" ] && return
    local file_temp patterns
    file_temp=$(mktemp)
    TEMP_FILES_TO_CLEAN+=("${file_temp}")
    patterns=$(mktemp)
    TEMP_FILES_TO_CLEAN+=("${patterns}")

    # Only remove from gracedhcp when MAC was promoted to an authoritative ACL
    # (mac-* or mac-hotspot).
    {
        grep -h '^a;' "$ACL_MAC_PATH"/mac-* 2>/dev/null || true
        grep -h '^a;' "$ACL_MAC_HOTSPOT" 2>/dev/null || true
    } | awk -F';' '{print tolower($2)}' | sort -u > "$file_temp"

    local removed=0
    while IFS= read -r mac_actual; do
        [ -z "$mac_actual" ] && continue
        if grep -qi "^a;${mac_actual};" "$ACL_GRACE_FILE" 2>/dev/null; then
            local found_in=""
            grep -qhi "^a;${mac_actual};" "$ACL_MAC_PATH"/mac-* 2>/dev/null && found_in="acl_mac" || true
            grep -qi "^a;${mac_actual};" "$ACL_MAC_HOTSPOT" 2>/dev/null && found_in="${found_in:+$found_in/}hotspot" || true
            ulog "clean_grace_list: removing $mac_actual from gracedhcp (found in ${found_in:-unknown}, date=$(date))"
            printf '^a;%s;\n' "$mac_actual" >> "$patterns"
            (( removed++ )) || true
        fi
    done < "$file_temp"

    TEMP_FILES_TO_CLEAN+=("${ACL_GRACE_FILE}.tmp")
    if (( removed > 0 )); then
        local _grep_rc=0
        grep -vif "$patterns" "$ACL_GRACE_FILE" > "$ACL_GRACE_FILE.tmp" || _grep_rc=$?
        if (( _grep_rc > 1 )); then
            ulog "ERROR: clean_grace_list: grep failed (rc=$_grep_rc) — skipping update of gracedhcp"
            rm -f "$ACL_GRACE_FILE.tmp"
        else
            chmod 600 "$ACL_GRACE_FILE.tmp"
            mv "$ACL_GRACE_FILE.tmp" "$ACL_GRACE_FILE"
        fi
    fi
    rm -f "$file_temp" "$patterns"
}

function expire_grace_entries() {
    [ ! -f "$ACL_GRACE_FILE" ] && return
    local file_temp now_epoch age
    file_temp=$(mktemp)
    TEMP_FILES_TO_CLEAN+=("${file_temp}")
    now_epoch=$(date +%s)
    while IFS= read -r _line; do
        IFS=';' read -r status mac ip hostname epoch _ <<< "$_line"
        if [[ "$status" != "a" || -z "$mac" || -z "$epoch" || ! "$epoch" =~ ^[0-9]+$ ]]; then
            ulog "WARNING: expire_grace_entries: skipping malformed line (status=$status mac=$mac epoch=$epoch)"
            continue
        fi
        age=$(( now_epoch - epoch ))
        if (( age >= BLOCKDHCP_GRACE_SECONDS )); then
            ulog "expire_grace_entries: expired $mac (age=${age}s) → blockdhcp"
            echo "a;${mac};${ip};${hostname};" >> "$ACL_BLOCK_FILE"
            # Queue lease removal so pydhcpd stops serving this MAC from the pool.
            if ! grep -qxF "$mac" "$LEASE_REMOVE_QUEUE" 2>/dev/null; then
                echo "$mac" >> "$LEASE_REMOVE_QUEUE"
                ulog "expire_grace_entries: queued lease removal for $mac"
            fi
        else
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
    TEMP_FILES_TO_CLEAN+=("$dhcp_conf_temp")

    function read_leases() {
        # grep returns exit 1 on no-match, which is legitimate here and must
        # not abort the script. Disable pipefail for the duration of this
        # function and restore it on return.
        local _saved_opts
        _saved_opts=$(set +o | grep pipefail)
        set +o pipefail

        local temp_leases
        temp_leases=$(mktemp)
        TEMP_FILES_TO_CLEAN+=("$temp_leases")
        local current_lease=""
        local lease_content=""

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
                    host_candidate=$(echo "$host_candidate" | tr -cd 'A-Za-z0-9._-' | cut -c1-64)
                    host="${host_candidate:-no_name_$(head -c100 /dev/urandom | sha1sum | head -c10)}"

                    if [[ -n "$mac_address" && -n "$ip_address" ]]; then
                        line_lease="a;$mac_address;$ip_address;$host;"

                        if [[ "${UNIFI_HOTSPOT_ENABLED:-true}" == "true" ]]; then
                            # Authoritative: managed MAC (mac-*) or voucher-authenticated (mac-hotspot).
                            mac_authoritative=""
                            grep -qi "^a;${mac_address};" "$ACL_MAC_PATH"/mac-* 2>/dev/null \
                                && mac_authoritative="yes" || true
                            if [[ -z "$mac_authoritative" ]]; then
                                grep -qi "^a;${mac_address};" "$ACL_MAC_HOTSPOT" 2>/dev/null \
                                    && mac_authoritative="yes" || true
                            fi

                            if [[ -n "$mac_authoritative" ]]; then
                                echo "$lease_content" >> "$temp_leases"
                            elif grep -qi "^a;${mac_address};" "$ACL_BLOCK_FILE" 2>/dev/null; then
                                :
                            elif grep -qi "^a;${mac_address};" "$ACL_GRACE_FILE" 2>/dev/null; then
                                echo "$lease_content" >> "$temp_leases"
                            else
                                local wellknow_file="${HOTSPOT_PATH}/guest-wellknow.txt"
                                if grep -qxiF "${mac_address}" "${wellknow_file}" 2>/dev/null; then
                                    echo "$lease_content" >> "$temp_leases"
                                else
                                    ulog "read_leases: $mac_address → new → gracedhcp (ip=$ip_address host=$host epoch=$(date +%s))"
                                    echo "a;${mac_address};${ip_address};${host};$(date +%s);" >> "$ACL_GRACE_FILE"
                                    echo "$lease_content" >> "$temp_leases"
                                fi
                            fi
                        else
                            if ! grep -qi "^a;${mac_address};" "$ACL_MAC_PATH"/mac-* 2>/dev/null; then
                                if ! grep -qi "^a;${mac_address};" "$ACL_BLOCK_FILE" 2>/dev/null; then
                                    ulog "read_leases: $mac_address → unknown (no hotspot) → blockdhcp (ip=$ip_address)"
                                    echo "$line_lease" >> "$ACL_BLOCK_FILE"
                                    echo "$lease_content" >> "$temp_leases"
                                fi
                            else
                                echo "$lease_content" >> "$temp_leases"
                            fi
                        fi
                    fi
                    current_lease=""
                    lease_content=""
                fi
            fi
        done < "$dhcpd"

        if [[ -s "$temp_leases" ]]; then
            mv -f "$temp_leases" "$dhcpd"
        else
            local original_count=0
            original_count=$(grep -c '^lease ' "$dhcpd" 2>/dev/null) || original_count=0
            if (( original_count > 0 )); then
                ulog "WARNING: read_leases: all $original_count lease(s) filtered out — preserving original $dhcpd"
                rm -f "$temp_leases"
            else
                echo "" > "$dhcpd"
            fi
        fi
        chown pydhcpd:pydhcpd "$dhcpd"
        chmod 640 "$dhcpd"

        # Restore pipefail to whatever it was before entering this function.
        eval "$_saved_opts"
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

        # gracedhcp clients retain
        # their pydhcpd pool lease and need no fixed-address entry here.

        echo '
class "blockdhcp" {
     match pick-first-value (option dhcp-client-identifier, hardware);
        }' >>"$dhcp_conf_temp"

        while IFS= read -r line; do
            macs=$(echo "$line" | cut -d ';' -f 2)
            if echo "$macs" | grep -qE '^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$'; then
                printf '    subclass "blockdhcp" 1:%s;\n' "$macs" >>"$dhcp_conf_temp"
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
        TEMP_FILES_TO_CLEAN+=("${file_temp}")
        patterns=$(mktemp)
        TEMP_FILES_TO_CLEAN+=("${patterns}")
        grep -hiE ';[0-9a-fA-F:]+;' "$ACL_MAC_PATH"/mac-* 2>/dev/null | cut -d ";" -f2 | tr '[:upper:]' '[:lower:]' | sort -u >"$file_temp" || true

        while read -r mac_actual; do
            [ -z "$mac_actual" ] && continue
            if grep -qF ";${mac_actual};" "$ACL_BLOCK_FILE" 2>/dev/null; then
                ulog "clean_block_list: removing $mac_actual from blockdhcp (found in acl_mac, date=$(date))"
                printf ';%s;\n' "$mac_actual" >> "$patterns"
                (( removed++ )) || true
            fi
        done <"$file_temp"

        if (( removed > 0 )); then
            local _grep_rc=0
            grep -vFf "$patterns" "$ACL_BLOCK_FILE" > "$ACL_BLOCK_FILE".tmp || _grep_rc=$?
            if (( _grep_rc > 1 )); then
                ulog "ERROR: clean_block_list: grep failed (rc=$_grep_rc) — skipping update of blockdhcp"
                rm -f "$ACL_BLOCK_FILE".tmp
            else
                chmod 600 "$ACL_BLOCK_FILE".tmp
                TEMP_FILES_TO_CLEAN+=("${ACL_BLOCK_FILE}.tmp")
                mv "$ACL_BLOCK_FILE".tmp "$ACL_BLOCK_FILE"
            fi
        fi
        rm -f "$file_temp" "$patterns"
        if (( removed > 0 )); then
            ulog "clean_block_list: done (removed=$removed)"
        fi
    }

    function clean_proxy_list {
        local removed=0 patterns
        patterns=$(mktemp)
        TEMP_FILES_TO_CLEAN+=("${patterns}")
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
            TEMP_FILES_TO_CLEAN+=("${file_temp}")
            local _grep_rc=0
            grep -vFf "$patterns" "$ACL_MAC_PROXY" > "$file_temp" || _grep_rc=$?
            if (( _grep_rc > 1 )); then
                ulog "ERROR: clean_proxy_list: grep failed (rc=$_grep_rc) — skipping update of mac-proxy"
                rm -f "$file_temp"
            else
                mv "$file_temp" "$ACL_MAC_PROXY"
            fi
        fi
        rm -f "$patterns"
        if (( removed > 0 )); then
            ulog "clean_proxy_list: done (removed=$removed)"
        fi
    }


    function clean_acl {
        ulog "clean_acl: removing empty lines from ACL files"
        sed '/^$/d' -i "$ACL_BLOCK_FILE"
        sed '/^$/d' -i "$ACL_MAC_PROXY"
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
        clean_grace_list
        expire_grace_entries
    fi

    clean_acl
    clean_block_list
    clean_proxy_list
    if [[ "${UNIFI_HOTSPOT_ENABLED:-true}" == "true" ]]; then
        clean_hotspot_list
    fi
    ulog "Stopping pydhcpd"
    trap 'rm -f "${TEMP_FILES_TO_CLEAN[@]}" 2>/dev/null; systemctl reset-failed pydhcpd 2>/dev/null; systemctl is-active --quiet pydhcpd || systemctl start pydhcpd' EXIT
    systemctl stop pydhcpd
    drain_lease_queue
    ulog "Processing leases"
    read_leases
    ulog "Sorting ACL files"
    order_files_acl
    ulog "Rebuilding pydhcpd.conf"
    update_dhcp_conf
    ulog "Starting pydhcpd"
    systemctl reset-failed pydhcpd 2>/dev/null || true
    systemctl start pydhcpd || true
    sleep 1
    if ! systemctl is-active --quiet pydhcpd; then
        ulog "ERROR: pydhcpd failed to start after config rebuild — attempting backup config restore"
        if [ -f "${dhcp_conf}.bak" ]; then
            cp -f "${dhcp_conf}.bak" "$dhcp_conf"
            ulog "Restored ${dhcp_conf}.bak — retrying pydhcpd start"
            systemctl reset-failed pydhcpd 2>/dev/null || true
            systemctl start pydhcpd || true
            sleep 1
            if ! systemctl is-active --quiet pydhcpd; then
                ulog "ERROR: pydhcpd failed to start even with backup config — manual intervention required"
                _notify "$local_user" "uhotspot Error" "pydhcpd failed to start (backup also failed). Check $LOG_FILE" -i error
            else
                ulog "pydhcpd recovered with backup config"
            fi
        else
            ulog "ERROR: No backup config found — manual intervention required"
            _notify "$local_user" "uhotspot Error" "pydhcpd failed to start. Check $LOG_FILE" -i error
        fi
    fi
    trap cleanup_temp EXIT
}

drain_lease_queue() {
    [[ ! -s "$LEASE_REMOVE_QUEUE" ]] && return
    local dhcpd_leases="/etc/pydhcp/pydhcpd.leases"
    [[ ! -f "$dhcpd_leases" ]] && { : > "$LEASE_REMOVE_QUEUE"; return; }

    local tmp removed=0
    tmp=$(mktemp)
    TEMP_FILES_TO_CLEAN+=("${tmp}")
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
    if ! : > "$LEASE_REMOVE_QUEUE" 2>/dev/null; then
        ulog "WARNING: drain_lease_queue: cannot truncate $LEASE_REMOVE_QUEUE (permissions?) — queue will be reprocessed next run"
    fi

    if (( removed > 0 )); then
        ulog "drain_lease_queue: removed $removed lease(s)"
    fi
}

function duplicate() {
    local has_error=0 sources=()
    shopt -s nullglob
    sources=("$ACL_MAC_PATH"/mac-*)
    shopt -u nullglob
    if [[ "${UNIFI_HOTSPOT_ENABLED:-true}" == "true" ]]; then
        sources+=("$ACL_MAC_HOTSPOT")
    fi
    if [[ ${#sources[@]} -eq 0 ]]; then
        ulog "duplicate: no ACL source files found — skipping duplicate check"
        is_pydhcp
        return
    fi

    local field field_name dups dup locations
    for field in 2 3 4; do
        case $field in 2) field_name="MAC" ;; 3) field_name="IP" ;; 4) field_name="hostname" ;; esac
        dups=$(awk -F';' '/^a;/' "${sources[@]}" 2>/dev/null | cut -d';' -f${field} | sort | uniq -d)
        if [[ -n "$dups" ]]; then
            while IFS= read -r dup; do
                [[ -z "$dup" ]] && continue
                locations=$(grep -lF ";${dup};" "${sources[@]}" 2>/dev/null | tr '\n' ' ')
                ulog "ERROR: duplicate $field_name '$dup' in: $locations"
            done <<< "$dups"
            has_error=1
        fi
    done

    if (( has_error == 0 )); then
        is_pydhcp
    else
        echo "Duplicate Data: $(date)" | tee -a /var/log/syslog 2>/dev/null || logger -t uleases "Duplicate Data detected — see uleases.log"
        _notify "$local_user" "Warning: Abort" "Duplicate ACL data. Check $LOG_FILE" -i error
        exit 1
    fi
}
duplicate


# Final summary
_count() { local c=0; c=$(grep -c '^a;' "$1" 2>/dev/null) || c=0; echo "$c"; }
ulog "Summary: blockdhcp=$(_count "$ACL_BLOCK_FILE") | proxy=$(_count "$ACL_MAC_PROXY") | unlimited=$(_count "$ACL_MAC_UNLIMITED")$(
    [[ "${UNIFI_HOTSPOT_ENABLED:-true}" == "true" ]] && echo " | hotspot=$(_count "$ACL_MAC_HOTSPOT") | gracedhcp=$(_count "$ACL_GRACE_FILE")"
)"
ulog "uleases done"
