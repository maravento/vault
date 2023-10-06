#!/bin/bash
# by maravento.com

# File Extensions Report
# source: https://askubuntu.com/questions/844711/how-can-i-find-all-video-files-on-my-system

# checking root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi
# checking script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi

echo "Start File Report..."

# variables
local_user=${SUDO_USER:-$(whoami)}
# replace "myfolder" and "filereport.txt" with yours
targetfolder=/home/$local_user/myfolder
logreport=/var/log/filereport.log

# Add file extensions you want to find
find $targetfolder -type f | grep -E "\.webm$|\.flv$|\.vob$|\.ogg$|\.ogv$|\.drc$|\.gifv$|\.mng$|\.avi$|\.mov$|\.qt$|\.wmv$|\.yuv$|\.rm$|\.rmvb$|/.asf$|\.amv$|\.mp4$|\.m4v$|\.mp*$|\.m?v$|\.svi$|\.3gp$|\.flv$|\.f4v$|\.iso$|\.exe$" >$logreport
# alternate command (slow) (for media files)
#find $pathfind -type f -exec file -N -i -- {} + | sed -n 's!: video/[^:]*$!!p' > $logreport
echo "Done"
