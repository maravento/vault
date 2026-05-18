#!/bin/bash
# maravento.com
#
################################################################################
#
# smbstack - Shared Folder Watch Shared Folder
# https://github.com/maravento/vault/tree/master/smbstack
#
# Monitors first-level subdirectories of the shared folder.
# When a subdirectory exceeds WATCH_LIMIT_MB, the triggering file
# is moved to the recycle bin.
#
# Usage:
#  ./smbwatch.sh {start|stop|status}
#
################################################################################

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

### PATHS
SMBSTACK_ENV="/var/www/smbstack/smbstack.env"
LOGFILE="/var/www/smbstack/tools/smbwatch.log"
PIDFILE="/tmp/smbstack-smbwatch.pid"

### CHECK DEPENDENCIES
for pkg in inotify-tools; do
    dpkg -s "$pkg" >/dev/null 2>&1 || {
        echo "ERROR: '$pkg' is missing. Run: sudo apt install $pkg"
        exit 1
    }
done

### LOAD ENV
if [ ! -f "$SMBSTACK_ENV" ]; then
    echo "ERROR: smbstack is not installed. Run smbinstall.sh --install first."
    exit 1
fi

load_env() {
    while IFS= read -r line; do
        [[ "$line" =~ ^[A-Z_]+=.* ]] && eval "export $line"
    done < "$SMBSTACK_ENV"
}
load_env

### CHECK AND SET WATCH_LIMIT_MB
if [ -z "${WATCH_LIMIT_MB:-}" ]; then
    while true; do
        read -p "Enter watch limit per folder in MB [1024]: " input_limit
        input_limit="${input_limit:-1024}"
        if [[ "$input_limit" =~ ^[0-9]+$ ]] && [ "$input_limit" -gt 0 ]; then
            WATCH_LIMIT_MB="$input_limit"
            echo "WATCH_LIMIT_MB=\"$WATCH_LIMIT_MB\"" >> "$SMBSTACK_ENV"
            echo "Watch limit set to ${WATCH_LIMIT_MB} MB"
            break
        else
            echo "ERROR: Enter a valid number greater than 0"
        fi
    done
fi

LIMIT=$((WATCH_LIMIT_MB * 1024 * 1024))

### BUILD WATCH_DIR from SHARED_PATH first-level subdirs (excluding recycle)
if [ -z "${SHARED_PATH:-}" ] || [ ! -d "$SHARED_PATH" ]; then
    echo "ERROR: SHARED_PATH is not set or does not exist. Check $SMBSTACK_ENV"
    exit 1
fi

RECYCLE_DIR="$SHARED_PATH/recycle"
WATCH_DIR=""
while IFS= read -r -d '' dir; do
    [ "$(basename "$dir")" = "recycle" ] && continue
    WATCH_DIR+="$dir "
done < <(find "$SHARED_PATH" -mindepth 1 -maxdepth 1 -type d -print0)
WATCH_DIR="${WATCH_DIR% }"

if [ -z "$WATCH_DIR" ]; then
    echo "ERROR: No subdirectories found in $SHARED_PATH"
    exit 1
fi

### HANDLE NEW FILE
handle_new_file() {
    local NEWFILE="$1"
    local DIR
    DIR=$(dirname "$NEWFILE")
    sleep 1

    [ ! -e "$NEWFILE" ] && return

    local SIZE
    SIZE=$(du -sb "$DIR" 2>/dev/null | awk '{print $1}')

    if [ "$SIZE" -ge "$LIMIT" ]; then
        mkdir -p "$RECYCLE_DIR"
        local TS
        TS=$(date +%Y%m%d)
        local DEST="$RECYCLE_DIR/$TS"
        mkdir -p "$DEST"

        if [ -f "$NEWFILE" ]; then
            mv -f "$NEWFILE" "$DEST/$(basename "$NEWFILE")"
            echo "$(date '+%F %T') Moved file to recycle: $NEWFILE -> $DEST" >> "$LOGFILE"
        elif [ -d "$NEWFILE" ] && [ -z "$(ls -A "$NEWFILE")" ]; then
            mv -f "$NEWFILE" "$DEST/$(basename "$NEWFILE")"
            echo "$(date '+%F %T') Moved empty dir to recycle: $NEWFILE -> $DEST" >> "$LOGFILE"
        fi
    fi
}

### START
start() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "SMBwatch is already running with PID $(cat "$PIDFILE")"
        exit 1
    fi

    echo "Starting smbwatch..."
    echo "  Shared path : $SHARED_PATH"
    echo "  Watch limit : ${WATCH_LIMIT_MB} MB per folder"
    echo "  Watching    : $WATCH_DIR"
    echo "  Recycle bin : $RECYCLE_DIR"
    echo "  Log         : $LOGFILE"
    echo ""

    # shellcheck disable=SC2086
    inotifywait -m -r -e create --format '%w%f' $WATCH_DIR 2>/dev/null | while read -r NEWFILE; do
        handle_new_file "$NEWFILE"
    done &

    echo $! > "$PIDFILE"
    echo "SMBwatch started with PID $(cat "$PIDFILE")"

    # add @reboot cron entry if not already present
    if ! crontab -l 2>/dev/null | grep -q "smbwatch.sh start"; then
        (crontab -l 2>/dev/null; echo "@reboot /var/www/smbstack/tools/smbwatch.sh start") | sort -u | crontab -
        echo "Added to cron @reboot"
    fi
}

### STOP
stop() {
    echo "Stopping smbwatch..."
    if [ -f "$PIDFILE" ]; then
        local PID
        PID=$(cat "$PIDFILE")
        kill "$PID" 2>/dev/null && echo "SMBwatch stopped (PID $PID)" || echo "Could not stop smbwatch"
        rm -f "$PIDFILE"
    else
        echo "SMBwatch is not running"
    fi
}

### STATUS
status() {
    echo "SMBwatch status..."
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "  SMBwatch is RUNNING (PID $(cat "$PIDFILE"))"
        echo "  Watch limit : ${WATCH_LIMIT_MB} MB per folder"
        echo "  Watching    : $WATCH_DIR"
    else
        echo "  SMBwatch is STOPPED"
    fi
}

### MAIN
case "$1" in
    start)  start ;;
    stop)   stop ;;
    status) status ;;
    *)      echo "Usage: $(basename "$0") {start|stop|status}" ;;
esac
