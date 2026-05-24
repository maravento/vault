#!/bin/bash
# maravento.com
#
################################################################################
#
# DHCP Leases & ACL Manager (pydhcpd)
#
# DESCRIPTION:
#   Advanced DHCP lease management script that:
#   - Parses and cleans /etc/pydhcp/pydhcpd.leases
#   - Detects unauthorized clients and adds them to block lists
#   - Dynamically rebuilds /etc/pydhcp/pydhcpd.conf based on ACL sources
#   - Applies static mappings (MAC → IP) from ACL files
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
#   - Optional WPAD/PAC support (activated by install.sh)
#   - Optional Unifi Hotspot integration (controlled via pyleases.env)
#
# REQUIREMENTS:
#   - pydhcpd installed and running
#   - ACL directories and files as defined in pyleases.env
#   - Root privileges
#   - python3 (for network calculations on first run)
#
# ACL FORMAT:
#   a;MAC;IP;HOSTNAME;
#
# ACL HOTSPOT:
#   a;MAC;IP;HOSTNAME;END_TIME_EPOCH;
#
# NOTES:
#   - Designed for environments enforcing DHCP-based access control
#   - Incorrect ACL data may disrupt IP assignments
#   - On first run, pyleases.env is created with network/path configuration
#   - Delete pyleases.env to re-run setup
#
# OPTIONAL ENTERPRISE MODULE: UniFi Hotspot Integration (independent block)
#
# DESCRIPTION:
#   Optional integration layer that:
#   - Imports hotspot client data (mac-hotspot, guest-pending)
#   - Extends DHCP reservations for hotspot users
#   - Synchronizes hotspot-related ACL entries
#
# USAGE:
#   - Controlled via UNIFI_HOTSPOT_ENABLED in pyleases.env
#   - Can be safely disabled without affecting core DHCP logic
#
################################################################################

echo "Leases Start. Wait..."
printf "\n"

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
rm -f "$SCRIPT_LOCK"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

# LOCAL USER (multi-strategy detection with validation)
local_user=""
# 1. Local graphical session (:0)
local_user=$(who | awk '/\(:0\)/{print $1; exit}')
# 2. Parent process logname (works well with sudo)
[ -z "$local_user" ] && local_user=$(logname 2>/dev/null || true)
# 3. SUDO_USER variable (when run via sudo from terminal)
[ -z "$local_user" ] && local_user="${SUDO_USER:-}"
# 4. First active session user (SSH or other)
[ -z "$local_user" ] && local_user=$(who | awk 'NR==1{print $1}')
# 5. First valid home directory
[ -z "$local_user" ] && local_user=$(ls -l /home 2>/dev/null | awk '/^d/{print $3; exit}')
# Validate the user actually exists on the system
if [ -z "$local_user" ] || ! id "$local_user" &>/dev/null; then
    echo "ERROR: Cannot determine a valid local user"
    exit 1
fi
echo "Using local user: $local_user"

### VARIABLES
# date — used inline where needed

# =============================================================================
# ENV SETUP
# =============================================================================
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

    UNIFI_HOTSPOT_ENABLED=false
    if [ -d "/etc/unhotspot" ]; then
        while true; do
            read -rp "Enable Unifi Hotspot integration? (compatible only with Unifi Network) [false]: " HOTSPOT_ANSWER
            HOTSPOT_ANSWER="${HOTSPOT_ANSWER:-false}"
            if [[ "$HOTSPOT_ANSWER" == "true" || "$HOTSPOT_ANSWER" == "false" ]]; then
                UNIFI_HOTSPOT_ENABLED="$HOTSPOT_ANSWER"
                break
            else
                echo "Please answer true or false"
            fi
        done
    fi

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
HOTSPOT_PATH=/etc/unhotspot

# ACL files
ACL_MAC_PROXY=/etc/acl/acl_mac/mac-proxy.txt
ACL_MAC_TRANSPARENT=/etc/acl/acl_mac/mac-transparent.txt
ACL_MAC_UNLIMITED=/etc/acl/acl_mac/mac-unlimited.txt
ACL_MAC_HOTSPOT=/etc/unhotspot/mac-hotspot.txt
ACL_GUEST_PENDING=/etc/unhotspot/guest-pending.txt
ACL_BLOCK_FILE=/etc/acl/acl_dhcp/blockdhcp.txt

# Features
UNIFI_HOTSPOT_ENABLED=$UNIFI_HOTSPOT_ENABLED
EOF
    chmod 600 "$env_file"
    echo "Configuration saved to $env_file"
}

ENV_FILE="$(dirname "$0")/pyleases.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "Configuration file not found. Running setup..."
    setup_env "$ENV_FILE"
fi
source "$ENV_FILE"

# =============================================================================
# UNIFI HOTSPOT (ENTERPRISE) — comment this block if not using Unifi hotspot
# =============================================================================
# Controlled via UNIFI_HOTSPOT_ENABLED in pyleases.env

# -----------------------------------------------------------------------------
# VERIFICATION FUNCTIONS
# -----------------------------------------------------------------------------

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
    chmod 775 /etc/pydhcp
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
    chmod 644 "/etc/pydhcp/pydhcpd.conf"
    chown root:root "/etc/pydhcp/pydhcpd.conf"
}

verify_directories() {
    for dir in "$ACL_MAC_PATH" "$ACL_DHCP_PATH"; do
        if [ ! -d "$dir" ]; then
            echo "ERROR: Directory $dir does not exist"
            exit 1
        fi
    done
    if [[ "${UNIFI_HOTSPOT_ENABLED:-false}" == "true" ]]; then
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
    if [[ "${UNIFI_HOTSPOT_ENABLED:-false}" == "true" ]]; then
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
    fi
}

# -----------------------------------------------------------------------------
# RUN VERIFICATIONS
# -----------------------------------------------------------------------------
verify_dhcp_service
verify_dhcp_files
verify_dhcp_config
verify_directories
initialize_empty_files

### LEASES

# -----------------------------------------------------------------------------
# UNIFI HOTSPOT FUNCTIONS — comment this block if not using Unifi hotspot
# -----------------------------------------------------------------------------
function guest_pending_fixed() {
    for line in $(cat "$ACL_GUEST_PENDING" 2>/dev/null); do
        macsource=$(echo "$line" | cut -d ';' -f 2)
        ipsource=$(echo "$line" | cut -d ';' -f 3)
        usersource=$(echo "$line" | cut -d ';' -f 4)
        echo "
    host pending_${usersource} {
    hardware ethernet ${macsource};
    fixed-address ${ipsource};
                }" >>"$dhcp_conf_temp"
    done
}

function clean_hotspot_list() {
    while read line; do
        mac_actual=$(echo "$line" | cut -d ';' -f 2)
        grep -vF "$mac_actual" "$ACL_MAC_HOTSPOT" > "$ACL_MAC_HOTSPOT".tmp && mv "$ACL_MAC_HOTSPOT".tmp "$ACL_MAC_HOTSPOT"
    done <"$ACL_MAC_UNLIMITED"
}
# -----------------------------------------------------------------------------

function is_iscdhcp() {
    dhcpd=/etc/pydhcp/pydhcpd.leases
    dhcpd_temp=/etc/pydhcp/pydhcpd.leases.temp
    dhcp_conf="/etc/pydhcp/pydhcpd.conf"
    dhcp_conf_temp="/etc/pydhcp/pydhcpd.conf.temp"
    echo "" >"$dhcp_conf_temp"

    function read_leases {
        num_line_actual=0
        while read line; do
            num_line_actual=$(($num_line_actual + 1))
            if $(echo "$line" | grep -E -q 'lease [0-9,.]+ {'); then
                host="no_name_$(get_cadena_random 10)"
                mac_address=""
                ip_address=$(echo "$line" | grep -E -o '([0-9]{1,3}\.){3}[0-9]{1,3}')
                num_line_ini_lease=$num_line_actual
                num_line_end_lease=0
                continue
            fi

            if $(echo "$line" | grep -E -q 'client-hostname "[^"]+";'); then
                host_candidate=$(echo "$line" | cut -d'"' -f2 | tr " " "_")
                if [[ -n "$host_candidate" ]]; then
                    host="$host_candidate"
                fi
                if [[ $mac_address != "" && $(grep -F "$mac_address;" "$ACL_MAC_PATH"/mac-* "$ACL_BLOCK_FILE" 2>/dev/null | grep -E ";no_name_[^;]+;") != "" ]]; then
                    line_aux=$(grep -F "$mac_address;" "$ACL_MAC_PATH"/mac-* "$ACL_BLOCK_FILE" 2>/dev/null | grep -E ";no_name_[^;]+;" | cut -d":" -f2- | head -1)
                    wcstatus_aux=$(echo "$line_aux" | cut -d ';' -f 1)
                    ipsource_aux=$(echo "$line_aux" | cut -d ';' -f 3)
                    date_aux=$(echo "$line_aux" | cut -d ';' -f 5)
                    for _f in "$ACL_BLOCK_FILE" "$ACL_MAC_PATH"/mac-*; do
                        [ -f "$_f" ] || continue
                        awk -F';' -v mac="$mac_address" -v w="$wcstatus_aux" -v ip="$ipsource_aux" \
                            -v h="$host" -v d="$date_aux" \
                            '$2==mac && $4~/^no_name_/ { $0=w";"mac";"ip";"h";"d } { print }' \
                            "$_f" > "$_f.tmp" && mv "$_f.tmp" "$_f"
                    done
                fi
                continue
            fi

            if $(echo "$line" | grep -E -q 'hardware ethernet [0-9,a-f,:]+;'); then
                mac_address=$(echo "$line" | grep -E -o '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}')
                continue
            fi

            if $(echo "$line" | grep -E -q '}'); then
                num_line_end_lease=$num_line_actual
                if [[ $host != "" && $mac_address != "" && $ip_address != "" ]]; then
                    line_lease="a;$mac_address;$ip_address;$host;"
                    if [[ $(grep -o "$mac_address" "$ACL_MAC_PATH"/mac-*) == "" ]]; then
                        if [[ $(grep -o "$mac_address" "$ACL_BLOCK_FILE") == "" ]]; then
                            echo "$line_lease" >>"$ACL_BLOCK_FILE"
                            sed "$num_line_ini_lease,$num_line_end_lease!d" "$dhcpd" >>"$dhcpd_temp"
                        fi
                    else
                        sed "$num_line_ini_lease,$num_line_end_lease!d" "$dhcpd" >>"$dhcpd_temp"
                        echo "" >>"$dhcpd_temp"
                    fi
                fi
            fi

        done <"$dhcpd"

        if [[ -e "$dhcpd_temp" ]]; then
            mv -f "$dhcpd_temp" "$dhcpd"
            chown pydhcpd:pydhcpd "$dhcpd"
        else
            echo "" >"$dhcpd"
            chown pydhcpd:pydhcpd "$dhcpd"
        fi
    }

    function update_dhcp_conf {
        echo "# pydhcpd Configuration
authoritative;
#option wpad code 252 = text;
server-identifier $SERV_DHCP;
deny duplicates;
one-lease-per-client true;
deny declines;
deny client-updates;
ping-check true;
log-facility local7;
ddns-update-style none;
        " >"$dhcp_conf_temp"

        acl_sources=$(cat "$ACL_MAC_PATH"/mac-* 2>/dev/null)

        if [[ "${UNIFI_HOTSPOT_ENABLED:-false}" == "true" ]]; then
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
                echo "
    host $usersource {
    hardware ethernet $macsource;
    fixed-address $ipsource;
                }" >>"$dhcp_conf_temp"
            fi
        done <<< "$all_sources"

        if [[ "${UNIFI_HOTSPOT_ENABLED:-false}" == "true" ]]; then
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
    #option wpad \"http://$SERV_DHCP:18100/wpad.pac\";
    option routers $SERV_DHCP;
    option subnet-mask $SERV_MASK;
    option broadcast-address $SERV_BROADCAST;
    #option domain-name \"example.org\";
    option domain-name-servers $SERV_DNS;
	min-lease-time 2592000; # 30 days
	default-lease-time 2592000; # 30 days
	max-lease-time 2592000; # 30 days
    pool {
        min-lease-time 120;
        default-lease-time 120;
        max-lease-time 120;
        deny members of \"blockdhcp\";
        range $SERV_INI_RANGE_BLOCK $SERV_END_RANGE_BLOCK;
    }
}
        " >>"$dhcp_conf_temp"

        mv -f "$dhcp_conf_temp" "$dhcp_conf"
    }

    function clean_block_list {
        file_temp=$(mktemp)
        grep -E ';[0-9,a-f,:]+;' "$ACL_MAC_PATH"/mac-* | cut -d ";" -f2 >"$file_temp"
        while read line; do
            mac_actual=$(echo "$line" | cut -d ';' -f 2)
            grep -vF "$mac_actual" "$ACL_BLOCK_FILE" > "$ACL_BLOCK_FILE".tmp && mv "$ACL_BLOCK_FILE".tmp "$ACL_BLOCK_FILE"
        done <"$file_temp"
        rm -f "$file_temp"
    }

    function clean_proxy_list {
        local file_temp
        file_temp=$(mktemp)
        while read line; do
            mac_actual=$(echo "$line" | cut -d ';' -f 2)
            grep -vF "$mac_actual" "$ACL_MAC_PROXY" > "$file_temp" && mv "$file_temp" "$ACL_MAC_PROXY"
        done <"$ACL_MAC_UNLIMITED"
        rm -f "$file_temp"
    }

    function clean_transparent_list {
        local file_temp
        file_temp=$(mktemp)
        while read line; do
            mac_actual=$(echo "$line" | cut -d ';' -f 2)
            grep -vF "$mac_actual" "$ACL_MAC_TRANSPARENT" > "$file_temp" && mv "$file_temp" "$ACL_MAC_TRANSPARENT"
        done <"$ACL_MAC_UNLIMITED"
        rm -f "$file_temp"
    }

    function clean_acl {
        sed '/^$/d' -i "$ACL_BLOCK_FILE"
        sed '/^$/d' -i "$ACL_MAC_PROXY"
        sed '/^$/d' -i "$ACL_MAC_TRANSPARENT"
        sed '/^$/d' -i "$ACL_MAC_UNLIMITED"
        if [[ "${UNIFI_HOTSPOT_ENABLED:-false}" == "true" ]]; then
            sed '/^$/d' -i "$ACL_MAC_HOTSPOT"
        fi
    }

    function get_cadena_random {
        head -c100 /dev/urandom | sha1sum | head -c10
    }

    function order_files_acl {
        sort -V "$ACL_BLOCK_FILE" -o "$ACL_BLOCK_FILE"
        if [[ "${UNIFI_HOTSPOT_ENABLED:-false}" == "true" ]]; then
            sort -t';' -k3,3V -u "$ACL_MAC_HOTSPOT" -o "$ACL_MAC_HOTSPOT"
        fi
    }

    clean_acl
    clean_block_list
    clean_proxy_list
    if [[ "${UNIFI_HOTSPOT_ENABLED:-false}" == "true" ]]; then
        clean_hotspot_list
    fi
    clean_transparent_list

    systemctl stop pydhcpd
    read_leases
    order_files_acl
    update_dhcp_conf
    systemctl start pydhcpd
}

# Stops the service if there are duplicates
function duplicate() {
    if [[ "${UNIFI_HOTSPOT_ENABLED:-false}" == "true" ]]; then
        aclall=$(for field in 2 3 4; do
            cat "$ACL_MAC_PATH"/mac-* "$ACL_MAC_HOTSPOT" \
                | cut -d\; -f${field} | sort | uniq -d
        done)
    else
        aclall=$(for field in 2 3 4; do
            cut -d\; -f${field} "$ACL_MAC_PATH"/mac-* | sort | uniq -d
        done)
    fi

    if [ "${aclall}" == "" ]; then
        is_iscdhcp
        echo OK
    else
        echo "Duplicate Data: $(date) $aclall" | tee -a /var/log/syslog
        sudo -u "$local_user" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u "$local_user")/bus \
            notify-send "Warning: Abort" "Duplicate: $aclall. $(date)" -i error
        exit
    fi
}
duplicate

echo "Done"
