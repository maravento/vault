#!/bin/bash
# maravento.com

# Cleaner
# Search and send to trash:
# - ADS files (Thumbs.db, Zone.Identifier, encryptable, etc.)
# - macOS system files (e.g., .fuse_hidden*, .spotlight-*, .fseventsd*, .ds_store*, ~lock.*, etc.)
# - Extended file attributes (e.g., attributes:, etc.)
# - Crash reports from apport (/var/crash/*crash)

echo "Start Cleaner. Wait..."
printf "\n"

# checking root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# checking script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi

# checking dependencies (optional)
pkg='trash-cli'
if apt-get -qq install $pkg; then
    true
else
    echo "Error installing $pkg. Abort"
    exit
fi

# Find and delete files
find . -type f -regextype posix-egrep -iregex "^.*(:encryptable|Zone\.identifier|.fuse_hidden*|goutputstream*|.spotlight-*|.fseventsd*|.ds_store*|~lock.*|Thumbs\.db|attributes:).*$" -exec trash {} \; 2>/dev/null

# Delete crash reports from apport
find /var/crash/*crash -type f -exec trash {} \; 2>/dev/null

# Log registry
echo "Cleaner: $(date)" | tee -a /var/log/syslog
