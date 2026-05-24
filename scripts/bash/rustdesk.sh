#!/bin/bash
# maravento.com
#
################################################################################
#
# RustDesk Client Manager
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

USER_LANG=$(locale | grep LANG= | cut -d= -f2 | cut -d_ -f1)

export LANG=${LANG:-C.UTF-8}
export LC_ALL=${LC_ALL:-C.UTF-8}

check_dependencies() {
    if ! dpkg -s curl >/dev/null 2>&1; then
        if ! apt-get -qq update; then
            echo "❌ Failed to update package lists while preparing to install curl"
            exit 1
        fi
        if ! apt-get install -y curl; then
            echo "❌ Failed to install curl"
            exit 1
        fi
    fi

    pkgs='libclang-dev ninja-build libayatana-appindicator3-1 libgstreamer1.0-dev libayatana-appindicator3-dev'
    missing=$(for p in $pkgs; do dpkg -s "$p" &>/dev/null || echo "$p"; done)
    unavailable=""
    for p in $missing; do
        apt-cache show "$p" &>/dev/null || unavailable+=" $p"
    done

    if [ -n "$unavailable" ]; then
        echo "❌ Missing dependencies not found in APT:"
        for u in $unavailable; do echo "   - $u"; done
        echo "💡 Please install them manually or enable the required repositories."
        exit 1
    fi

    if [ -n "$missing" ]; then
        echo "🔧 Installing missing dependencies: $missing"
        APT_LOCK_TIMEOUT=120
        APT_LOCK_ELAPSED=0
        APT_LOCK_FILES="/var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend"
        while lsof $APT_LOCK_FILES >/dev/null 2>&1; do
            if [ "$APT_LOCK_ELAPSED" -ge "$APT_LOCK_TIMEOUT" ]; then
                echo "❌ APT/DPKG locks still held after ${APT_LOCK_TIMEOUT}s. Aborting."
                exit 1
            fi
            echo "   Locks still held, waiting... (${APT_LOCK_ELAPSED}s elapsed)"
            sleep 5
            APT_LOCK_ELAPSED=$((APT_LOCK_ELAPSED + 5))
        done
        if ! apt-get -qq update; then
            echo "❌ Failed to update package lists"
            exit 1
        fi
        if ! apt-get install -y $missing; then
            echo "❌ Failed to install dependencies"
            exit 1
        fi
    fi
}

setup_keyboard() {
    if [ -z "$local_user" ]; then
        echo "⚠️  Warning: Could not detect local user, skipping keyboard setup"
        return
    fi

    user_home=$(eval echo ~$local_user)
    XPROFILE="$user_home/.xprofile"

    if [ ! -f "$XPROFILE" ]; then
        touch "$XPROFILE"
        chown $local_user:$local_user "$XPROFILE" 2>/dev/null || true
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
        chown $local_user:$local_user "$XPROFILE" 2>/dev/null || true
    fi
}

install_rustdesk() {
    check_dependencies

    VER_TAG=$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk/releases/latest | grep tag_name | cut -d '"' -f 4 | sed 's/v//')
    if [ -z "$VER_TAG" ]; then
        echo "❌ Failed to fetch latest version"
        exit 1
    fi

    if dpkg -l | grep -q '^ii  rustdesk'; then
        INSTALLED_VER=$(dpkg -l rustdesk | grep '^ii' | awk '{print $3}')
        echo "ℹ️  RustDesk installed: $INSTALLED_VER"
    else
        INSTALLED_VER=""
        echo "ℹ️  RustDesk not installed"
    fi

    echo "ℹ️  Latest version: $VER_TAG"

    if [ "$INSTALLED_VER" = "$VER_TAG" ]; then
        echo "✅ You already have the latest version. Nothing to do."
        return
    fi

    read -rp "Do you want to install/update RustDesk to version $VER_TAG? (y/n): " RESP
    if [[ ! "$RESP" =~ ^[Yy]$ ]]; then
        echo "⚠️  Installation/update canceled."
        return
    fi

    DEB_FILE="rustdesk-${VER_TAG}-x86_64.deb"
    SHA256_FILE="rustdesk-${VER_TAG}-x86_64.deb.sha256"
    BASE_URL="https://github.com/rustdesk/rustdesk/releases/download/${VER_TAG}"

    cd /tmp
    if ! wget -q "${BASE_URL}/${DEB_FILE}"; then
        echo "❌ Download failed"
        rm -f "$DEB_FILE"
        exit 1
    fi
    if wget -q "${BASE_URL}/${SHA256_FILE}" 2>/dev/null; then
        EXPECTED_SHA256=$(awk '{print $1}' "$SHA256_FILE")
        ACTUAL_SHA256=$(sha256sum "$DEB_FILE" | awk '{print $1}')
        rm -f "$SHA256_FILE"
        if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
            echo "❌ Integrity check failed for $DEB_FILE. Aborting."
            rm -f "$DEB_FILE"
            exit 1
        fi
    else
        ACTUAL_SHA256=$(sha256sum "$DEB_FILE" | awk '{print $1}')
        echo "📋 $DEB_FILE SHA256: $ACTUAL_SHA256"
    fi

    echo "📦 Installing package..."
    if dpkg -i "./$DEB_FILE"; then
        setup_keyboard
        rm -f "$DEB_FILE"
        echo "✅ RustDesk $VER_TAG installed successfully"
    else
        echo "❌ Installation failed"
        rm -f "$DEB_FILE"
        exit 1
    fi
}

remove_rustdesk() {
    if ! dpkg -l | grep -q '^ii  rustdesk'; then
        echo "ℹ️  RustDesk is not installed"
        return
    fi

    echo "🗑️  Removing RustDesk..."
    if apt-get remove --purge -y rustdesk; then
        echo "✅ RustDesk removed successfully"
    else
        echo "❌ Failed to remove RustDesk"
        exit 1
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
read option

case $option in
    1)
        install_rustdesk
        ;;
    2)
        remove_rustdesk
        ;;
    3)
        echo "👋 Goodbye!"
        exit 0
        ;;
    *)
        echo "❌ Invalid option"
        exit 1
        ;;
esac
