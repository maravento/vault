#!/bin/bash
# maravento.com
#
################################################################################
#
# Start | Stop VMs Virtualbox
# FILE: vm.sh
#
# DESCRIPTION: Drives one VirtualBox machine headless through VBoxManage, as
# the detected local user. Asks for the VM name or UUID at the prompt.
#
# USAGE:
# COMMAND                     ACTION
# sudo bash vm.sh --start     Start
# sudo bash vm.sh --stop      Stop
# sudo bash vm.sh --shutdown  Shut down
# sudo bash vm.sh --reset     Run
# sudo bash vm.sh --status    Show status
#
# Add user to vboxusers: usermod -a -G vboxusers $USER
#
################################################################################

set -uo pipefail

# root check
if [ "$(id -u)" != "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# awk is a command, not a package: check it before its first use
command -v awk >/dev/null 2>&1 || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: awk not found -abort" >&2; exit 1; }

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
for dep in coreutils grep sudo iproute2 libc-bin; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep" 2>/dev/null)" != *"ok installed"* ]]; then
        if [ "$net_checked" -eq 0 ]; then
            if ! command -v ip >/dev/null 2>&1; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: installing iproute2"
                apt-get install -y iproute2 >/dev/null 2>&1 || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install iproute2 -abort" >&2; exit 1; }
                # the download proves link and internet; only IPv4 is left to check
                check_ipv4_interfaces
            else
                check_ipv4_interfaces
                check_internet
            fi
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
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: using local user: $local_user"

# dependencies (version-variable package)
if ! command -v VBoxManage &>/dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: VBoxManage is not installed -abort" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

# Reject a bad option before asking for the VM name
case "${1:-}" in
    --start|--stop|--shutdown|--reset|--status) ;;
    *)
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: invalid option -abort" >&2
        echo "Usage: $0 {--start|--stop|--shutdown|--reset|--status}"
        exit 1
        ;;
esac

# Set name of VM (e.g: win10) or UUID (e.g.: 4ec6acc1-a232-566d-a040-6bc4aadc19a6)
read -rp "Enter the VM name or UUID to manage: " vm_name
if [ -z "$vm_name" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: VM name cannot be empty -abort" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# CHECKS
# ------------------------------------------------------------------------------

# Require an existing virtual machine before processing its action
if ! sudo -H -u "$local_user" VBoxManage showvminfo "$vm_name" &>/dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: VM '$vm_name' unavailable -abort" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# ACTIONS
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: vm start..."

case "${1:-}" in
--start)
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Starting $vm_name..."
    sudo -H -u "$local_user" VBoxManage startvm "$vm_name" --type headless || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot start $vm_name -abort" >&2
        exit 1
    }
    ;;
--stop)
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Saving State $vm_name..."
    sudo -H -u "$local_user" VBoxManage controlvm "$vm_name" savestate || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot save state of $vm_name -abort" >&2
        exit 1
    }
    sleep 20
    ;;
--shutdown)
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Shutting Down $vm_name..."
    sudo -H -u "$local_user" VBoxManage controlvm "$vm_name" acpipowerbutton || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot shut down $vm_name -abort" >&2
        exit 1
    }
    sleep 20
    ;;
--reset)
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Resetting $vm_name..."
    sudo -H -u "$local_user" VBoxManage controlvm "$vm_name" reset || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot reset $vm_name -abort" >&2
        exit 1
    }
    ;;
--status)
    vm_state=$(sudo -H -u "$local_user" VBoxManage showvminfo "$vm_name" --machinereadable | grep '^VMState=' | cut -d '=' -f2) || vm_state=""
    if ! [[ "$vm_state" =~ ^\"[a-z-]+\"$ ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot read state of $vm_name -abort" >&2
        exit 1
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: $vm_name: ${vm_state//\"/}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: vm done"
    exit 0
    ;;
esac

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: vm done"

exit 0
