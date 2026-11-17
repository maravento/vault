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
# USAGE:
# COMMAND                  ACTION
# sudo bash realtekdrv.sh  Run (no arguments)
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

# dependencies
net_checked=0
for dep in pciutils kmod initramfs-tools util-linux iproute2 libc-bin; do
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

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Installing and configuring 'r8168' driver..."
    check_ipv4_interfaces
    check_internet
    if ! retry_cmd "update package lists" apt-get -qq update; then
        echo "Failed to update package lists"
        exit 1
    fi
    if ! retry_cmd "install packages" apt-get install -y r8168-dkms; then
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

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Restoring 'r8169' driver..."
    rm -f /etc/modprobe.d/blacklist-r8169.conf

    for realtek_mod in r8168 r8125; do
        if lsmod | grep -q "^$realtek_mod"; then
            modprobe -r "$realtek_mod" 2>/dev/null
        fi
    done

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Removing Realtek DKMS packages..."
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

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Installing and configuring 'r8125' driver..."
    check_ipv4_interfaces
    check_internet
    if ! retry_cmd "update package lists" apt-get -qq update; then
        echo "Failed to update package lists"
        exit 1
    fi
    if ! retry_cmd "install packages" apt-get install -y r8125-dkms; then
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
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: realtekdrv start..."

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
    read -rp "Select an option (1-4) [4]: " option || exit 1
    if [ -z "$option" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: no option selected, exit -skip"
        option=4
    fi

    case $option in
        1) install_r8168; break ;;
        2) restore_r8169; break ;;
        3) install_r8125; break ;;
        4) break ;;
        *) echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: invalid option -retry"; continue ;;
    esac
done

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: realtekdrv done"
