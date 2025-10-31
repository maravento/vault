#!/bin/bash
# maravento.com
#
# Cryptomator Encrypted Disk - Mount | Umount
# https://www.maravento.com/2020/12/montando-boveda-cryptomator-como-unidad_2.html

echo "DriveCrypt Starting. Wait..."
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

# check SO
UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
if [[ "$UBUNTU_ID" != "ubuntu" || ( "$UBUNTU_VERSION" != "22.04" && "$UBUNTU_VERSION" != "24.04" ) ]]; then
    echo "Unsupported system. Use at your own risk"
    # exit 1
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
