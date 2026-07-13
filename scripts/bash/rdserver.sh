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

set -euo pipefail

RD_USER="rustdesk"
RD_DATA_DIR="/var/lib/rustdesk-server"
RD_LOG_DIR="/var/log/rustdesk-server"
CONF_DIR="/etc/rustdesk-server"
CONF_FILE="$CONF_DIR/rdserver.conf"
HBBS_UNIT="/lib/systemd/system/rustdesk-hbbs.service"
HBBR_UNIT="/lib/systemd/system/rustdesk-hbbr.service"

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

    if [ ${#missing[@]} -gt 0 ]; then
        echo "INFO: Installing missing dependencies: ${missing[*]}"
        APT_LOCK_TIMEOUT=120
        APT_LOCK_ELAPSED=0
        APT_LOCK_FILES="/var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend"
        while lsof $APT_LOCK_FILES >/dev/null 2>&1; do
            if [ "$APT_LOCK_ELAPSED" -ge "$APT_LOCK_TIMEOUT" ]; then
                echo "ERROR: APT/DPKG locks still held after ${APT_LOCK_TIMEOUT}s. Aborting."
                exit 1
            fi
            echo "   Locks still held, waiting... (${APT_LOCK_ELAPSED}s elapsed)"
            sleep 5
            APT_LOCK_ELAPSED=$((APT_LOCK_ELAPSED + 5))
        done
        if ! apt-get -qq update || ! apt-get install -y "${missing[@]}"; then
            echo "ERROR: Failed to install dependencies: ${missing[*]}"
            exit 1
        fi
    fi
}

ensure_service_user() {
    if ! id "$RD_USER" &>/dev/null; then
        useradd --system --no-create-home --shell /usr/sbin/nologin "$RD_USER"
    fi
    mkdir -p "$RD_DATA_DIR" "$RD_LOG_DIR"
    chown -R "$RD_USER:$RD_USER" "$RD_DATA_DIR" "$RD_LOG_DIR"
}

# Rewrite ExecStart/User/Group on both units using $RELAY_HOST (must be set)
# and restart the services. Safe to re-run: each sed replaces the whole line.
patch_units() {
    if [ -z "${RELAY_HOST:-}" ]; then
        echo "ERROR: RELAY_HOST is not set, cannot configure the services."
        return 1
    fi

    sed -i "s#^ExecStart=.*#ExecStart=/usr/bin/hbbs -r ${RELAY_HOST}#" "$HBBS_UNIT"
    sed -i "s#^User=.*#User=${RD_USER}#" "$HBBS_UNIT"
    sed -i "s#^Group=.*#Group=${RD_USER}#" "$HBBS_UNIT"

    sed -i "s#^User=.*#User=${RD_USER}#" "$HBBR_UNIT"
    sed -i "s#^Group=.*#Group=${RD_USER}#" "$HBBR_UNIT"

    systemctl daemon-reload
    systemctl enable rustdesk-hbbs.service rustdesk-hbbr.service >/dev/null 2>&1 || true
    systemctl restart rustdesk-hbbs.service rustdesk-hbbr.service
}

apply_config() {
    if [ ! -f "$CONF_FILE" ]; then
        echo "ERROR: No configuration found. Run 'Configure Relay Host' first."
        return 1
    fi
    RELAY_HOST=""
    # shellcheck disable=SC1090
    . "$CONF_FILE"
    patch_units
}

configure_relay_host() {
    local suggested
    suggested=$(curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || true)
    [ -n "$suggested" ] && echo "INFO: Detected public IP: $suggested"

    read -rp "Server address for clients (IP/domain): " RELAY_HOST
    RELAY_HOST="${RELAY_HOST:-$suggested}"
    if [ -z "$RELAY_HOST" ]; then
        echo "WARNING: No host provided, configuration canceled."
        return 1
    fi

    mkdir -p "$CONF_DIR"
    printf 'RELAY_HOST=%s\n' "$RELAY_HOST" > "$CONF_FILE"
    patch_units
    echo "OK: Relay host set to: $RELAY_HOST"
}

install_server() {
    check_dependencies

    RELEASE_JSON=$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest || true)
    VER_TAG=$(echo "$RELEASE_JSON" | jq -r '.tag_name' 2>/dev/null || true)
    if [ -z "$VER_TAG" ] || [ "$VER_TAG" = "null" ]; then
        echo "ERROR: Failed to fetch latest version"
        exit 1
    fi

    if dpkg -l rustdesk-server-hbbs 2>/dev/null | grep -q '^ii'; then
        INSTALLED_VER=$(dpkg -l rustdesk-server-hbbs | grep '^ii' | awk '{print $3}')
        echo "INFO: RustDesk Server installed: $INSTALLED_VER"
    else
        INSTALLED_VER=""
        echo "INFO: RustDesk Server not installed"
    fi

    echo "INFO: Latest version: $VER_TAG"

    if [ "$INSTALLED_VER" = "$VER_TAG" ]; then
        echo "OK: You already have the latest version. Nothing to do."
        return
    fi

    HBBS_DEB="rustdesk-server-hbbs_${VER_TAG}_amd64.deb"
    HBBR_DEB="rustdesk-server-hbbr_${VER_TAG}_amd64.deb"
    BASE_URL="https://github.com/rustdesk/rustdesk-server/releases/download/${VER_TAG}"

    cd /tmp
    for deb in "$HBBS_DEB" "$HBBR_DEB"; do
        EXPECTED_SHA256=$(echo "$RELEASE_JSON" | jq -r --arg name "$deb" '.assets[] | select(.name == $name) | .digest' | sed 's/^sha256://')
        if [ -z "$EXPECTED_SHA256" ] || [ "$EXPECTED_SHA256" = "null" ]; then
            echo "ERROR: Failed to obtain the expected checksum for ${deb} from GitHub. Aborting."
            rm -f "$HBBS_DEB" "$HBBR_DEB"
            exit 1
        fi

        if ! wget -q "${BASE_URL}/${deb}"; then
            echo "ERROR: Download failed: $deb"
            rm -f "$HBBS_DEB" "$HBBR_DEB"
            exit 1
        fi

        ACTUAL_SHA256=$(sha256sum "$deb" | awk '{print $1}')
        if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
            echo "ERROR: Integrity check failed for $deb. Aborting."
            rm -f "$HBBS_DEB" "$HBBR_DEB"
            exit 1
        fi
    done

    echo "INFO: Installing packages..."
    DPKG_OUT=$(mktemp)
    if dpkg -i "./$HBBS_DEB" "./$HBBR_DEB" >"$DPKG_OUT" 2>&1; then
        rm -f "$HBBS_DEB" "$HBBR_DEB" "$DPKG_OUT"
    else
        echo "ERROR: Installation failed"
        cat "$DPKG_OUT" >&2
        rm -f "$HBBS_DEB" "$HBBR_DEB" "$DPKG_OUT"
        exit 1
    fi

    ensure_service_user

    if [ -f "$CONF_FILE" ]; then
        apply_config
    else
        configure_relay_host
    fi

    echo "OK: RustDesk Server $VER_TAG installed successfully"
    echo "TIP: Use option 6 to show the server's public key for client configuration."
}

remove_server() {
    if ! dpkg -l rustdesk-server-hbbs 2>/dev/null | grep -q '^ii'; then
        echo "INFO: RustDesk Server is not installed"
        return
    fi

    echo "INFO: Removing RustDesk Server..."
    systemctl stop rustdesk-hbbs.service rustdesk-hbbr.service 2>/dev/null || true

    APT_OUT=$(mktemp)
    if apt-get remove --purge -y rustdesk-server-hbbs rustdesk-server-hbbr >"$APT_OUT" 2>&1; then
        rm -f "$APT_OUT"
    else
        echo "ERROR: Failed to remove RustDesk Server"
        cat "$APT_OUT" >&2
        rm -f "$APT_OUT"
        exit 1
    fi

    echo "WARNING: this invalidates the key for ALL connected clients."
    read -rp "Also delete server data (key) at $RD_DATA_DIR? (y/n): " RESP
    if [[ "$RESP" =~ ^[Yy]$ ]]; then
        rm -rf "$RD_DATA_DIR" "$RD_LOG_DIR" "$CONF_DIR"
        echo "OK: Server data removed."
    fi

    if id "$RD_USER" &>/dev/null; then
        read -rp "Also remove the '$RD_USER' system user? (y/n): " RESP
        [[ "$RESP" =~ ^[Yy]$ ]] && userdel "$RD_USER"
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
    KEY_FILE="$RD_DATA_DIR/id_ed25519.pub"
    if [ ! -f "$KEY_FILE" ]; then
        echo "WARNING: Public key not found yet at $KEY_FILE (start the server first so hbbs can generate it)."
        return 1
    fi
    echo "INFO: Set as Key + ID/Relay Server in RustDesk client settings:"
    cat "$KEY_FILE"
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
