#!/bin/bash
# maravento.com
#
################################################################################
#
# Virtualbox 7.x install | remove
# FILE: vbox.sh
#
# DESCRIPTION: Installs VirtualBox 7.x from the Oracle repository, or purges
# it if a version is already present.
#
# USAGE: sudo bash vbox.sh
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

# local_user detection
detect_local_user() {
    local uid_min uid_max
    local user uid best_user="" best_uid=999999

    uid_min=$(awk '/^UID_MIN/{print $2}' /etc/login.defs 2>/dev/null)
    uid_max=$(awk '/^UID_MAX/{print $2}' /etc/login.defs 2>/dev/null)
    uid_min=${uid_min:-1000}
    uid_max=${uid_max:-60000}

    while IFS=: read -r user _ uid _ _ _ shell; do
        [ "$user" = "root" ] && continue
        [ -z "$uid" ] && continue
        [ "$uid" -lt "$uid_min" ] && continue
        [ "$uid" -gt "$uid_max" ] && continue

        case "$shell" in
            */false|*/nologin) continue ;;
        esac

        id -nG "$user" 2>/dev/null | grep -qw sudo || continue

        if [ "$uid" -lt "$best_uid" ]; then
            best_uid="$uid"
            best_user="$user"
        fi
    done </etc/passwd

    [ -n "$best_user" ] || return 1
    echo "$best_user"
}

if ! local_user=$(detect_local_user); then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no local user; create one with sudo access -abort" >&2
    exit 1
fi
echo "Using local user: $local_user"

# dependencies
for dep in wget gnupg lsb-release psmisc procps findutils systemd sudo util-linux iproute2 libc-bin; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
        exit 1
    fi
done

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: vbox start..."

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

# Define VirtualBox installation and removal operations
vboxinstall() {
    check_ipv4_interfaces
    check_internet
    echo "$(date '+%Y-%m-%d %H:%M:%S') Installing Virtualbox..."
    # Download and install .asc
    wget --timeout=30 -O- https://www.virtualbox.org/download/oracle_vbox_2016.asc | gpg --dearmor | tee /usr/share/keyrings/virtualbox.gpg &>/dev/null
    # add repo
    distro=$(lsb_release -sc 2>/dev/null || grep -oP '(?<=UBUNTU_CODENAME=)\S+' /etc/os-release 2>/dev/null || grep -oP '(?<=VERSION_CODENAME=)\S+' /etc/os-release)
    echo deb [arch=amd64 signed-by=/usr/share/keyrings/virtualbox.gpg] https://download.virtualbox.org/virtualbox/debian "$distro" contrib | tee /etc/apt/sources.list.d/virtualbox.list
    apt-get update || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot update package lists -abort" >&2
        exit 1
    }
    # install vbox
    apt-get -y install linux-headers-$(uname -r) build-essential gcc make perl dkms bridge-utils || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install prerequisites -abort" >&2
        exit 1
    }
    vbox_pkg=$(apt-cache search '^virtualbox-7\.' | awk '{print $1}' | sort -V | tail -1)
    if [ -z "$vbox_pkg" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: virtualbox-7.x unavailable for $distro -abort"
        exit 1
    fi
    apt-get -y install "$vbox_pkg" || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install VirtualBox -abort" >&2
        exit 1
    }
    dpkg --configure -a
    apt-get -f -y install
    # configure
    usermod -aG vboxusers $local_user
    # for host
    #adduser $local_user vboxsf
    update-grub
    /sbin/vboxconfig
    # check status vboxdrv
    #systemctl status vboxdrv # Optional
    systemctl restart vboxdrv
    # install Extension Pack
    export VBOX_VER=$(VBoxManage --version | awk 'END {print $1}' | cut -d 'r' -f 1)
    if ! wget --timeout=30 -c "https://download.virtualbox.org/virtualbox/$VBOX_VER/Oracle_VirtualBox_Extension_Pack-$VBOX_VER.vbox-extpack"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot download Extension Pack -abort" >&2
        return 1
    fi
    if ! VBoxManage extpack install "Oracle_VirtualBox_Extension_Pack-$VBOX_VER.vbox-extpack"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install Extension Pack -abort" >&2
        return 1
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: VirtualBox installed, reboot required"
}

vboxpurge() {
    local purge_failed=0
    echo "$(date '+%Y-%m-%d %H:%M:%S') Removing Virtualbox..."
    sudo -u $local_user bash -c "VBoxManage list runningvms | grep -oP '(?<=\{)[0-9a-f-]+(?=\})' | xargs -r -I {} VBoxManage controlvm {} poweroff"
    pkill -9 -x 'vboxwebsrv|VirtualBox' &>/dev/null || true
    systemctl stop vboxweb-service.service &>/dev/null
    service vboxdrv stop &>/dev/null
    killall VirtualBox iprt-VBoxTscThread VBoxSVC &>/dev/null
    VBoxManage extpack uninstall "Oracle VM VirtualBox Extension Pack"
    if ! apt-get -y autoremove --purge; then
        purge_failed=1
    fi
    /opt/VirtualBox/uninstall.sh &>/dev/null
    if ! apt-get -y remove --purge 'virtualbox*'; then
        purge_failed=1
    fi
    rm -rf /etc/vbox /opt/VirtualBox /usr/lib/virtualbox /etc/apt/sources.list.d/virtualbox.list &>/dev/null
    rm -rf /var/lib/dpkg/info/virtualbox* &>/dev/null
    # Optional: delete virtual disk config
    #rm -rf ~/.config/VirtualBox # Optional
    if [ "$purge_failed" -gt 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: VirtualBox data removed, packages pending -alert"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: VirtualBox packages and data removed"
    fi
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

vboxversion=$(dpkg -l | grep -P 'virtualbox-\d+\.\d+' | awk '{print $2}')

if [ "$vboxversion" ]; then
    echo "Virtualbox is installed. Do you want to delete it? (y/n)"
    read -r answer
    if [ "$answer" = "y" ]; then
        vboxpurge
    else
        echo "Virtualbox will not be removed"
    fi
else
    echo "Virtualbox is not installed. Do you want to install it? (y/n)"
    read -r answer
    if [ "$answer" = "y" ]; then
        vboxinstall || exit 1
    else
        echo "Virtualbox will not be installed"
    fi
fi

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: vbox done"
