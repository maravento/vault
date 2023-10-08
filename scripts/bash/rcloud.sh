#!/bin/bash
# by maravento.com

# Cloud Drive Mount (Gdrive, PCloud, Dropbox, OneDrive, Mega...)
# You can add any service supported by Rclone
# https://www.maravento.com/2023/09/2-way-sync-con-rclone.html

echo "Cloud Drive Mount Start. Wait..."
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
            exit 1
        fi
    done
fi

# checking dependencies
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
    echo "Rclone is already installed"
fi

### VARIABLES
# LOCAL USER (sudo user no root)
#local_user=${SUDO_USER:-$(whoami)}
local_user=$(who | head -1 | awk '{print $1;}')
# rclone config
config_file="/home/$local_user/.config/rclone/rclone.conf"
# local path
local_path="/home/$local_user/cloud"
if [ ! -d $local_path ]; then mkdir -p $local_path; fi &>/dev/null
# services name an path
dropbox_path="$local_path/dropbox"
dropbox_service="dropbox"
drive_path="$local_path/drive"
drive_service="drive"
mega_path="$local_path/mega"
mega_service="mega"
onedrive_path="$local_path/onedrive"
onedrive_service="onedrive"
pcloud_path="$local_path/pcloud"
pcloud_service="pcloud"

# log
rclonelog=$local_path/rclone.log

### CHECK INTERNET
internet_check_url="https://www.google.com"
if curl --output /dev/null --silent --head --fail "$internet_check_url"; then
    echo "online"
else
    echo "offline"
    exit 1
fi

# check service
check_service_existence() {
    local service_name="$1"
    local config_file="$2"
    if grep -q "\[$service_name\]" "$config_file"; then
        return 0  # service exist
    else
        return 1  # service does not exist
    fi
}

# check mount
check_mounted_folder() {
    local folder_path="$1"

    if mount | grep -q "$folder_path"; then
        return 0  # folder is mounted
    else
        return 1  # folder is not mounted
    fi
}

# function to mount the service
mount_service() {
    local service_name="$1"
    local service_path="$2"
    echo "mounting $service_name"
    sudo -u $local_user bash -c "rclone mount $service_name: $service_path --log-file $rclonelog --log-level INFO --vfs-cache-mode writes &"
    echo "$service_name mount"
}

### MOUNT DROPBOX
check_service_existence "$dropbox_service" "$config_file"
if [ $? -eq 0 ]; then
    check_mounted_folder "$dropbox_path"
    if [ $? -eq 0 ]; then
        echo "$dropbox_service is already mounted"
    else
        mount_service "$dropbox_service" "$dropbox_path"
    fi
else
    echo "$dropbox_service does not exist"
fi

### MOUNT DRIVE (Google Drive)
check_service_existence "$drive_service" "$config_file"
if [ $? -eq 0 ]; then
    check_mounted_folder "$drive_path"
    if [ $? -eq 0 ]; then
        echo "$drive_service is already mounted"
    else
        mount_service "$drive_service" "$drive_path"
    fi
else
    echo "$drive_service does not exist"
fi

### MOUNT MEGA (Currently does not accept 2FA)
check_service_existence "$mega_service" "$config_file"
if [ $? -eq 0 ]; then
    check_mounted_folder "$mega_path"
    if [ $? -eq 0 ]; then
        echo "$mega_service is already mounted"
    else
        mount_service "$mega_service" "$mega_path"
    fi
else
    echo "$mega_service does not exist"
fi

### MOUNT ONEDRIVE
check_service_existence "$onedrive_service" "$config_file"
if [ $? -eq 0 ]; then
    check_mounted_folder "$onedrive_path"
    if [ $? -eq 0 ]; then
        echo "$onedrive_service is already mounted"
    else
        mount_service "$onedrive_service" "$onedrive_path"
    fi
else
    echo "$onedrive_service does not exist"
fi

### MOUNT PCLOUD
check_service_existence "$pcloud_service" "$config_file"
if [ $? -eq 0 ]; then
    check_mounted_folder "$pcloud_path"
    if [ $? -eq 0 ]; then
        echo "$pcloud_service is already mounted"
    else
        mount_service "$pcloud_service" "$pcloud_path"
    fi
else
    echo "$pcloud_service does not exist"
fi

echo "Done"
