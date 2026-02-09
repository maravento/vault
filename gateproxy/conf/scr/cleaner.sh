#!/bin/bash
# maravento.com

# Cleaner
# Search and send to trash:
# - Windows ADS files (e.g., :Zone.Identifier, :encryptable, Thumbs.db)
# - macOS and Linux system files (e.g., .fuse_hidden*, .spotlight-*, .fseventsd*, .DS_Store, ~lock.*)
# - Extended attributes and metadata streams (e.g., :attributes:)
# - Crash reports from Apport (/var/crash/*.crash)

echo "Start Cleaner. Wait..."

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

start=$(date +%s)

find . -type f -regextype posix-egrep -iregex \
'^.*(:encryptable|Zone\.identifier|\.fuse_hidden.*|goutputstream.*|\.spotlight-.*|\.fseventsd.*|\.ds_store.*|~lock\..*|Thumbs\.db|attributes:).*$' \
-print0 | xargs -0 -n 100 -P 8 rm -f 2>/dev/null

end=$(date +%s)
duration=$((end - start))

# Log registry
echo "Cleaner: $(date +"%a %d %b %Y %H:%M:%S") - Time: ${duration}s" | tee -a /var/log/syslog
