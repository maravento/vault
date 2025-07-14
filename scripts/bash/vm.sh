#!/bin/bash
# maravento.com

# Start | Stop VMs Virtualbox

# how to use:           /path_to/vm.sh {start|stop|shutdown|reset|status}
# update-rc.d add:      update-rc.d vm.sh defaults 99 01
# remove:               update-rc.d -f vm.sh remove
# confirm update-rc.d:  ls -al /etc/rc?.d/ | grep vm.sh
# add user vboxusers:   usermod -a -G vboxusers $USER # where $USER is your user

echo "Virtualbox Starting. Wait..."
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

### VARIABLES
# LOCAL USER (sudo user no root)
local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}' || who | head -1 | awk '{print $1}')
# replace "my_vm_name" with your vm name
# Set name of VM (e.j: VMNAME="win10") or UUID (e.j.: VMNAME="4ec6acc1-a232-566d-a040-6bc4aadc19a6")
VMNAME="my_vm"

### FUNCTIONS
case "$1" in
start)
    echo "Starting $VMNAME..."
    sudo -H -u $local_user VBoxManage startvm "$VMNAME" --type headless
    ;;
stop)
    echo "Saving State $VMNAME..."
    sudo -H -u $local_user VBoxManage controlvm "$VMNAME" savestate
    sleep 20
    ;;
shutdown)
    echo "Shutting Down $VMNAME..."
    sudo -H -u $local_user VBoxManage controlvm "$VMNAME" acpipowerbutton
    sleep 20
    ;;
reset)
    echo "Resetting $VMNAME..."
    sudo -H -u $local_user VBoxManage controlvm "$VMNAME" reset
    ;;
status)
    echo -n "VMNAME->"
    sudo -H -u $local_user VBoxManage showvminfo "$VMNAME" --machinereadable | grep "VMState=" | cut -d "=" -f2
    exit 1
    ;;
esac
exit 0
