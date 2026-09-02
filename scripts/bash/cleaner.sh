#!/bin/bash
# maravento.com
#
################################################################################
#
# Cleaner
# Search and permanently delete:
# - Windows ADS files (e.g., :Zone.Identifier, :encryptable, Thumbs.db)
# - macOS and Linux system files (e.g., .fuse_hidden*, .spotlight-*, .fseventsd*, .DS_Store, ~lock.*)
# - Extended attributes and metadata streams (e.g., :attributes:)
# - Crash reports from Apport (/var/crash/*.crash)
#
################################################################################

set -uo pipefail

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

## root check
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root -- abort"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$SCRIPT_LOCK")
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "ERROR: script $(basename "$0") is already running -- abort"
    exit 1
fi

# DEPENDENCIES
for dep in findutils coreutils util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "ERROR: dependency '$dep' is not installed -- abort" >&2
        exit 1
    fi
done

echo "Start Cleaner. Wait..."

start=$(date +%s)

search_path="${1:-/}"

deleted_count=0
while IFS= read -r -d '' f; do
    if rm -f "$f" 2>>/var/log/cleaner.log; then
        deleted_count=$((deleted_count + 1))
    fi
done < <(find "$search_path" -type f -regextype posix-egrep -iregex \
'^.*(:encryptable|Zone\.identifier|\.fuse_hidden.*|goutputstream.*|\.spotlight-.*|\.fseventsd.*|\.ds_store.*|~lock\..*|Thumbs\.db|attributes:).*$' \
-print0 2>>/var/log/cleaner.log)

end=$(date +%s)
duration=$((end - start))

# Log registry
echo "Cleaner: $(date +"%a %d %b %Y %H:%M:%S") - Files deleted: ${deleted_count} - Time: ${duration}s" | tee -a /var/log/syslog
