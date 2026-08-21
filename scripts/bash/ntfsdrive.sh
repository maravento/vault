#!/bin/bash
# maravento.com
#
################################################################################
#
# Mount | Umount NTFS Disk Drive (HDD/SSD)
#
################################################################################

set -uo pipefail

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
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

echo "Auto Mount/Unmount NTFS Starting. Wait..."

# DEPENDENCIES
for dep in ntfs-3g util-linux bsdextrautils; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "ERROR: Required dependency '$dep' is not installed." >&2
        exit 1
    fi
done

list_drives() {
    echo "Connected Devices"
    lsblk -o NAME,LABEL,UUID,SIZE,FSTYPE | grep -i ntfs | column -t
    echo ""
}

mount_drive() {
    list_drives
    read -r -p "Enter the LABEL or UUID of the disk to be mounted ('exit' to exit): " DISKID

    [ -z "$DISKID" ] || [ "$DISKID" == "exit" ] && echo "Exiting..." && return

    DEVICE=$(lsblk -rn -o NAME,LABEL,UUID | awk -v id="$DISKID" '$2 == id || $3 == id {print "/dev/" $1}')

    if [ -n "$DEVICE" ]; then
        LABEL=$(lsblk -no LABEL "$DEVICE" | tr -d ' ')
        [ -z "$LABEL" ] && LABEL=$(basename "$DEVICE")

        MOUNT_POINT="/media/$local_user/$LABEL"

        if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
            echo "Device is already mounted at $MOUNT_POINT."
            return
        fi

        mkdir -p "$MOUNT_POINT"
        chown "$local_user:$local_user" "$MOUNT_POINT"

        if mount -o uid=$(id -u "$local_user"),gid=$(id -g "$local_user"),fmask=0022,dmask=0022,windows_names -t ntfs-3g "$DEVICE" "$MOUNT_POINT"; then
            echo "Device mounted on $MOUNT_POINT."
        else
            echo "Error mounting device"
            rmdir "$MOUNT_POINT" 2>/dev/null || true
        fi
    else
        echo "No disk found with LABEL/UUID '$DISKID'."
    fi
}

umount_drive() {
    MOUNT_POINTS=$(lsblk -nr -o MOUNTPOINT | grep -E "^/mnt|^/media")

    if [ -z "$MOUNT_POINTS" ]; then
        echo "There are no disks mounted in /mnt or /media"
        return
    fi

    echo "Mounted devices:"
    echo "$MOUNT_POINTS"
    echo ""

    read -r -p "Enter the name of the folder where the disk is mounted ('exit' to exit): " FOLDER
    [ "$FOLDER" == "exit" ] && echo "Exiting..." && return

    if ! echo "$FOLDER" | grep -qE '^[a-zA-Z0-9_:@. -]+$'; then
        echo "Invalid folder name."
        return
    fi

    MOUNT_POINT=$(echo "$MOUNT_POINTS" | awk -F/ -v f="$FOLDER" '$NF == f')

    if [ -n "$MOUNT_POINT" ]; then
        echo "Unmounting $MOUNT_POINT..."
        umount "$MOUNT_POINT" && echo "Device unmounted" || echo "Error unmounting device"
    else
        echo "No mounted disk found at '/$FOLDER'."
    fi
}

echo "Do you want to mount or unmount an NTFS disk?"
select choice in "Mount" "Unmount" "Exit"; do
    case $choice in
        "Mount") mount_drive; break ;;
        "Unmount") umount_drive; break ;;
        "Exit") echo "Exiting..."; exit 0 ;;
        *) echo "Invalid option, please try again" ;;
    esac
done
