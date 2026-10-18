#!/bin/bash
# maravento.com
#
################################################################################
#
# Run TRIM for SSD
#
# DESCRIPTION: Runs fstrim on every mounted filesystem whose device supports
# TRIM, and prints the freed space reported for each one.
#
# USAGE: sudo ./trim.sh
#
# WARNING: TRIM is a highly destructive command. Use it at your own risk.
# Safe for: modern SSDs (SATA or NVMe) without RAID or LVM.
# Avoid on: software RAID arrays, LVM over HDD, or virtual disks (behavior
#            depends on the hypervisor and may cause unexpected data loss).
#
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
for dep in util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
        exit 1
    fi
done

echo "$(date '+%Y-%m-%d %H:%M:%S') TRIM Start. Wait..."

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') trim start..."

# Execute TRIM
# -a: all mounted filesystems on devices that support TRIM
# -v: verbose output
TRIM_LOG=$(fstrim -av) || { echo "ERROR: fstrim failed -abort"; exit 1; }
echo "$TRIM_LOG"

echo ""
echo "TRIM Finished"

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') trim done at: $(date '+%Y-%m-%d %H:%M:%S')"
