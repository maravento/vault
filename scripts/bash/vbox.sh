#!/bin/bash
# maravento.com
#
################################################################################
#
# Virtualbox 7.x install | remove
#
################################################################################

set -uo pipefail

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$SCRIPT_LOCK")
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

# LOCAL USER detection
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
    echo "ERROR: No valid local user found. Create one with sudo access."
    exit 1
fi
echo "Using local user: $local_user"

echo "Virtualbox Install | Remove Starting. Wait..."

### FUNCTIONS
function vboxinstall() {
    echo "Installing Virtualbox..."
    # Download and install .asc
    wget --timeout=30 -O- https://www.virtualbox.org/download/oracle_vbox_2016.asc | gpg --dearmor | tee /usr/share/keyrings/virtualbox.gpg &>/dev/null
    # add repo
    distro=$(lsb_release -sc 2>/dev/null || grep -oP '(?<=UBUNTU_CODENAME=)\S+' /etc/os-release 2>/dev/null || grep -oP '(?<=VERSION_CODENAME=)\S+' /etc/os-release)
    echo deb [arch=amd64 signed-by=/usr/share/keyrings/virtualbox.gpg] https://download.virtualbox.org/virtualbox/debian "$distro" contrib | tee /etc/apt/sources.list.d/virtualbox.list
    apt-get update
    # install vbox
    apt-get -y install linux-headers-$(uname -r) build-essential gcc make perl dkms bridge-utils
    apt-get -y install virtualbox-7.2
    dpkg --configure -a
    apt-get -f -y install
    # configure
    usermod -aG vboxusers $local_user
    # for host
    #adduser $local_user vboxsf
    update-grub
    /sbin/vboxconfig
    # check status vboxdrv
    #systemctl status vboxdrv
    systemctl restart vboxdrv
    # install Extension Pack
    export VBOX_VER=$(VBoxManage --version | awk 'END {print $1}' | cut -d 'r' -f 1)
    wget --timeout=30 -c https://download.virtualbox.org/virtualbox/$VBOX_VER/Oracle_VirtualBox_Extension_Pack-$VBOX_VER.vbox-extpack
    VBoxManage extpack install Oracle_VirtualBox_Extension_Pack-$VBOX_VER.vbox-extpack
    echo "Done. Reboot"
}

function vboxpurge() {
    echo "Removing Virtualbox..."
    sudo -u $local_user bash -c "VBoxManage list runningvms | grep -oP '(?<=\{)[0-9a-f-]+(?=\})' | xargs -r -I {} VBoxManage controlvm {} poweroff"
    ps ax | grep -P 'vboxwebsrv|VirtualBox|Vbox' | awk '{print $1}' | xargs kill -9 &>/dev/null
    systemctl stop vboxweb-service.service &>/dev/null
    service vboxdrv stop &>/dev/null
    killall VirtualBox iprt-VBoxTscThread VBoxSVC &>/dev/null
    VBoxManage extpack uninstall "Oracle VM VirtualBox Extension Pack"
    apt-get -y autoremove --purge $(echo $vboxversion)
    /opt/VirtualBox/uninstall.sh &>/dev/null
    apt-get -y remove --purge virtualbox*
    rm -rf /etc/vbox /opt/VirtualBox /usr/lib/virtualbox /etc/apt/sources.list.d/virtualbox.list &>/dev/null
    rm -rf /var/lib/dpkg/info/virtualbox* &>/dev/null
    # Optional: delete virtual disk config
    #rm -rf ~/.config/VirtualBox
    echo "Done"
}

vboxversion=$(dpkg -l | grep -P 'virtualbox-\d+\.\d+' | awk '{print $2}')

if [ "$vboxversion" ]; then
    echo "Virtualbox is installed. Do you want to delete it? (y/n)"
    read answer
    if [ "$answer" = "y" ]; then
        vboxpurge
    else
        echo "Virtualbox will not be removed."
    fi
else
    echo "Virtualbox is not installed. Do you want to install it? (y/n)"
    read answer
    if [ "$answer" = "y" ]; then
        vboxinstall
    else
        echo "Virtualbox will not be installed."
    fi
fi
