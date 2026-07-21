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

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# check no-root
if [ "$(id -u)" == "0" ]; then
    echo "[ERROR] This script should not be run as root."
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "[ERROR] Script $(basename "$0") is already running"
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

echo "Check Crontab. Wait..."

# VARIABLES
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
