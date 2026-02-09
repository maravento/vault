#!/bin/bash
# maravento.com

# Backup System Files

echo "Backup System Files Start. Wait..."
printf "\n"

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

### VARIABLES
# path to cloud
bkconfig="/home/$local_user/bkconf"
mkdir -p "$bkconfig" >/dev/null 2>&1

### BACKUP
zipbk="backup_$(date +%Y%m%d_%H%M).zip"
pathbk="/etc/squid /etc/acl /etc/apache2 /var/www /etc/hosts /etc/scr /etc/fstab /etc/samba /etc/network/interfaces /etc/netplan /etc/apt/sources.list /var/spool/cron/crontabs /etc/logrotate.d/rsyslog /etc/sarg"

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
