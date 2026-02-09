#!/bin/bash
# maravento.com
#
# Cryptomator Encrypted Disk - Mount | Umount
# https://www.maravento.com/2020/12/montando-boveda-cryptomator-como-unidad_2.html

echo "DriveCrypt Starting. Wait..."
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

# check dependencies
pkgs='bindfs'
missing=$(for p in $pkgs; do dpkg -s "$p" &>/dev/null || echo "$p"; done)
unavailable=""
for p in $missing; do
    apt-cache show "$p" &>/dev/null || unavailable+=" $p"
done
if [ -n "$unavailable" ]; then
    echo "❌ Missing dependencies not found in APT:"
    for u in $unavailable; do echo "   - $u"; done
    echo "💡 Please install them manually or enable the required repositories."
    exit 1
fi
if [ -n "$missing" ]; then
    echo "🔧 Releasing APT/DKPG locks..."
    killall -q apt apt-get dpkg 2>/dev/null
    rm -f /var/lib/apt/lists/lock
    rm -f /var/cache/apt/archives/lock
    rm -f /var/lib/dpkg/lock
    rm -f /var/lib/dpkg/lock-frontend
    rm -rf /var/lib/apt/lists/*
    dpkg --configure -a
    echo "📦 Installing: $missing"
    apt-get -qq update
    if ! apt-get -y install $missing; then
        echo "❌ Error installing: $missing"
        exit 1
    fi
else
    echo "✅ Dependencies OK"
fi

the_ppa=sebastian-stenzel/cryptomator
if ! grep -q "^deb .*$the_ppa" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
    add-apt-repository -y ppa:$the_ppa >/dev/null 2>&1
    apt-get update -qq
    apt-get install -y cryptomator >/dev/null 2>&1
fi

### VARIABLES
# path drivecrypt
dstpath="/home/$local_user/dcrypt"
if [ ! -d $dstpath ]; then mkdir -p $dstpath && chmod u+rwx,go-rwx -R $dstpath; fi
# original path drivecrypt
originpath="/home/$local_user/.local/share/Cryptomator/mnt"

### DRIVE CRYPT
case "$1" in
'start')
    # mount
    echo "Mounting DriveCrypt..."
    # create folder if doesn't exist
    if [ ! -d "$dstpath" ]; then sudo -u $local_user mkdir -p $dstpath; fi >/dev/null
    # mount
    sudo -u $local_user bindfs -n $originpath $dstpath
    echo "DriveCrypt Mount: $(date)" | tee -a /var/log/syslog
    ;;
'stop')
    echo "Umounting DriveCrypt..."
    # umount
    sudo -u $local_user fusermount -u $dstpath
    echo "DriveCrypt Umount: $(date)" | tee -a /var/log/syslog
    ;;
*)
    echo "Usage: $0 { start | stop }"
    ;;
esac
