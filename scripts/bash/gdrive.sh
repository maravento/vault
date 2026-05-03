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

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# LOCAL USER (multi-strategy detection with validation)
local_user=""
# 1. Local graphical session (:0)
local_user=$(who | awk '/\(:0\)/{print $1; exit}')
# 2. Parent process logname (works well with sudo)
[ -z "$local_user" ] && local_user=$(logname 2>/dev/null || true)
# 3. SUDO_USER variable (when run via sudo from terminal)
[ -z "$local_user" ] && local_user="${SUDO_USER:-}"
# 4. First active session user (SSH or other)
[ -z "$local_user" ] && local_user=$(who | awk 'NR==1{print $1}')
# 5. First valid home directory
[ -z "$local_user" ] && local_user=$(ls -l /home 2>/dev/null | awk '/^d/{print $3; exit}')
# Validate the user actually exists on the system
if [ -z "$local_user" ] || ! id "$local_user" &>/dev/null; then
    echo "ERROR: Cannot determine a valid local user"
    exit 1
fi
echo "Using local user: $local_user"

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
