#!/bin/bash
# maravento.com
#
# Mount | Umount google drive folder (no root)
# https://www.maravento.com/2018/11/compartir-google-drive-con-samba.html

# how to use (not sudo/root)
#./gdrive start
#./gdrive stop

echo "Gdrive Starting. Wait..."
printf "\n"

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# check no-root
if [ "$(id -u)" == "0" ]; then
    echo "❌ This script should not be run as root."
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

# check dependencies
pkgs='google-drive-ocamlfuse libcurl3-gnutls libfuse2 libsqlite3-0'
for pkg in $pkgs; do
  dpkg -s "$pkg" &>/dev/null || command -v "$pkg" &>/dev/null || {
    echo "❌ '$pkg' is not installed. Run:"
    echo "sudo add-apt-repository -y ppa:alessandro-strada/ppa"
    echo "sudo apt install $pkg"
    exit 1
  }
done

### VARIABLES
# replace "GoogleDrive" with your (path) GoogleDrive Folder
GD="/home/$local_user/gdrive"
if [ ! -d $GD ]; then mkdir -p $GD && chmod 777 $GD; fi

### MOUNT | UMOUNT
case "$1" in
start)
    echo 'Mount Google Drive...'
    google-drive-ocamlfuse $GD
    echo "OK"
    exit
    ;;
stop)
    echo 'Umount Google Drive...'
    fusermount -u $GD
    echo "OK"
    exit
    ;;
*)
    echo "Usage: ./gdmu {start|stop}"
    exit 1
    ;;
esac
exit 0
