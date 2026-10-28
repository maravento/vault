#!/bin/bash
# maravento.com
#
################################################################################
#
# Cleaner
# FILE: cleaner.sh
#
# DESCRIPTION: Searches and permanently deletes:
# - Windows ADS files (e.g., :Zone.Identifier, :encryptable, Thumbs.db)
# - macOS and Linux system files (e.g., .fuse_hidden*, .spotlight-*,
#   .fseventsd*, .DS_Store, ~lock.*)
# - Extended attributes and metadata streams (e.g., :attributes:)
#
# USAGE: sudo ./cleaner.sh [search_path]
# Without arguments, searches from /
#
# LOG: /var/log/cleaner.log
#      /var/log/syslog
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# path for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# root check
if [ "$(id -u)" -ne 0 ]; then
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
for dep in findutils coreutils util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: cleaner start..."

start=$(date +%s)

search_path="${1:-/}"

deleted_count=0
while IFS= read -r -d '' f; do
    if rm -f "$f" 2>>/var/log/cleaner.log; then
        deleted_count=$((deleted_count + 1))
    fi
done < <(find "$search_path" -type f -regextype posix-egrep -iregex \
'^(.*/)?[^/]*(:encryptable|Zone\.identifier|\.fuse_hidden[^/]*|goutputstream[^/]*|\.spotlight-[^/]*|\.fseventsd[^/]*|\.ds_store[^/]*|~lock\.[^/]*|Thumbs\.db|attributes:)[^/]*$' \
-print0 2>>/var/log/cleaner.log)

end=$(date +%s)
duration=$((end - start))

# Log registry
echo "Cleaner: $(date +"%a %d %b %Y %H:%M:%S") - Files deleted: ${deleted_count} - Time: ${duration}s" | tee -a /var/log/syslog

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: cleaner done"
