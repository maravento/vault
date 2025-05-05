#!/bin/bash
# maravento.com

# Cryptomator Encrypted Disk - Mount | Umount
# https://www.maravento.com/2020/12/montando-boveda-cryptomator-como-unidad_2.html

echo "DriveCrypt Starting. Wait..."
printf "\n"

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

# checking dependencies
pkgs='bindfs'
if apt-get install -qq $pkgs; then
    true
else
    echo "Error installing $pkgs. Abort"
    exit
fi

the_ppa=sebastian-stenzel/cryptomator... # e.g. the_ppa="foo/bar2"
if ! grep -q "^deb .*$the_ppa" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
    add-apt-repository -y ppa:malcscott/ppa >/dev/null 2>&1
    apt-get install -qq cryptomator
else
    echo OK
fi

### VARIABLES
# LOCAL USER (sudo user no root)
local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}' || who | head -1 | awk '{print $1}')
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
