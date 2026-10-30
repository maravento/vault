#!/bin/bash
# maravento.com
#
################################################################################
#
# Realtek Driver Manager
# FILE: realtekdrv.sh
#
# DESCRIPTION: Switches the Realtek NIC driver between the in-kernel r8169 and
# the proprietary DKMS drivers r8168 (RTL8111/8168) and r8125 (RTL8125 2.5G).
# The proprietary ones can perform better, but need maintenance out of tree.
#
# USAGE: sudo bash realtekdrv.sh
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

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

# dependencies
for dep in pciutils kmod initramfs-tools util-linux; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep" 2>/dev/null)" != *"ok installed"* ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

# Function to show detected chipset
show_chipset() {
    echo "Detected chipset:"
    lspci | grep -i ethernet
}

# Function to show current Realtek kernel module
show_current_module() {
    echo "Current Realtek network module:"
    lspci -k | grep -A 2 -i ethernet | grep -i 'kernel driver'
}

# Function to install r8168 driver
install_r8168() {
    if lsmod | grep -q '^r8168'; then
        echo "Driver 'r8168' is already active. Installation not needed"
        return 0
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') Installing and configuring 'r8168' driver..."
    if ! apt-get -qq update; then
        echo "Failed to update package lists"
        exit 1
    fi
    if ! apt-get install -y r8168-dkms; then
        echo "Failed to install r8168-dkms"
        exit 1
    fi

    update-initramfs -u
    depmod -a

    if ! grep -qF 'blacklist r8169' /etc/modprobe.d/blacklist-r8169.conf 2>/dev/null; then
        echo "blacklist r8169" >> /etc/modprobe.d/blacklist-r8169.conf
    fi

    if lsmod | grep -q '^r8169'; then
        modprobe -r r8169 2>/dev/null
    fi
    modprobe r8168

    if lsmod | grep -q '^r8168'; then
        echo "Driver 'r8168' installed and in use"
    else
        echo "Could not activate 'r8168'. Please reboot and try again"
    fi
}

# Function to restore r8169 driver
restore_r8169() {
    if lsmod | grep -q '^r8169'; then
        echo "Driver 'r8169' is already active. Restore not needed"
        return 0
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') Restoring 'r8169' driver..."
    rm -f /etc/modprobe.d/blacklist-r8169.conf

    for realtek_mod in r8168 r8125; do
        if lsmod | grep -q "^$realtek_mod"; then
            modprobe -r "$realtek_mod" 2>/dev/null
        fi
    done

    echo "$(date '+%Y-%m-%d %H:%M:%S') Removing Realtek DKMS packages..."
    for realtek_pkg in r8168-dkms r8125-dkms; do
        if dpkg -s "$realtek_pkg" &>/dev/null && ! apt-get purge -y "$realtek_pkg"; then
            echo "Failed to remove $realtek_pkg"
            exit 1
        fi
    done

    update-initramfs -u
    depmod -a

    modprobe r8169

    if lsmod | grep -q '^r8169'; then
        echo "Driver 'r8169' restored and in use"
    else
        echo "Could not activate 'r8169'. Please reboot and try again"
    fi
}

# Function to install r8125 driver
install_r8125() {
    # Detect RTL8125 chipset
    if ! lspci | grep -i 'RTL8125' >/dev/null; then
        echo "No compatible RTL8125 NIC detected. Aborting"
        exit 1
    fi

    if lsmod | grep -q '^r8125'; then
        echo "Driver 'r8125' is already active. Installation not needed"
        return 0
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') Installing and configuring 'r8125' driver..."
    if ! apt-get -qq update; then
        echo "Failed to update package lists"
        exit 1
    fi
    if ! apt-get install -y r8125-dkms; then
        echo "Failed to install r8125-dkms"
        exit 1
    fi

    update-initramfs -u
    depmod -a

    if ! grep -qF 'blacklist r8169' /etc/modprobe.d/blacklist-r8169.conf 2>/dev/null; then
        echo "blacklist r8169" >> /etc/modprobe.d/blacklist-r8169.conf
    fi

    if lsmod | grep -q '^r8169'; then
        modprobe -r r8169 2>/dev/null
    fi
    modprobe r8125

    if lsmod | grep -q '^r8125'; then
        echo "Driver 'r8125' installed and in use"
    else
        echo "Could not activate 'r8125'. Please reboot and try again"
    fi
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

# Start the interactive workflow
clear

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: realtekdrv start..."

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
    read -rp "Select an option (1-4): " option || exit 1

    case $option in
        1) install_r8168; break ;;
        2) restore_r8169; break ;;
        3) install_r8125; break ;;
        4) break ;;
        *) echo " Invalid option"; continue ;;
    esac
done

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: realtekdrv done"
