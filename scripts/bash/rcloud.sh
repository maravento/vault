#!/bin/bash
# by maravento.com

# Rclone Cloud (Gdrive, PCloud, Dropbox, OneDrive, Mega...)
# https://www.maravento.com/2023/09/2-way-sync-con-rclone.html

# Usage:
# sudo ./rclone.sh start | stop | restart | status

# LOG FILE para debugging
SCRIPT_LOG="/var/log/rcloud-startup.log"
exec 1> >(tee -a "$SCRIPT_LOG")
exec 2>&1

echo "================================================"
echo "$(date) - Rclone Cloud Start"
echo "User: $(whoami)"
echo "================================================"

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

# LOCAL USER
local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}' || who | head -1 | awk '{print $1}')
# Fallback
if [ -z "$local_user" ]; then
    local_user=$(ls -l /home | grep '^d' | head -1 | awk '{print $3}')
    if [ -z "$local_user" ]; then
        echo "ERROR: Cannot determine local user"
        exit 1
    fi
    echo "Using fallback user: $local_user"
fi

# check internet with retry (essential for @reboot)
echo "Checking internet connection..."
max_attempts=24  # 2 minutos máximo
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if timeout 3 host www.google.com &>/dev/null; then
        echo "Internet: Online (attempt $((attempt + 1)))"
        break
    else
        attempt=$((attempt + 1))
        if [ $attempt -eq $max_attempts ]; then
            echo "ERROR: Internet offline after $((max_attempts * 5)) seconds"
            exit 1
        fi
        echo "Waiting for internet... attempt $attempt/$max_attempts"
        sleep 5
    fi
done

# checking dependencies
if ! command -v rclone &>/dev/null; then
    echo "Installing Rclone..."
    curl https://rclone.org/install.sh | bash
    if ! command -v rclone &>/dev/null; then
        echo "ERROR: Failed to install Rclone"
        exit 1
    fi
    echo "Rclone installed successfully"
fi

# checking fuse3
pkg='fuse3'
if ! dpkg -l | grep -q "^ii.*$pkg"; then
    echo "Installing $pkg..."
    if ! apt-get -qq install -y $pkg; then
        echo "ERROR: Failed to install $pkg"
        exit 1
    fi
fi

# VARIABLES
local_path="/home/$local_user/cloud"
rclonelog="$local_path/rclone.log"
mount_lock="/tmp/cloud_drive_mount.lock"

# Log Level (INFO, DEBUG, NOTICE, ERROR)
loglevel="DEBUG"

# add any services supported by Rclone with its route
services=(
    # Mega
    "mega:$local_path/mega"
    # Pcloud
    "pcloud:$local_path/pcloud"
    # Dropbox
    "dropbox:$local_path/dropbox"
    # Google Drive
    "drive:$local_path/drive"
    # MS OneDrive
    "onedrive:$local_path/onedrive"
    # Add more services here as needed
)

# Create directories if they don't exist
for service_info in "${services[@]}"; do
    IFS=':' read -r service_name service_path <<<"$service_info"
    if [ ! -d "$service_path" ]; then
        echo "Creating directory: $service_path"
        sudo -u "$local_user" mkdir -p "$service_path"
    fi
done

# start script
start_script() {
    if [ -e "$mount_lock" ]; then
        echo "WARNING: Lock file exists, script may already be running"
        exit 1
    fi
    touch "$mount_lock"

    # mount
    for service_info in "${services[@]}"; do
        IFS=':' read -r service_name service_path <<<"$service_info"
        echo "Mounting $service_name to $service_path"
        
        # check rclone for service
        if ! sudo -u "$local_user" rclone listremotes | grep -q "^${service_name}:$"; then
            echo "ERROR: Rclone remote '$service_name' not configured"
            continue
        fi
        
        # mount with nohup
        sudo -u "$local_user" nohup rclone mount "$service_name:" "$service_path" \
            --log-file "$rclonelog" \
            --log-level "$loglevel" \
            --vfs-cache-mode writes \
            --daemon \
            >/dev/null 2>&1 &
        
        sleep 2
        
        # check mount
        if mount | grep -q "$service_path"; then
            echo "SUCCESS: $service_name mounted"
        else
            echo "WARNING: $service_name may not be mounted correctly"
        fi
    done

    echo "Script started successfully"
}

# stop script
stop_script() {
    if [ ! -e "$mount_lock" ]; then
        echo "WARNING: Script is not running (no lock file)"
    fi

    # umount
    for service_info in "${services[@]}"; do
        IFS=':' read -r service_name service_path <<<"$service_info"
        if mount | grep -q "$service_path"; then
            echo "Unmounting $service_name"
            fusermount -uz "$service_path"
            echo "$service_name unmounted"
        else
            echo "$service_name is not mounted"
        fi
    done
    
    # clean
    rm -f "$mount_lock"
    echo "Script stopped"
}

# restart script
restart_script() {
    echo "Restarting..."
    stop_script
    sleep 3
    start_script
}

# status script
status_script() {
    echo "=== Rclone Cloud Status ==="
    
    if [ -e "$mount_lock" ]; then
        echo "Lock file: EXISTS"
    else
        echo "Lock file: NOT FOUND"
    fi

    echo ""
    echo "Mount status:"
    for service_info in "${services[@]}"; do
        IFS=':' read -r service_name service_path <<<"$service_info"
        if mount | grep -q "$service_path"; then
            echo "  ✓ $service_name is MOUNTED at $service_path"
        else
            echo "  ✗ $service_name is NOT MOUNTED"
        fi
    done
    
    echo ""
    echo "Rclone processes:"
    ps aux | grep "[r]clone mount" || echo "  No rclone mount processes found"
}

# additional commands (start, stop, restart, status)
case "$1" in
'start')
    start_script
    ;;
'stop')
    stop_script
    ;;
'restart')
    restart_script
    ;;
'status')
    status_script
    ;;
*)
    echo
    echo "Usage: $0 { start | stop | restart | status }"
    echo
    exit 1
    ;;
esac

exit 0
