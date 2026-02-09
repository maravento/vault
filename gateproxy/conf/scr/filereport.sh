#!/bin/bash
# maravento.com

# File Extensions Report
# source: https://askubuntu.com/questions/844711/how-can-i-find-all-video-files-on-my-system

echo "File Extensions Report Start. Wait..."
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
# replace "myfolder" and "filereport.txt" with yours
targetfolder=/home/$local_user/myfolder
logreport=/var/log/filereport.log

### REPORT
# Add file extensions you want to find
find $targetfolder -type f | grep -E "\.webm$|\.flv$|\.vob$|\.ogg$|\.ogv$|\.drc$|\.gifv$|\.mng$|\.avi$|\.mov$|\.qt$|\.wmv$|\.yuv$|\.rm$|\.rmvb$|/.asf$|\.amv$|\.mp4$|\.m4v$|\.mp*$|\.m?v$|\.svi$|\.3gp$|\.flv$|\.f4v$|\.iso$|\.exe$" >$logreport
# alternate command (slow) (for media files)
#find $pathfind -type f -exec file -N -i -- {} + | sed -n 's!: video/[^:]*$!!p' > $logreport
echo "Done"
