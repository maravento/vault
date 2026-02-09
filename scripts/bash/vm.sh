#!/bin/bash
# maravento.com
#
# Start | Stop VMs Virtualbox

# how to use:           /path_to/vm.sh {start|stop|shutdown|reset|status}
# update-rc.d add:      update-rc.d vm.sh defaults 99 01
# remove:               update-rc.d -f vm.sh remove
# confirm update-rc.d:  ls -al /etc/rc?.d/ | grep vm.sh
# add user vboxusers:   usermod -a -G vboxusers $USER # where $USER is your user

echo "Virtualbox Starting. Wait..."
printf "\n"

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# checking root
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# checking script execution
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

# LOCAL USER
local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}' || who | head -1 | awk '{print $1}')
# Fallback
if [ -z "$local_user" ]; then
    local_user=$(ls -l /home | grep '^d' | head -1 | awk '{print $3}')
    if [ -z "$local_user" ]; then
        echo "ERROR: Cannot determine local user"
        exit 1
    fi
    echo "Using fallback user: $local_user"
fi

### VARIABLES
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
