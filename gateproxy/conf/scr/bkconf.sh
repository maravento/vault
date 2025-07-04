#!/bin/bash
# maravento.com

# Backup System Files

echo "Backup System Files Start. Wait..."
printf "\n"

# check root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

### VARIABLES
# local user
local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}' || who | head -1 | awk '{print $1}')
# path to cloud
bkconfig="/home/$local_user/bkconf"
mkdir -p "$bkconfig" >/dev/null 2>&1

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
