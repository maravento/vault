#!/bin/bash
# maravento.com

# System Migration Tool
# Backup and Restore of programs and settings for re-installing OS
# The migration must be done on the same distro and version

echo "System Migration Tool Starting. Wait..."
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

# checking dependencies (optional)
pkgs='dselect dpkg rsync'
if apt-get install -qq $pkgs; then
    true
else
    echo "Error installing $pkgs. Abort"
    exit
fi

### VARIABLES
# local user
local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}' || who | head -1 | awk '{print $1}')
# Backup folder
BACKUP_DIR=/home/$local_user/BackupApps
mkdir -p $BACKUP_DIR/etc_backup
# tar.gz outfile
OUTFILE=/home/$local_user/BackupAppstar.tar.gz

# backup
backup() {
    echo "Backup Start. Wait.."
    # Save the list of installed packages
    dpkg --get-selections > $BACKUP_DIR/package.list
    # Save package sources and PPA repositories
    cp -R /etc/apt/sources.list* $BACKUP_DIR/
    cp -r /etc/apt/trusted.gpg.d $BACKUP_DIR/keys
    # Save program configuration files
    rsync -a /etc/ $BACKUP_DIR/etc_backup/
    # compress file
    tar -czvf $OUTFILE $BACKUP_DIR
    echo "Done"
}

# restore
restore() {
    echo "Restore Start. Wait.."
    # uncompress tar.gz
    cat $OUTFILE | tar xzf -
    # Restore package sources, keys, and PPA repositories
    cp -r $BACKUP_DIR/keys /etc/apt/trusted.gpg.d
    gpg --import /etc/apt/trusted.gpg.d/*.gpg
    cp -R $BACKUP_DIR/sources.list* /etc/apt/
    apt-get update
    # Restore installed programs
    dselect update
    dpkg --set-selections < $BACKUP_DIR/package.list
    apt-get dselect-upgrade -y
    # Restore program configuration files
    rsync -a $BACKUP_DIR/etc_backup/ /etc/
    echo "Done"
}

# menu
echo "System Migration Tool, Start"
printf "\n"
echo "Choose an option:"
echo "1. Backup"
echo "2. Restore"
echo "3. Exit"
read -p "Enter your choice (1, 2 or 3): " choice

while true; do
    case $choice in
        1)
            backup
            exit
            ;;
        2)
            restore
            exit
            ;;
        3)
            exit
            ;;
        *)
            echo "Invalid option"
            ;;
    esac
done
