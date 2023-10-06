#!/bin/bash
# by maravento.com

# FreeFileSync Update

echo "FreeFileSync Update Start. Wait..."
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

# checking dependencies
pkgs='expect tcl-expect libnotify-bin'
if apt-get install -qq $pkgs; then
    echo "OK"
else
    echo "Error installing $pkgs. Abort"
    exit
fi

# ffs update
ffsfile=FreeFileSync.tar.gz
url="https://www.freefilesync.org/download.php"
link=$(wget -q $url -O - | grep -Pio '/download/[^"]+Linux[^"]+gz')
version=$(echo $link | sed -r 's:.*FreeFileSync_([0-9]+\.[0-9]+)_.*:\1:')

echo "link: $link"
echo "version: $version"
echo "Download FreeFileync..."
$(wget -q -O $ffsfile https://www.freefilesync.org$link -U "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/63.0.3239.84 Chrome/63.0.3239.84 Safari/537.36")
tar xvf $ffsfile >/dev/null 2>&1
mv FreeFileSync*.run FreeFileSync.run >/dev/null 2>&1
chmod +x FreeFileSync.run
echo OK

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
