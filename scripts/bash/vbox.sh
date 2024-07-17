#!/bin/bash
# by maravento.com

# Virtualbox install | remove
# tested: Ubuntu 22.04 | 24.04

# LOCAL USER (sudo user no root)
local_user=$(who | head -1 | awk '{print $1;}')

clear
printf "\n"

# checking root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# checking script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi

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
    apt-get -y install virtualbox-7.0
    dpkg --configure -a
    apt-get -f -y install
    # install Extension Pack
    export VBOX_VER=$(VBoxManage --version | awk 'END {print $1}' | cut -d 'r' -f 1)
    wget -c http://download.virtualbox.org/virtualbox/$VBOX_VER/Oracle_VM_VirtualBox_Extension_Pack-$VBOX_VER.vbox-extpack
    VBoxManage extpack install Oracle_VM_VirtualBox_Extension_Pack-$VBOX_VER.vbox-extpack
    # configure
    usermod -a -G vboxusers $USER
    #adduser $USER vboxsf # for host
    update-grub
    /sbin/vboxconfig
    # check status vboxdrv
    #systemctl status vboxdrv
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
