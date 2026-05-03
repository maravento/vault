#!/bin/bash
# maravento.com
#
# Cleaner
# Search and send to trash:
# - Windows ADS files (e.g., :Zone.Identifier, :encryptable, Thumbs.db)
# - macOS and Linux system files (e.g., .fuse_hidden*, .spotlight-*, .fseventsd*, .DS_Store, ~lock.*)
# - Extended attributes and metadata streams (e.g., :attributes:)
# - Crash reports from Apport (/var/crash/*.crash)

echo "Start Cleaner. Wait..."

set -uo pipefail

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

## root check
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
readonly LOCK_FD=200
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec {LOCK_FD}>"$SCRIPT_LOCK"
if ! flock -n $LOCK_FD; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

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
