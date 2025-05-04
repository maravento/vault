#!/bin/bash
# maravento.com

# Mount | Umount NTFS Disk Drive (HDD/SSD)

echo "Auto Mount/Unmount NTFS Starting. Wait..."
printf "\n"

# Check if the script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# Prevent multiple instances of the script from running
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit 1
        fi
    done
fi

### VARIABLES
local_user=$(who | head -1 | awk '{print $1;}')  # Local user (non-root)

# list connected USB devices (UUID/Label)
list_drives() {
    echo "Connected Devices"
    lsblk -o NAME,LABEL,UUID,SIZE,FSTYPE | grep -E "sd[b-z][0-9]?" | column -t
    echo ""
}

mount_drive() {
    local_user=$(who | head -1 | awk '{print $1;}')

    list_drives
    read -p "Enter the LABEL or UUID of the disk to be mounted ('exit' to exit): " DISKID

    [ "$DISKID" == "exit" ] && echo "Exiting..." && return

    DEVICE=$(lsblk -rn -o NAME,LABEL,UUID | awk -v id="$DISKID" '$2 == id || $3 == id {print "/dev/" $1}')

    if [ -n "$DEVICE" ]; then
        LABEL=$(lsblk -no LABEL "$DEVICE" | tr -d ' ')
        [ -z "$LABEL" ] && LABEL=$(basename "$DEVICE")

        MOUNT_POINT="/media/$local_user/$LABEL"
        mkdir -p "$MOUNT_POINT"
        chown "$local_user:$local_user" "$MOUNT_POINT"  # Ensures the user has access

        # Mount with user permissions and visibility on the desktop
        mount -o uid=$(id -u "$local_user"),gid=$(id -g "$local_user"),fmask=0022,dmask=0022,windows_names -t ntfs-3g "$DEVICE" "$MOUNT_POINT"

        if [ $? -eq 0 ]; then
            echo "Device mounted on $MOUNT_POINT."
        else
            echo "Error mounting device"
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

    read -p "Enter the name of the folder where the disk is mounted ('exit' to exit): " FOLDER
    [ "$FOLDER" == "exit" ] && echo "Exiting..." && return

    MOUNT_POINT=$(echo "$MOUNT_POINTS" | grep "/$FOLDER$")

    if [ -n "$MOUNT_POINT" ]; then
        echo "Unmounting $MOUNT_POINT..."
        umount "$MOUNT_POINT" && echo "Device unmounted" || echo "Error unmounting device"
    else
        echo "No mounted disk found at '/$FOLDER'."
    fi
}


# Menú principal
echo "Do you want to mount or unmount an NTFS disk?"
select choice in "Mount" "Unmount" "Exit"; do
    case $choice in
        "Mount") mount_drive; break ;;
        "Unmount") umount_drive; break ;;
        "Exit") echo "Exiting..."; exit 0 ;;
        *) echo "Invalid option, please try again" ;;
    esac
done

