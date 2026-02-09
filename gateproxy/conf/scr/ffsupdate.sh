#!/bin/bash
# maravento.com

# FreeFileSync Update

echo "FreeFileSync Update Start. Wait..."
printf "\n"

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

### VARIABLES
# ffs update
ffsfile=FreeFileSync.tar.gz
url="https://www.freefilesync.org/download.php"
link=$(wget -q $url -O - | grep -Pio '/download/[^"]+Linux[^"]+gz')
version=$(echo $link | sed -r 's:.*FreeFileSync_([0-9]+\.[0-9]+)_.*:\1:')

### DOWNLOAD
echo "link: $link"
echo "version: $version"
echo "Download FreeFileync..."
$(wget -qO $ffsfile https://www.freefilesync.org$link -U "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/63.0.3239.84 Chrome/63.0.3239.84 Safari/537.36")
tar xvf $ffsfile >/dev/null 2>&1
mv FreeFileSync*.run FreeFileSync.run >/dev/null 2>&1
chmod +x FreeFileSync.run
echo OK

### UPDATE
echo "Run Update..."
/usr/bin/expect <<EOF
set timeout -1
log_user 0
spawn ./FreeFileSync.run --accept-license
log_user 1
expect -exact "to begin installation:"
send -- "y\r"
expect -exact "https://freefilesync.org/donate\r
\r"
EOF

### END
rm -fv FreeFileSync*
echo "FreeFileSync Update Done: $(date)"
echo "Done"
