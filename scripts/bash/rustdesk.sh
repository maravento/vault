#!/bin/bash
# maravento.com
#
# RustDesk Client

# Check root permissions
if [ "$EUID" -ne 0 ]; then
    echo "❌ This script requires root permissions (sudo)"
    exit 1
fi

# check script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi

# LOCAL USER
# Get real user (not root) - multiple fallback methods
local_user=$(logname 2>/dev/null || echo "$SUDO_USER")
# If not found or is root, try detecting active graphical user
if [ -z "$local_user" ] || [ "$local_user" = "root" ]; then
    local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}')
fi
# As a final fallback, take the first logged user
if [ -z "$local_user" ]; then
    local_user=$(who | head -1 | awk '{print $1}')
fi
# Clean possible spaces or line breaks
local_user=$(echo "$local_user" | xargs)

# Detect user's language BEFORE modifying LANG variables
USER_LANG=$(locale | grep LANG= | cut -d= -f2 | cut -d_ -f1)

# Set locale for script execution
export LANG=${LANG:-C.UTF-8}
export LC_ALL=${LC_ALL:-C.UTF-8}

# Check dependencies
check_dependencies() {
    echo "🔍 Checking dependencies..."
    
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
        echo "🔧 Releasing APT/DPKG locks..."
        killall -q apt apt-get dpkg 2>/dev/null
        rm -f /var/lib/apt/lists/lock
        rm -f /var/cache/apt/archives/lock
        rm -f /var/lib/dpkg/lock
        rm -f /var/lib/dpkg/lock-frontend
        rm -rf /var/lib/apt/lists/*
        dpkg --configure -a
        
        echo "📦 Installing: $missing"
        apt-get -qq update
        if ! apt-get -y install $missing; then
            echo "❌ Error installing: $missing"
            exit 1
        fi
    else
        echo "✅ Dependencies OK"
    fi
}

# Setup keyboard layout based on system language
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
    
    # Detect keyboard layout from system language
    case "$USER_LANG" in
        es) KB_LAYOUT="latam" ;;      # Spanish - Latin America
        en) KB_LAYOUT="us" ;;         # English - US
        fr) KB_LAYOUT="fr" ;;         # French
        de) KB_LAYOUT="de" ;;         # German
        it) KB_LAYOUT="it" ;;         # Italian
        pt) KB_LAYOUT="br" ;;         # Portuguese - Brazil
        ru) KB_LAYOUT="ru" ;;         # Russian
        ja) KB_LAYOUT="jp" ;;         # Japanese
        zh) KB_LAYOUT="cn" ;;         # Chinese
        ko) KB_LAYOUT="kr" ;;         # Korean
        ar) KB_LAYOUT="ara" ;;        # Arabic
        tr) KB_LAYOUT="tr" ;;         # Turkish
        pl) KB_LAYOUT="pl" ;;         # Polish
        nl) KB_LAYOUT="nl" ;;         # Dutch
        sv) KB_LAYOUT="se" ;;         # Swedish
        no) KB_LAYOUT="no" ;;         # Norwegian
        da) KB_LAYOUT="dk" ;;         # Danish
        fi) KB_LAYOUT="fi" ;;         # Finnish
        cs) KB_LAYOUT="cz" ;;         # Czech
        hu) KB_LAYOUT="hu" ;;         # Hungarian
        ro) KB_LAYOUT="ro" ;;         # Romanian
        el) KB_LAYOUT="gr" ;;         # Greek
        he) KB_LAYOUT="il" ;;         # Hebrew
        th) KB_LAYOUT="th" ;;         # Thai
        vi) KB_LAYOUT="vn" ;;         # Vietnamese
        *) KB_LAYOUT="us" ;;          # Default to US
    esac
    
    if ! grep -q "setxkbmap $KB_LAYOUT" "$XPROFILE"; then
        echo "setxkbmap $KB_LAYOUT" >> "$XPROFILE"
        chown $local_user:$local_user "$XPROFILE" 2>/dev/null
    fi
}

# Install RustDesk
# Install RustDesk
install_rustdesk() {
    # Check if already installed
    if command -v rustdesk >/dev/null 2>&1; then
        echo "ℹ️  RustDesk is already installed (version: $(rustdesk --version 2>/dev/null || echo 'unknown'))"
        echo "   Skipping installation."
        return
    fi

    check_dependencies
    
    echo "📥 Downloading latest RustDesk version..."
    VER_TAG=$(curl -s https://api.github.com/repos/rustdesk/rustdesk/releases/latest | grep tag_name | cut -d '"' -f 4 | sed 's/v//')
    
    if [ -z "$VER_TAG" ]; then
        echo "❌ Failed to fetch latest version"
        exit 1
    fi
    
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
        echo "✅ RustDesk installed successfully"
    else
        echo "❌ Installation failed"
        rm -f rustdesk-*.deb
        exit 1
    fi
}

# Remove RustDesk
remove_rustdesk() {
    if ! dpkg -l | grep -q rustdesk; then
        echo "ℹ️  RustDesk is not installed"
        exit 0
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

# Main menu
show_menu() {
    echo "================================"
    echo "   RUSTDESK CLIENT MANAGER"
    echo "================================"
    echo "1. Install RustDesk Client"
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
