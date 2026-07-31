#!/bin/bash
# maravento.com
#
################################################################################
#
# Cryptomator Encrypted Disk - Mount | Umount
# https://www.maravento.com/2020/12/montando-boveda-cryptomator-como-unidad_2.html
#
################################################################################

set -uo pipefail

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

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

echo "DriveCrypt Starting. Wait..."

# DEPENDENCIES
for dep in bindfs fuse3 software-properties-common; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "ERROR: Required dependency '$dep' is not installed." >&2
        exit 1
    fi
done

the_ppa="sebastian-stenzel/cryptomator"
if ! grep -q "^deb .*$the_ppa" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
    add-apt-repository -y "ppa:$the_ppa" >/dev/null 2>&1
    apt-get update -qq
    apt-get install -y cryptomator >/dev/null 2>&1
fi

dstpath="/home/$local_user/dcrypt"
if [ ! -d "$dstpath" ]; then
    sudo -u "$local_user" mkdir -p "$dstpath"
    chmod u+rwx,go-rwx "$dstpath"
fi

originpath="/home/$local_user/.local/share/Cryptomator/mnt"

case "${1:-}" in
'start')
    echo "Mounting DriveCrypt..."
    if [ ! -d "$originpath" ]; then
        echo "Source path does not exist: $originpath"
        exit 1
    fi
    sudo -u "$local_user" bindfs -n "$originpath" "$dstpath"
    msg="DriveCrypt Mount: $(date)"
    echo "$msg"
    logger -t drivecrypt "$msg"
    ;;
'stop')
    echo "Umounting DriveCrypt..."
    sudo -u "$local_user" fusermount -u "$dstpath"
    msg="DriveCrypt Umount: $(date)"
    echo "$msg"
    logger -t drivecrypt "$msg"
    ;;
*)
    echo "Usage: $0 { start | stop }"
    ;;
esac
