#!/bin/bash
# maravento.com
#
# Rclone 2-Way Sync (Gdrive, PCloud, Dropbox, OneDrive, Mega...)
# https://www.maravento.com/2023/09/2-way-sync-con-rclone.html

echo "Rclone Sync Starting. Wait..."
echo "Run Sync Script at $(date)" | tee -a /var/log/syslog
printf "\n"

# check root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# check script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi

# check internet
if host www.google.com &>/dev/null; then
    true
else
    echo "Internet: Offline"
    exit 1
fi

# check SO
UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
if [[ "$UBUNTU_ID" != "ubuntu" || ( "$UBUNTU_VERSION" != "22.04" && "$UBUNTU_VERSION" != "24.04" ) ]]; then
    echo "Unsupported system. Use at your own risk"
    # exit 1
fi

# check dependencies
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

# check dependencies
pkgs='fuse3'
missing=$(for p in $pkgs; do dpkg -s "$p" &>/dev/null || echo "$p"; done)
unavailable=""
for p in $missing; do
    apt-cache show "$p" &>/dev/null || unavailable+=" $p"
done
if [ -n "$unavailable" ]; then
    echo "❌ Missing dependencies not found in APT:"
    for u in $unavailable; do echo "   - $u"; done
    echo "💡 Please install them manually or enable the required repositories."
    exit 1
fi
if [ -n "$missing" ]; then
    echo "🔧 Releasing APT/DKPG locks..."
    killall -q apt apt-get dpkg 2>/dev/null
    rm -f /var/lib/apt/lists/lock
    rm -f /var/cache/apt/archives/lock
    rm -f /var/lib/dpkg/lock
    rm -f /var/lib/dpkg/lock-frontend
    rm -rf /var/lib/apt/lists/*
    dpkg --configure -a
    echo "📦 Installing: $missing"
    apt-get -qq update
    if ! apt-get -y install $missing; then
        echo "❌ Error installing: $missing"
        exit 1
    fi
else
    echo "✅ Dependencies OK"
fi

# LOCAL USER
# Get real user (not root) - multiple fallback methods
local_user=$(logname 2>/dev/null || echo "$SUDO_USER")
# If not found or is root, try detecting active graphical user
if [ -z "$local_user" ] || [ "$local_user" = "root" ]; then
    local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}')
fi
# As a final fallback, take the first logged user
if [ -z "$local_user" ]; then
    local_user=$(who | head -1 | awk '{print $1}')
fi
# Clean possible spaces or line breaks
local_user=$(echo "$local_user" | xargs)

# VARIABLES
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
