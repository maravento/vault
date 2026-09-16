#!/bin/bash
# maravento.com
#
################################################################################
#
# Start | Stop VMs Virtualbox
#
# Usage: /path_to/vm.sh {start|stop|shutdown|reset|status}
# Add user to vboxusers: usermod -a -G vboxusers $USER
#
################################################################################

set -uo pipefail

# root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root -- abort"
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
    echo "ERROR: No valid local user found. Create one with sudo access."
    exit 1
fi
echo "Using local user: $local_user"

# dependencies (version-variable package)
if ! command -v VBoxManage &>/dev/null; then
    echo "ERROR: VirtualBox (VBoxManage) is not installed." >&2
    exit 1
fi

echo "Virtualbox Starting. Wait..."

# VARIABLES
# Set name of VM (e.g: win10) or UUID (e.g.: 4ec6acc1-a232-566d-a040-6bc4aadc19a6)
read -rp "Enter the VM name or UUID to manage: " vm_name
if [ -z "$vm_name" ]; then
    echo "ERROR: VM name cannot be empty"
    exit 1
fi

# FUNCTIONS
if ! sudo -H -u "$local_user" VBoxManage showvminfo "$vm_name" &>/dev/null; then
    echo "ERROR: VM '$vm_name' not found or not accessible"
    exit 1
fi

case "${1:-}" in
start)
    echo "Starting $vm_name..."
    sudo -H -u "$local_user" VBoxManage startvm "$vm_name" --type headless
    ;;
stop)
    echo "Saving State $vm_name..."
    sudo -H -u "$local_user" VBoxManage controlvm "$vm_name" savestate
    sleep 20
    ;;
shutdown)
    echo "Shutting Down $vm_name..."
    sudo -H -u "$local_user" VBoxManage controlvm "$vm_name" acpipowerbutton
    sleep 20
    ;;
reset)
    echo "Resetting $vm_name..."
    sudo -H -u "$local_user" VBoxManage controlvm "$vm_name" reset
    ;;
status)
    echo -n "VM->"
    sudo -H -u "$local_user" VBoxManage showvminfo "$vm_name" --machinereadable | grep 'VMState=' | cut -d '=' -f2
    exit 0
    ;;
*)
    echo "Usage: $0 {start|stop|shutdown|reset|status}"
    exit 1
    ;;
esac
exit 0
