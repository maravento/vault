#!/bin/bash
# maravento.com
#
################################################################################
#
# Virtual Hard Disk (VHD) image (.img) with loop or kpartx - Create and Mount | Umount
# https://www.maravento.com/2018/03/disco-virtual.html
#
################################################################################

echo "Virtual Hard Disk Starting. Wait..."
printf "\n"

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

# LOCAL USER (multi-strategy detection with validation)
local_user=""
# 1. Local graphical session (:0)
local_user=$(who | awk '/\(:0\)/{print $1; exit}')
# 2. Parent process logname (works well with sudo)
[ -z "$local_user" ] && local_user=$(logname 2>/dev/null || true)
# 3. SUDO_USER variable (when run via sudo from terminal)
[ -z "$local_user" ] && local_user="${SUDO_USER:-}"
# 4. First active session user (SSH or other)
[ -z "$local_user" ] && local_user=$(who | awk 'NR==1{print $1}')
# 5. First valid home directory
[ -z "$local_user" ] && local_user=$(ls -l /home 2>/dev/null | awk '/^d/{print $3; exit}')
# Validate the user actually exists on the system
if [ -z "$local_user" ] || ! id "$local_user" &>/dev/null; then
    echo "ERROR: Cannot determine a valid local user"
    exit 1
fi
echo "Using local user: $local_user"

# check dependencies
pkgs='kpartx'
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
    pkill -x apt 2>/dev/null; pkill -x apt-get 2>/dev/null; pkill -x dpkg 2>/dev/null; true
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
    parted $myimg \
        mklabel $vptable \
        mkpart $ptype ntfs 2048s 100% \
        set 1 lba on \
        align-check optimal 1
    mkntfs -Q -v -F -L "$vlabel" $myimg
    ntfsresize -i -f -v $myimg
    ntfsresize --force --force --no-action $myimg
    ntfsresize --force --force $myimg
    fdisk -lu $myimg
}

# format fat32
function pfat32() {
    parted $myimg \
        mklabel $vptable \
        mkpart $ptype fat32 2048s 100% \
        set 1 lba on \
        align-check optimal 1
    mkfs.fat -F32 -v -I -n "$vlabel " $myimg
    fsck.fat -a -w -v $myimg
    fdisk -lu $myimg
}

# format ext4
function pext4() {
    parted $myimg \
        mklabel $vptable \
        mkpart $ptype 2048s 100%
    mkfs.ext4 -F -L "$vlabel" $myimg
    parted -s $myimg align-check optimal 1
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
            chmod a+rwx -R $mountpoint
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
                echo "❌ kpartx failed to map partitions for $myimg. Exiting."
                exit 1
            fi
            for f in $(losetup --list | grep "$myvhd" | awk '{print $1}'); do mount $f $mountpoint; done
            chmod a+rwx -R $mountpoint
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

# Menú de selección
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
