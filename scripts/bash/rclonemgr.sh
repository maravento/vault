#!/bin/bash
# maravento.com
#
################################################################################
#
# rclonemgr -- Rclone cloud remote mount and sync manager
# FILE: rclonemgr.sh
#
# DESCRIPTION:
# Manages Rclone cloud remotes (Gdrive, PCloud, Dropbox, OneDrive, Mega...):
# mounts configured remotes as local folders and performs 2-way sync between
# local upload/download folders and the mounted cloud folders.
# Requires Rclone remotes already configured (rclone config) for each
# service.
#
# USAGE:
# sudo ./rclonemgr.sh mount { --start | --stop | --restart | --status }
# sudo ./rclonemgr.sh sync { --run | --status }
# Without arguments, shows an interactive menu.
#
# LOG: /var/log/rclonemgr.log
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# path for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# root check
if [ "$(id -u)" != "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# prevent overlapping runs
MOUNT_LOCK="/var/lock/$(basename "$0" .sh)-mount.lock"
SYNC_LOCK="/var/lock/$(basename "$0" .sh)-sync.lock"

lock_mount() {
    exec 200>"$MOUNT_LOCK"
    if ! flock -n 200; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: another mount operation is running -abort" >&2
        exit 1
    fi
}

lock_sync() {
    exec 201>"$SYNC_LOCK"
    if ! flock -n 201; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: a sync pass is already running -abort" >&2
        exit 1
    fi
}

# LOG FILE for debugging
SCRIPT_LOG="/var/log/rclonemgr.log"
exec 1> >(tee -a "$SCRIPT_LOG")
exec 2>&1

# local_user detection
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
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no local user; create one with sudo access -abort" >&2
    exit 1
fi
echo "Using local user: $local_user"

# dependencies
for dep in fuse3 curl iproute2 libc-bin bsdutils util-linux; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep" 2>/dev/null)" != *"ok installed"* ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
        exit 1
    fi
done

# dependencies (curl install)
if ! command -v rclone &>/dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: 'rclone' is not installed" >&2
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: install it with: curl https://rclone.org/install.sh | sudo bash -abort" >&2
    exit 1
fi

# check ipv4 interfaces
list_ifaces() {
    ip -br link show 2>/dev/null | awk '$1 != "lo" {sub(/@.*/, "", $1); printf "%s %s\n", $1, ($2 == "UP") ? "UP" : "DOWN"}'
}

list_ipv4_ifaces() {
    local iface state
    while read -r iface state; do
        [ "$state" = UP ] || continue
        if ip -4 -o addr show dev "$iface" scope global 2>/dev/null \
            | awk '$4 != "" {found=1} END {exit !found}'; then
            printf '%s\n' "$iface"
        fi
    done < <(list_ifaces)
}

check_ipv4_interfaces() {
    local max_attempts=24 attempt=1

    while (( attempt <= max_attempts )); do
        if [ -n "$(list_ipv4_ifaces)" ]; then
            return 0
        fi
        if (( attempt == 1 )); then
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: waiting for an interface with IPv4..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no interface with IPv4 -abort" >&2
    exit 1
}

# check internet (essential for @reboot)
check_internet() {
    local max_attempts="${1:-24}" attempt=1

    while (( attempt <= max_attempts )); do
        if getent hosts www.google.com >/dev/null 2>&1; then
            return 0
        fi
        if (( attempt == 1 )); then
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: waiting for internet..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    return 1
}

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

rclone_path="/home/$local_user/rclone"
cloud_path="$rclone_path/cloud"
sync_path="$rclone_path/sync"

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

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

# SERVICE CHECK
# Answers whether the remote is already configured in the user's rclone
is_service_configured() {
    local service_name="$1"
    sudo -u "$local_user" bash -c "rclone listremotes | grep -q '^${service_name}:\$'"
}

# ------------------------------------------------------------------------------
# MOUNT
# ------------------------------------------------------------------------------

# Mounts the configured cloud remote as a local drive

# Exact match against the kernel mount table: a path that only starts the same
# as another mount does not count.
is_mounted() {
    findmnt --kernel --noheadings --mountpoint "$1" >/dev/null 2>&1
}

# MOUNT START
# Creates the mount point and starts rclone for each remote
mount_start() {
    local mount_failed=0
    for service_name in "${services[@]}"; do
        local service_path="$cloud_path/$service_name"
        [ -d "$service_path" ] || sudo -u "$local_user" mkdir -p "$service_path"

        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Mounting $service_name to $service_path"

        if ! is_service_configured "$service_name"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: rclone remote '$service_name' not configured -alert"
            continue
        fi

        if is_mounted "$service_path"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: $service_name is already mounted at $service_path -skip"
            continue
        fi

        (exec 200>&- 201>&-
        sudo -u "$local_user" nohup rclone mount "$service_name:" "$service_path" \
            --log-file "$rclone_path/rclone.log" \
            --log-level "$loglevel" \
            --vfs-cache-mode writes \
            --daemon \
            >/dev/null 2>&1 &)

        sleep 2

        if is_mounted "$service_path"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: $service_name mounted"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: $service_name may not be mounted correctly -alert"
            mount_failed=1
        fi
    done

    if (( mount_failed )); then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: mount incomplete -abort" >&2
        return 1
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Mount start finished"
}

# MOUNT STOP
# Unmounts each mounted remote, forcing it when the graceful way fails
mount_stop() {
    local stop_failed=0 mount_info
    for service_name in "${services[@]}"; do
        local service_path="$cloud_path/$service_name"
        if mount_info=$(findmnt --kernel --raw --noheadings --output FSTYPE,SOURCE --mountpoint "$service_path"); then
            if [[ "$mount_info" != "fuse.rclone $service_name:" ]]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: unexpected mount at $service_name -alert"
                stop_failed=1
                continue
            fi
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Unmounting $service_name"
            if fusermount -u "$service_path" 2>/dev/null; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: $service_name unmounted"
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: graceful unmount failed for $service_name, forcing -alert"
                if [[ $(findmnt --kernel --raw --noheadings --output FSTYPE,SOURCE --mountpoint "$service_path") == "fuse.rclone $service_name:" ]] &&
                   fusermount -uz "$service_path"; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: $service_name force-unmounted"
                else
                    echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: cannot unmount $service_name -alert"
                    stop_failed=1
                fi
            fi
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: $service_name is not mounted -skip"
        fi
    done

    if (( stop_failed )); then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: unmount incomplete -abort" >&2
        return 1
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Mount stop finished"
}

# MOUNT RESTART
# Unmounts everything, waits, and mounts again
mount_restart() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Restarting mount..."
    mount_stop || return 1
    sleep 3
    mount_start || return 1
}

# MOUNT STATUS
# Prints which remotes are mounted and lists the rclone mount processes
mount_status() {
    echo "=== Rclone Mount Status ==="

    echo "Mount status:"
    for service_name in "${services[@]}"; do
        local service_path="$cloud_path/$service_name"
        if is_mounted "$service_path"; then
            echo "$service_name is MOUNTED at $service_path"
        else
            echo "$service_name is NOT MOUNTED"
        fi
    done

    echo ""
    echo "Rclone processes:"
    ps aux | grep "[r]clone mount" || echo " No rclone mount processes found"
}

# RUN MOUNT
# Takes the mount action, locks what it needs and calls it
run_mount() {
    case "${1:-}" in
    --start)
        lock_mount
        check_ipv4_interfaces
        check_internet || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no internet connection -abort"; exit 1; }
        mount_start || exit 1
        ;;
    --stop)
        lock_mount
        lock_sync
        mount_stop || exit 1
        ;;
    --restart)
        lock_mount
        lock_sync
        check_ipv4_interfaces
        check_internet || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no internet connection -abort"; exit 1; }
        mount_restart || exit 1
        ;;
    --status) mount_status ;;
    *)
        echo
        echo "Usage: $0 mount { --start | --stop | --restart | --status }"
        echo
        exit 1
        ;;
    esac
}

# ------------------------------------------------------------------------------
# SYNC
# ------------------------------------------------------------------------------

# Two-way sync between the local folders and the mounted cloud

# SYNC TRANSFER
# Copies one direction between a local folder and the mounted cloud
sync_transfer() {
    local direction="$1" service_name="$2" src="$3" dst="$4"
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Sync $direction $service_name"
    if sudo -u "$local_user" rclone sync "$src" "$dst" --update --modify-window 1h --skip-links --verbose --transfers 30 --checkers 8 --contimeout 60s --timeout 300s --retries 3 --low-level-retries 10 --stats 1s --stats-file-name-length 0 --log-file="$rclone_path/rsync.log"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Sync $direction $service_name completed"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: Sync $direction $service_name failed -alert"
        return 1
    fi
}

# SYNC RUN
# Syncs download and upload folders for every mounted remote
sync_run() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Run Sync"
    logger -t rclonemgr "Run Sync" || true
    local sync_failed=0

    for service_name in "${services[@]}"; do
        local service_path="$cloud_path/$service_name"
        if ! is_service_configured "$service_name"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: $service_name is not configured in rclone -skip"
            continue
        fi
        if ! is_mounted "$service_path"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: $service_name is not mounted -skip"
            continue
        fi

        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: $service_name is mounted"
        local folders_ready=1
        for subfolder in download upload; do
            sudo -u "$local_user" mkdir -p -- "$service_path/$subfolder" || folders_ready=0
            sudo -u "$local_user" mkdir -p -- "$sync_path/$service_name/$subfolder" || folders_ready=0
        done
        if (( ! folders_ready )); then
            echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: cannot prepare $service_name sync folders -alert"
            sync_failed=1
            continue
        fi

        sync_transfer "Download" "$service_name" "$service_path/download" "$sync_path/$service_name/download" || sync_failed=1
        sync_transfer "Upload" "$service_name" "$sync_path/$service_name/upload" "$service_path/upload" || sync_failed=1
    done

    return "$sync_failed"
}

# SYNC STATUS
# Prints, per remote, whether it is configured and whether it is mounted
sync_status() {
    echo "=== Rclone Sync Status ==="
    for service_name in "${services[@]}"; do
        if is_service_configured "$service_name"; then
            if is_mounted "$cloud_path/$service_name"; then
                echo "$service_name: configured, mounted"
            else
                echo "$service_name: configured, NOT mounted (sync will skip it)"
            fi
        else
            echo "$service_name: NOT configured in Rclone"
        fi
    done
}

# RUN SYNC
# Takes the sync action, locks what it needs and calls it
run_sync() {
    case "${1:-}" in
    --run)
        lock_sync
        check_ipv4_interfaces
        check_internet || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no internet connection -abort"; exit 1; }
        sync_run || {
            echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: sync finished with failures -alert"
            exit 1
        }
        ;;
    --status) sync_status ;;
    *)
        echo
        echo "Usage: $0 sync { --run | --status }"
        echo
        exit 1
        ;;
    esac
}

# ------------------------------------------------------------------------------
# MENU
# ------------------------------------------------------------------------------

# Interactive menu shown when the script runs without arguments

# SHOW MENU
# Lists the seven options and runs the one chosen
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
    1) run_mount --start ;;
    2) run_mount --stop ;;
    3) run_mount --restart ;;
    4) run_mount --status ;;
    5) run_sync --run ;;
    6) run_sync --status ;;
    7) ;;
    *) echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: invalid option -abort" >&2; exit 1 ;;
    esac
}

# ------------------------------------------------------------------------------
# ACTIONS
# ------------------------------------------------------------------------------

# Dispatch the requested mode and action to its function

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: rclonemgr start..."

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
    echo "Usage: $0 { mount { --start | --stop | --restart | --status } | sync { --run | --status } }"
    echo
    exit 1
    ;;
esac

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: rclonemgr done"

exit 0
