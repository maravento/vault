#!/bin/bash
# maravento.com
#
# FreeFileSync Update

echo "FreeFileSync Update Starting. Wait..."
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

# check dependencies
pkgs='expect tcl-expect libnotify-bin'
missing=$(for p in $pkgs; do dpkg -s "$p" &>/dev/null || echo "$p"; done)
unavailable=""
for p in $missing; do
    apt-cache show "$p" &>/dev/null || unavailable+=" $p"
done
if [ -n "$unavailable" ]; then
    echo "❌ Missing dependencies not found in APT:"
    for u in $unavailable; do echo "   - $u"; done
    echo "💡 Please install them manually or enable the required repositories."
    exit 1
fi
if [ -n "$missing" ]; then
    echo "🔧 Releasing APT/DKPG locks..."
    killall -q apt apt-get dpkg 2>/dev/null
    rm -f /var/lib/apt/lists/lock
    rm -f /var/cache/apt/archives/lock
    rm -f /var/lib/dpkg/lock
    rm -f /var/lib/dpkg/lock-frontend
    rm -rf /var/lib/apt/lists/*
    dpkg --configure -a
    echo "📦 Installing: $missing"
    apt-get -qq update
    if ! apt-get -y install $missing; then
        echo "❌ Error installing: $missing"
        exit 1
    fi
else
    echo "✅ Dependencies OK"
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

# Deleting downloaded files (optional)
rm -fv FreeFileSync*
echo "FreeFileSync Update Done: $(date)"
