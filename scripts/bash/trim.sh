#!/bin/bash
# maravento.com
#
################################################################################
#
# Run TRIM for SSD
#
# WARNING: TRIM is a highly destructive command. Use it at your own risk.
# Safe for: modern SSDs (SATA or NVMe) without RAID or LVM.
# Avoid on: software RAID arrays, LVM over HDD, or virtual disks (behavior
#            depends on the hypervisor and may cause unexpected data loss).
#
################################################################################

set -uo pipefail

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$SCRIPT_LOCK")
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

echo "TRIM Start. Wait..."

# Execute TRIM
# -a: all mounted filesystems on devices that support TRIM
# -v: verbose output
TRIM_LOG=$(fstrim -av) || { echo "ERROR: fstrim failed"; exit 1; }
echo "$TRIM_LOG"

echo ""
echo "TRIM Finished."
