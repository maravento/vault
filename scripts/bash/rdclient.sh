#!/bin/bash
# maravento.com
#
################################################################################
#
# RustDesk Client Install
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

# LOCAL USER (multi-strategy detection with validation)
local_user=""
local_user=$(who | awk '/\(:0\)/{print $1; exit}')
[ -z "$local_user" ] && local_user=$(logname 2>/dev/null || true)
[ -z "$local_user" ] && local_user="${SUDO_USER:-}"
[ -z "$local_user" ] && local_user=$(who | awk 'NR==1{print $1}')
[ -z "$local_user" ] && local_user=$(ls -l /home 2>/dev/null | awk '/^d/{print $3; exit}')
if [ -z "$local_user" ] || ! id "$local_user" &>/dev/null; then
    echo "ERROR: Cannot determine a valid local user"
    exit 1
fi
echo "Using local user: $local_user"

USER_LANG=$(locale | grep LANG= | cut -d= -f2 | cut -d_ -f1) || true

export LANG=${LANG:-C.UTF-8}
export LC_ALL=${LC_ALL:-C.UTF-8}

check_dependencies() {
    if ! dpkg -s curl >/dev/null 2>&1; then
        if ! apt-get -qq update; then
            echo "ERROR: Failed to update package lists while preparing to install curl"
            exit 1
        fi
        if ! apt-get install -y curl; then
            echo "ERROR: Failed to install curl"
            exit 1
        fi
    fi

    pkgs='libclang-dev ninja-build libayatana-appindicator3-1 libgstreamer1.0-dev libayatana-appindicator3-dev'
    missing=()
    for p in $pkgs; do
        dpkg -s "$p" &>/dev/null || missing+=("$p")
    done
    unavailable=()
    for p in "${missing[@]}"; do
        apt-cache show "$p" &>/dev/null || unavailable+=("$p")
    done

    if [ ${#unavailable[@]} -gt 0 ]; then
        echo "ERROR: Missing dependencies not found in APT:"
        for u in "${unavailable[@]}"; do echo "   - $u"; done
        echo "TIP: Please install them manually or enable the required repositories."
        exit 1
    fi

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
        if ! apt-get -qq update; then
            echo "ERROR: Failed to update package lists"
            exit 1
        fi
        if ! apt-get install -y "${missing[@]}"; then
            echo "ERROR: Failed to install dependencies"
            exit 1
        fi
    fi

    # rustdesk depends on libxdo3 | libxdo4 (either one satisfies it)
    if ! dpkg -s libxdo3 &>/dev/null && ! dpkg -s libxdo4 &>/dev/null; then
        echo "INFO: Installing missing dependency: libxdo3"
        if ! apt-get install -y libxdo3; then
            echo "ERROR: Failed to install libxdo3"
            exit 1
        fi
    fi
}

setup_keyboard() {
    if [ -z "$local_user" ]; then
        echo "WARNING: Could not detect local user, skipping keyboard setup"
        return
    fi

    user_home=$(getent passwd "$local_user" | cut -d: -f6)
    XPROFILE="$user_home/.xprofile"
    local_group=$(id -gn "$local_user")

    if [ ! -f "$XPROFILE" ]; then
        touch "$XPROFILE"
        chown "$local_user:$local_group" "$XPROFILE" 2>/dev/null || true
    fi

    case "$USER_LANG" in
        es) KB_LAYOUT="latam" ;;
        en) KB_LAYOUT="us" ;;
        fr) KB_LAYOUT="fr" ;;
        de) KB_LAYOUT="de" ;;
        it) KB_LAYOUT="it" ;;
        pt) KB_LAYOUT="br" ;;
        ru) KB_LAYOUT="ru" ;;
        ja) KB_LAYOUT="jp" ;;
        zh) KB_LAYOUT="cn" ;;
        ko) KB_LAYOUT="kr" ;;
        ar) KB_LAYOUT="ara" ;;
        tr) KB_LAYOUT="tr" ;;
        pl) KB_LAYOUT="pl" ;;
        nl) KB_LAYOUT="nl" ;;
        sv) KB_LAYOUT="se" ;;
        no) KB_LAYOUT="no" ;;
        da) KB_LAYOUT="dk" ;;
        fi) KB_LAYOUT="fi" ;;
        cs) KB_LAYOUT="cz" ;;
        hu) KB_LAYOUT="hu" ;;
        ro) KB_LAYOUT="ro" ;;
        el) KB_LAYOUT="gr" ;;
        he) KB_LAYOUT="il" ;;
        th) KB_LAYOUT="th" ;;
        vi) KB_LAYOUT="vn" ;;
        *) KB_LAYOUT="us" ;;
    esac

    if ! grep -q "setxkbmap $KB_LAYOUT" "$XPROFILE"; then
        echo "setxkbmap $KB_LAYOUT" >> "$XPROFILE"
        chown "$local_user:$local_group" "$XPROFILE" 2>/dev/null || true
    fi
}

install_rustdesk() {
    check_dependencies

    VER_TAG=$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk/releases/latest | grep tag_name | cut -d '"' -f 4 | sed 's/v//' || true)
    if [ -z "$VER_TAG" ]; then
        echo "ERROR: Failed to fetch latest version"
        exit 1
    fi

    if dpkg -l rustdesk 2>/dev/null | grep -q '^ii'; then
        INSTALLED_VER=$(dpkg -l rustdesk | grep '^ii' | awk '{print $3}')
        echo "INFO: RustDesk installed: $INSTALLED_VER"
    else
        INSTALLED_VER=""
        echo "INFO: RustDesk not installed"
    fi

    echo "INFO: Latest version: $VER_TAG"

    if [ "$INSTALLED_VER" = "$VER_TAG" ]; then
        echo "OK: You already have the latest version. Nothing to do."
        return
    fi

    DEB_FILE="rustdesk-${VER_TAG}-x86_64.deb"
    BASE_URL="https://github.com/rustdesk/rustdesk/releases/download/${VER_TAG}"

    cd /tmp
    if ! wget -q "${BASE_URL}/${DEB_FILE}"; then
        echo "ERROR: Download failed"
        rm -f "$DEB_FILE"
        exit 1
    fi

    echo "INFO: Installing package..."
    DPKG_OUT=$(mktemp)
    if dpkg -i "./$DEB_FILE" >"$DPKG_OUT" 2>&1; then
        setup_keyboard
        # The .deb's own postinst enables and starts rustdesk.service on its
        # own; undo that here so the package is installed but not running
        # until the user starts it manually.
        systemctl stop rustdesk 2>/dev/null || true
        systemctl disable rustdesk 2>/dev/null || true
        rm -f "$DEB_FILE" "$DPKG_OUT"
        echo "OK: RustDesk $VER_TAG installed successfully"
        echo "INFO: Service stopped. To start it now: sudo systemctl start rustdesk"
        echo "INFO: To start it on every boot: sudo systemctl enable rustdesk"
    else
        echo "ERROR: Installation failed"
        cat "$DPKG_OUT" >&2
        rm -f "$DEB_FILE" "$DPKG_OUT"
        exit 1
    fi
}

remove_rustdesk() {
    if ! dpkg -l rustdesk 2>/dev/null | grep -q '^ii'; then
        echo "INFO: RustDesk is not installed"
        return
    fi

    echo "INFO: Removing RustDesk..."
    APT_OUT=$(mktemp)
    if apt-get remove --purge -y rustdesk >"$APT_OUT" 2>&1; then
        rm -f "$APT_OUT"
        echo "OK: RustDesk removed successfully"
    else
        echo "ERROR: Failed to remove RustDesk"
        cat "$APT_OUT" >&2
        rm -f "$APT_OUT"
        exit 1
    fi

    # apt-get purge only removes what dpkg tracks. The client also leaves
    # per-user runtime state it creates itself (dpkg never sees it), plus
    # the .xprofile line this script added in setup_keyboard().
    if [ -n "$local_user" ]; then
        user_home=$(getent passwd "$local_user" | cut -d: -f6)
        user_uid=$(id -u "$local_user" 2>/dev/null || true)

        XPROFILE="$user_home/.xprofile"
        [ -f "$XPROFILE" ] && sed -i '/^setxkbmap /d' "$XPROFILE"

        rm -rf "$user_home/.local/share/logs/RustDesk"
        [ -n "$user_uid" ] && rm -rf "/tmp/RustDesk-service" "/tmp/RustDesk-$user_uid"

        if [ -d "$user_home/.config/rustdesk" ]; then
            read -rp "Also delete saved profiles/connections at $user_home/.config/rustdesk? (y/n): " RESP
            [[ "$RESP" =~ ^[Yy]$ ]] && rm -rf "$user_home/.config/rustdesk"
        fi

        if [ -d "$user_home/Videos/RustDesk" ]; then
            read -rp "Also delete recordings at $user_home/Videos/RustDesk? (y/n): " RESP
            [[ "$RESP" =~ ^[Yy]$ ]] && rm -rf "$user_home/Videos/RustDesk"
        fi
    fi
}

show_menu() {
    echo "================================"
    echo "   RUSTDESK CLIENT MANAGER"
    echo "================================"
    echo "1. Install / Update RustDesk Client"
    echo "2. Remove RustDesk Client"
    echo "3. Exit"
    echo "================================"
    echo -n "Select an option: "
}

show_menu
read -r option

case $option in
    1)
        install_rustdesk
        ;;
    2)
        remove_rustdesk
        ;;
    3)
        echo "Goodbye!"
        exit 0
        ;;
    *)
        echo "ERROR: Invalid option"
        exit 1
        ;;
esac
