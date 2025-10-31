#!/bin/bash
# maravento.com

# File Extensions Report
# source: https://askubuntu.com/questions/844711/how-can-i-find-all-video-files-on-my-system

echo "File Extensions Report Start. Wait..."
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

# LOCAL USER
# Get real user (not root) - multiple fallback methods
local_user=$(logname 2>/dev/null || echo "$SUDO_USER")
# If not found or is root, try detecting active graphical user
if [ -z "$local_user" ] || [ "$local_user" = "root" ]; then
    local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}')
fi
# As a final fallback, take the first logged user
if [ -z "$local_user" ]; then
    local_user=$(who | head -1 | awk '{print $1}')
fi
# Clean possible spaces or line breaks
local_user=$(echo "$local_user" | xargs)

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
