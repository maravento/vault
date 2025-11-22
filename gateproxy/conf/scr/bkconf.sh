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
