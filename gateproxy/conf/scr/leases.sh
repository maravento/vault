#!/bin/bash
# maravento.com
#
# DHCP Leases & ACL Manager (ISC DHCP Server)
#
# DESCRIPTION:
#   Advanced DHCP lease management script that:
#   - Parses and cleans /var/lib/dhcp/dhcpd.leases
#   - Detects unauthorized clients and adds them to block lists
#   - Dynamically rebuilds /etc/dhcp/dhcpd.conf based on ACL sources
#   - Applies static mappings (MAC → IP) from ACL files
#   - Removes duplicates and enforces consistency across data sources
#   - Safely restarts the ISC DHCP Server service
#
# FEATURES:
#   - Locking mechanism to prevent concurrent executions (flock)
#   - Lease filtering and selective persistence
#   - Automatic cleanup and normalization of ACL files
#   - Duplicate detection with fail-safe abort
#
# REQUIREMENTS:
#   - isc-dhcp-server
#   - ACL files located in /etc/acl
#   - Root privileges
#
# ACL FORMAT:
#   a;MAC;IP;HOSTNAME;
#
# ACL HOTSPOT
#   a;MAC;IP;HOSTNAME;END_TIME_EPOCH;
#
# NOTES:
#   - Designed for environments enforcing DHCP-based access control
#   - Incorrect ACL data may disrupt IP assignments
#
# -----------------------------------------------------------------------------
# OPTIONAL ENTERPRISE MODULE: UniFi Hotspot Integration (independent block)
#
# DESCRIPTION:
#   Optional integration layer that:
#   - Imports hotspot client data (mac-hotspot, guest-pending)
#   - Extends DHCP reservations for hotspot users
#   - Synchronizes hotspot-related ACL entries
#
# USAGE:
#   - Controlled via UNIFI_HOTSPOT_ENABLED=true/false
#   - Can be safely disabled without affecting core DHCP logic
# -----------------------------------------------------------------------------

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

### VARIABLES
acl_path="/etc/acl"
acl_mac_path="$acl_path/acl_mac"
acl_dhcp_path="$acl_path/acl_dhcp"
dhcp_path="/etc/dhcp"
# date
script_date=$(date)

# =============================================================================
# UNIFI HOTSPOT (ENTERPRISE) — comment this block if not using Unifi hotspot
# =============================================================================
UNIFI_HOTSPOT_ENABLED=false
hotspot_path="/etc/unhotspot"
# =============================================================================

# -----------------------------------------------------------------------------
# VERIFICATION FUNCTIONS
# -----------------------------------------------------------------------------

verify_dhcp_service() {
    if ! command -v dhcpd &>/dev/null; then
        echo "ERROR: isc-dhcp-server is not installed"
        exit 1
    fi
    if ! systemctl is-active --quiet isc-dhcp-server; then
        echo "ERROR: isc-dhcp-server is not running"
        exit 1
    fi
}

verify_dhcp_files() {
    mkdir -p /var/lib/dhcp
    chown root:dhcpd /var/lib/dhcp
    chmod 775 /var/lib/dhcp
    if [ ! -f /var/lib/dhcp/dhcpd.leases ]; then
        touch /var/lib/dhcp/dhcpd.leases
    fi
    chown dhcpd:dhcpd /var/lib/dhcp/dhcpd.leases
    chmod 644 /var/lib/dhcp/dhcpd.leases
}

verify_dhcp_config() {
    if [ ! -f "/etc/dhcp/dhcpd.conf" ]; then
        echo "ERROR: /etc/dhcp/dhcpd.conf does not exist"
        exit 1
    fi
    chmod 644 "/etc/dhcp/dhcpd.conf"
    chown root:root "/etc/dhcp/dhcpd.conf"
}

verify_directories() {
    for dir in "$acl_mac_path" "$acl_dhcp_path"; do
        if [ ! -d "$dir" ]; then
            echo "ERROR: Directory $dir does not exist"
            exit 1
        fi
    done
    if [[ "${UNIFI_HOTSPOT_ENABLED:-false}" == "true" ]]; then
        if [ ! -d "$hotspot_path" ]; then
            echo "ERROR: Directory $hotspot_path does not exist"
            exit 1
        fi
    fi
}

initialize_empty_files() {
    if [ ! -f "$acl_dhcp_path/blockdhcp.txt" ]; then
        touch "$acl_dhcp_path/blockdhcp.txt"
        chmod 600 "$acl_dhcp_path/blockdhcp.txt"
        chown root:root "$acl_dhcp_path/blockdhcp.txt"
    fi
    for file in mac-proxy.txt mac-transparent.txt mac-unlimited.txt; do
        if [ ! -f "$acl_mac_path/$file" ]; then
            touch "$acl_mac_path/$file"
            chmod 600 "$acl_mac_path/$file"
            chown root:root "$acl_mac_path/$file"
        fi
    done
    if [[ "${UNIFI_HOTSPOT_ENABLED:-false}" == "true" ]]; then
        if [ ! -f "$hotspot_path/mac-hotspot.txt" ]; then
            touch "$hotspot_path/mac-hotspot.txt"
            chmod 600 "$hotspot_path/mac-hotspot.txt"
            chown root:root "$hotspot_path/mac-hotspot.txt"
        fi
        if [ ! -f "$hotspot_path/guest-pending.txt" ]; then
            touch "$hotspot_path/guest-pending.txt"
            chmod 600 "$hotspot_path/guest-pending.txt"
            chown root:root "$hotspot_path/guest-pending.txt"
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
    for line in $(cat "$hotspot_path"/guest-pending.txt 2>/dev/null); do
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
        sed -i "/$mac_actual/d" "$hotspot_path"/mac-hotspot.txt
    done <"$acl_mac_path"/mac-unlimited.txt
}
# -----------------------------------------------------------------------------

function is_iscdhcp() {
    dhcpd=/var/lib/dhcp/dhcpd.leases
    dhcpd_temp=/var/lib/dhcp/dhcpd.leases.temp
    dhcp_conf="$dhcp_path/dhcpd.conf"
    dhcp_conf_temp="$dhcp_path/dhcpd.conf.temp"
    echo "" >"$dhcp_conf_temp"

    serv_dhcp=192.168.0.10
    serv_subnet=192.168.0.0
    serv_ini_range_block=192.168.0.230
    serv_end_range_block=192.168.0.235
    serv_broadcast=192.168.0.255
    serv_mask=255.255.255.0
    serv_dns=8.8.8.8,1.1.1.1

    function read_leases {
        num_line_actual=0
        while read line; do
            num_line_actual=$(($num_line_actual + 1))
            if $(echo "$line" | grep -E -q 'lease [0-9,.]+ {'); then
                host="no_name_$(get_cadena_random 10)"
                mac_address=""
                ip_address=$(echo "$line" | grep -E -o '[0-9,.]+')
                num_line_ini_lease=$num_line_actual
                num_line_end_lease=0
                continue
            fi

            if $(echo "$line" | grep -E -q 'client-hostname "[^"]+";'); then
                host=$(echo "$line" | cut -d"\"" -f2 | tr " " "_")
                if [[ $mac_address != "" && $(grep -E "$mac_address;[^;]+;no_name_[^;]+;" "$acl_mac_path"/mac-* "$acl_dhcp_path"/blockdhcp.txt) != "" ]]; then
                    line_aux=$(grep -E "$mac_address;[^;]+;no_name_[^;]+;" "$acl_mac_path"/mac-* "$acl_dhcp_path"/blockdhcp.txt | cut -d":" -f2-)
                    wcstatus_aux=$(echo "$line_aux" | cut -d ';' -f 1)
                    macsource_aux=$(echo "$line_aux" | cut -d ';' -f 2)
                    ipsource_aux=$(echo "$line_aux" | cut -d ';' -f 3)
                    date_aux=$(echo "$line_aux" | cut -d ';' -f 5)
                    sed -i "s/$line_aux/$wcstatus_aux;$macsource_aux;$ipsource_aux;$host;$date_aux/g" "$acl_dhcp_path"/blockdhcp.txt "$acl_mac_path"/mac-*
                fi
                continue
            fi

            if $(echo "$line" | grep -E -q 'hardware ethernet [0-9,a-f,:]+;'); then
                mac_address=$(echo "$line" | grep -E -o '[0-9,a-f,:]+;' | cut -d";" -f1)
                continue
            fi

            if $(echo "$line" | grep -E -q '}'); then
                num_line_end_lease=$num_line_actual
                if [[ $host != "" && $mac_address != "" && $ip_address != "" ]]; then
                    line_lease="a;$mac_address;$ip_address;$host;"
                    if [[ $(grep -o "$mac_address" "$acl_mac_path"/mac-*) == "" ]]; then
                        if [[ $(grep -o "$mac_address" "$acl_dhcp_path"/blockdhcp.txt) == "" ]]; then
                            echo "$line_lease" >>"$acl_dhcp_path"/blockdhcp.txt
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
            chown dhcpd:dhcpd "$dhcpd"
        else
            echo "" >"$dhcpd"
            chown dhcpd:dhcpd "$dhcpd"
        fi
    }

    function update_dhcp_conf {
        echo "# ISC-DHCP-Server Configuration
authoritative;
option wpad code 252 = text;
server-identifier $serv_dhcp;
deny duplicates;
one-lease-per-client true;
deny declines;
deny client-updates;
ping-check true;
log-facility local7;
ddns-update-style none;
        " >"$dhcp_conf_temp"

        acl_sources=$(cat "$acl_mac_path"/mac-* 2>/dev/null)

        if [[ "${UNIFI_HOTSPOT_ENABLED:-false}" == "true" ]]; then
            hotspot_normalized=$(awk -F';' 'NF>=5{print $1";"$2";"$3";"$4";"}' \
                "$hotspot_path/mac-hotspot.txt" 2>/dev/null || true)
            all_sources=$(printf '%s\n' "$acl_sources" "$hotspot_normalized" | sort -u)
        else
            all_sources=$acl_sources
        fi

        for line in $all_sources; do
            wcstatus=$(echo "$line" | cut -d ';' -f 1)
            macsource=$(echo "$line" | cut -d ';' -f 2)
            ipsource=$(echo "$line" | cut -d ';' -f 3)
            usersource=$(echo "$line" | cut -d ';' -f 4)
            if [[ $wcstatus == "a" ]]; then
                echo '
    host '$usersource '{
    hardware ethernet '$macsource';
    fixed-address '$ipsource';
                }' >>"$dhcp_conf_temp"
            fi
        done

        if [[ "${UNIFI_HOTSPOT_ENABLED:-false}" == "true" ]]; then
            guest_pending_fixed
        fi

        echo '
class "blockdhcp" {
     match pick-first-value (option dhcp-client-identifier, hardware);
        }' >>"$dhcp_conf_temp"

        for line in $(cat "$acl_dhcp_path"/blockdhcp.txt); do
            macs=$(echo "$line" | cut -d ';' -f 2)
            echo '    subclass "blockdhcp" 1:'$macs';' >>"$dhcp_conf_temp"
        done

        echo "" >>"$dhcp_conf_temp"

        echo "subnet $serv_subnet netmask $serv_mask {
    option wpad \"http://$serv_dhcp:18100/wpad.pac\";
    option routers $serv_dhcp;
    option subnet-mask $serv_mask;
    option broadcast-address $serv_broadcast;
    #option domain-name \"example.org\";
    option domain-name-servers $serv_dns;
	min-lease-time 2592000; # 30 days
	default-lease-time 2592000; # 30 days
	max-lease-time 2592000; # 30 days
    pool {
        min-lease-time 120;
        default-lease-time 120;
        max-lease-time 120;
        deny members of \"blockdhcp\";
        range $serv_ini_range_block $serv_end_range_block;
    }
}
        " >>"$dhcp_conf_temp"

        mv -f "$dhcp_conf_temp" "$dhcp_conf"
    }

    function clean_block_list {
        file_temp=$(mktemp)
        grep -E ';[0-9,a-f,:]+;' "$acl_mac_path"/mac-* | cut -d ";" -f2 >"$file_temp"
        while read line; do
            mac_actual=$(echo "$line" | cut -d ';' -f 2)
            sed -i "/$mac_actual/d" "$acl_dhcp_path"/blockdhcp.txt
        done <"$file_temp"
        rm -f "$file_temp"
    }

    function clean_proxy_list {
        while read line; do
            mac_actual=$(echo "$line" | cut -d ';' -f 2)
            sed -i "/$mac_actual/d" "$acl_mac_path"/mac-proxy.txt
        done <"$acl_mac_path"/mac-unlimited.txt
    }

    function clean_transparent_list {
        while read line; do
            mac_actual=$(echo "$line" | cut -d ';' -f 2)
            sed -i "/$mac_actual/d" "$acl_mac_path"/mac-transparent.txt
        done <"$acl_mac_path"/mac-unlimited.txt
    }

    function clean_acl {
        sed '/^$/d' -i "$acl_dhcp_path"/blockdhcp.txt
        sed '/^$/d' -i "$acl_mac_path"/mac-proxy.txt
        sed '/^$/d' -i "$acl_mac_path"/mac-transparent.txt
        sed '/^$/d' -i "$acl_mac_path"/mac-unlimited.txt
        if [[ "${UNIFI_HOTSPOT_ENABLED:-false}" == "true" ]]; then
            sed '/^$/d' -i "$hotspot_path"/mac-hotspot.txt
        fi
    }

    function get_cadena_random {
        head -c100 /dev/urandom | sha1sum | head -c10
    }

    function order_files_acl {
        sort -n -t . -k 3,3 -k 4,4 "$acl_dhcp_path"/blockdhcp.txt -o "$acl_dhcp_path"/blockdhcp.txt
        sort -n -t . -k 3,3 -k 4,4 "$acl_mac_path"/mac-proxy.txt -u -o "$acl_mac_path"/mac-proxy.txt
        sort -n -t . -k 3,3 -k 4,4 "$acl_mac_path"/mac-transparent.txt -u -o "$acl_mac_path"/mac-transparent.txt
        sort -n -t . -k 3,3 -k 4,4 "$acl_mac_path"/mac-unlimited.txt -u -o "$acl_mac_path"/mac-unlimited.txt
        if [[ "${UNIFI_HOTSPOT_ENABLED:-false}" == "true" ]]; then
            sort -n -t . -k 3,3 -k 4,4 "$hotspot_path"/mac-hotspot.txt -u -o "$hotspot_path"/mac-hotspot.txt
        fi
    }

    clean_acl
    clean_block_list
    clean_proxy_list
    if [[ "${UNIFI_HOTSPOT_ENABLED:-false}" == "true" ]]; then
        clean_hotspot_list
    fi
    clean_transparent_list

    /etc/init.d/isc-dhcp-server stop
    read_leases
    order_files_acl
    update_dhcp_conf
    /etc/init.d/isc-dhcp-server start
}

# Stops the service if there are duplicates
function duplicate() {
    if [[ "${UNIFI_HOTSPOT_ENABLED:-false}" == "true" ]]; then
        aclall=$(for field in 2 3 4; do
            cat "$acl_mac_path"/mac-* "$hotspot_path"/mac-hotspot.txt \
                | cut -d\; -f${field} | sort | uniq -d
        done)
    else
        aclall=$(for field in 2 3 4; do
            cut -d\; -f${field} "$acl_mac_path"/mac-* | sort | uniq -d
        done)
    fi

    if [ "${aclall}" == "" ]; then
        is_iscdhcp
        echo OK
    else
        echo "Duplicate Data: $(date) "$aclall"" | tee -a /var/log/syslog
        sudo -u $local_user DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u $local_user)/bus \
            notify-send "Warning: Abort" "Duplicate: "$aclall". $script_date" -i error
        exit
    fi
}
duplicate

echo "Done"
