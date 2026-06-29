#!/bin/bash
# maravento.com
#
################################################################################
#
# Check for Changes in Crontab Files
#
# This script checks for changes in crontab files after the marker line "# m h  dom mon dow   command".
# If changes are detected, it prints the modified line numbers (starting after the marker).
# The original backup files are preserved to maintain auditability.
#
# To view change alerts, run: sudo grep "crontab-check" /var/log/syslog
#
################################################################################

set -uo pipefail

echo "Check Crontab. Wait..."
printf "\n"

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

LOCK_FD=200
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n $LOCK_FD; then
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
# 4. Filter to only real users (UID >= 1000) from /etc/passwd to avoid capturing system accounts
[ -z "$local_user" ] && {
    _candidate=$(who | awk 'NR==1{print $1}')
    [ -n "$_candidate" ] && \
        local_user=$(awk -F: -v u="$_candidate" '$1==u && $3>=1000{print $1; exit}' /etc/passwd) || true
    unset _candidate
}
# 5. First valid home directory
[ -z "$local_user" ] && local_user=$(ls -l /home 2>/dev/null | awk '/^d/{print $3; exit}')
# Validate the user actually exists on the system
if [ -z "$local_user" ] || ! id "$local_user" &>/dev/null; then
    echo "ERROR: Cannot determine a valid local user"
    exit 1
fi
echo "Using local user: $local_user"

readonly user_crontab="/var/spool/cron/crontabs/$local_user"
readonly user_crontab_bak="/var/spool/cron/crontabs/${local_user}.bak"
readonly root_crontab="/var/spool/cron/crontabs/root"
readonly root_crontab_bak="/var/spool/cron/crontabs/root.bak"

readonly TMP_CURRENT="/tmp/crontab_current_$$"
readonly TMP_BACKUP="/tmp/crontab_backup_$$"

cleanup() {
    rm -f "$TMP_CURRENT" "$TMP_BACKUP"
}
trap cleanup EXIT INT TERM

backup_if_missing() {
    local src=$1
    local bak=$2
    if [ ! -f "$bak" ]; then
        if ! cp "$src" "$bak"; then
            echo "ERROR: Failed to create backup: $bak"
            return 1
        fi
    fi
}

get_start_line() {
    local file=$1
    if [ ! -f "$file" ]; then
        echo "ERROR: get_start_line: file not found: $file" >&2
        return 1
    fi
    grep -n "^# m h  dom mon dow   command" "$file" | cut -d: -f1
}

# Compare current and backup crontab files for a user
compare_crontabs() {
    local file=$1
    local bak=$2
    local user=$3

    # Check if files exist
    if [ ! -f "$file" ] || [ ! -f "$bak" ]; then
        echo "Crontab files missing for $user."
        return 1
    fi

    # Get the marker line and adjust the starting line
    local header_line
    header_line=$(get_start_line "$file")
    local start_line=1
    [ -n "$header_line" ] && start_line=$((header_line + 1))

    # Extract relevant part of the files starting after the marker
    tail -n +"$start_line" "$file" > "$TMP_CURRENT"
    tail -n +"$start_line" "$bak"  > "$TMP_BACKUP"

    local diff_output
    local offset=$(( start_line - 1 ))
    diff_output=$(diff --unchanged-line-format="" \
                       --old-line-format="OLD %dn %L" \
                       --new-line-format="NEW %dn %L" \
                       "$TMP_BACKUP" "$TMP_CURRENT" | \
        awk -v off="$offset" '
            /^OLD/{ n=$2; $1=$2=""; sub(/^ +/,""); printf "Line %d in backup:  %s\n", n+off, $0; next }
            /^NEW/{ n=$2; $1=$2=""; sub(/^ +/,""); printf "Line %d in current: %s\n", n+off, $0 }
        ' || true)

    if [ -z "$diff_output" ]; then
        echo "No changes detected in crontab for $user."
    else
        echo "Alert: Changes detected in crontab for $user (lines shown below):"
        echo "$diff_output"
    fi
}

# Validate files before enabling the tee/logger redirect
[ ! -f "$user_crontab" ] && echo "Missing file: $user_crontab" && exit 1
[ ! -f "$root_crontab" ] && echo "Missing file: $root_crontab" && exit 1

# Create backups if missing (only once)
backup_if_missing "$user_crontab" "$user_crontab_bak" || exit 1
backup_if_missing "$root_crontab" "$root_crontab_bak" || exit 1

# Now safe to enable tee+logger redirect (output goes to tty AND syslog)
if [ -t 1 ]; then
    exec > >(tee /dev/tty | logger -p user.alert -t crontab-check) 2>&1
else
    exec > >(logger -p user.alert -t crontab-check) 2>&1
fi

# Perform comparison for user and root crontabs
compare_crontabs "$user_crontab" "$user_crontab_bak" "$local_user"
compare_crontabs "$root_crontab" "$root_crontab_bak" "root"
