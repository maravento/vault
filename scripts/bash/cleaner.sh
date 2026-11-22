#!/bin/bash
# maravento.com
#
################################################################################
#
# Cleaner
# FILE: cleaner.sh
#
# DESCRIPTION: Searches and permanently deletes:
# - Windows ADS files (e.g., :Zone.Identifier, :encryptable, Thumbs.db)
# - macOS and Linux system files (e.g., .fuse_hidden*, .spotlight-*,
#   .fseventsd*, .DS_Store, ~lock.*)
# - Extended attributes and metadata streams (e.g., :attributes:)
# Never enters trash bins or system folders (.Trash-*, .recycle, $RECYCLE.BIN,
# System Volume Information, lost+found, .Trashes, .Spotlight-V100, .fseventsd,
# .TemporaryItems, LOST.DIR)
#
# USAGE:
# COMMAND                             ACTION
# sudo bash cleaner.sh [search_path]  Clean the selected path
#
# Without arguments, searches from /
#
# LOG: /var/log/cleaner.log
#      system logger (destination set by system configuration)
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# path for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# root check
if [ "$(id -u)" -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# awk is a command, not a package: check it before its first use
command -v awk >/dev/null 2>&1 || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: awk not found -abort" >&2; exit 1; }

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

# check ipv4 interfaces
list_ifaces() {
    ip -br link show 2>/dev/null | awk '$1 != "lo" {sub(/@.*/, "", $1); printf "%s %s\n", $1, ($2 == "UP") ? "UP" : "DOWN"}'
}

list_ipv4_ifaces() {
    local iface state
    while read -r iface state; do
        [ "$state" = UP ] || continue
        if ip -4 -o addr show dev "$iface" scope global 2>/dev/null \
            | awk '$4 != "" {found=1} END {exit !found}'; then
            printf '%s\n' "$iface"
        fi
    done < <(list_ifaces)
}

check_ipv4_interfaces() {
    local max_attempts=24 attempt=1

    while (( attempt <= max_attempts )); do
        if [ -n "$(list_ipv4_ifaces)" ]; then
            return 0
        fi
        if (( attempt == 1 )); then
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: waiting for an interface with IPv4..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no interface with IPv4 -abort" >&2
    exit 1
}

# check internet
check_internet() {
    local max_attempts=24 attempt=1

    while (( attempt <= max_attempts )); do
        if getent hosts www.google.com >/dev/null 2>&1; then
            return 0
        fi
        if (( attempt == 1 )); then
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: waiting for internet..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no internet connection -abort" >&2
    exit 1
}

# dependencies
net_checked=0
for dep in findutils coreutils util-linux bsdutils iproute2 libc-bin; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep" 2>/dev/null)" != *"ok installed"* ]]; then
        if [ "$net_checked" -eq 0 ]; then
            if ! command -v ip >/dev/null 2>&1; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: installing iproute2"
                apt-get install -y iproute2 >/dev/null 2>&1 || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install iproute2 -abort" >&2; exit 1; }
            fi
            check_ipv4_interfaces
            check_internet
            apt-get update -qq || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot update package lists -abort" >&2; exit 1; }
            net_checked=1
        fi
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: installing $dep"
        if ! apt-get install -y "$dep" >/dev/null 2>&1; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install $dep -abort" >&2
            exit 1
        fi
    fi
done

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: cleaner start..."

start=$(date +%s)

search_path="${1:-/}"

deleted_count=0
while IFS= read -r -d '' f; do
    if rm -f "$f" 2>>/var/log/cleaner.log; then
        deleted_count=$((deleted_count + 1))
    fi
done < <(find "$search_path" -regextype posix-egrep \
\( -type d \( -iname '.Trash-*' -o -iname '.recycle' -o -iname '$RECYCLE.BIN' \
    -o -iname 'System Volume Information' -o -iname 'lost+found' -o -iname '.Trashes' \
    -o -iname '.Spotlight-V100' -o -iname '.fseventsd' -o -iname '.TemporaryItems' \
    -o -iname 'LOST.DIR' \) -prune \) -o \
\( -type f -iregex \
'^(.*/)?([^/]*:(encryptable|Zone\.identifier)|\.fuse_hidden[^/]*|\.goutputstream-[^/]*|\.spotlight-[^/]*|\.fseventsd[^/]*|\.ds_store|\.?~lock\.[^/]*#|thumbs\.db|[^/]*:attributes:[^/]*)$' \
-print0 \) 2>>/var/log/cleaner.log)

end=$(date +%s)
duration=$((end - start))

# Log registry
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Files deleted: ${deleted_count} - Time: ${duration}s"
logger -t cleaner "Cleaner: Files deleted: ${deleted_count} - Time: ${duration}s" || true

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: cleaner done"
