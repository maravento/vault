#!/bin/bash
# maravento.com
#
################################################################################
#
# Kworker Kill
# FILE: kworker.sh
#
# DESCRIPTION: Detects an ACPI GPE interrupt in storm (high count) and
# disables it to stop the associated kworker CPU spike. Run as root.
#
# USAGE: sudo ./kworker.sh
#
# LOG: system logger (destination set by system configuration)
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

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
for dep in grep coreutils util-linux bsdutils; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep" 2>/dev/null)" != *"ok installed"* ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: kworker start..."

kworker=$(mktemp /tmp/gpelist.XXXXXX)
trap 'rm -f "$kworker"' EXIT

echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Checking GPE list..."
grep enabled /sys/firmware/acpi/interrupts/* 2>/dev/null > "$kworker"

gpe=$(grep -E '[1-9][0-9][0-9][0-9]+ ' "$kworker" | sort -rnk 2 | head -n1 | cut -d":" -f1)
# Pattern matches GPE interrupt counts >= 1000, indicating a potential IRQ storm

if [ -z "$gpe" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: no GPE interrupt storm found"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Disabling ${gpe##*/}..."
    echo "disable" > "$gpe"
    gpe_rc=$?
    if [ "$gpe_rc" -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: kworker disable: $gpe"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: cannot disable ${gpe##*/}, rc=$gpe_rc -alert"
    fi
    logger -t kworker "kworker disable: $gpe rc=$gpe_rc" || true
fi

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: kworker done"
