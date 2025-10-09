#!/bin/bash
# maravento.com
#
# Virtualbox 7.2 install | remove
# tested: Ubuntu 24.04

echo "Virtualbox Install | Remove Starting. Wait..."
printf "\n"

# check root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
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

# check SO
UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
if [[ "$UBUNTU_ID" != "ubuntu" || ( "$UBUNTU_VERSION" != "22.04" && "$UBUNTU_VERSION" != "24.04" ) ]]; then
    echo "Unsupported system. Use at your own risk"
    # exit 1
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

### FUNCTIONS
function vboxinstall() {
    echo "Installing Virtualbox..."
    # Download and install .asc
    wget -O- https://www.virtualbox.org/download/oracle_vbox_2016.asc | gpg --dearmor | tee /usr/share/keyrings/virtualbox.gpg &>/dev/null
    # add repo
    echo deb [arch=amd64 signed-by=/usr/share/keyrings/virtualbox.gpg] http://download.virtualbox.org/virtualbox/debian $(lsb_release -sc) contrib | tee /etc/apt/sources.list.d/virtualbox.list
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
    wget -c https://download.virtualbox.org/virtualbox/$VBOX_VER/Oracle_VirtualBox_Extension_Pack-$VBOX_VER.vbox-extpack
    VBoxManage extpack install Oracle_VirtualBox_Extension_Pack-$VBOX_VER.vbox-extpack
    echo "Done. Reboot"
}

function vboxpurge() {
    echo "Removing Virtualbox..."
    sudo -u $local_user bash -c "vboxmanage list runningvms | sed -r 's/.*\{(.*)\}/\1/' | xargs -I {} VBoxManage controlvm {} poweroff"
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
    if [ "$answer" == "y" ]; then
        vboxpurge
    else
        echo "Virtualbox will not be removed."
    fi
else
    echo "Virtualbox is not installed. Do you want to install it? (y/n)"
    read answer
    if [ "$answer" == "y" ]; then
        vboxinstall
    else
        echo "Virtualbox will not be installed."
    fi
fi
