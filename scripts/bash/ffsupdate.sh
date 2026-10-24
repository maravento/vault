#!/bin/bash
# maravento.com
#
################################################################################
#
# FreeFileSync Update
# FILE: ffsupdate.sh
#
# DESCRIPTION: Downloads and silently installs the latest FreeFileSync
# release. Run as root, intended for cron/unattended use.
#
# USAGE: sudo ./ffsupdate.sh
#
# LOG: /var/log/ffsupdate.log (rewritten on each run)
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# root check
if [ "$(id -u)" != "0" ]; then
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

# logging
log_file="/var/log/ffsupdate.log"
{ > "$log_file"; } 2>/dev/null || true
log() {
    local msg="$1"
    local log_msg="$(date '+%Y-%m-%d %H:%M:%S') $msg"
    echo "$log_msg" >> "$log_file" 2>/dev/null || true
    if [[ "$msg" == ERROR:* ]]; then
        echo "$log_msg" >&2
    else
        echo "$log_msg"
    fi
}

# Start
log "ffsupdate start..."

# dependencies
for dep in expect tcl-expect wget tar coreutils util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: dependency '$dep' is not installed -abort"
        exit 1
    fi
done

# check internet
check_internet() {
    local max_attempts="${1:-24}" attempt=1

    while (( attempt <= max_attempts )); do
        if getent hosts www.google.com >/dev/null 2>&1; then
            log "INFO: internet is available"
            return 0
        fi
        log "INFO: waiting for internet ($attempt/$max_attempts)"
        attempt=$((attempt + 1))
        sleep 5
    done

    return 1
}

if ! check_internet; then
    log "ERROR: no internet connection -abort"
    exit 1
fi

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

ffsfile="FreeFileSync.tar.gz"
ffsrun="FreeFileSync.run"
url="https://www.freefilesync.org/download.php"

trap 'rm -f "$ffsfile" "$ffsrun"; log "ERROR: aborted, temporary files cleaned up -abort"; exit 1' ERR INT TERM

link=$(wget -q "$url" -O - | grep -Pio '/download/[^"]+Linux[^"]+gz') || true
if [ -z "$link" ]; then
    log "ERROR: download link missing; site may have changed -abort"
    exit 1
fi

version=$(echo "$link" | sed -r 's:.*FreeFileSync_([0-9]+\.[0-9]+)_.*:\1:')
if [ -z "$version" ]; then
    log "ERROR: could not parse version from link: $link -abort"
    exit 1
fi

if ! wget -qO "$ffsfile" "https://www.freefilesync.org$link" \
    -U "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/63.0.3239.84 Chrome/63.0.3239.84 Safari/537.36"; then
    log "PARTIAL: https://www.freefilesync.org$link"
    rm -f "$ffsfile"
    exit 1
fi
log "SAVED: $ffsfile"

if ! tar xf "$ffsfile" >/dev/null 2>&1; then
    log "ERROR: extraction failed; archive may be corrupt -abort"
    rm -f "$ffsfile"
    exit 1
fi

extracted=$(ls FreeFileSync*.run 2>/dev/null | head -1)
if [ -z "$extracted" ]; then
    log "ERROR: no FreeFileSync installer after extraction -abort"
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

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# End
log "ffsupdate done at: $(date '+%Y-%m-%d %H:%M:%S')"
