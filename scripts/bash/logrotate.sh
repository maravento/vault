#!/bin/bash
# maravento.com
#
################################################################################
#
# Force Log Rotate
# You should only use it if logrotate fails.
#
################################################################################

set -uo pipefail

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root -- abort"
    exit 1
fi

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock")
exec 200>"$script_lock"
if ! flock -n 200; then
    echo "ERROR: script $(basename "$0") is already running -- abort"
    exit 1
fi

echo "Force Log Rotate Start. Wait..."

# dependencies
for dep in logrotate bsdutils util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "ERROR: dependency '$dep' is not installed -- abort" >&2
        exit 1
    fi
done

logrotate_bin=$(command -v logrotate)

logrotate_err=$("$logrotate_bin" -f /etc/logrotate.conf 2>&1 >/dev/null)
exit_value=$?

if [ "$exit_value" -ne 0 ]; then
    /usr/bin/logger -t logrotate "ALERT exited abnormally with [$exit_value]: $logrotate_err"
fi

exit 0
