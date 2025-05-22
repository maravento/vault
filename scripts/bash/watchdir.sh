#!/bin/bash

# Watch Directories Script
# https://www.maravento.com/2025/05/control-de-carpetas-compartidas.html
#
# Monitors directories (WATCH_DIR) for new files or empty folders.
# If WATCH_DIR or DELETE_DIR are not defined, the script prompts the user for them.
# When the size limit (MAX_SIZE_MB) is exceeded, it executes an action:
# 1) Delete, 2) Move to Trash, or 3) Move to DELETE_DIR.
#
# Usage:
#  ./watchdir.sh {start|stop|status}

# local user
local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}' || who | head -1 | awk '{print $1}')
user_base=$(getent passwd "$local_user" | cut -d: -f6)
# Log (In the same path as the script)
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
LOGFILE="$SCRIPT_DIR/watcher.log"
# PID
PIDFILE="/tmp/watcher.pid"

### CHANGE VALUES ###

# Folders to monitor (separate with spaces if multiple)
WATCH_DIR="/home/$local_user/dir1 /home/$local_user/dir2"

# To monitor subfolders inside a parent folder:
# MAINDIR="/home/$local_user/dir"
# Subfolder names (separate with spaces if multiple):
# SUBDIRS="dir1 dir2 dir3"
# WATCH_DIR=""
# for d in $SUBDIRS; do
#   WATCH_DIR+="$MAINDIR/$d "
# done
# WATCH_DIR="${WATCH_DIR% }"

# Destination for deleted files and folders (optional)
DELETE_DIR="/home/$local_user/delete"

# Folder size limit
# Example: 30 GB = LIMIT=$((30*1024*1024*1024)) or 1 GB = LIMIT=$((1024*1024*1024))
LIMIT=$((1024*1024*1024))

#####################

# Check dependencies
for pkg in inotify-tools trash-cli; do
    dpkg -s "$pkg" >/dev/null 2>&1 || {
        echo "❌ '$pkg' is missing. Run: sudo apt install $pkg"
        exit 1
    }
done

# Handle a new file or empty directory creation event
handle_new_file() {
    NEWFILE="$1"
    DIR=$(dirname "$NEWFILE")
    sleep 1

    [ ! -e "$NEWFILE" ] && return

    SIZE=$(du -sb "$DIR" 2>/dev/null | awk '{print $1}')
    if [ "$SIZE" -ge "$LIMIT" ]; then
                
        case $ACTION_TYPE in
            permanent_delete)
                if [ -f "$NEWFILE" ]; then
                    rm -f "$NEWFILE"
                    echo "$(date '+%F %T') Permanently deleted: $NEWFILE" >> "$LOGFILE"
                elif [ -d "$NEWFILE" ] && [ -z "$(ls -A "$NEWFILE")" ]; then
                    rmdir "$NEWFILE"
                    echo "$(date '+%F %T') Empty directory permanently deleted: $NEWFILE" >> "$LOGFILE"
                fi
                ;;
            trash)
                if [ -f "$NEWFILE" ] || ([ -d "$NEWFILE" ] && [ -z "$(ls -A "$NEWFILE")" ]); then
                    trash "$NEWFILE"
                    echo "$(date '+%F %T') Sent to trash: $NEWFILE" >> "$LOGFILE"
                fi
                ;;
            move)
                TS=$(date +%Y%m%d)
                DEST="$DELETE_DIR/$TS"

                # Create the base folder where the structure will be rebuilt
                mkdir -p "$DEST"

                if [[ "$NEWFILE" == "$user_base"* ]]; then
                    RELPATH="${NEWFILE#$user_base}"
                    RELPATH="${RELPATH#/}"   # Remove leading slash
                else
                    RELPATH="${NEWFILE#/}"    # Or remove only the first slash if not in home
                fi
                
                mkdir -p "$DEST/$(dirname "$RELPATH")"

                if [ -f "$NEWFILE" ]; then
                    mv -f "$NEWFILE" "$DEST/$RELPATH"
                    echo "$(date '+%F %T') Moved file: $NEWFILE -> $DEST/$RELPATH" >> "$LOGFILE"
                elif [ -d "$NEWFILE" ] && [ -z "$(ls -A "$NEWFILE")" ]; then
                    mv -f "$NEWFILE" "$DEST/$RELPATH"
                    echo "$(date '+%F %T') Moved empty directory: $NEWFILE -> $DEST/$RELPATH" >> "$LOGFILE"
                fi
                ;;
        esac
    fi
}

# Starting Watcher
start() {
    if [ -f "$PIDFILE" ] && kill -0 $(cat "$PIDFILE") 2>/dev/null; then
        echo "Watcher is already running with PID $(cat "$PIDFILE")"
        exit 1
    fi
    
    echo "Starting Watcher..."
    echo
    # Check WATCH_DIR: si TODOS los directorios existen, lo damos por válido
    INVALID_DIRS=0
    if [ -n "$WATCH_DIR" ]; then
        for dir in $WATCH_DIR; do
            if [ ! -d "$dir" ]; then
                INVALID_DIRS=1
                break
            fi
        done
    else
        INVALID_DIRS=1
    fi

    if [ "$INVALID_DIRS" -eq 0 ]; then
        echo "WATCH_DIR is already defined and valid: $WATCH_DIR"
    else
        echo "🔍 Checking WATCH_DIR..."
        INVALID_DIRS=0
        for dir in $WATCH_DIR; do
            if [ ! -d "$dir" ]; then
                echo "❌ Directory not found: $dir"
                INVALID_DIRS=1
            fi
        done

        if [ "$INVALID_DIRS" -eq 1 ]; then
            echo "⚠️ One or more directories are invalid. Try again."
            read -p "Enter watch directory(ies) (separated by spaces): " WATCH_DIR

            echo "🔍 Rechecking WATCH_DIR..."
            INVALID_DIRS=0
            for dir in $WATCH_DIR; do
                if [ ! -d "$dir" ]; then
                    echo "❌ Directory not found: $dir"
                    INVALID_DIRS=1
                fi
            done

            if [ "$INVALID_DIRS" -eq 1 ]; then
                echo "❌ Still invalid. Exiting."
                exit 1
            fi
        fi
    fi

    VALID_DELETE=0
    if [ -n "$DELETE_DIR" ] && [ -d "$DELETE_DIR" ] && [ -w "$DELETE_DIR" ]; then
        echo "DELETE_DIR is already defined and valid: $DELETE_DIR"
        ACTION_OPTION=3
        VALID_DELETE=1
    else
        echo "DELETE_DIR is not defined or invalid/unwritable: $DELETE_DIR"
        # Menu to select the action to perform with files/folders exceeding the size limit
        echo "Action for files/folders over size limit?"
        echo "1. Permanent deletion"
        echo "2. Send to trash"
        echo "3. Move to a specific folder"
        read -p "Select an option (1-3): " ACTION_OPTION
    fi

    if [ "$ACTION_OPTION" = "3" ] && [ "$VALID_DELETE" -eq 0 ]; then
        read -rp "Enter the destination folder path: " CUSTOM_DIR

        if [ ! -d "$CUSTOM_DIR" ]; then
            echo "📁 The folder '$CUSTOM_DIR' does not exist. Do you want to create it? (y/n)"
            read -r CREATE_DIR
            if [[ "$CREATE_DIR" =~ ^[Yy]$ ]]; then
                mkdir -p "$CUSTOM_DIR" 2>/dev/null || {
                    echo "❌ Could not create the folder (check permissions). Exiting."
                    exit 1
                }
            else
                echo "❌ Destination folder does not exist. Exiting."
                exit 1
            fi
        fi

        if [ ! -w "$CUSTOM_DIR" ]; then
            echo "❌ No write permission in destination folder: $CUSTOM_DIR"
            exit 1
        fi

        DELETE_DIR="$CUSTOM_DIR"
    fi
    
    case $ACTION_OPTION in
        1)
            ACTION_TYPE="permanent_delete"
            echo "Files will be permanently deleted."
            ;;
        2)
            ACTION_TYPE="trash"
            echo "Files will be sent to trash."
            ;;
        3)
            ACTION_TYPE="move"
            # ── Añadido: Solo solicitar CUSTOM_DIR si DELETE_DIR no estaba definido ──
            if [ -z "$DELETE_DIR" ]; then
                read -rp "Enter the destination folder path: " CUSTOM_DIR

                if [ ! -d "$CUSTOM_DIR" ]; then
                    echo "📁 The folder '$CUSTOM_DIR' does not exist. Do you want to create it? (y/n)"
                    read -r CREATE_DIR
                    if [[ "$CREATE_DIR" =~ ^[Yy]$ ]]; then
                        mkdir -p "$CUSTOM_DIR" 2>/dev/null
                        if [ $? -ne 0 ]; then
                            echo "❌ Could not create the folder (check permissions). Exiting."
                            exit 1
                        fi
                    else
                        echo "❌ Destination folder does not exist. Exiting."
                        exit 1
                    fi
                fi

                if [ ! -w "$CUSTOM_DIR" ]; then
                    echo "❌ No write permission in destination folder: $CUSTOM_DIR"
                    exit 1
                fi

                DELETE_DIR="$CUSTOM_DIR"
            fi

            echo "✅ Files will be moved to: $DELETE_DIR"
            ;;
        *)
            echo "❌ Invalid option. Exiting."
            exit 1
            ;;
    esac

    export -f handle_new_file

    inotifywait -m -r -e create --format '%w%f' $WATCH_DIR 2>/dev/null | while read NEWFILE; do
        handle_new_file "$NEWFILE"
    done &

    echo $! > "$PIDFILE"
    echo "Watcher started with PID $(cat "$PIDFILE")"
}


# Stopping Watcher
stop() {
    echo "Stopping Watcher..."
    echo
    if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE")
        kill "$PID" 2>/dev/null && echo "Watcher stopped (PID $PID)" || echo "Could not stop watcher"
        rm -f "$PIDFILE"
    else
        echo "Watcher is not running"
    fi
}

# Watcher Status
status() {
    echo "Watcher Status..."
    echo
    if [ -f "$PIDFILE" ] && kill -0 $(cat "$PIDFILE") 2>/dev/null; then
        echo "Watcher is running (PID $(cat "$PIDFILE"))"
    else
        echo "Watcher is not running"
    fi
}

case "$1" in
    start) start ;;
    stop) stop ;;
    status) status ;;
    *) echo "Usage: $0 {start|stop|status}" ;;
esac

