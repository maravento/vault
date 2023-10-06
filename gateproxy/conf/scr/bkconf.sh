#!/bin/bash
# by maravento.com

# Backup System Files

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

# user account
myuser="your_user"
# path to cloud
cloud="/home/$myuser/backup"
if [ ! -d "$cloud" ]; then sudo mkdir -p "$cloud"; fi
zipbk="backup_$(date +%Y%m%d_%H%M).zip"
pathbk="/etc/squid/* /etc/acl/* /etc/apache2/* /var/www/wpad/* /etc/hosts /etc/sarg/* /etc/scr/* /etc/fstab /etc/samba/* /etc/network/interfaces /etc/netplan/config.yaml /etc/apt/sources.list /var/spool/cron/crontabs/*"

case "$1" in
'start')
    echo "Start Backup Config Files..."
    zip -r "$cloud"/"$zipbk" $pathbk >/dev/null
    echo "Backup Config: $(date)" | tee -a /var/log/syslog
    ;;
'stop') ;;
*)
    echo "Usage: $0 { start | stop }"
    ;;
esac
