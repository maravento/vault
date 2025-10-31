#!/bin/bash
# maravento.com
#
# RustDesk Client Manager

# -----------------------------
# Check root permissions
# -----------------------------
if [ "$EUID" -ne 0 ]; then
    echo "❌ This script requires root permissions (sudo)"
    exit 1
fi

# -----------------------------
# Prevent multiple script runs
# -----------------------------
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi

# -----------------------------
# Detect local user
# -----------------------------
local_user=$(logname 2>/dev/null || echo "$SUDO_USER")
if [ -z "$local_user" ] || [ "$local_user" = "root" ]; then
    local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}')
fi
if [ -z "$local_user" ]; then
    local_user=$(who | head -1 | awk '{print $1}')
fi
local_user=$(echo "$local_user" | xargs)

# -----------------------------
# Detect user language
# -----------------------------
USER_LANG=$(locale | grep LANG= | cut -d= -f2 | cut -d_ -f1)

export LANG=${LANG:-C.UTF-8}
export LC_ALL=${LC_ALL:-C.UTF-8}

# -----------------------------
# Check dependencies
# -----------------------------
check_dependencies() {
    # Ensure curl is installed silently
    if ! dpkg -s curl >/dev/null 2>&1; then
        apt-get update -qq
        apt-get install -y curl
    fi

    # Other dependencies
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
        killall -q apt apt-get dpkg 2>/dev/null
        rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend
        dpkg --configure -a
        apt-get -qq update
        apt-get install -y $missing
    fi
}

# -----------------------------
# Setup keyboard layout
# -----------------------------
setup_keyboard() {
    if [ -z "$local_user" ]; then
        echo "⚠️  Warning: Could not detect local user, skipping keyboard setup"
        return
    fi

    user_home=$(eval echo ~$local_user)
    XPROFILE="$user_home/.xprofile"

    if [ ! -f "$XPROFILE" ]; then
        touch "$XPROFILE"
        chown $local_user:$local_user "$XPROFILE" 2>/dev/null
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
        chown $local_user:$local_user "$XPROFILE" 2>/dev/null
    fi
}

# -----------------------------
# Install or Update RustDesk
# -----------------------------
install_rustdesk() {
    check_dependencies

    # Get latest version from GitHub
    VER_TAG=$(curl -s https://api.github.com/repos/rustdesk/rustdesk/releases/latest | grep tag_name | cut -d '"' -f 4 | sed 's/v//')
    if [ -z "$VER_TAG" ]; then
        echo "❌ Failed to fetch latest version"
        exit 1
    fi

    # Check installed version using dpkg
    if dpkg -l | grep -q '^ii  rustdesk'; then
        INSTALLED_VER=$(dpkg -l rustdesk | grep '^ii' | awk '{print $3}')
        echo "ℹ️  RustDesk installed: $INSTALLED_VER"
    else
        INSTALLED_VER=""
        echo "ℹ️  RustDesk not installed"
    fi

    echo "ℹ️  Latest version: $VER_TAG"

    # If already latest, exit
    if [ "$INSTALLED_VER" = "$VER_TAG" ]; then
        echo "✅ You already have the latest version. Nothing to do."
        return
    fi

    # Ask user to install/update
    read -p "Do you want to install/update RustDesk to version $VER_TAG? (y/n): " RESP
    if [[ ! "$RESP" =~ ^[Yy]$ ]]; then
        echo "⚠️  Installation/update canceled."
        return
    fi

    # Download and install .deb
    cd /tmp
    wget -q https://github.com/rustdesk/rustdesk/releases/download/$VER_TAG/rustdesk-$VER_TAG-x86_64.deb
    if [ $? -ne 0 ]; then
        echo "❌ Download failed"
        rm -f rustdesk-*.deb
        exit 1
    fi

    echo "📦 Installing package..."
    dpkg -i ./rustdesk-$VER_TAG-x86_64.deb
    if [ $? -eq 0 ]; then
        setup_keyboard
        rm -f rustdesk-*.deb
        echo "✅ RustDesk $VER_TAG installed successfully"
    else
        echo "❌ Installation failed"
        rm -f rustdesk-*.deb
        exit 1
    fi
}

# -----------------------------
# Remove RustDesk
# -----------------------------
remove_rustdesk() {
    if ! dpkg -l | grep -q '^ii  rustdesk'; then
        echo "ℹ️  RustDesk is not installed"
        return
    fi

    echo "🗑️  Removing RustDesk..."
    apt-get remove --purge -y rustdesk
    if [ $? -eq 0 ]; then
        echo "✅ RustDesk removed successfully"
    else
        echo "❌ Failed to remove RustDesk"
        exit 1
    fi
}

# -----------------------------
# Main menu
# -----------------------------
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

