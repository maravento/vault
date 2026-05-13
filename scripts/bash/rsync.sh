#!/bin/bash
# maravento.com
#
################################################################################
#
# Rclone 2-Way Sync (Gdrive, PCloud, Dropbox, OneDrive, Mega...)
# https://www.maravento.com/2023/09/2-way-sync-con-rclone.html
#
################################################################################

echo "Rclone Sync Starting. Wait..."
echo "Run Sync Script at $(date)" | tee -a /var/log/syslog
printf "\n"

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

local_user=""
local_user=$(who | awk '/\(:0\)/{print $1; exit}')
[ -z "$local_user" ] && local_user=$(logname 2>/dev/null || true)
[ -z "$local_user" ] && local_user="${SUDO_USER:-}"
[ -z "$local_user" ] && local_user=$(who | awk 'NR==1{print $1}')
[ -z "$local_user" ] && local_user=$(ls -l /home 2>/dev/null | awk '/^d/{print $3; exit}')
if [ -z "$local_user" ] || ! id "$local_user" &>/dev/null; then
    echo "ERROR: Cannot determine a valid local user"
    exit 1
fi
echo "Using local user: $local_user"

if curl -s --head --max-time 10 https://www.google.com | grep -q "HTTP/"; then
    true
else
    echo "Internet: Offline"
    exit 1
fi

if [ -f /etc/os-release ]; then
    . /etc/os-release
    UBUNTU_ID=$(echo "${ID:-}" | tr '[:upper:]' '[:lower:]')
    UBUNTU_VERSION="${VERSION_ID:-}"
else
    UBUNTU_ID=""
    UBUNTU_VERSION=""
fi
if [[ "$UBUNTU_ID" != "ubuntu" || "$UBUNTU_VERSION" != "24.04" ]]; then
    echo "This script requires Ubuntu 24.04. Use at your own risk"
fi

if ! command -v rclone &>/dev/null; then
    echo "Installing Rclone..."
    curl https://rclone.org/install.sh | sudo bash
    if ! command -v rclone &>/dev/null; then
        echo "Error installing Rclone"
        exit 1
    fi
    echo "OK"
fi

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

local_path="/home/$local_user/sync"
cloud_path="/home/$local_user/cloud"
rclonelog="$local_path/rsync.log"

services=(
    "mega:$cloud_path/mega"
    "pcloud:$cloud_path/pcloud"
    "dropbox:$cloud_path/dropbox"
    "drive:$cloud_path/drive"
    "onedrive:$cloud_path/onedrive"
)

is_service_configured() {
    local service_name="$1"
    if sudo -u "$local_user" bash -c "rclone listremotes | grep -q '$service_name'"; then
        return 0
    else
        return 1
    fi
}

upload_script() {
    local service_name="$1"
    echo "Sync Upload $service_name"
    sudo -u "$local_user" bash -c "rclone sync '$local_path/$service_name/upload' '$cloud_path/$service_name/upload' --update --modify-window 1h --skip-links --verbose --transfers 30 --checkers 8 --contimeout 60s --timeout 300s --retries 3 --low-level-retries 10 --stats 1s --stats-file-name-length 0 --log-file='$rclonelog'"
    echo "OK"
}

download_script() {
    local service_name="$1"
    echo "Sync Download $service_name"
    sudo -u "$local_user" bash -c "rclone sync '$cloud_path/$service_name/download' '$local_path/$service_name/download' --update --modify-window 1h --skip-links --verbose --transfers 30 --checkers 8 --contimeout 60s --timeout 300s --retries 3 --low-level-retries 10 --stats 1s --stats-file-name-length 0 --log-file='$rclonelog'"
    echo "OK"
}

for service_info in "${services[@]}"; do
    IFS=':' read -r service_name service_path <<< "$service_info"
    if is_service_configured "$service_name"; then
        if mount | grep -q "$service_path"; then
            echo "$service_name is mounted."
            subfolders=("download" "upload")
            for subfolder in "${subfolders[@]}"; do
                sudo -u "$local_user" bash -c "mkdir -p '$service_path/$subfolder'"
                sudo -u "$local_user" bash -c "mkdir -p '$local_path/$service_name/$subfolder'"
            done
            download_script "$service_name"
            upload_script "$service_name"
        else
            echo "$service_name is not mounted."
        fi
    else
        echo "$service_name is not configured in Rclone. Skipping..."
    fi
done

echo "Done"
