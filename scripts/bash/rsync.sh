#!/bin/bash
# maravento.com

# Rclone 2-Way Sync (Gdrive, PCloud, Dropbox, OneDrive, Mega...)
# https://www.maravento.com/2023/09/2-way-sync-con-rclone.html

echo "Rclone Sync Starting. Wait..."
echo "Run Sync Script at $(date)" | tee -a /var/log/syslog
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

# check internet (essential)
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
# Local user
local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}' || who | head -1 | awk '{print $1}')
# Local path
local_path="/home/$local_user/sync"
# cloud path
cloud_path="/home/$local_user/cloud"
# Rclone log
rclonelog="$local_path/rsync.log"

# add any services supported by Rclone with its route
services=(
    # Mega
    "mega:$cloud_path/mega"
    # Pcloud
    "pcloud:$cloud_path/pcloud"
    # Dropbox
    "dropbox:$cloud_path/dropbox"
    # Google Drive
    "drive:$cloud_path/drive"
    # MS OneDrive
    "onedrive:$cloud_path/onedrive"
    # Add more services here as needed
)

# Function to check if a service is configured
is_service_configured() {
    local service_name="$1"
    # Check if the service is configured using rclone listremotes
    if sudo -u $local_user bash -c "rclone listremotes | grep -q $service_name"; then
        return 0 # Service is configured
    else
        return 1 # Service is not configured
    fi
}

for service_info in "${services[@]}"; do
    IFS=':' read -r service_name service_path <<<"$service_info"
    if is_service_configured "$service_name"; then
        true
    else
        false
    fi
done

# Function to check if a service is mounted
is_service_mounted() {
    local service_name="$1"
    local service_mount_point="$cloud_path/$service_name"

    # Verificar si el punto de montaje del servicio existe
    if [ -d "$service_mount_point" ]; then
        return 0 # Service is mounted
    else
        return 1 # Service is not mounted
    fi
}

upload_script() {
    local service_name="$1"
    echo "Sync Upload $service_name"
    sudo -u $local_user bash -c "rclone sync $local_path/$service_name/upload $cloud_path/$service_name/upload --update --modify-window 1h --skip-links --verbose --transfers 30 --checkers 8 --contimeout 60s --timeout 300s --retries 3 --low-level-retries 10 --stats 1s --stats-file-name-length 0 --log-file=$rclonelog"
    echo "OK"
}

download_script() {
    local service_name="$1"
    echo "Sync Download $service_name"
    sudo -u $local_user bash -c "rclone sync $cloud_path/$service_name/download $local_path/$service_name/download --update --modify-window 1h --skip-links --verbose --transfers 30 --checkers 8 --contimeout 60s --timeout 300s --retries 3 --low-level-retries 10 --stats 1s --stats-file-name-length 0 --log-file=$rclonelog"
    echo "OK"
}

# Iterate through services to check if they are mounted and create local directories
for service_info in "${services[@]}"; do
    IFS=':' read -r service_name service_path <<< "$service_info"
    if is_service_configured "$service_name"; then
        if mount | grep -q "$service_path"; then
            echo "$service_name is mounted."
            subfolders=("download" "upload")
            for subfolder in "${subfolders[@]}"; do
                # Create the subfolders in the cloud service
                sudo -u $local_user bash -c "mkdir -p $service_path/$subfolder"
                # Create the subfolders locally
                sudo -u $local_user bash -c "mkdir -p $local_path/$service_name/$subfolder"
            done
            download_script $service_name
            upload_script $service_name
        else
            echo "$service_name is not mounted."
        fi
    else
        echo "$service_name is not configured in Rclone. Skipping..."
    fi
done

echo "Done"
