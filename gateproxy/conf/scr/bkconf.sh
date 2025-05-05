#!/bin/bash
# maravento.com

# Backup System Files

echo "Backup System Files Start. Wait..."
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

### VARIABLES
# local user
local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}' || who | head -1 | awk '{print $1}')
# path to cloud
bkconfig="/home/$local_user/bkconf"
if [ ! -d "$bkconfig" ]; then sudo mkdir -p "$bkconfig"; fi

### BACKUP
zipbk="backup_$(date +%Y%m%d_%H%M).zip"
pathbk="/etc/squid/* /etc/acl/* /etc/apache2/* /var/www/wpad/* /etc/hosts /etc/sarg/* /etc/scr/* /etc/fstab /etc/samba/* /etc/network/interfaces /etc/netplan/config.yaml /etc/apt/sources.list /var/spool/cron/crontabs/*"

case "$1" in
'start')
    echo "Start Backup Config Files..."
    zip -r "$bkconfig"/"$zipbk" $pathbk >/dev/null
    echo "Backup Config: $(date)" | tee -a /var/log/syslog
    ;;
'stop') ;;
*)
    echo "Usage: $0 { start | stop }"
    ;;
esac
echo "Done"
