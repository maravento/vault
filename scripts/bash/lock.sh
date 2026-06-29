#!/bin/bash
# maravento.com
#
################################################################################
#
# Lock
# Schedules a randomized delayed re-execution of itself (1-3 min)
# to prevent predictable script timing. Intended to run at boot via cron (@reboot).
#
################################################################################

echo "Lock Script Start. Wait..."
printf "\n"

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

# at dependency
if ! command -v at &>/dev/null; then
    apt-get install -y at &>/dev/null
    systemctl enable --now atd &>/dev/null
fi

### LOCK
randa=$(($RANDOM % 3 + 1))
echo "Lock Start: $(date)" | tee -a /var/log/syslog
echo "$0 $@" | at now + "$randa" min
exit 0
