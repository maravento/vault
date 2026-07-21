#!/bin/bash
# maravento.com
#
################################################################################
#
# Rclone 2-Way Sync (Gdrive, PCloud, Dropbox, OneDrive, Mega...)
# https://www.maravento.com/2023/09/2-way-sync-con-rclone.html
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

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$SCRIPT_LOCK")
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

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

echo "Rclone Sync Starting. Wait..."
echo "Run Sync Script at $(date)" | tee -a /var/log/syslog

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
    _rclone_installer=$(mktemp /tmp/rclone_install.XXXXXX.sh)
    if ! curl -fsSL https://rclone.org/install.sh -o "$_rclone_installer"; then
        echo "Error downloading Rclone installer"
        rm -f "$_rclone_installer"
        exit 1
    fi
    bash "$_rclone_installer"
    rm -f "$_rclone_installer"
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
    echo "Missing dependencies not found in APT:"
    for u in $unavailable; do echo "   - $u"; done
    echo "Please install them manually or enable the required repositories."
    exit 1
fi
if [ -n "$missing" ]; then
    echo "Waiting for APT/DPKG locks to be released..."
    APT_LOCK_TIMEOUT=120
    APT_LOCK_ELAPSED=0
    APT_LOCK_FILES="/var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend"
    while lsof $APT_LOCK_FILES >/dev/null 2>&1; do
        if [ "$APT_LOCK_ELAPSED" -ge "$APT_LOCK_TIMEOUT" ]; then
            echo "APT/DPKG locks still held after ${APT_LOCK_TIMEOUT}s. Aborting."
            exit 1
        fi
        echo "   Locks held, waiting... (${APT_LOCK_ELAPSED}s)"
        sleep 5
        APT_LOCK_ELAPSED=$((APT_LOCK_ELAPSED + 5))
    done
    dpkg --configure -a
    echo "Installing: $missing"
    apt-get -qq update
    if ! apt-get -y install $missing; then
        echo "Error installing: $missing"
        exit 1
    fi
else
    echo "Dependencies OK"
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
    if sudo -u "$local_user" bash -c "rclone listremotes | grep -q '^${service_name}:\$'"; then
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
