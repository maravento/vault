#!/bin/bash
# maravento.com
#
################################################################################
#
# File Extensions Report
# source: https://askubuntu.com/questions/844711/how-can-i-find-all-video-files-on-my-system
#
# Scans /home/<local_user>/filereport by default (created automatically if
# missing). To scan a different folder, edit the targetfolder variable below.
#
################################################################################

set -uo pipefail

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root -- abort"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$SCRIPT_LOCK")
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "ERROR: script $(basename "$0") is already running -- abort"
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

# DEPENDENCIES
for dep in findutils util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "ERROR: dependency '$dep' is not installed -- abort" >&2
        exit 1
    fi
done

echo "File Extensions Report Start. Wait..."

### VARIABLES
# default target folder (created automatically if missing); edit to scan
# a different folder
targetfolder="/home/$local_user/filereport"
mkdir -p "$targetfolder"
logreport=/var/log/filereport.log

### REPORT
# Add file extensions you want to find
find "$targetfolder" -type f | grep -E "\.webm$|\.flv$|\.vob$|\.ogg$|\.ogv$|\.drc$|\.gifv$|\.mng$|\.avi$|\.mov$|\.qt$|\.wmv$|\.yuv$|\.rm$|\.rmvb$|\.asf$|\.amv$|\.m4v$|\.mp[34]$|\.svi$|\.3gp$|\.f4v$|\.iso$|\.exe$" >"$logreport"
# alternate command (slow) (for media files)
#find $pathfind -type f -exec file -N -i -- {} + | sed -n 's!: video/[^:]*$!!p' > $logreport
echo "Done"
