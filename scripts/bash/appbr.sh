#!/bin/bash
# maravento.com
#
# System Migration Tool
# Backup and Restore of programs and settings for re-installing OS
# The migration must be done on the same distro and version

echo "System Migration Tool Starting. Wait..."
printf "\n"

# check root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# check script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi

# check SO
UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
if [[ "$UBUNTU_ID" != "ubuntu" || "$UBUNTU_VERSION" != "24.04" ]]; then
    echo "This script requires Ubuntu 24.04. Use at your own risk"
    # exit 1
fi

# check dependencies
pkgs='dselect dpkg rsync'
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

# LOCAL USER
# Get real user (not root) - multiple fallback methods
local_user=$(logname 2>/dev/null || echo "$SUDO_USER")
# If not found or is root, try detecting active graphical user
if [ -z "$local_user" ] || [ "$local_user" = "root" ]; then
    local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}')
fi
# As a final fallback, take the first logged user
if [ -z "$local_user" ]; then
    local_user=$(who | head -1 | awk '{print $1}')
fi
# Clean possible spaces or line breaks
local_user=$(echo "$local_user" | xargs)

### VARIABLES
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
