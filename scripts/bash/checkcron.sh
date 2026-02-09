#!/bin/bash
# maravento.com
#
# Check for Changes in Crontab Files
#
# This script checks for changes in crontab files after the marker line "# m h  dom mon dow   command".
# If changes are detected, it prints the modified line numbers (starting after the marker).
# The original backup files are preserved to maintain auditability.
#
# To view change alerts, run: sudo grep "crontab-check" /var/log/syslog

echo "Check Crontab. Wait..."
printf "\n"

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# checking root
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# checking script execution
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

# LOCAL USER
local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}' || who | head -1 | awk '{print $1}')
# Fallback
if [ -z "$local_user" ]; then
    local_user=$(ls -l /home | grep '^d' | head -1 | awk '{print $3}')
    if [ -z "$local_user" ]; then
        echo "ERROR: Cannot determine local user"
        exit 1
    fi
    echo "Using fallback user: $local_user"
fi

# Define paths to current and backup crontab files for both the user and root
user_crontab="/var/spool/cron/crontabs/$local_user"
user_crontab_bak="/var/spool/cron/crontabs/${local_user}.bak"
root_crontab="/var/spool/cron/crontabs/root"
root_crontab_bak="/var/spool/cron/crontabs/root.bak"

# Create a backup of a crontab file if the backup does not already exist
backup_if_missing() {
    local src=$1
    local bak=$2
    [ ! -f "$bak" ] && cp "$src" "$bak"
}

exec > >(tee /dev/tty | logger -p user.alert -t crontab-check) 2>&1

# Get the line number of the marker line "# m h  dom mon dow   command"
get_start_line() {
    grep -n "^# m h  dom mon dow   command" "$1" | cut -d: -f1
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
    tail -n +"$start_line" "$file" > /tmp/current
    tail -n +"$start_line" "$bak" > /tmp/backup

    local total_current=$(wc -l < /tmp/current)
    local total_backup=$(wc -l < /tmp/backup)

    local max_lines=$(( total_current > total_backup ? total_current : total_backup ))
    local changed_lines=()

    # Detect different lines
    for ((i=1; i<=max_lines; i++)); do
        local line_cur=$(sed -n "${i}p" /tmp/current)
        local line_bak=$(sed -n "${i}p" /tmp/backup)

        # Treat empty lines as ""
        line_cur=${line_cur:-""}
        line_bak=${line_bak:-""}

        if [ "$line_cur" != "$line_bak" ]; then
            changed_lines+=($((i + start_line - 1)))
        fi
    done

    if [ ${#changed_lines[@]} -eq 0 ]; then
        echo "No changes detected in crontab for $user."
    else
        echo "Alert: Modified lines in crontab for $user: ${changed_lines[*]}"
        for line_num in "${changed_lines[@]}"; do
            local line_in_bak=$(sed -n "${line_num}p" "$bak")
            local line_in_cur=$(sed -n "${line_num}p" "$file")
            echo "Line $line_num in backup: ${line_in_bak:-<empty>}"
            echo "Line $line_num in current: ${line_in_cur:-<empty>}"
        done
    fi

    rm -f /tmp/current /tmp/backup
}

# Validate that both crontab files exist before proceeding
[ ! -f "$user_crontab" ] && echo "Missing file: $user_crontab" && exit 1
[ ! -f "$root_crontab" ] && echo "Missing file: $root_crontab" && exit 1

# Create backups if missing (only once)
backup_if_missing "$user_crontab" "$user_crontab_bak"
backup_if_missing "$root_crontab" "$root_crontab_bak"

# Perform comparison for user and root crontabs
compare_crontabs "$user_crontab" "$user_crontab_bak" "$local_user"
compare_crontabs "$root_crontab" "$root_crontab_bak" "root"

