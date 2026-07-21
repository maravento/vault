#!/bin/bash
# maravento.com
#
################################################################################
#
# Rclone Manager (Gdrive, PCloud, Dropbox, OneDrive, Mega...)
# https://www.maravento.com/2023/09/2-way-sync-con-rclone.html
#
# Cloud mount and 2-way folder sync in a single menu/CLI.
#
# Requires Rclone remotes already configured (rclone config) for each
# service in the `services` array below.
#
# MOUNT
# Mounts each configured remote as a folder under /home/$local_user/cloud
# (e.g. cloud/drive, cloud/dropbox) using rclone mount + fuse3.
# sudo ./rclonemgr.sh mount start     mount all configured remotes
# sudo ./rclonemgr.sh mount stop      unmount all
# sudo ./rclonemgr.sh mount restart   stop + start
# sudo ./rclonemgr.sh mount status    show mount/process status
#
# Once remotes are configured, mount start can be scheduled in root's
# crontab to run on boot:
# @reboot /etc/scr/rclonemgr.sh mount start
#
# SYNC
# 2-way syncs local /home/$local_user/sync/<service>/{upload,download}
# against the mounted cloud/<service>/{upload,download} folders, per
# service, using `rclone sync`. Only acts on services that are both
# configured in Rclone and currently mounted (run mount start first).
# sudo ./rclonemgr.sh sync run        run one sync pass
# sudo ./rclonemgr.sh sync status     show configured/mounted status
#
# Sync is not scheduled by this script -- add your own cron entry
# (e.g. */15 * * * * /etc/scr/rclonemgr.sh sync run) once mount is set up
# and the upload/download folders are in place.
#
# Interactive menu (no arguments):
# sudo ./rclonemgr.sh
#
################################################################################

set -uo pipefail

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# LOG FILE for debugging
SCRIPT_LOG="/var/log/rclonemgr.log"
exec 1> >(tee -a "$SCRIPT_LOG")
exec 2>&1

# LOCAL USER detection
detect_local_user() {
    local uid_min uid_max
    local user uid best_user="" best_uid=999999

    uid_min=$(awk '/^UID_MIN/{print $2}' /etc/login.defs 2>/dev/null)
    uid_max=$(awk '/^UID_MAX/{print $2}' /etc/login.defs 2>/dev/null)
    uid_min=${uid_min:-1000}
    uid_max=${uid_max:-60000}

    while IFS=: read -r user _ uid _ _ _ shell; do
        [ "$user" = "root" ] && continue
        [ -z "$uid" ] && continue
        [ "$uid" -lt "$uid_min" ] && continue
        [ "$uid" -gt "$uid_max" ] && continue

        case "$shell" in
            */false|*/nologin) continue ;;
        esac

        id -nG "$user" 2>/dev/null | grep -qw sudo || continue

        if [ "$uid" -lt "$best_uid" ]; then
            best_uid="$uid"
            best_user="$user"
        fi
    done </etc/passwd

    [ -n "$best_user" ] || return 1
    echo "$best_user"
}

if ! local_user=$(detect_local_user); then
    echo "ERROR: No valid local user found. Create one with sudo access."
    exit 1
fi
echo "Using local user: $local_user"

# check internet with retry (essential for @reboot)
check_internet() {
    echo "Checking internet connection..."
    local max_attempts=24 attempt=0 # 2 min top
    while [ $attempt -lt $max_attempts ]; do
        if timeout 3 host www.google.com &>/dev/null; then
            echo "Internet: Online (attempt $((attempt + 1)))"
            return 0
        fi
        attempt=$((attempt + 1))
        if [ $attempt -eq $max_attempts ]; then
            echo "ERROR: Internet offline after $((max_attempts * 5)) seconds"
            return 1
        fi
        echo "Waiting for internet... attempt $attempt/$max_attempts"
        sleep 5
    done
}

# checking dependencies
install_dependencies() {
    if ! command -v rclone &>/dev/null; then
        echo "Installing Rclone..."
        local rclone_installer
        rclone_installer="$(mktemp /tmp/rclone-install.XXXXXX.sh)"
        if ! curl -fsSL https://rclone.org/install.sh -o "$rclone_installer"; then
            echo "ERROR: Failed to download Rclone installer"
            rm -f "$rclone_installer"
            return 1
        fi
        bash "$rclone_installer"
        rm -f "$rclone_installer"
        if ! command -v rclone &>/dev/null; then
            echo "ERROR: Failed to install Rclone"
            return 1
        fi
        echo "Rclone installed successfully"
    fi

    local pkg='fuse3'
    if ! dpkg -s "$pkg" &>/dev/null; then
        echo "Installing $pkg..."
        if ! apt-get -qq install -y $pkg; then
            echo "ERROR: Failed to install $pkg"
            return 1
        fi
    fi
}

# VARIABLES
cloud_path="/home/$local_user/cloud"
sync_path="/home/$local_user/sync"
mount_lock="/tmp/cloud_drive_mount.lock"

# Log Level (INFO, DEBUG, NOTICE, ERROR)
loglevel="DEBUG"

# add any services supported by Rclone
services=(
    # Mega
    mega
    # Pcloud
    pcloud
    # Dropbox
    dropbox
    # Google Drive
    drive
    # MS OneDrive
    onedrive
    # Add more services here as needed
)

is_service_configured() {
    local service_name="$1"
    sudo -u "$local_user" bash -c "rclone listremotes | grep -q '^${service_name}:\$'"
}

##############################################
# MOUNT (cloud as a mounted drive)
##############################################

mount_start() {
    if [ -e "$mount_lock" ]; then
        echo "WARNING: Lock file exists, script may already be running"
        exit 1
    fi
    touch "$mount_lock"

    for service_name in "${services[@]}"; do
        local service_path="$cloud_path/$service_name"
        [ -d "$service_path" ] || sudo -u "$local_user" mkdir -p "$service_path"

        echo "Mounting $service_name to $service_path"

        if ! is_service_configured "$service_name"; then
            echo "ERROR: Rclone remote '$service_name' not configured"
            continue
        fi

        if mount | grep -q "$service_path"; then
            echo "WARNING: $service_name is already mounted at $service_path, skipping"
            continue
        fi

        sudo -u "$local_user" nohup rclone mount "$service_name:" "$service_path" \
            --log-file "$cloud_path/rclone.log" \
            --log-level "$loglevel" \
            --vfs-cache-mode writes \
            --daemon \
            >/dev/null 2>&1 &

        sleep 2

        if mount | grep -q "$service_path"; then
            echo "SUCCESS: $service_name mounted"
        else
            echo "WARNING: $service_name may not be mounted correctly"
        fi
    done

    echo "Mount started successfully"
}

mount_stop() {
    if [ ! -e "$mount_lock" ]; then
        echo "WARNING: Mount is not running (no lock file)"
    fi

    for service_name in "${services[@]}"; do
        local service_path="$cloud_path/$service_name"
        if mount | grep -q "$service_path"; then
            echo "Unmounting $service_name"
            if fusermount -u "$service_path" 2>/dev/null; then
                echo "$service_name unmounted"
            else
                echo "WARNING: Graceful unmount failed for $service_name, forcing..."
                fusermount -uz "$service_path"
                echo "$service_name force-unmounted"
            fi
        else
            echo "$service_name is not mounted"
        fi
    done

    rm -f "$mount_lock"
    echo "Mount stopped"
}

mount_restart() {
    echo "Restarting mount..."
    mount_stop
    sleep 3
    mount_start
}

mount_status() {
    echo "=== Rclone Mount Status ==="

    if [ -e "$mount_lock" ]; then
        echo "Lock file: EXISTS"
    else
        echo "Lock file: NOT FOUND"
    fi

    echo ""
    echo "Mount status:"
    for service_name in "${services[@]}"; do
        local service_path="$cloud_path/$service_name"
        if mount | grep -q "$service_path"; then
            echo "$service_name is MOUNTED at $service_path"
        else
            echo "$service_name is NOT MOUNTED"
        fi
    done

    echo ""
    echo "Rclone processes:"
    ps aux | grep "[r]clone mount" || echo " No rclone mount processes found"
}

run_mount() {
    case "${1:-}" in
    start)
        check_internet || exit 1
        install_dependencies || exit 1
        mount_start
        ;;
    stop) mount_stop ;;
    restart)
        check_internet || exit 1
        install_dependencies || exit 1
        mount_restart
        ;;
    status) mount_status ;;
    *)
        echo
        echo "Usage: $0 mount { start | stop | restart | status }"
        echo
        exit 1
        ;;
    esac
}

##############################################
# SYNC (2-way sync of a local upload/download folder)
##############################################

sync_transfer() {
    local direction="$1" service_name="$2" src="$3" dst="$4"
    echo "Sync $direction $service_name"
    sudo -u "$local_user" bash -c "rclone sync '$src' '$dst' --update --modify-window 1h --skip-links --verbose --transfers 30 --checkers 8 --contimeout 60s --timeout 300s --retries 3 --low-level-retries 10 --stats 1s --stats-file-name-length 0 --log-file='$cloud_path/rsync.log'"
    echo "OK"
}

sync_run() {
    echo "Run Sync at $(date)" | tee -a /var/log/syslog

    for service_name in "${services[@]}"; do
        local service_path="$cloud_path/$service_name"
        if ! is_service_configured "$service_name"; then
            echo "$service_name is not configured in Rclone. Skipping..."
            continue
        fi
        if ! mount | grep -q "$service_path"; then
            echo "$service_name is not mounted."
            continue
        fi

        echo "$service_name is mounted."
        for subfolder in download upload; do
            sudo -u "$local_user" bash -c "mkdir -p '$service_path/$subfolder'"
            sudo -u "$local_user" bash -c "mkdir -p '$sync_path/$service_name/$subfolder'"
        done

        sync_transfer "Download" "$service_name" "$service_path/download" "$sync_path/$service_name/download"
        sync_transfer "Upload" "$service_name" "$sync_path/$service_name/upload" "$service_path/upload"
    done

    echo "Done"
}

sync_status() {
    echo "=== Rclone Sync Status ==="
    for service_name in "${services[@]}"; do
        if is_service_configured "$service_name"; then
            if mount | grep -q "$cloud_path/$service_name"; then
                echo "$service_name: configured, mounted"
            else
                echo "$service_name: configured, NOT mounted (sync will skip it)"
            fi
        else
            echo "$service_name: NOT configured in Rclone"
        fi
    done
}

run_sync() {
    case "${1:-}" in
    run)
        check_internet || exit 1
        install_dependencies || exit 1
        sync_run
        ;;
    status) sync_status ;;
    *)
        echo
        echo "Usage: $0 sync { run | status }"
        echo
        exit 1
        ;;
    esac
}

##############################################
# MENU / DISPATCH
##############################################

show_menu() {
    echo
    echo "Rclone Manager"
    echo "1) Mount start"
    echo "2) Mount stop"
    echo "3) Mount restart"
    echo "4) Mount status"
    echo "5) Sync run"
    echo "6) Sync status"
    echo "7) Exit"
    echo
    read -rp "Select an option [1-7]: " opt
    case "$opt" in
    1) run_mount start ;;
    2) run_mount stop ;;
    3) run_mount restart ;;
    4) run_mount status ;;
    5) run_sync run ;;
    6) run_sync status ;;
    7) exit 0 ;;
    *) echo "Invalid option" ;;
    esac
}

MODE="${1:-}"
ACTION="${2:-}"

case "$MODE" in
mount)
    run_mount "$ACTION"
    ;;
sync)
    run_sync "$ACTION"
    ;;
'')
    show_menu
    ;;
*)
    echo
    echo "Usage: $0 { mount { start | stop | restart | status } | sync { run | status } }"
    echo
    exit 1
    ;;
esac

exit 0
