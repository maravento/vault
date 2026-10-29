#!/bin/bash
# maravento.com
#
################################################################################
#
# Cryptomator Encrypted Disk - Mount | Umount
# FILE: drivecrypt.sh
#
# DESCRIPTION: Mounts/unmounts the local user's Cryptomator vault path via
# bindfs, auto-detecting the local sudo user and installing Cryptomator
# if missing.
#
# USAGE: ./drivecrypt.sh { --start | --stop }
#
# LOG: system log (via logger, tag drivecrypt)
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

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

# dependencies
for dep in bindfs fuse3 software-properties-common util-linux iproute2 libc-bin coreutils grep mawk sudo apt bsdutils; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: '$dep' is not installed -abort" >&2
        exit 1
    fi
done

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

the_ppa="sebastian-stenzel/cryptomator"
if ! dpkg -s cryptomator &>/dev/null; then
    check_ipv4_interfaces
    check_internet
    add-apt-repository -y "ppa:$the_ppa" >/dev/null 2>&1
    apt-get update -qq || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot update package lists -abort" >&2
        exit 1
    }
    apt-get install -y cryptomator >/dev/null 2>&1 || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install cryptomator -abort" >&2
        exit 1
    }
fi

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

dstpath="/home/$local_user/dcrypt"
if [ ! -d "$dstpath" ]; then
    sudo -u "$local_user" mkdir -p "$dstpath"
    chmod u+rwx,go-rwx "$dstpath"
fi

originpath="/home/$local_user/.local/share/Cryptomator/mnt"

# ------------------------------------------------------------------------------
# ACTIONS
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: drivecrypt start..."

case "${1:-}" in
'--start')
    echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: mounting DriveCrypt..."
    if [ ! -d "$originpath" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: source folder $(basename "$originpath") not found -abort" >&2
        exit 1
    fi
    sudo -u "$local_user" bindfs -n "$originpath" "$dstpath"
    msg="$(date '+%Y-%m-%d %H:%M:%S') INFO: DriveCrypt mounted"
    echo "$msg"
    logger -t drivecrypt "$msg"
    ;;
'--stop')
    echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: unmounting DriveCrypt..."
    sudo -u "$local_user" fusermount -u "$dstpath"
    msg="$(date '+%Y-%m-%d %H:%M:%S') INFO: DriveCrypt unmounted"
    echo "$msg"
    logger -t drivecrypt "$msg"
    ;;
*)
    echo "Usage: $0 { --start | --stop }"
    ;;
esac

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: drivecrypt done"
