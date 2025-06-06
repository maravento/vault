#!/bin/bash
# maravento.com
#
# This script allows installing or restoring realtek drivers.
# - r8169: Default in-kernel driver included with Linux kernel.
# - r8168: Realtek's proprietary, out-of-tree driver installed via DKMS (for RTL8111/8168 series).
# - r8125: Realtek's proprietary, out-of-tree driver installed via DKMS (for RTL8125 2.5G NICs).
#
# The proprietary drivers may provide better compatibility and performance for certain Realtek NICs,
# but require installation and maintenance outside the kernel.

# Check if running as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# Function to show detected chipset
show_chipset() {
    echo "🔍 Detected chipset:"
    lspci | grep -i ethernet
}

# Function to show current Realtek kernel module
show_current_module() {
    echo "🔍 Current Realtek network module:"
    lspci -k | grep -A 2 -i ethernet | grep -i 'kernel driver'
}

# Function to install r8168 driver
install_r8168() {
    if lsmod | grep -q '^r8168'; then
        echo "⚠️ Driver 'r8168' is already active. Installation not needed."
        exit 0
    fi

    echo "🚧 Installing and configuring 'r8168' driver..."
    apt update
    apt install -y r8168-dkms

    echo "blacklist r8169" > /etc/modprobe.d/blacklist-r8169.conf

    modprobe -r r8169 2>/dev/null
    modprobe r8168

    if lsmod | grep -q '^r8168'; then
        echo "✅ Driver 'r8168' installed and in use."
    else
        echo "⚠️ Could not activate 'r8168'. Please reboot and try again."
    fi
    exit 0
}

# Function to restore r8169 driver
restore_r8169() {
    if lsmod | grep -q '^r8169'; then
        echo "⚠️ Driver 'r8169' is already active. Restore not needed."
        exit 0
    fi

    echo "🚧 Restoring 'r8169' driver..."
    rm -f /etc/modprobe.d/blacklist-r8169.conf

    modprobe -r r8168 r8125 2>/dev/null
    modprobe r8169

    if lsmod | grep -q '^r8169'; then
        echo "✅ Driver 'r8169' restored and in use."
    else
        echo "⚠️ Could not activate 'r8169'. Please reboot and try again."
    fi
    exit 0
}

# Function to install r8125 driver
install_r8125() {
    # Detect RTL8125 chipset
    if ! lspci | grep -i 'RTL8125' >/dev/null; then
        echo "⚠️ No compatible RTL8125 NIC detected. Aborting."
        exit 1
    fi

    if lsmod | grep -q '^r8125'; then
        echo "⚠️ Driver 'r8125' is already active. Installation not needed."
        exit 0
    fi

    echo "🚧 Installing and configuring 'r8125' driver..."
    apt update
    apt install -y r8125-dkms

    echo "blacklist r8169" > /etc/modprobe.d/blacklist-r8169.conf

    modprobe -r r8169 2>/dev/null
    modprobe r8125

    if lsmod | grep -q '^r8125'; then
        echo "✅ Driver 'r8125' installed and in use."
    else
        echo "⚠️ Could not activate 'r8125'. Please reboot and try again."
    fi
    exit 0
}

# MAIN
clear
show_chipset
show_current_module

while true; do
    echo ""
    echo "====== Menu ======"
    echo "1. Install r8168 (Realtek 1G proprietary DKMS driver)"
    echo "2. Restore r8169 (Default 1G in-kernel driver)"
    echo "3. Install r8125 (Realtek 2.5G proprietary DKMS driver)"
    echo "4. Exit"
    echo "=================="
    read -rp "Select an option (1-4): " option

    case $option in
        1) install_r8168 ;;
        2) restore_r8169 ;;
        3) install_r8125 ;;
        4) echo "👋 Exiting."; exit 0 ;;
        *) echo "❌ Invalid option."; continue ;;
    esac
done

