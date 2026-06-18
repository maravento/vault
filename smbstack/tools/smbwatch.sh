#!/bin/bash
# maravento.com
#
################################################################################
#
# smbstack - Shared Folder Watchdog
# https://github.com/maravento/vault/tree/master/smbstack
#
# Monitors first-level subdirectories of the shared folder.
# When a subdirectory exceeds WATCH_LIMIT_GB, the triggering file
# is moved to .recycle bin.
# Folders listed in WATCH_EXCLUDE are not monitored (no size limit).
#
# smbstack.env variables:
#  WATCH_LIMIT_GB  : size limit per monitored folder in GB (default: 10)
#  WATCH_EXCLUDE   : comma-separated folder names to exclude from monitoring
#                    e.g. WATCH_EXCLUDE="FINANCE,LEGAL"
#
# Log file:
#  /var/log/smbwatch.log (root:root, 640)
#  Rotated weekly via /etc/logrotate.d/smbwatch
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

# checking script execution (only for start)
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"

### PATHS
SMBSTACK_ENV="/var/www/smbstack/smbstack.env"
LOGFILE="/var/log/smbwatch.log"
PIDFILE="/tmp/smbstack-smbwatch.pid"
STATEFILE="/tmp/smbstack-smbwatch.state"

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
        if [[ "$line" =~ ^[A-Z_]+=.* ]]; then
            key="${line%%=*}"
            val="${line#*=}"
            val="${val//\"}"
            export "$key=$val"
        fi
    done < "$SMBSTACK_ENV"
}
load_env

set_env_var() {
    local key="$1" val="$2"
    local esc_val
    val=$(printf '%s' "$val" | tr -d '\r\n')
    esc_val=$(printf '%s' "$val" | sed -e 's/[\&|]/\\&/g')
    if grep -q "^${key}=" "$SMBSTACK_ENV"; then
        sed -i "s|^${key}=.*|${key}=\"${esc_val}\"|" "$SMBSTACK_ENV"
    else
        echo "${key}=\"${val}\"" >> "$SMBSTACK_ENV"
    fi
}

### HANDLE NEW FILE
handle_new_file() {
    local NEWFILE="$1"
    sleep 1

    [ ! -e "$NEWFILE" ] && return

    local REL="${NEWFILE#"$SHARED_PATH"/}"
    local TOP_DIR="$SHARED_PATH/${REL%%/*}"

    local SIZE
    SIZE=$(du -sb "$TOP_DIR" 2>/dev/null | awk '{print $1}')
    [[ "$SIZE" =~ ^[0-9]+$ ]] || SIZE=0

    if [ "$SIZE" -ge "$LIMIT" ]; then
        mkdir -p "$RECYCLE_DIR"
        chown "${LOCAL_USER:-root}":sambashare "$RECYCLE_DIR" 2>/dev/null || true
        chmod 775 "$RECYCLE_DIR"
        local TS
        TS=$(date +%Y%m%d)
        local DEST="$RECYCLE_DIR/$TS"
        mkdir -p "$DEST"
        chown "${LOCAL_USER:-root}":sambashare "$DEST"
        chmod 775 "$DEST"

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

    if [ ! -f "$LOGFILE" ]; then
        touch "$LOGFILE"
        chmod 640 "$LOGFILE"
        chown root:root "$LOGFILE"
    fi

    ### CHECK AND SET WATCH_LIMIT_GB
    if [ -z "${WATCH_LIMIT_GB:-}" ]; then
        while true; do
            read -p "Enter watch limit per folder in GB [10]: " input_limit
            input_limit="${input_limit:-10}"
            if [[ "$input_limit" =~ ^[0-9]+$ ]] && [ "$input_limit" -gt 0 ] && [ "$input_limit" -le 10000 ]; then
                WATCH_LIMIT_GB="$input_limit"
                set_env_var "WATCH_LIMIT_GB" "$WATCH_LIMIT_GB"
                echo "Watch limit set to ${WATCH_LIMIT_GB} GB"
                break
            else
                echo "ERROR: Enter a valid number between 1 and 10000"
            fi
        done
    fi

    ### CHECK AND SET WATCH_EXCLUDE
    if [ -z "${WATCH_EXCLUDE:-}" ]; then
        read -p "Enter folders to exclude from watch limit (comma-separated, or leave empty): " input_exclude
        if [ -n "$input_exclude" ]; then
            WATCH_EXCLUDE="$input_exclude"
            set_env_var "WATCH_EXCLUDE" "$WATCH_EXCLUDE"
            echo "Excluded folders: ${WATCH_EXCLUDE}"
        else
            WATCH_EXCLUDE="NONE"
            set_env_var "WATCH_EXCLUDE" "NONE"
            echo "No folders excluded"
        fi
    fi
    [ "$WATCH_EXCLUDE" = "NONE" ] && WATCH_EXCLUDE=""

    LIMIT=$((WATCH_LIMIT_GB * 1024 * 1024 * 1024))

    ### BUILD WATCH_DIR from SHARED_PATH first-level subdirs (excluding hidden dirs and excluded folders)
    if [ -z "${SHARED_PATH:-}" ] || [ ! -d "$SHARED_PATH" ]; then
        echo "ERROR: SHARED_PATH is not set or does not exist. Check $SMBSTACK_ENV"
        exit 1
    fi

    RECYCLE_DIR="$SHARED_PATH/.recycle"
    WATCH_DIRS=()
    IFS=',' read -ra EXCLUDE_LIST <<< "${WATCH_EXCLUDE:-}"
    while IFS= read -r -d '' dir; do
        dirname="$(basename "$dir")"
        [[ "$dirname" == .* ]] && continue
        excluded=0
        for ex in "${EXCLUDE_LIST[@]}"; do
            ex="${ex#"${ex%%[![:space:]]*}"}" ; ex="${ex%"${ex##*[![:space:]]}"}"
            [ "$dirname" = "$ex" ] && excluded=1 && break
        done
        [ "$excluded" -eq 1 ] && continue
        WATCH_DIRS+=("$dir")
    done < <(find "$SHARED_PATH" -mindepth 1 -maxdepth 1 -type d -print0)

    if [ "${#WATCH_DIRS[@]}" -eq 0 ]; then
        echo "ERROR: No subdirectories found in $SHARED_PATH"
        exit 1
    fi

    printf '%s\n' "${WATCH_DIRS[@]}" > "$STATEFILE"

    echo "Starting smbwatch..."
    echo "  Shared path : $SHARED_PATH"
    echo "  Watch limit : ${WATCH_LIMIT_GB} GB per folder"
    echo "  Watching    :"
    printf '    %s\n' "${WATCH_DIRS[@]}"
    echo "  Excluded    : ${WATCH_EXCLUDE:-none}"
    echo "  Recycle bin : $RECYCLE_DIR"
    echo "  Log         : $LOGFILE"
    echo ""

    exec 200>&-
    inotifywait -m -r -e create --format '%w%f' "${WATCH_DIRS[@]}" 2>>"$LOGFILE" | while read -r NEWFILE; do
        handle_new_file "$NEWFILE"
    done &

    echo $! > "$PIDFILE"
    echo "SMBwatch started with PID $(cat "$PIDFILE")"

    # add @reboot cron entry if not already present
    if ! crontab -l 2>/dev/null | grep -q "smbwatch.sh start"; then
        crontab -l 2>/dev/null > "/var/www/smbstack/tools/crontab-$(date +%Y%m%d%H%M%S).bak" || true
        (crontab -l 2>/dev/null; echo "@reboot /var/www/smbstack/tools/smbwatch.sh start") | crontab -
        echo "Added to cron @reboot"
    fi
}

### STOP
stop() {
    echo "Stopping smbwatch..."
    if [ -f "$PIDFILE" ]; then
        local PID PGID
        PID=$(cat "$PIDFILE")
        if kill -0 "$PID" 2>/dev/null; then
            PGID=$(ps -o pgid= -p "$PID" 2>/dev/null | tr -d ' ')
            if [ -n "$PGID" ]; then
                kill -- "-$PGID" 2>/dev/null
            else
                kill "$PID" 2>/dev/null
            fi
            echo "SMBwatch stopped (PID $PID)"
        else
            echo "SMBwatch was not running (stale PID file removed)"
        fi
        rm -f "$PIDFILE" "$STATEFILE"
    else
        echo "SMBwatch is not running"
    fi
}

### STATUS
status() {
    echo "SMBwatch status..."
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "  SMBwatch is RUNNING (PID $(cat "$PIDFILE"))"
        echo "  Watch limit : ${WATCH_LIMIT_GB} GB per folder"
        if [ -f "$STATEFILE" ]; then
            echo "  Watching    :"
            sed 's/^/    /' "$STATEFILE"
        else
            echo "  Watching    : (unknown, state file missing)"
        fi
    else
        echo "  SMBwatch is STOPPED"
    fi
}

### MAIN
case "$1" in
    start)
        exec 200>"$SCRIPT_LOCK"
        if ! flock -n 200; then
            echo "Script $(basename "$0") is already running"
            exit 1
        fi
        start
        ;;
    stop)   stop ;;
    status) status ;;
    *)      echo "Usage: $(basename "$0") {start|stop|status}" ;;
esac
