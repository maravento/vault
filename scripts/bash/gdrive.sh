#!/bin/bash
# maravento.com
#
################################################################################
#
# Mount | Umount google drive folder (no root)
# https://www.maravento.com/2018/11/compartir-google-drive-con-samba.html
# how to use (not sudo/root)
# ./gdrive start
# ./gdrive stop
#
################################################################################

echo "Gdrive Starting. Wait..."
printf "\n"

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# check no-root
if [ "$(id -u)" == "0" ]; then
    echo "ERROR: This script should not be run as root."
    exit 1
fi

local_user="$(id -un)"
echo "Using local user: $local_user"

# check dependencies
pkgs='google-drive-ocamlfuse libcurl3-gnutls libfuse2 libsqlite3-0'
for pkg in $pkgs; do
    dpkg -s "$pkg" &>/dev/null || command -v "$pkg" &>/dev/null || {
        echo "❌ '$pkg' is not installed. Run:"
        echo "   sudo add-apt-repository -y ppa:alessandro-strada/ppa"
        echo "   sudo apt install $pkg"
        exit 1
    }
done

GD="/home/$local_user/gdrive"
if [ -e "$GD" ] && [ ! -d "$GD" ]; then
    echo "ERROR: $GD exists but is not a directory"
    exit 1
fi
if [ ! -d "$GD" ]; then
    mkdir -p "$GD"
    chmod 755 "$GD"
fi

case "$1" in
start)
    echo 'Mount Google Drive...'
    if mountpoint -q "$GD"; then
        echo "⚠️ $GD is already mounted."
        exit 0
    fi
    if ! google-drive-ocamlfuse "$GD"; then
        echo "❌ Failed to mount Google Drive."
        exit 1
    fi
    echo "OK"
    exit 0
    ;;
stop)
    echo 'Umount Google Drive...'
    if ! mountpoint -q "$GD"; then
        echo "⚠️ $GD is not mounted."
        exit 0
    fi
    if ! fusermount -u "$GD"; then
        echo "❌ Failed to unmount Google Drive."
        exit 1
    fi
    echo "OK"
    exit 0
    ;;
*)
    echo "Usage: $0 {start|stop}"
    exit 1
    ;;
esac
