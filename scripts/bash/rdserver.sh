#!/bin/bash
# maravento.com
#
################################################################################
#
# RustDesk Self-Hosted Server Manager (hbbs + hbbr)
# FILE: rdserver.sh
#
# DESCRIPTION: Installs the official rustdesk-server packages, hbbs for ID and
# rendezvous and hbbr for relay, under a dedicated non-root system user. Sets
# the public relay address, so a client needs one entry plus the public key.
#
# USAGE:
# COMMAND                ACTION
# sudo bash rdserver.sh  Run (no arguments)
#
# Ports: hbbs, the ID and rendezvous server, listens on 21115/tcp and
#        21116/tcp+udp. hbbr, the relay server, listens on 21117/tcp,
#        21118/tcp and 21119/tcp. The last two serve the web client only.
#        The script does not open any of them. Open them by hand, with ufw,
#        iptables or the cloud security group, before a client connects.
#
################################################################################

set -euo pipefail

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

retry_cmd() {
    [ "$#" -ge 2 ] || return 2
    local retry_label="$1" retry_attempt retry_status
    shift
    for retry_attempt in 1 2 3; do
        if "$@"; then
            return 0
        else
            retry_status=$?
        fi
        [ "$retry_attempt" -lt 3 ] || return "$retry_status"
        if declare -F log >/dev/null; then
            log "INFO: $retry_label: retry $((retry_attempt + 1))/3" >&2
        else
            printf '%s INFO: %s: retry %s/3\n' \
                "$(date '+%Y-%m-%d %H:%M:%S')" "$retry_label" \
                "$((retry_attempt + 1))" >&2
        fi
        sleep 5
    done
}

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

rd_user="rustdesk"
rd_data_dir="/var/lib/rustdesk-server"
rd_log_dir="/var/log/rustdesk-server"
conf_dir="/etc/rustdesk-server"
conf_file="$conf_dir/rdserver.conf"
hbbs_unit="/lib/systemd/system/rustdesk-hbbs.service"
hbbr_unit="/lib/systemd/system/rustdesk-hbbr.service"

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

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

# dependencies (network checks, before the menu)
net_checked=0
for dep in iproute2 libc-bin coreutils grep sed wget curl jq lsof; do
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

# The tools the script uses (wget, curl, jq, lsof) are initial dependencies
check_dependencies() {
    if ! command -v systemctl &>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: systemctl not found, systemd required -abort" >&2
        exit 1
    fi
}

ensure_service_user() {
    if ! id "$rd_user" &>/dev/null; then
        useradd --system --no-create-home --shell /usr/sbin/nologin "$rd_user"
    fi
    mkdir -p "$rd_data_dir" "$rd_log_dir"
    chown -R "$rd_user:$rd_user" "$rd_data_dir" "$rd_log_dir"
}

# Rewrite ExecStart/User/Group on both units using $relay_host (must be set)
# and restart the services. Safe to re-run: each sed replaces the whole line.
patch_units() {
    if [ -z "${relay_host:-}" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: relay_host is not set, cannot configure services -skip"
        return 1
    fi

    sed -i "s#^ExecStart=.*#ExecStart=/usr/bin/hbbs -r ${relay_host}#" "$hbbs_unit"
    sed -i "s#^User=.*#User=${rd_user}#" "$hbbs_unit"
    sed -i "s#^Group=.*#Group=${rd_user}#" "$hbbs_unit"

    sed -i "s#^User=.*#User=${rd_user}#" "$hbbr_unit"
    sed -i "s#^Group=.*#Group=${rd_user}#" "$hbbr_unit"

    systemctl daemon-reload
    systemctl enable rustdesk-hbbs.service rustdesk-hbbr.service >/dev/null 2>&1 || true
    systemctl restart rustdesk-hbbs.service rustdesk-hbbr.service
}

validate_relay_host() {
    local LC_ALL=C
    if [[ "$relay_host" == -* || ! "$relay_host" =~ ^[][a-zA-Z0-9.:-]+$ ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: invalid relay host -abort" >&2
        return 1
    fi
}

apply_config() {
    if [ ! -f "$conf_file" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: no configuration, run 'Configure Relay Host' -skip"
        return 1
    fi
    relay_host=$(sed -n 's/^relay_host=//p' "$conf_file") || return 1
    validate_relay_host || return 1
    patch_units
}

configure_relay_host() {
    local suggested
    suggested=$(curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || true)
    [ -n "$suggested" ] && echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Detected public IP: $suggested"

    read -rp "Server address for clients (IP/domain): " relay_host
    relay_host="${relay_host:-$suggested}"
    if [ -z "$relay_host" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: no host provided, configuration canceled -skip"
        return 1
    fi

    validate_relay_host || return 1
    mkdir -p "$conf_dir"
    printf 'relay_host=%s\n' "$relay_host" > "$conf_file"
    patch_units
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: relay host set to $relay_host"
}

install_server() {
    check_ipv4_interfaces
    check_internet
    check_dependencies

    release_json=$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest || true)
    ver_tag=$(echo "$release_json" | jq -r '.tag_name' 2>/dev/null || true)
    if [ -z "$ver_tag" ] || [ "$ver_tag" = "null" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: failed to fetch latest version -abort" >&2
        exit 1
    fi

    if dpkg -l rustdesk-server-hbbs 2>/dev/null | grep -q '^ii'; then
        installed_ver=$(dpkg -l rustdesk-server-hbbs | grep '^ii' | awk '{print $3}')
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: RustDesk Server installed: $installed_ver"
    else
        installed_ver=""
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: RustDesk Server not installed"
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Latest version: $ver_tag"

    if [ "$installed_ver" = "$ver_tag" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: already at latest version"
        return
    fi

    hbbs_deb="rustdesk-server-hbbs_${ver_tag}_amd64.deb"
    hbbr_deb="rustdesk-server-hbbr_${ver_tag}_amd64.deb"
    base_url="https://github.com/rustdesk/rustdesk-server/releases/download/${ver_tag}"

    # Private directory: another user cannot plant a package
    deb_dir=$(mktemp -d) || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot create temporary directory -abort" >&2; exit 1; }
    trap 'rm -rf -- "$deb_dir"' EXIT
    cd "$deb_dir"
    for deb in "$hbbs_deb" "$hbbr_deb"; do
        expected_sha256=$(echo "$release_json" | jq -r --arg name "$deb" '.assets[] | select(.name == $name) | .digest' | sed 's/^sha256://')
        if [ -z "$expected_sha256" ] || [ "$expected_sha256" = "null" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: failed to obtain checksum for ${deb} -abort" >&2
            rm -f "$hbbs_deb" "$hbbr_deb"
            exit 1
        fi

        if ! retry_cmd "download RustDesk server" wget --tries=1 -q "${base_url}/${deb}"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: download failed: $deb -abort" >&2
            rm -f "$hbbs_deb" "$hbbr_deb"
            exit 1
        fi

        actual_sha256=$(sha256sum "$deb" | awk '{print $1}')
        if [ "$actual_sha256" != "$expected_sha256" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: integrity check failed for $deb -abort" >&2
            rm -f "$hbbs_deb" "$hbbr_deb"
            exit 1
        fi
    done

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Installing packages..."
    dpkg_out=$(mktemp)
    if dpkg -i "./$hbbs_deb" "./$hbbr_deb" >"$dpkg_out" 2>&1; then
        rm -f "$hbbs_deb" "$hbbr_deb" "$dpkg_out"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: installation failed -abort" >&2
        cat "$dpkg_out" >&2
        rm -f "$hbbs_deb" "$hbbr_deb" "$dpkg_out"
        exit 1
    fi

    ensure_service_user

    if [ -f "$conf_file" ]; then
        apply_config
    else
        configure_relay_host
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: RustDesk Server $ver_tag installed"
    echo "Use option 6 to show the server public key"
}

remove_server() {
    if ! dpkg -l rustdesk-server-hbbs 2>/dev/null | grep -q '^ii'; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: RustDesk Server is not installed"
        return
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Removing RustDesk Server..."
    systemctl stop rustdesk-hbbs.service rustdesk-hbbr.service 2>/dev/null || true

    apt_out=$(mktemp)
    if apt-get remove --purge -y rustdesk-server-hbbs rustdesk-server-hbbr >"$apt_out" 2>&1; then
        rm -f "$apt_out"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: failed to remove RustDesk Server -abort" >&2
        cat "$apt_out" >&2
        rm -f "$apt_out"
        exit 1
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: this invalidates key for ALL connected clients"
    read -rp "Also delete server data (key) at $rd_data_dir? (y/n): " user_response
    if [[ "$user_response" =~ ^[Yy]$ ]]; then
        rm -rf "$rd_data_dir" "$rd_log_dir" "$conf_dir"
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: server data removed"
    fi

    if id "$rd_user" &>/dev/null; then
        read -rp "Also remove the '$rd_user' system user? (y/n): " user_response
        [[ "$user_response" =~ ^[Yy]$ ]] && userdel "$rd_user"
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: RustDesk Server removed"
}

start_server() {
    systemctl start rustdesk-hbbs.service rustdesk-hbbr.service
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: started"
}

stop_server() {
    systemctl stop rustdesk-hbbs.service rustdesk-hbbr.service
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: stopped"
}

status_server() {
    systemctl status rustdesk-hbbs.service rustdesk-hbbr.service --no-pager || true
}

show_public_key() {
    key_file="$rd_data_dir/id_ed25519.pub"
    if [ ! -f "$key_file" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: public key not found at $key_file, start server first -skip"
        return 1
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: use as Key + ID/Relay Server in RustDesk client:"
    cat "$key_file"
    echo
}

show_menu() {
    echo "================================"
    echo "  RUSTDESK SERVER MANAGER"
    echo "  (Self-Hosted: hbbs + hbbr)"
    echo "================================"
    echo "1. Install / Update Server"
    echo "2. Configure Relay Host"
    echo "3. Start"
    echo "4. Stop"
    echo "5. Status"
    echo "6. Show Server Public Key"
    echo "7. Remove Server"
    echo "8. Exit"
    echo "================================"
    echo -n "Select an option [8]: "
}

# ------------------------------------------------------------------------------
# MENU
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: rdserver start..."

show_menu
read -r option
if [ -z "$option" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: no option selected, exit -skip"
    option=8
fi

case $option in
    1)
        install_server
        ;;
    2)
        configure_relay_host
        ;;
    3)
        start_server
        ;;
    4)
        stop_server
        ;;
    5)
        status_server
        ;;
    6)
        show_public_key
        ;;
    7)
        remove_server
        ;;
    8)
        ;;
    *)
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: invalid option -abort" >&2
        exit 1
        ;;
esac

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: rdserver done"
