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

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

# LOCAL USER (multi-strategy detection with validation)
local_user=""
# 1. Local graphical session (:0)
local_user=$(who | awk '/\(:0\)/{print $1; exit}')
# 2. Parent process logname (works well with sudo)
[ -z "$local_user" ] && local_user=$(logname 2>/dev/null || true)
# 3. SUDO_USER variable (when run via sudo from terminal)
[ -z "$local_user" ] && local_user="${SUDO_USER:-}"
# 4. First active session user (SSH or other)
[ -z "$local_user" ] && local_user=$(who | awk 'NR==1{print $1}')
# 5. First valid home directory
[ -z "$local_user" ] && local_user=$(ls -l /home 2>/dev/null | awk '/^d/{print $3; exit}')
# Validate the user actually exists on the system
if [ -z "$local_user" ] || ! id "$local_user" &>/dev/null; then
    echo "ERROR: Cannot determine a valid local user"
    exit 1
fi
echo "Using local user: $local_user"

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
