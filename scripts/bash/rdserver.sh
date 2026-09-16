#!/bin/bash
# maravento.com
#
################################################################################
#
# RustDesk Self-Hosted Server Manager (hbbs + hbbr)
#
# Installs the official rustdesk-server .deb packages (hbbs = ID/rendezvous
# server, hbbr = relay server), runs both under a dedicated non-root system
# user, and configures hbbs with the public relay address so clients only
# need one "ID/Relay Server" entry plus the server's public key.
#
################################################################################
#
# NOTE on firewall:
# - hbbs (ID/rendezvous server) listens on: 21115/tcp, 21116/tcp+udp
# - hbbr (relay server) listens on: 21117/tcp, 21118/tcp, 21119/tcp (last two
#   are only needed for the web client)
# - This script does NOT open firewall ports automatically. Open them
#   manually (ufw/iptables/cloud security group) before clients can connect.
#
################################################################################

set -euo pipefail

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

retry_cmd() {
    local max_attempts=10
    local attempt=1
    until "$@"; do
        if [ "$attempt" -ge "$max_attempts" ]; then
            echo "ERROR: command failed after $max_attempts attempts: $*"
            exit 1
        fi
        echo "WARNING: command failed (attempt $attempt/$max_attempts), retrying in 10s: $*"
        attempt=$((attempt + 1))
        sleep 10
    done
}

rd_user="rustdesk"
rd_data_dir="/var/lib/rustdesk-server"
rd_log_dir="/var/log/rustdesk-server"
conf_dir="/etc/rustdesk-server"
conf_file="$conf_dir/rdserver.conf"
hbbs_unit="/lib/systemd/system/rustdesk-hbbs.service"
hbbr_unit="/lib/systemd/system/rustdesk-hbbr.service"

check_dependencies() {
    for c in wget dpkg systemctl; do
        command -v "$c" &>/dev/null && continue
        if [ "$c" = "systemctl" ]; then
            echo "ERROR: systemd (systemctl) not found. This script requires a systemd-based system."
            exit 1
        fi
    done

    missing=()
    command -v curl &>/dev/null || missing+=("curl")
    command -v jq &>/dev/null || missing+=("jq")
    command -v lsof &>/dev/null || missing+=("lsof")

    if [ ${#missing[@]} -gt 0 ]; then
        echo "INFO: Installing missing dependencies: ${missing[*]}"
        apt_lock_timeout=120
        apt_lock_elapsed=0
        apt_lock_files="/var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend"
        while lsof $apt_lock_files >/dev/null 2>&1; do
            if [ "$apt_lock_elapsed" -ge "$apt_lock_timeout" ]; then
                echo "ERROR: APT/DPKG locks still held after ${apt_lock_timeout}s. Aborting."
                exit 1
            fi
            echo "   Locks still held, waiting... (${apt_lock_elapsed}s elapsed)"
            sleep 5
            apt_lock_elapsed=$((apt_lock_elapsed + 5))
        done
        if ! retry_cmd apt-get -qq update || ! retry_cmd apt-get install -y "${missing[@]}"; then
            echo "ERROR: Failed to install dependencies: ${missing[*]}"
            exit 1
        fi
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
        echo "ERROR: relay_host is not set, cannot configure the services."
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

apply_config() {
    if [ ! -f "$conf_file" ]; then
        echo "ERROR: No configuration found. Run 'Configure Relay Host' first."
        return 1
    fi
    relay_host=""
    # shellcheck disable=SC1090
    . "$conf_file"
    patch_units
}

configure_relay_host() {
    local suggested
    suggested=$(curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || true)
    [ -n "$suggested" ] && echo "INFO: Detected public IP: $suggested"

    read -rp "Server address for clients (IP/domain): " relay_host
    relay_host="${relay_host:-$suggested}"
    if [ -z "$relay_host" ]; then
        echo "WARNING: No host provided, configuration canceled."
        return 1
    fi

    mkdir -p "$conf_dir"
    printf 'relay_host=%s\n' "$relay_host" > "$conf_file"
    patch_units
    echo "OK: Relay host set to: $relay_host"
}

install_server() {
    check_dependencies

    release_json=$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest || true)
    ver_tag=$(echo "$release_json" | jq -r '.tag_name' 2>/dev/null || true)
    if [ -z "$ver_tag" ] || [ "$ver_tag" = "null" ]; then
        echo "ERROR: Failed to fetch latest version"
        exit 1
    fi

    if dpkg -l rustdesk-server-hbbs 2>/dev/null | grep -q '^ii'; then
        installed_ver=$(dpkg -l rustdesk-server-hbbs | grep '^ii' | awk '{print $3}')
        echo "INFO: RustDesk Server installed: $installed_ver"
    else
        installed_ver=""
        echo "INFO: RustDesk Server not installed"
    fi

    echo "INFO: Latest version: $ver_tag"

    if [ "$installed_ver" = "$ver_tag" ]; then
        echo "OK: You already have the latest version. Nothing to do."
        return
    fi

    hbbs_deb="rustdesk-server-hbbs_${ver_tag}_amd64.deb"
    hbbr_deb="rustdesk-server-hbbr_${ver_tag}_amd64.deb"
    base_url="https://github.com/rustdesk/rustdesk-server/releases/download/${ver_tag}"

    cd /tmp
    for deb in "$hbbs_deb" "$hbbr_deb"; do
        expected_sha256=$(echo "$release_json" | jq -r --arg name "$deb" '.assets[] | select(.name == $name) | .digest' | sed 's/^sha256://')
        if [ -z "$expected_sha256" ] || [ "$expected_sha256" = "null" ]; then
            echo "ERROR: Failed to obtain the expected checksum for ${deb} from GitHub. Aborting."
            rm -f "$hbbs_deb" "$hbbr_deb"
            exit 1
        fi

        if ! retry_cmd wget -q "${base_url}/${deb}"; then
            echo "ERROR: Download failed: $deb"
            rm -f "$hbbs_deb" "$hbbr_deb"
            exit 1
        fi

        actual_sha256=$(sha256sum "$deb" | awk '{print $1}')
        if [ "$actual_sha256" != "$expected_sha256" ]; then
            echo "ERROR: Integrity check failed for $deb. Aborting."
            rm -f "$hbbs_deb" "$hbbr_deb"
            exit 1
        fi
    done

    echo "INFO: Installing packages..."
    dpkg_out=$(mktemp)
    if dpkg -i "./$hbbs_deb" "./$hbbr_deb" >"$dpkg_out" 2>&1; then
        rm -f "$hbbs_deb" "$hbbr_deb" "$dpkg_out"
    else
        echo "ERROR: Installation failed"
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

    echo "OK: RustDesk Server $ver_tag installed successfully"
    echo "TIP: Use option 6 to show the server's public key for client configuration."
}

remove_server() {
    if ! dpkg -l rustdesk-server-hbbs 2>/dev/null | grep -q '^ii'; then
        echo "INFO: RustDesk Server is not installed"
        return
    fi

    echo "INFO: Removing RustDesk Server..."
    systemctl stop rustdesk-hbbs.service rustdesk-hbbr.service 2>/dev/null || true

    apt_out=$(mktemp)
    if apt-get remove --purge -y rustdesk-server-hbbs rustdesk-server-hbbr >"$apt_out" 2>&1; then
        rm -f "$apt_out"
    else
        echo "ERROR: Failed to remove RustDesk Server"
        cat "$apt_out" >&2
        rm -f "$apt_out"
        exit 1
    fi

    echo "WARNING: this invalidates the key for ALL connected clients."
    read -rp "Also delete server data (key) at $rd_data_dir? (y/n): " user_response
    if [[ "$user_response" =~ ^[Yy]$ ]]; then
        rm -rf "$rd_data_dir" "$rd_log_dir" "$conf_dir"
        echo "OK: Server data removed."
    fi

    if id "$rd_user" &>/dev/null; then
        read -rp "Also remove the '$rd_user' system user? (y/n): " user_response
        [[ "$user_response" =~ ^[Yy]$ ]] && userdel "$rd_user"
    fi

    echo "OK: RustDesk Server removed successfully"
}

start_server() {
    systemctl start rustdesk-hbbs.service rustdesk-hbbr.service
    echo "OK: Started."
}

stop_server() {
    systemctl stop rustdesk-hbbs.service rustdesk-hbbr.service
    echo "OK: Stopped."
}

status_server() {
    systemctl status rustdesk-hbbs.service rustdesk-hbbr.service --no-pager || true
}

show_public_key() {
    key_file="$rd_data_dir/id_ed25519.pub"
    if [ ! -f "$key_file" ]; then
        echo "WARNING: Public key not found yet at $key_file (start the server first so hbbs can generate it)."
        return 1
    fi
    echo "INFO: Set as Key + ID/Relay Server in RustDesk client settings:"
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
    echo -n "Select an option: "
}

show_menu
read -r option

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
        echo "Goodbye!"
        exit 0
        ;;
    *)
        echo "ERROR: Invalid option"
        exit 1
        ;;
esac
