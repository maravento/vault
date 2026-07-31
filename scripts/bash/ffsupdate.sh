#!/bin/bash
# maravento.com
#
################################################################################
#
# FreeFileSync Update
#
# NOTE on logging:
# - Writes to /var/log/ffsupdate.log (append-only, no rotation configured
#   by this script). Set up logrotate for this file if disk usage matters.
# - To clear it manually: truncate -s 0 /var/log/ffsupdate.log
#
################################################################################

set -uo pipefail

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# logging
log_file="/var/log/ffsupdate.log"
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" | tee -a "$log_file" 2>/dev/null || true
}

## root check
if [ "$(id -u)" != "0" ]; then
    log "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$SCRIPT_LOCK")
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    log "Script $(basename "$0") is already running"
    exit 1
fi

# Start
log "ffsupdate start..."

# DEPENDENCIES
for dep in expect tcl-expect wget tar coreutils; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: Required dependency '$dep' is not installed."
        exit 1
    fi
done

ffsfile="FreeFileSync.tar.gz"
ffsrun="FreeFileSync.run"
url="https://www.freefilesync.org/download.php"

trap 'rm -f "$ffsfile" "$ffsrun"; log "ERROR: Aborted. Temporary files cleaned up."; exit 1' ERR INT TERM

link=$(wget -q "$url" -O - | grep -Pio '/download/[^"]+Linux[^"]+gz')
if [ -z "$link" ]; then
    log "ERROR: Could not find download link. Site may have changed."
    exit 1
fi

version=$(echo "$link" | sed -r 's:.*FreeFileSync_([0-9]+\.[0-9]+)_.*:\1:')
if [ -z "$version" ]; then
    log "ERROR: Could not parse version from link: $link"
    exit 1
fi

if ! wget -qO "$ffsfile" "https://www.freefilesync.org$link" \
    -U "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/63.0.3239.84 Chrome/63.0.3239.84 Safari/537.36"; then
    log "ERROR: Download failed."
    rm -f "$ffsfile"
    exit 1
fi

if ! tar xf "$ffsfile" >/dev/null 2>&1; then
    log "ERROR: Failed to extract $ffsfile. File may be corrupt."
    rm -f "$ffsfile"
    exit 1
fi

extracted=$(ls FreeFileSync*.run 2>/dev/null | head -1)
if [ -z "$extracted" ]; then
    log "ERROR: No FreeFileSync*.run file found after extraction."
    rm -f "$ffsfile"
    exit 1
fi

mv "$extracted" "$ffsrun"
chmod +x "$ffsrun"

/usr/bin/expect <<'EOF'
set timeout 120
log_user 0
spawn ./FreeFileSync.run --accept-license
log_user 1
expect -exact "to begin installation:"
send -- "y\r"
expect eof
EOF

rm -f "$ffsfile" "$ffsrun"

# End
log "ffsupdate done at: $(date)"
