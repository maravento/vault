#!/bin/bash
# maravento.com
#
################################################################################
#
# Hardware Clock Sync
# Syncs the hardware clock (hwclock) with the system clock.
# Intended to run at boot via cron (@reboot).
#
################################################################################

echo "Update HWClock. Wait..."
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

hwclock -w || echo "WARNING: hwclock -w failed (VM or container?)"
echo "HWClock Update: $(date)" | tee -a /var/log/syslog
echo "Done"
