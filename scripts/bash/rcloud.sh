#!/bin/bash
# by maravento.com

# Rclone Cloud (Gdrive, PCloud, Dropbox, OneDrive, Mega...)
# https://www.maravento.com/2023/09/2-way-sync-con-rclone.html

# Usage:
# sudo ./rclone.sh start | stop | restart | status

echo "Rclone Cloud Start. Wait..."

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
            exit 1
        fi
    done
fi

# check internet (eesential)
if host www.google.com &>/dev/null; then
    true
else
    echo "Internet: Offline"
    exit 1
fi

# checking dependencies (optional)
if ! command -v rclone &>/dev/null; then
    echo "Installing Rclone..."
    sudo -v
    curl https://rclone.org/install.sh | sudo bash
    if ! command -v rclone &>/dev/null; then
        echo "Error installing Rclone"
        exit 1
    fi
    echo "OK"
else
    true
fi

# checking dependencies (optional)
pkg='fuse3'
if apt-get -qq install $pkg; then
    true
else
    echo "Error installing $pkg. Abort"
    exit
fi

# VARIABLES
local_user=$(who | head -1 | awk '{print $1;}')
local_path="/home/$local_user/cloud"
lock_file="/tmp/cloud_drive_mount.lock"
rclonelog="$local_path/rclone.log"

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

# if local_path or service_path does not exist, create them
for service_info in "${services[@]}"; do
    IFS=':' read -r service_name service_path <<<"$service_info"
    if [ ! -d "$service_path" ]; then
        sudo -u $local_user bash -c "mkdir -p $service_path"
    fi
done

# start script
start_script() {
    if [ -e "$lock_file" ]; then
        echo "Script is already running."
        exit 1
    fi
    touch "$lock_file"

    # mount
    for service_info in "${services[@]}"; do
        IFS=':' read -r service_name service_path <<<"$service_info"
        echo "Mounting $service_name"
        sudo -u $local_user bash -c "rclone mount $service_name: $service_path --log-file $rclonelog --log-level $loglevel --vfs-cache-mode writes &"
        echo "$service_name mounted"
    done

    echo "Script started."
}

# stop script
stop_script() {
    if [ ! -e "$lock_file" ]; then
        echo "Script is not running."
        exit 1
    fi

    # umount
    for service_info in "${services[@]}"; do
        IFS=':' read -r service_name service_path <<<"$service_info"
        if mount | grep -q "$service_path"; then
            fusermount -uz "$service_path"
            # alternative
            #umount "$service_path" 2>/dev/null
            rm -f "$lock_file"
            echo "$service_name unmounted"
        else
            echo "$service_name is not mounted."
        fi
    done
}

# restart script
restart_script() {
    stop_script
    echo "Sleeping..."
    sleep 1
    start_script
}

# status script
status_script() {
    if [ -e "$lock_file" ]; then
        echo "Script is running."
    else
        echo "Script is not running."
    fi

    # status
    for service_info in "${services[@]}"; do
        IFS=':' read -r service_name service_path <<<"$service_info"
        if mount | grep -q "$service_path"; then
            echo "$service_name is mounted."
        else
            echo "$service_name is not mounted."
        fi
    done
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
    stop_script
    echo "Sleeping..."
    sleep 5
    start_script
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
