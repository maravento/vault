#!/bin/bash
# maravento.com
#
################################################################################
#
# Cryptomator Encrypted Disk - Mount | Umount
# https://www.maravento.com/2020/12/montando-boveda-cryptomator-como-unidad_2.html
#
################################################################################

echo "DriveCrypt Starting. Wait..."
printf "\n"

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
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
    echo "🔧 Releasing APT/DPKG locks..."
    rm -f /var/lib/apt/lists/lock
    rm -f /var/cache/apt/archives/lock
    rm -f /var/lib/dpkg/lock
    rm -f /var/lib/dpkg/lock-frontend
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

the_ppa="sebastian-stenzel/cryptomator"
if ! grep -q "^deb .*$the_ppa" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
    add-apt-repository -y "ppa:$the_ppa" >/dev/null 2>&1
    apt-get update -qq
    apt-get install -y cryptomator >/dev/null 2>&1
fi

dstpath="/home/$local_user/dcrypt"
if [ ! -d "$dstpath" ]; then
    sudo -u "$local_user" mkdir -p "$dstpath"
    chmod u+rwx,go-rwx "$dstpath"
fi

originpath="/home/$local_user/.local/share/Cryptomator/mnt"

case "$1" in
'start')
    echo "Mounting DriveCrypt..."
    if [ ! -d "$originpath" ]; then
        echo "❌ Source path does not exist: $originpath"
        exit 1
    fi
    sudo -u "$local_user" bindfs -n "$originpath" "$dstpath"
    echo "DriveCrypt Mount: $(date)" | tee -a /var/log/syslog
    ;;
'stop')
    echo "Umounting DriveCrypt..."
    sudo -u "$local_user" fusermount -u "$dstpath"
    echo "DriveCrypt Umount: $(date)" | tee -a /var/log/syslog
    ;;
*)
    echo "Usage: $0 { start | stop }"
    ;;
esac
