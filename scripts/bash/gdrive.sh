#!/bin/bash
# by maravento.com

# Mount | Umount google drive folder (no root)
# https://www.maravento.com/2018/11/compartir-google-drive-con-samba.html

# how to use (not sudo/root)
#./gdrive start
#./gdrive stop

echo "Gdrive Start. Wait..."
printf "\n"

# checking script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi

# checking dependencies
pkgs='google-drive-ocamlfuse install libcurl3-gnutls libfuse2 libsqlite3-0'
status="$(dpkg-query -W --showformat='${db:Status-Status}' "$pkgs" 2>&1)"
if [ ! $? = 0 ] || [ ! "$status" = installed ]; then
    sudo add-apt-repository -y ppa:alessandro-strada/ppa &>/dev/null
    sudo apt-get install -qq $pkgs
else
    echo ok
fi

# LOCAL USER (sudo user no root)
local_user=${SUDO_USER:-$(whoami)}

# replace "GoogleDrive" with your (path) GoogleDrive Folder
GD="/home/$local_user/GDrive"
if [ ! -d $GD ]; then mkdir -p $GD && chmod 777 $GD; fi

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
