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
# WPAD/PAC OPTION (option 252)
# If you need WPAD/PAC for proxy auto-configuration:
# 1. Install and configure Apache2
# 2. Create virtual host on port 18100
# 3. Create wpad.pac file in Apache document root
# 4. Set WPAD_ENABLED=true in /etc/pydhcp/tools/pyleases.env
#
# NOTE on logging:
# - Writes to /var/log/pydhcp.log. Rotation is normally deployed by
#   pyinstall.sh (/etc/logrotate.d/pydhcp); this script just ensures the
#   config exists in case it runs without a fresh install.
#
################################################################################

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# logging
log_file="/var/log/pydhcp.log"
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" | tee -a "$log_file" 2>/dev/null || true
}

# Delimits where a new run starts in the log — useful with heavy activity
# (dozens of MACs coming and going per run).
echo "────────────────────────────────────────────────────────────────────────────────" | tee -a "$log_file" 2>/dev/null || true

# Start
log "pyleases start..."

if [ "$(id -u)" != "0" ]; then
    log "ERROR: This script must be run as root"
    exit 1
fi

# pyinstall.sh normally deploys this at install time; make sure it exists
# in case this script runs on its own (e.g. env restored without reinstall).
logrotate_conf="/etc/logrotate.d/pydhcp"
if [ ! -f "$logrotate_conf" ]; then
    cat > "$logrotate_conf" <<'EOF'
/var/log/pydhcp.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 640 root pydhcpd
}
EOF
    chmod 644 "$logrotate_conf"
    chown root:root "$logrotate_conf"
    log "Created logrotate config: $logrotate_conf"
fi

SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    log "Script $(basename "$0") is already running"
    exit 1
fi

TEMP_FILES_TO_CLEAN=()
PYDHCPD_NEEDS_RESTART=0
cleanup_temp() {
    for f in "${TEMP_FILES_TO_CLEAN[@]}"; do
        rm -f "$f" 2>/dev/null
    done
    # Lockfile is NOT removed: deleting it creates a TOCTOU race
    # where two processes could flock different inodes of the same path.
    if [ "$PYDHCPD_NEEDS_RESTART" = "1" ]; then
        systemctl is-active --quiet pydhcpd || systemctl start pydhcpd
    fi
}
trap cleanup_temp EXIT

local_user=""
local_user=$(who | awk '/\(:0\)/{print $1; exit}')
[ -z "$local_user" ] && local_user=$(logname 2>/dev/null || true)
[ -z "$local_user" ] && local_user="${SUDO_USER:-}"
[ -z "$local_user" ] && local_user=$(who | awk 'NR==1{print $1}')
if [ -z "$local_user" ] || ! id "$local_user" &>/dev/null; then
    log "ERROR: Cannot determine a valid local user"
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
        validate_ip "$SERV_DHCP" && break || log "Invalid IP, try again"
    done

    while true; do
        read -rp "Netmask [255.255.255.0]: " SERV_MASK
        SERV_MASK="${SERV_MASK:-255.255.255.0}"
        validate_mask "$SERV_MASK" && break || log "Invalid netmask, try again"
    done

    SERV_SUBNET=$(SERV_DHCP="$SERV_DHCP" SERV_MASK="$SERV_MASK" python3 -c '
import ipaddress
import os
net = ipaddress.IPv4Network(os.environ["SERV_DHCP"] + "/" + os.environ["SERV_MASK"], strict=False)
print(net.network_address)
')
    SERV_BROADCAST=$(SERV_DHCP="$SERV_DHCP" SERV_MASK="$SERV_MASK" python3 -c '
import ipaddress
import os
net = ipaddress.IPv4Network(os.environ["SERV_DHCP"] + "/" + os.environ["SERV_MASK"], strict=False)
print(net.broadcast_address)
')
    log "Subnet: $SERV_SUBNET"
    log "Broadcast: $SERV_BROADCAST"

    NET_BASE="${SERV_DHCP%.*}"
    while true; do
        read -rp "Block pool start (last octet, e.g. 230): " POOL_START_OCT
        if [[ "$POOL_START_OCT" =~ ^[0-9]+$ ]] && (( POOL_START_OCT >= 1 && POOL_START_OCT <= 254 )); then
            SERV_INI_RANGE_BLOCK="${NET_BASE}.${POOL_START_OCT}"
            break
        fi
        log "Invalid value, enter a number between 1 and 254"
    done

    while true; do
        read -rp "Block pool end (last octet, e.g. 235): " POOL_END_OCT
        if [[ "$POOL_END_OCT" =~ ^[0-9]+$ ]] && (( POOL_END_OCT > POOL_START_OCT && POOL_END_OCT <= 254 )); then
            SERV_END_RANGE_BLOCK="${NET_BASE}.${POOL_END_OCT}"
            break
        fi
        log "Pool end must be greater than pool start ($POOL_START_OCT) and <= 254"
    done

    while true; do
        read -rp "DNS servers (e.g. 8.8.8.8,1.1.1.1): " SERV_DNS
        validate_dns "$SERV_DNS" && break || log "Invalid DNS format, try again"
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
ACL_MAC_UNLIMITED=/etc/acl/acl_mac/mac-unlimited.txt
ACL_BLOCK_FILE=/etc/acl/acl_dhcp/blockdhcp.txt

# Lease cleanup interval in seconds (should be <= pool min-lease-time)
CLEANUP_INTERVAL=60

# DHCP timing (seconds) (min-lease|default-lease|max-lease -time)
AUTHORIZED_LEASE_TIME=2592000

# WPAD/PAC support (requires Apache2 on port 18100 with wpad.pac)
WPAD_ENABLED=false

# Ping check: pydhcpd pings each IP before OFFER to detect conflicts.
# Set to false in environments with strict ICMP firewall rules.
PING_CHECK_ENABLED=true
EOF
    chmod 640 "$env_file"
    chown root:pydhcpd "$env_file"
    log "Configuration saved to $env_file"
}

ENV_FILE="$(dirname "$0")/pyleases.env"
if [ ! -f "$ENV_FILE" ]; then
    log "Configuration file not found. Running setup..."
    setup_env "$ENV_FILE"
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
        case "$key" in
            SERV_DHCP|SERV_SUBNET|SERV_BROADCAST|SERV_MASK|SERV_INI_RANGE_BLOCK|SERV_END_RANGE_BLOCK|SERV_DNS|\
            ACL_PATH|ACL_MAC_PATH|ACL_DHCP_PATH|ACL_MAC_PROXY|ACL_MAC_UNLIMITED|ACL_BLOCK_FILE|\
            CLEANUP_INTERVAL|AUTHORIZED_LEASE_TIME|WPAD_ENABLED|PING_CHECK_ENABLED)
                printf -v "$key" '%s' "$value"
                ;;
            *)
                ;;
        esac
    done < "$file"
}
load_env_file "$ENV_FILE"

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
        log "ERROR: pydhcpd is not installed"
        exit 1
    fi
    if ! systemctl is-active --quiet pydhcpd; then
        log "ERROR: pydhcpd is not running"
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
        log "ERROR: /etc/pydhcp/pydhcpd.conf does not exist"
        exit 1
    fi
    chmod 640 "/etc/pydhcp/pydhcpd.conf"
    chown root:pydhcpd "/etc/pydhcp/pydhcpd.conf"
}

verify_directories() {
    for dir in "$ACL_MAC_PATH" "$ACL_DHCP_PATH"; do
        if [ ! -d "$dir" ]; then
            log "ERROR: Directory $dir does not exist"
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
    for file in "$ACL_MAC_PROXY" "$ACL_MAC_UNLIMITED"; do
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
log "Verification OK — pydhcpd active, paths valid"

function is_pydhcp() {
    dhcpd=/etc/pydhcp/pydhcpd.leases
    dhcp_conf="/etc/pydhcp/pydhcpd.conf"
    dhcp_conf_temp="/etc/pydhcp/pydhcpd.conf.temp"
    echo "" >"$dhcp_conf_temp"
    TEMP_FILES_TO_CLEAN+=("$dhcp_conf_temp")

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

                        shopt -s nullglob
                        acl_mac_files=("$ACL_MAC_PATH"/mac-*)
                        shopt -u nullglob
                        if [ ${#acl_mac_files[@]} -eq 0 ] || ! grep -qi "^a;${mac_address};" "${acl_mac_files[@]}" 2>/dev/null; then
                            if ! grep -qi "^a;${mac_address};" "$ACL_BLOCK_FILE" 2>/dev/null; then
                                log "read_leases: $mac_address → unknown → blockdhcp (ip=$ip_address host=$host)"
                                echo "$line_lease" >> "$ACL_BLOCK_FILE"
                                echo "$lease_content" >> "$temp_leases"
                            else
                                log "read_leases: $mac_address → blocked (lease discarded)"
                            fi
                        else
                            log "read_leases: $mac_address → authoritative (ip=$ip_address)"
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
        log "read_leases: done (leases_kept=$leases_kept)"

        if [[ -s "$temp_leases" ]]; then
            mv -f "$temp_leases" "$dhcpd"
            chown pydhcpd:pydhcpd "$dhcpd"
            chmod 640 "$dhcpd"
        elif [[ -s "$dhcpd" ]]; then
            # Parser kept nothing but the source file was not empty: this can
            # mean every lease was genuinely blocked, but it can just as
            # easily mean the parser failed to recognize the format. Either
            # way, silently truncating a non-empty leases file is worse than
            # leaving stale data for pydhcpd's own expiry to clean up.
            log "read_leases: WARNING — kept 0 leases but $dhcpd was not empty; leaving it untouched to avoid data loss"
        else
            : > "$dhcpd"
            chown pydhcpd:pydhcpd "$dhcpd"
            chmod 640 "$dhcpd"
        fi
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

        while IFS= read -r line; do
            wcstatus=$(echo "$line" | cut -d ';' -f 1)
            macsource=$(echo "$line" | cut -d ';' -f 2)
            ipsource=$(echo "$line" | cut -d ';' -f 3)
            usersource=$(echo "$line" | cut -d ';' -f 4)
            if [[ $wcstatus == "a" ]]; then
                # Validate every field before writing it into the config so an
                # ACL entry cannot inject arbitrary dhcpd directives.
                if ! [[ $macsource =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
                    log "update_dhcp_conf: skipping entry, invalid MAC: $macsource"
                    continue
                fi
                if ! [[ $ipsource =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                    log "update_dhcp_conf: skipping entry, invalid IP: $ipsource"
                    continue
                fi
                if ! [[ $usersource =~ ^[A-Za-z0-9._-]{1,63}$ ]]; then
                    log "update_dhcp_conf: skipping entry, invalid hostname: $usersource"
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
        local removed=0
        file_temp=$(mktemp)
        TEMP_FILES_TO_CLEAN+=("$file_temp")
        TEMP_FILES_TO_CLEAN+=("${ACL_BLOCK_FILE}.tmp")
        shopt -s nullglob
        acl_mac_files=("$ACL_MAC_PATH"/mac-*)
        shopt -u nullglob
        if [ ${#acl_mac_files[@]} -gt 0 ]; then
            grep -hE ';[0-9a-f:]+;' "${acl_mac_files[@]}" 2>/dev/null | cut -d ";" -f2 >"$file_temp"
        else
            : >"$file_temp"
        fi
        while read -r mac_actual; do
            if grep -qF ";${mac_actual};" "$ACL_BLOCK_FILE" 2>/dev/null; then
                log "clean_block_list: removing $mac_actual from blockdhcp (found in acl_mac)"
                (( removed++ )) || true
            fi
            grep -vF ";${mac_actual};" "$ACL_BLOCK_FILE" > "$ACL_BLOCK_FILE".tmp
            chmod 600 "$ACL_BLOCK_FILE".tmp
            mv "$ACL_BLOCK_FILE".tmp "$ACL_BLOCK_FILE"
        done <"$file_temp"
        rm -f "$file_temp"
        log "clean_block_list: done (removed=$removed)"
    }

    function clean_proxy_list {
        local file_temp removed=0
        file_temp=$(mktemp)
        TEMP_FILES_TO_CLEAN+=("$file_temp")
        while IFS= read -r line; do
            mac_actual=$(echo "$line" | cut -d ';' -f 2)
            if grep -qF ";${mac_actual};" "$ACL_MAC_PROXY" 2>/dev/null; then
                log "clean_proxy_list: removing $mac_actual from mac-proxy (found in mac-unlimited)"
                (( removed++ )) || true
            fi
            grep -vF ";${mac_actual};" "$ACL_MAC_PROXY" > "$file_temp"
            mv "$file_temp" "$ACL_MAC_PROXY"
        done <"$ACL_MAC_UNLIMITED"
        rm -f "$file_temp"
        log "clean_proxy_list: done (removed=$removed)"
    }


    function clean_acl {
        log "clean_acl: removing empty lines from ACL files"
        sed '/^$/d' -i "$ACL_BLOCK_FILE"
        sed '/^$/d' -i "$ACL_MAC_PROXY"
        sed '/^$/d' -i "$ACL_MAC_UNLIMITED"
    }

    function order_files_acl {
        sort -V "$ACL_BLOCK_FILE" -o "$ACL_BLOCK_FILE"
    }

    clean_acl
    clean_block_list
    clean_proxy_list

    log "Stopping pydhcpd"
    systemctl stop pydhcpd
    if systemctl is-active --quiet pydhcpd; then
        log "ERROR: Stopping pydhcpd FAILED — still active, aborting before touching config/ACLs"
        _notify "$local_user" "Warning: Abort" "pydhcpd did not stop, aborting. $(date)" -i error
        exit 1
    fi
    log "Stopping pydhcpd: done"
    PYDHCPD_NEEDS_RESTART=1
    log "Processing leases"
    read_leases
    log "Sorting ACL files"
    order_files_acl
    log "Rebuilding pydhcpd.conf"
    update_dhcp_conf
    log "Starting pydhcpd"
    systemctl start pydhcpd
    if ! systemctl is-active --quiet pydhcpd; then
        log "ERROR: Starting pydhcpd FAILED — check 'systemctl status pydhcpd'"
        _notify "$local_user" "Warning: Abort" "pydhcpd did not start after reload. $(date)" -i error
        exit 1
    fi
    log "Starting pydhcpd: done"
    PYDHCPD_NEEDS_RESTART=0
}

function duplicate() {
    aclall=$(
        shopt -s nullglob
        acl_mac_files=("$ACL_MAC_PATH"/mac-*)
        shopt -u nullglob
        if [ ${#acl_mac_files[@]} -gt 0 ]; then
            for field in 2 3 4; do
                awk -F';' '/^a;/' "${acl_mac_files[@]}" 2>/dev/null \
                    | cut -d\; -f${field} | sort | uniq -d
            done
        fi
    )
    if [ "${aclall}" == "" ]; then
        log "Duplicate check: OK"
        is_pydhcp
    else
        log "ERROR: Duplicate data detected: $aclall"
        log "Duplicate Data: $aclall"
        _notify "$local_user" "Warning: Abort" "Duplicate: $aclall. $(date)" -i error
        exit 1
    fi
}
duplicate

_count() { local c; c=$(grep -c '^a;' "$1" 2>/dev/null) || true; echo "${c:-0}"; }
log "Summary: blockdhcp=$(_count "$ACL_BLOCK_FILE") | proxy=$(_count "$ACL_MAC_PROXY") | unlimited=$(_count "$ACL_MAC_UNLIMITED")"

# End
log "pyleases done at: $(date)"
