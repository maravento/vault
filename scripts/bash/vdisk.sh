#!/bin/bash
# by maravento.com

# Virtual Hard Disk (VHD) image (.img) with loop or kpartx - Create and Mount | Umount
# https://www.maravento.com/2018/03/disco-virtual.html

echo "Virtual Hard Disk Start. Wait..."
printf "\n"

# checking root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# checking script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi

# check dependencies
pkgs='kpartx'
if apt-get install -qq $pkgs; then
    echo "OK"
else
    echo "Error installing $pkgs. Abort"
    exit
fi

# LOCAL USER (sudo user no root)
local_user=${SUDO_USER:-$(whoami)}

# CHANGE VALUES AND PATHS
## path to mount point folder (change it)
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
# if no mount point exists, create it
if [ ! -d $mountpoint ]; then
    mkdir -p $mountpoint
    chmod a+rwx -R $mountpoint
fi
# if no img folder exists, create it
if [ ! -d $myvhd ]; then
    mkdir -p $myvhd
    chmod a+rwx -R $myvhd
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
        echo "unknown option"
        ;;
    esac
}

# if no .img exists, create it
if [ ! -f $myimg ]; then create_img; fi

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
            mount -o loop,rw,sync $myimg $mountpoint
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
            kpartx -a -v $myimg
            for f in $(losetup --list | grep $myvhd | awk '{print $1}'); do mount $f $mountpoint; done
            chmod a+rwx -R $mountpoint
            echo "VHD-IMG Mount: $(date)" | tee -a /var/log/syslog
            ;;
        2)
            # umount .img
            echo "Umount VHD-IMG..."
            umount $mountpoint
            if [ -n "$(kpartx -d -v $myimg)" ]; then
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
