#!/bin/bash

# Mount | Umount NTFS Disk Drive (HDD/SSD)

# Usage:
# sudo ./ntfsdrive.sh

# checking root
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

echo "Auto Mount/Unmount NTFS. Please wait..."
printf "\n"

### VARIABLES
local_user=$(who | head -1 | awk '{print $1;}')  # Local user (non-root)

# Function to list connected USB devices
list_drives() {
  echo "Connected USB disks:"
  lsblk -o NAME,LABEL,SIZE | grep -E "sd[b-z][0-9]?"
}

# Function to mount the drive
mount_drive() {
  list_drives

  read -p "Enter the label of the disk to mount or 'exit' to finish: " DISKLABEL

  if [ "$DISKLABEL" == "exit" ]; then
    echo "Exiting..."
    return
  fi

  # Find the device by label
  USBDISK=$(lsblk -o LABEL,NAME | grep -iw "$DISKLABEL" | awk '{print $2}' | tr -d '└─')

  if [ -n "$USBDISK" ]; then
    DEVICE="/dev/$USBDISK"
    echo "Trying to mount the device $DEVICE..."

    read -p "Enter folder name to mount the drive: " FOLDER
    MOUNT_POINT="/home/$local_user/$FOLDER"

    if [ ! -d "$MOUNT_POINT" ]; then
        sudo -u "$local_user" mkdir -p "$MOUNT_POINT"
        echo "Folder created at: $MOUNT_POINT"
    fi

    # Mount the device
    mount -t ntfs-3g "$DEVICE" "$MOUNT_POINT"

    if [ $? -eq 0 ]; then
      echo "Device successfully mounted at $MOUNT_POINT."
    else
      echo "Error mounting the device. Please check the device and try again."
    fi
  else
    echo "No disk with the label '$DISKLABEL' was found."
  fi
}

# Function to unmount the drive
umount_drive() {
  # List currently mounted drives for clarity
  df -h | grep "/home/$local_user"

  read -p "Enter the label of the disk to unmount or 'exit' to finish: " DISKLABEL

  if [ "$DISKLABEL" == "exit" ]; then
    echo "Exiting..."
    return
  fi

  # Find the mount point
  MOUNT_POINT=$(df -h | grep "/home/$local_user" | grep "$DISKLABEL" | awk '{print $6}')

  if [ -n "$MOUNT_POINT" ]; then
    echo "Unmounting device mounted at $MOUNT_POINT..."
    umount "$MOUNT_POINT"

    if [ $? -eq 0 ]; then
      echo "Device successfully unmounted."
    else
      echo "Error unmounting the device. Please try again."
    fi
  else
    echo "No mounted disk with the label '$DISKLABEL' found."
  fi
}

# Main script logic
echo "Do you want to mount or unmount an NTFS drive?"
select choice in "Mount" "Unmount" "Exit"; do
  case $choice in
    "Mount")
      mount_drive
      break
      ;;
    "Unmount")
      umount_drive
      break
      ;;
    "Exit")
      echo "Exiting..."
      break
      ;;
    *)
      echo "Invalid choice, please try again."
      ;;
  esac
done

