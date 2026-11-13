#!/bin/bash
# maravento.com
#
################################################################################
#
# Virtual Hard Disk (VHD) image (.img) with loop or kpartx
# FILE: vdisk.sh
#
# DESCRIPTION: Creates a VHD image file, then mounts or unmounts it through a
# loop device or kpartx. Asks for the file system on creation.
#
# USAGE: sudo bash vdisk.sh
#
# LOG: system logger (destination set by system configuration)
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

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock") || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot open $(basename "$script_lock") -abort" >&2
    exit 1
}
exec 200>"$script_lock"
if ! flock -n 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: script $(basename "$0") is already running -abort" >&2
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
for dep in kpartx dmsetup pv ntfs-3g dosfstools e2fsprogs util-linux bsdutils coreutils; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep" 2>/dev/null)" != *"ok installed"* ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

# Declare the configuration values used by this script
# CHANGE VALUES AND PATHS
# path to mount point folder (change it)
mountpoint="/home/$local_user/vdisk"
# path to .img folder (change it)
myvhd="/home/$local_user/img"
# path to .img file (e.g: 4GB_HDD.img) (change it)
myimg="$myvhd/1GB_HDD.img"
# Large .img file in MB/MiB (e.g: 4096 = 4GB) (change it)
vsize="1024"
# disk label (change it)
vlabel="mydisk"
# 1M or 1k/2k/4k/16k
vbs="1M"

# mount
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

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

# format ntfs
pntfs() {
    mkntfs -Q -v -F -L "$vlabel" "$1" &&
        ntfsresize -i -f -v "$1" &&
        ntfsresize --force --force --no-action "$1" &&
        ntfsresize --force --force "$1" &&
        fdisk -lu "$1"
}

# format fat32
pfat32() {
    mkfs.fat -F32 -v -I -n "$vlabel" "$1" &&
        fsck.fat -a -w -v "$1" &&
        fdisk -lu "$1"
}

# format ext4
pext4() {
    mkfs.ext4 -F -L "$vlabel" "$1" || return 1
    # e2fsck: 0 is clean and 1 is errors corrected; anything else is a failure
    e2fsck -f -y -v -C 0 "$1"
    [ "$?" -le 1 ] || return 1
    resize2fs -p "$1" &&
        fdisk -lu "$1"
}

# aborts the image creation; removes only this run's temporary file
create_fail() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: $1 -abort" >&2
    exit 1
}

# create and format disk .img in a temporary file, then publish it without overwriting
create_img() {
    local pset formatter
    read -r -p "Enter File System (e.g. ntfs, fat32, ext4): " pset
    case "$pset" in
    "")
        create_fail "no file system selected"
        ;;
    ntfs)
        formatter=pntfs
        ;;
    fat32)
        formatter=pfat32
        ;;
    ext4)
        formatter=pext4
        ;;
    *)
        create_fail "unknown file system: $pset"
        ;;
    esac

    img_tmp=$(mktemp "$myimg.XXXXXX") || create_fail "cannot create VHD-IMG temporary file"
    trap 'rm -f -- "$img_tmp"' EXIT
    trap 'exit 1' INT TERM

    # the first dd ends by SIGPIPE (141) once the last dd has its blocks
    dd if=/dev/zero | pv | dd of="$img_tmp" iflag=fullblock bs=$vbs count=$vsize
    local pipe_rc=("${PIPESTATUS[@]}")
    if [[ ! "${pipe_rc[0]}" =~ ^(0|141)$ || ! "${pipe_rc[1]}" =~ ^(0|141)$ || "${pipe_rc[2]}" -ne 0 ]]; then
        create_fail "cannot write VHD-IMG, rc=${pipe_rc[*]}"
    fi
    sync || create_fail "cannot sync VHD-IMG"
    printf "\n"
    "$formatter" "$img_tmp" || create_fail "cannot format VHD-IMG as $pset"
    chmod "$(printf '%o' "$((0666 & ~0$(umask)))")" "$img_tmp" || create_fail "cannot set VHD-IMG mode"

    # ln fails if the destination appeared meanwhile, and never overwrites it
    if ! ln -T -- "$img_tmp" "$myimg" 2>/dev/null; then
        [ ! -e "$myimg" ] || create_fail "VHD-IMG already exists, not overwritten"
        create_fail "cannot publish VHD-IMG"
    fi
    rm -f -- "$img_tmp"
    trap - EXIT INT TERM
}

# removes only the kpartx resources that this run created
kpartx_cleanup() {
    local map before
    if [ "${#loops_before[@]}" -eq 0 ]; then
        kpartx -d "$myimg" >/dev/null || return 1
        return 0
    fi
    for map in "${maps_after[@]}"; do
        for before in "${maps_before[@]}"; do
            [ "$map" = "$before" ] && continue 2
        done
        dmsetup remove "$map" || return 1
    done
}

# aborts the kpartx mount before mounting anything
kpartx_abort() {
    kpartx_cleanup || echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: VHD-IMG mappings not removed -alert"
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: $1 -abort" >&2
    exit 1
}

mount_img() {
    if [ $# -eq 0 ]; then
        echo "Select an operation loop: "
        echo "1. Mount"
        echo "2. Unmount"
        read -r -p "Enter your choice (1 or 2): " choice

        case "$choice" in
        1)
            # mount .img
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Mounting VHD-IMG..."
            mount -o loop,rw,sync "$myimg" "$mountpoint"
            mount_rc=$?
            if [ "$mount_rc" -eq 0 ]; then
                chown -R "$local_user": "$mountpoint"
                chmod 750 "$mountpoint"
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: VHD-IMG mounted"
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: VHD-IMG Mount failed, rc=$mount_rc -alert"
            fi
            logger -t vdisk "VHD-IMG Mount: $myimg rc=$mount_rc" || true
            ;;
        2)
            # umount .img
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Unmounting VHD-IMG..."
            umount "$mountpoint"
            umount_rc=$?
            if [ "$umount_rc" -eq 0 ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: VHD-IMG unmounted"
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: VHD-IMG Umount failed, rc=$umount_rc -alert"
            fi
            logger -t vdisk "VHD-IMG Umount: $myimg rc=$umount_rc" || true
            ;;
        *)
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: invalid option -abort" >&2
            exit 1
            ;;
        esac
    else
        echo "Usage: $0"
    fi
}

mount_img_kpartx() {
    if [ $# -eq 0 ]; then
        echo "Select an operation kpartx: "
        echo "1. Mount"
        echo "2. Umount"
        read -r -p "Enter your choice (1 or 2): " choice

        case "$choice" in
        1)
            # mount .img
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Mounting VHD-IMG..."
            if findmnt --mountpoint "$mountpoint" >/dev/null 2>&1; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: mount point already in use -abort" >&2
                exit 1
            fi
            mapfile -t loops_before < <(losetup -j "$myimg" | cut -d: -f1)
            maps_before=()
            for loop_dev in "${loops_before[@]}"; do
                for map_dev in "/dev/mapper/${loop_dev##*/}p"*; do
                    [ -e "$map_dev" ] && maps_before+=("${map_dev##*/}")
                done
            done
            maps_after=()
            if ! kpartx -a -v "$myimg" >/dev/null; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: kpartx cannot map VHD-IMG partitions -abort" >&2
                exit 1
            fi
            mapfile -t maps_after < <(kpartx -l "$myimg" | awk '{print $1}')
            mapfile -t loops < <(losetup -j "$myimg" | cut -d: -f1)
            if [ "${#loops[@]}" -gt 1 ] || [ "${#maps_after[@]}" -gt 1 ]; then
                kpartx_abort "ambiguous VHD-IMG device"
            elif [ "${#maps_after[@]}" -eq 1 ]; then
                mount_dev="/dev/mapper/${maps_after[0]}"
            elif [ "${#loops[@]}" -eq 1 ]; then
                mount_dev="${loops[0]}"
            else
                kpartx_abort "no VHD-IMG device found to mount"
            fi
            mount "$mount_dev" "$mountpoint"
            mount_rc=$?
            if [ "$mount_rc" -eq 0 ]; then
                chown -R "$local_user": "$mountpoint"
                chmod 750 "$mountpoint"
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: VHD-IMG mounted"
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: VHD-IMG Mount failed, rc=$mount_rc -alert"
            fi
            logger -t vdisk "VHD-IMG Mount: $myimg rc=$mount_rc" || true
            ;;
        2)
            # umount .img
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Unmounting VHD-IMG..."
            was_mounted=0
            findmnt --mountpoint "$mountpoint" >/dev/null 2>&1 && was_mounted=1
            umount "$mountpoint"
            umount_rc=$?
            kpartx_out=$(kpartx -d -v "$myimg")
            kpartx_rc=$?
            if [ "$was_mounted" -eq 1 ]; then
                if [ "$umount_rc" -eq 0 ] && [ "$kpartx_rc" -eq 0 ]; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: VHD-IMG unmounted"
                else
                    echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: VHD-IMG Umount failed, rc=$umount_rc kpartx_rc=$kpartx_rc -alert"
                fi
                logger -t vdisk "VHD-IMG Umount: $myimg rc=$umount_rc kpartx_rc=$kpartx_rc" || true
            elif [ "$kpartx_rc" -ne 0 ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: VHD-IMG Umount failed, rc=$umount_rc kpartx_rc=$kpartx_rc -alert"
                logger -t vdisk "VHD-IMG Umount: $myimg rc=$umount_rc kpartx_rc=$kpartx_rc" || true
            elif [ -n "$kpartx_out" ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: VHD-IMG mappings removed"
                logger -t vdisk "VHD-IMG Umount: $myimg rc=$umount_rc kpartx_rc=$kpartx_rc" || true
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: no mounted VHD-IMG -skip"
            fi
            ;;
        *)
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: invalid option -abort" >&2
            exit 1
            ;;
        esac
    else
        echo "Usage: $0"
    fi
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: vdisk start..."

# if no .img exists, create it
if [ ! -f "$myimg" ]; then create_img; fi

# Selection menu
printf "\n"
echo "Select a method for VHD image:"
echo "1. With loop"
echo "2. With kpartx"
read -r -p "Choose an option (1 or 2): " choice

case "$choice" in
1)
    mount_img
    ;;
2)
    mount_img_kpartx
    ;;
*)
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: invalid option -abort" >&2
    exit 1
    ;;
esac

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: vdisk done"
