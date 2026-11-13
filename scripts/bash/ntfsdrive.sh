#!/bin/bash
# maravento.com
#
################################################################################
#
# Mount | Umount NTFS Disk Drive (HDD/SSD)
# FILE: ntfsdrive.sh
#
# DESCRIPTION: Mounts or unmounts an NTFS disk by label or UUID, owned by the
# local user. Asks for the identifier and the mount folder name.
#
# USAGE: sudo bash ntfsdrive.sh
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# root check
if [ "$(id -u)" != "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

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
for dep in ntfs-3g util-linux bsdextrautils; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep" 2>/dev/null)" != *"ok installed"* ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

list_drives() {
    echo "Connected Devices"
    lsblk -o NAME,LABEL,UUID,SIZE,FSTYPE | grep -i ntfs | column -t
    echo ""
}

mount_drive() {
    list_drives
    read -r -p "Enter the label or UUID of the disk to be mounted ('exit' to exit): " disk_id

    [ -z "$disk_id" ] || [ "$disk_id" == "exit" ] && return

    device_path=$(blkid -L "$disk_id" 2>/dev/null || blkid -U "$disk_id" 2>/dev/null)

    if [ -n "$device_path" ]; then
        disk_label=$(lsblk -no LABEL "$device_path" | tr -d ' /')
        [ -z "$disk_label" ] && disk_label=$(basename "$device_path")

        mount_point="/media/$local_user/$disk_label"

        if mountpoint -q "$mount_point" 2>/dev/null; then
            echo "Device is already mounted at $mount_point"
            return
        fi

        # Only a folder created by this run may be removed on failure.
        local created_dir=0
        [ -d "$mount_point" ] || created_dir=1
        if ! mkdir -p "$mount_point"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot create mount folder -abort" >&2
            return 1
        fi
        if ! chown "$local_user:$local_user" "$mount_point"; then
            (( created_dir )) && rmdir "$mount_point" 2>/dev/null
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot set mount folder owner -abort" >&2
            return 1
        fi

        if mount -o uid=$(id -u "$local_user"),gid=$(id -g "$local_user"),fmask=0022,dmask=0022,windows_names -t ntfs-3g "$device_path" "$mount_point"; then
            echo "Device mounted on $mount_point"
        else
            (( created_dir )) && rmdir "$mount_point" 2>/dev/null
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot mount device -abort" >&2
            return 1
        fi
    else
        echo "No disk found with LABEL/UUID '$disk_id'"
    fi
}

umount_drive() {
    mount_points=$(lsblk -nr -o MOUNTPOINT | grep -E "^/mnt|^/media")

    if [ -z "$mount_points" ]; then
        echo "There are no disks mounted in /mnt or /media"
        return
    fi

    echo "Mounted devices:"
    echo "$mount_points"
    echo ""

    read -r -p "Enter the name of the folder where the disk is mounted ('exit' to exit): " folder_name
    [ "$folder_name" == "exit" ] && return

    if [ -z "$folder_name" ] || [[ "$folder_name" == */* ]]; then
        echo "Invalid folder name"
        return
    fi

    mount_point=$(echo "$mount_points" | awk -F/ -v f="$folder_name" '$NF == f')

    if [[ "$mount_point" == *$'\n'* ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: more than one mount named $folder_name -abort" >&2
        return 1
    fi

    if [ -n "$mount_point" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Unmounting $mount_point..."
        if ! umount "$mount_point"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot unmount device -abort" >&2
            return 1
        fi
        echo "Device unmounted"
    else
        echo "No mounted disk found at '/$folder_name'"
    fi
}

echo "Do you want to mount or unmount an NTFS disk?"

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: ntfsdrive start..."

select choice in "Mount" "Unmount" "Exit"; do
    case $choice in
        "Mount") mount_drive || exit 1; break ;;
        "Unmount") umount_drive || exit 1; break ;;
        "Exit") break ;;
        *) echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: invalid option -retry" ;;
    esac
done

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: ntfsdrive done"
