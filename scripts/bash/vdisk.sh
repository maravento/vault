#!/bin/bash
# maravento.com
#
################################################################################
#
# Virtual Hard Disk (VHD) image (.img) with loop or kpartx - Create and Mount | Umount
# https://www.maravento.com/2018/03/disco-virtual.html
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

echo "Virtual Hard Disk Starting. Wait..."

# check dependencies
pkgs='kpartx pv'
missing=$(for p in $pkgs; do dpkg -s "$p" &>/dev/null || echo "$p"; done)
unavailable=""
for p in $missing; do
    apt-cache show "$p" &>/dev/null || unavailable+=" $p"
done
if [ -n "$unavailable" ]; then
    echo "Missing dependencies not found in APT:"
    for u in $unavailable; do echo " - $u"; done
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
        echo "Locks held, waiting... (${APT_LOCK_ELAPSED}s)"
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

### VARIABLES
# CHANGE VALUES AND PATHS
# path to mount point folder (change it)
mountpoint="/home/$local_user/vdisk"
# path to .img folder (change it)
myvhd="/home/$local_user/img"
# path to .img file (e.g: 4GB_HDD.img) (change it)
myimg="$myvhd/1GB_HDD.img"
# choose type: msdos, gpt
vptable="msdos"
# Large .img file in MB/MiB (e.g: 4096 = 4GB) (change it)
vsize="1024"
# disk label (change it)
vlabel="mydisk"
# 1M or 1k/2k/4k/16k
vbs="1M"
# partition: primary/logical/extended
ptype="primary"

### mount
# if no mount point exists, create it
if [ ! -d "$mountpoint" ]; then
    mkdir -p "$mountpoint"
    chown "$local_user": "$mountpoint"
    chmod 750 "$mountpoint"
fi
# if no img folder exists, create it
if [ ! -d "$myvhd" ]; then
    mkdir -p "$myvhd"
    chown "$local_user": "$myvhd"
    chmod 750 "$myvhd"
fi

# format ntfs
function pntfs() {
    mkntfs -Q -v -F -L "$vlabel" $myimg
    ntfsresize -i -f -v $myimg
    ntfsresize --force --force --no-action $myimg
    ntfsresize --force --force $myimg
    fdisk -lu $myimg
}

# format fat32
function pfat32() {
    mkfs.fat -F32 -v -I -n "$vlabel" $myimg
    fsck.fat -a -w -v $myimg
    fdisk -lu $myimg
}

# format ext4
function pext4() {
    mkfs.ext4 -F -L "$vlabel" $myimg
    e2fsck -f -y -v -C 0 $myimg
    resize2fs -p $myimg
    fdisk -lu $myimg
}

# create and format disk .img
function create_img() {
    # create img
    dd if=/dev/zero | pv | dd of=$myimg iflag=fullblock bs=$vbs count=$vsize && sync
    printf "\n"
    read -p "Enter File System (e.g. ntfs, fat32, ext4): " pset
    if [ -z "$pset" ]; then
        echo "No file system selected. Exiting."
        exit 1
    fi
    case $pset in
    "ntfs")
        pntfs
        ;;
    "fat32")
        pfat32
        ;;
    "ext4")
        pext4
        ;;
    *)
        echo "Unknown file system: $pset. Exiting."
        exit 1
        ;;
    esac
}

# if no .img exists, create it
if [ ! -f "$myimg" ]; then create_img; fi

function mount_img() {
    if [ $# -eq 0 ]; then
        echo "Select an operation loop: "
        echo "1. Mount"
        echo "2. Unmount"
        read -p "Enter your choice (1 or 2): " choice

        case "$choice" in
        1)
            # mount .img
            echo "Mount VHD-IMG..."
            mount -o loop,rw,sync "$myimg" "$mountpoint"
            chown -R "$local_user": "$mountpoint"
            chmod 750 "$mountpoint"
            echo "VHD-IMG Mount: $(date)" | tee -a /var/log/syslog
            ;;
        2)
            # umount .img
            echo "Umount VHD-IMG..."
            umount "$mountpoint"
            echo "VHD-IMG Umount: $(date)" | tee -a /var/log/syslog
            ;;
        *)
            echo "Invalid choice. Exiting."
            ;;
        esac
    else
        echo "Usage: $0"
    fi
}

function mount_img_kpartx() {
    if [ $# -eq 0 ]; then
        echo "Select an operation kpartx: "
        echo "1. Mount"
        echo "2. Umount"
        read -p "Enter your choice (1 or 2): " choice

        case "$choice" in
        1)
            # mount .img
            echo "Mount VHD-IMG..."
            if ! kpartx -a -v "$myimg"; then
                echo "kpartx failed to map partitions for $myimg. Exiting."
                exit 1
            fi
            for f in $(losetup --list | grep "$myvhd" | awk '{print $1}'); do mount $f $mountpoint; done
            chown -R "$local_user": "$mountpoint"
            chmod 750 "$mountpoint"
            echo "VHD-IMG Mount: $(date)" | tee -a /var/log/syslog
            ;;
        2)
            # umount .img
            echo "Umount VHD-IMG..."
            umount "$mountpoint"
            if [ -n "$(kpartx -d -v "$myimg")" ]; then
                echo "VHD-IMG Umount: $(date)" | tee -a /var/log/syslog
            else
                echo "No Mounted Image"
            fi
            ;;
        *)
            echo "Invalid choice. Exiting."
            ;;
        esac
    else
        echo "Usage: $0"
    fi
}

# Selection menu
printf "\n"
echo "Select a method for VHD image:"
echo "1. With loop"
echo "2. With kpartx"
read -p "Choose an option (1 or 2): " choice

case "$choice" in
1)
    mount_img
    ;;
2)
    mount_img_kpartx
    ;;
*)
    echo "Invalid option. Exiting"
    ;;
esac
