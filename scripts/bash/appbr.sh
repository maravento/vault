#!/bin/bash
# maravento.com
#
################################################################################
#
# System Migration Tool
# Backup and Restore of programs and settings for re-installing OS
# The migration must be done on the same distro and version
#
################################################################################

echo "System Migration Tool Starting. Wait..."
printf "\n"

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
pkgs='dselect dpkg rsync'
missing=$(for p in $pkgs; do dpkg -s "$p" &>/dev/null || echo "$p"; done | xargs)
unavailable=""
for p in $missing; do
    apt-cache show "$p" &>/dev/null || unavailable+=" $p"
done
if [ -n "$unavailable" ]; then
    echo "Missing dependencies not found in APT:"
    for u in $unavailable; do echo "   - $u"; done
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
        echo "   Locks held, waiting... (${APT_LOCK_ELAPSED}s)"
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
# Backup staging folder (inside user home)
BACKUP_DIR="/home/$local_user/BackupApps"
# FIX: outfile lives OUTSIDE BACKUP_DIR to avoid compressing itself
OUTFILE="/home/$local_user/BackupApps.tar.gz"

# backup
backup() {
    echo "Backup Start. Wait..."

    # Clean staging dir to avoid stale files from previous runs
    rm -rf "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR/etc_backup"
    mkdir -p "$BACKUP_DIR/keys"

    # Save the list of installed packages
    dpkg --get-selections > "$BACKUP_DIR/package.list"

    # Save package sources and PPA repositories
    cp -R /etc/apt/sources.list* "$BACKUP_DIR/" 2>/dev/null || true

    # FIX: copy contents of trusted.gpg.d, not the directory itself
    # Original: cp -r /etc/apt/trusted.gpg.d "$BACKUP_DIR/keys"
    #   → creates keys/trusted.gpg.d/ (wrong nesting)
    # Fixed:
    cp -r /etc/apt/trusted.gpg.d/. "$BACKUP_DIR/keys/"

    # Save program configuration files
    rsync -a /etc/ "$BACKUP_DIR/etc_backup/"

    # FIX: use -C to anchor tar at BACKUP_DIR so archive paths are RELATIVE
    # Original: tar -czvf "$OUTFILE" "$BACKUP_DIR"  ← no -C, embeds full absolute path
    # Fixed:
    tar -czf "$OUTFILE" -C "$BACKUP_DIR" .

    # Verify the archive is intact before declaring success
    if tar -tzf "$OUTFILE" > /dev/null 2>&1; then
        echo "Backup complete: $OUTFILE ($(du -sh "$OUTFILE" | cut -f1))"
    else
        echo "Archive verification FAILED. Backup may be corrupt."
        exit 1
    fi

    # Generate SHA256 hash of the archive
    sha256sum "$OUTFILE" > "${OUTFILE}.sha256"
    echo "Hash saved: ${OUTFILE}.sha256"
    echo "   $(cat "${OUTFILE}.sha256")"
}

# restore
restore() {
    echo "Restore Start. Wait..."

    # Verify archive integrity BEFORE touching the live system
    if ! tar -tzf "$OUTFILE" > /dev/null 2>&1; then
        echo "Archive $OUTFILE is missing or corrupt. Aborting."
        exit 1
    fi

    # Verify SHA256 hash if it exists (optional — warns but does not abort)
    HASHFILE="${OUTFILE}.sha256"
    if [ -f "$HASHFILE" ]; then
        echo "Verifying hash..."
        if sha256sum -c "$HASHFILE" > /dev/null 2>&1; then
            echo "   Hash OK — archive integrity confirmed"
        else
            echo "   Hash MISMATCH — archive may have been modified or corrupted"
            read -r -p "   Continue anyway? (y/N): " override
            [[ ! "$override" =~ ^[Yy]$ ]] && { echo "Restore cancelled."; exit 0; }
        fi
    else
        echo "   No hash file found (${HASHFILE}) — skipping verification"
    fi

    # Recreate staging dir
    rm -rf "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"

    # FIX: extract into BACKUP_DIR explicitly
    tar xzf "$OUTFILE" -C "$BACKUP_DIR"

    # Diff report: show what would change in /etc before touching anything
    echo ""
    echo "Differences between backup and current /etc:"
    diff_output=$(rsync -avnc --delete "$BACKUP_DIR/etc_backup/" /etc/ 2>/dev/null \
        | grep -E '^(>|<|deleting)')
    if [ -z "$diff_output" ]; then
        echo "   No differences found. /etc is identical to backup."
    else
        echo "$diff_output"
        echo ""
        echo "   Lines starting with '>'       = files that will be overwritten"
        echo "   Lines starting with 'deleting' = files in /etc not present in backup (will NOT be deleted)"
    fi
    echo ""
    read -r -p "Proceed with restore? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Restore cancelled."
        exit 0
    fi

    # Restore package sources and keys
    # FIX: copy contents, not the directory node itself
    cp -r "$BACKUP_DIR/keys/." /etc/apt/trusted.gpg.d/

    # Import GPG keys (skip non-gpg files silently)
    for key in /etc/apt/trusted.gpg.d/*.gpg; do
        [ -f "$key" ] && gpg --import "$key" 2>/dev/null || true
    done

    cp -R "$BACKUP_DIR/sources.list"* /etc/apt/ 2>/dev/null || true
    apt-get update

    # Restore installed programs
    dselect update
    dpkg --set-selections < "$BACKUP_DIR/package.list"
    apt-get dselect-upgrade -y

    # Restore program configuration files
    rsync -a "$BACKUP_DIR/etc_backup/" /etc/

    echo "Restore complete."
}

# menu
echo "System Migration Tool"
printf "\n"
echo "Choose an option:"
echo "1. Backup"
echo "2. Restore"
echo "3. Exit"

# FIX: read is INSIDE the loop so invalid input re-prompts instead of looping forever
# Original: read was outside while, $choice never updated on bad input → infinite loop
while true; do
    read -r -p "Enter your choice (1, 2 or 3): " choice
    case $choice in
        1) backup;  exit 0 ;;
        2) restore; exit 0 ;;
        3) exit 0 ;;
        *) echo "Invalid option. Please enter 1, 2 or 3." ;;
    esac
done
