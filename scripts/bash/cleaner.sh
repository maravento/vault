#!/bin/bash
# maravento.com

# Cleaner
# Search and send to trash:
# - Windows ADS files (e.g., :Zone.Identifier, :encryptable, Thumbs.db)
# - macOS and Linux system files (e.g., .fuse_hidden*, .spotlight-*, .fseventsd*, .DS_Store, ~lock.*)
# - Extended attributes and metadata streams (e.g., :attributes:)
# - Crash reports from Apport (/var/crash/*.crash)

echo "Start Cleaner. Wait..."

# check root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# check script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi

# check SO
UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
if [[ "$UBUNTU_ID" != "ubuntu" || ( "$UBUNTU_VERSION" != "22.04" && "$UBUNTU_VERSION" != "24.04" ) ]]; then
    echo "Unsupported system. Use at your own risk"
    # exit 1
fi

start=$(date +%s)

find . -type f -regextype posix-egrep -iregex \
'^.*(:encryptable|Zone\.identifier|\.fuse_hidden.*|goutputstream.*|\.spotlight-.*|\.fseventsd.*|\.ds_store.*|~lock\..*|Thumbs\.db|attributes:).*$' \
-print0 | xargs -0 -n 100 -P 8 rm -f 2>/dev/null

end=$(date +%s)
duration=$((end - start))

# Log registry
echo "Cleaner: $(date +"%a %d %b %Y %H:%M:%S") - Time: ${duration}s" | tee -a /var/log/syslog
