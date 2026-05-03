#!/bin/bash
# maravento.com
#
# Mount | Umount google drive folder (no root)
# https://www.maravento.com/2018/11/compartir-google-drive-con-samba.html
# how to use (not sudo/root)
# ./gdrive start
# ./gdrive stop

echo "Gdrive Starting. Wait..."
printf "\n"

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

local_user=""
local_user=$(who | awk '/\(:0\)/{print $1; exit}')
[ -z "$local_user" ] && local_user=$(logname 2>/dev/null || true)
[ -z "$local_user" ] && local_user="${SUDO_USER:-}"
[ -z "$local_user" ] && local_user=$(who | awk 'NR==1{print $1}')
[ -z "$local_user" ] && local_user=$(ls -l /home 2>/dev/null | awk '/^d/{print $3; exit}')
if [ -z "$local_user" ] || ! id "$local_user" &>/dev/null; then
    echo "ERROR: Cannot determine a valid local user"
    exit 1
fi
echo "Using local user: $local_user"

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
if [ ! -d "$GD" ]; then
    mkdir -p "$GD"
    chmod 755 "$GD"
    chown "$local_user":"$local_user" "$GD"
fi

case "$1" in
start)
    echo 'Mount Google Drive...'
    if mountpoint -q "$GD"; then
        echo "⚠️ $GD is already mounted."
        exit 0
    fi
    if ! sudo -u "$local_user" google-drive-ocamlfuse "$GD"; then
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
