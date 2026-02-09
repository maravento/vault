#!/bin/bash
# maravento.com
#
# Check temp HDD, SSD, NVME and send alert to desktop and syslog
# Note: Not compatible with some storages hdd | ssd

echo "Check Disk Temp Starting. Wait..."
printf "\n"

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

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

# check dependencies
pkgs='libnotify-bin inxi'
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

# check ppa
the_ppa=malcscott/ppa
if ! grep -q "^deb .*$the_ppa" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
    add-apt-repository -y ppa:$the_ppa >/dev/null 2>&1
    apt-get update -qq
    apt-get install -y hddtemp >/dev/null 2>&1
fi

# VARIABLES
# Select the maximum degrees Celsius (default 50):
degrees=50

# for ssd sata and nvme
# option 1
#inxi -xD | awk "/temp/ {if (\$2>$degrees) print \"ALERT: hard drive temperature is above: \" \$2}" | tee -a /var/log/syslog | xargs -0 sudo -u $local_user DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u $local_user)/bus notify-send -i checkbox
# option 2
TEMP_OUTPUT=$(inxi -xD | awk "/temp/ {if (\$2>$degrees) print \"ALERT: hard drive temperature is above: \" \$2}")
if [ -n "$TEMP_OUTPUT" ]; then
    echo "$TEMP_OUTPUT" | xargs -0 sudo -u $local_user DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u $local_user)/bus notify-send -i checkbox
    echo "$TEMP_OUTPUT" | tee -a /var/log/syslog
fi
# option 3 (for some ssd sata and hdd)
#temperature=$(hddtemp /dev/sda --numeric)
#if [ $temperature -ge $degrees ]; then
#    echo "ALERT: hard drive's temperature is above: $temperature" | tee -a /var/log/syslog | xargs -0 sudo -u $local_user DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u $local_user)/bus notify-send -i checkbox
#fi
