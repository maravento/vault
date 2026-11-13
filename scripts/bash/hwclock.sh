#!/bin/bash
# maravento.com
#
################################################################################
#
# Hardware Clock Sync
# FILE: hwclock.sh
#
# DESCRIPTION: Syncs the hardware clock with the system clock. Run as root,
# intended to run at boot via cron (@reboot).
#
# USAGE: sudo ./hwclock.sh
#
# LOG: system logger (destination set by system configuration)
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# path for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# root check
if [ "$(id -u)" != "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock") || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot open $(basename "$script_lock") -abort" >&2
    exit 1
}
exec 200>"$script_lock"
if ! flock -n 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: script $(basename "$0") is already running -abort" >&2
    exit 1
fi

# dependencies
for dep in util-linux util-linux-extra bsdutils coreutils; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep" 2>/dev/null)" != *"ok installed"* ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Installing $dep..."
        if ! apt-get install -y "$dep"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install $dep -abort" >&2
            exit 1
        fi
    fi
done

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: hwclock start..."

hwclock_rc=0
hwclock -w || {
    hwclock_rc=$?
    echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: hwclock -w failed, VM or container? -alert"
}
if [ "$hwclock_rc" -eq 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: HWClock Update"
fi
logger -t hwclock "HWClock Update: rc=$hwclock_rc" || true

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: hwclock done"
