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

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
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

echo "Virtualbox Starting. Wait..."

### VARIABLES
# Set name of VM (e.g: win10) or UUID (e.g.: 4ec6acc1-a232-566d-a040-6bc4aadc19a6)
read -rp "Enter the VM name or UUID to manage: " VMNAME
if [ -z "$VMNAME" ]; then
    echo "ERROR: VM name cannot be empty"
    exit 1
fi

### FUNCTIONS
if ! sudo -H -u "$local_user" VBoxManage showvminfo "$VMNAME" &>/dev/null; then
    echo "ERROR: VM '$VMNAME' not found or not accessible"
    exit 1
fi

case "${1:-}" in
start)
    echo "Starting $VMNAME..."
    sudo -H -u "$local_user" VBoxManage startvm "$VMNAME" --type headless
    ;;
stop)
    echo "Saving State $VMNAME..."
    sudo -H -u "$local_user" VBoxManage controlvm "$VMNAME" savestate
    sleep 20
    ;;
shutdown)
    echo "Shutting Down $VMNAME..."
    sudo -H -u "$local_user" VBoxManage controlvm "$VMNAME" acpipowerbutton
    sleep 20
    ;;
reset)
    echo "Resetting $VMNAME..."
    sudo -H -u "$local_user" VBoxManage controlvm "$VMNAME" reset
    ;;
status)
    echo -n "VMNAME->"
    sudo -H -u "$local_user" VBoxManage showvminfo "$VMNAME" --machinereadable | grep 'VMState=' | cut -d '=' -f2
    exit 0
    ;;
*)
    echo "Usage: $0 {start|stop|shutdown|reset|status}"
    exit 1
    ;;
esac
exit 0
