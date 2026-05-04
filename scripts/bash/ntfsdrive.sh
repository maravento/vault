#!/bin/bash
# maravento.com
#
# Mount | Umount NTFS Disk Drive (HDD/SSD)

echo "Auto Mount/Unmount NTFS Starting. Wait..."
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

pkgs='ntfs-3g'
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

list_drives() {
    echo "Connected Devices"
    lsblk -o NAME,LABEL,UUID,SIZE,FSTYPE | grep -E "sd[b-z][0-9]?" | column -t
    echo ""
}

mount_drive() {
    list_drives
    read -p "Enter the LABEL or UUID of the disk to be mounted ('exit' to exit): " DISKID

    [ "$DISKID" == "exit" ] && echo "Exiting..." && return

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

    read -p "Enter the name of the folder where the disk is mounted ('exit' to exit): " FOLDER
    [ "$FOLDER" == "exit" ] && echo "Exiting..." && return

    if ! echo "$FOLDER" | grep -qE '^[a-zA-Z0-9_:@. -]+$'; then
        echo "Invalid folder name."
        return
    fi

    MOUNT_POINT=$(echo "$MOUNT_POINTS" | grep -F "/$FOLDER")

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
