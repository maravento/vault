#!/bin/bash
# maravento.com

# Cleaner
# Search and send to trash:
# - Windows ADS files (e.g., :Zone.Identifier, :encryptable, Thumbs.db)
# - macOS and Linux system files (e.g., .fuse_hidden*, .spotlight-*, .fseventsd*, .DS_Store, ~lock.*)
# - Extended attributes and metadata streams (e.g., :attributes:)
# - Crash reports from Apport (/var/crash/*.crash)

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

# Find and delete (to trash) ADS, metadata, and temp files
find . -type f \( \
    -iname "Thumbs.db" -o \
    -iname "*Zone.identifier*" -o \
    -iname ".fuse_hidden*" -o \
    -iname "goutputstream*" -o \
    -iname ".spotlight-*" -o \
    -iname ".fseventsd*" -o \
    -iname ".ds_store*" -o \
    -iname "~lock.*" -o \
    -iname "*:encryptable*" -o \
    -iname "*:attributes:*" \
\) -exec trash {} + 2>/dev/null

# Delete crash reports from apport
find /var/crash/*crash -type f -exec trash {} \; 2>/dev/null

# Log registry
echo "Cleaner: $(date)" | tee -a /var/log/syslog
