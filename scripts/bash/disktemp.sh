#!/bin/bash
# by maravento.com

# Check temp HDD, SSD, NVME and send alert to desktop and syslog
# Note: Not compatible with some storages hdd | ssd

echo "Check Disk Temp Starting. Wait..."
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

# checking dependencies (optional)
pkgs='notify-osd libnotify-bin inxi'
if apt-get install -qq $pkgs; then
    true
else
    echo "Error installing $pkgs. Abort"
    exit
fi

# checking dependencies (optional)
the_ppa=malcscott/ppa... # e.g. the_ppa="foo/bar2"
if ! grep -q "^deb .*$the_ppa" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
    add-apt-repository -y ppa:malcscott/ppa >/dev/null 2>&1
    apt-get install -qq hddtemp
else
    true
fi

# VARIABLES
# local user
local_user=$(who | head -1 | awk '{print $1;}')
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
