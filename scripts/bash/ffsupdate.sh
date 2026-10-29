#!/bin/bash
# maravento.com
#
################################################################################
#
# FreeFileSync Update
# FILE: ffsupdate.sh
#
# DESCRIPTION: Downloads and silently installs the latest FreeFileSync
# release. Run as root, intended for cron/unattended use.
#
# USAGE: sudo ./ffsupdate.sh
#
# LOG: /var/log/ffsupdate.log (rewritten on each run)
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

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

# logging
log_file="/var/log/ffsupdate.log"
{ > "$log_file"; } 2>/dev/null || true
log() {
    local msg="$1"
    local log_msg="$(date '+%Y-%m-%d %H:%M:%S') $msg"
    echo "$log_msg" >> "$log_file" 2>/dev/null || true
    if [[ "$msg" == ERROR:* ]]; then
        echo "$log_msg" >&2
    else
        echo "$log_msg"
    fi
}

# Start
log "EVENT: ffsupdate start..."

# dependencies
for dep in expect tcl-expect wget tar coreutils util-linux iproute2 libc-bin; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: dependency '$dep' is not installed -abort"
        exit 1
    fi
done

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
            log "INFO: waiting for an interface with IPv4..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    log "ERROR: no interface with IPv4 -abort"
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
            log "INFO: waiting for internet..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    log "ERROR: no internet connection -abort"
    exit 1
}

check_ipv4_interfaces
check_internet

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

ffs_work_dir=$(mktemp -d) || {
    log "ERROR: cannot create temporary directory -abort"
    exit 1
}
trap 'rm -rf -- "$ffs_work_dir"' EXIT
cd "$ffs_work_dir" || {
    log "ERROR: cannot enter temporary directory -abort"
    exit 1
}
ffsfile="$ffs_work_dir/FreeFileSync.tar.gz"
ffsrun="$ffs_work_dir/FreeFileSync.run"
url="https://www.freefilesync.org/download.php"

trap 'log "ERROR: FreeFileSync installation failed -abort"; exit 1' ERR INT TERM

link=$(wget -q "$url" -O - | grep -Pio '/download/[^"]+Linux[^"]+gz') || true
if [ -z "$link" ]; then
    log "ERROR: download link missing; site may have changed -abort"
    exit 1
fi

version=$(echo "$link" | sed -r 's:.*FreeFileSync_([0-9]+\.[0-9]+)_.*:\1:')
if [ -z "$version" ]; then
    log "ERROR: could not parse version from link: $link -abort"
    exit 1
fi

if ! wget -qO "$ffsfile" "https://www.freefilesync.org$link" \
    -U "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/63.0.3239.84 Chrome/63.0.3239.84 Safari/537.36"; then
    log "PARTIAL: https://www.freefilesync.org$link"
    rm -f "$ffsfile"
    exit 1
fi
log "SAVED: $(basename "$ffsfile")"

if ! tar xf "$ffsfile" >/dev/null 2>&1; then
    log "ERROR: extraction failed; archive may be corrupt -abort"
    rm -f "$ffsfile"
    exit 1
fi

extracted=$(ls FreeFileSync*.run 2>/dev/null | head -1)
if [ -z "$extracted" ]; then
    log "ERROR: no FreeFileSync installer after extraction -abort"
    rm -f "$ffsfile"
    exit 1
fi

mv "$extracted" "$ffsrun"
chmod +x "$ffsrun"

/usr/bin/expect -f /dev/stdin "$ffsrun" "$log_file" <<'EOF'
proc installer_error {message} {
    set line "[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] ERROR: $message -abort"
    puts stderr $line
    set output [open [lindex $::argv 1] a]
    puts $output $line
    close $output
    exit 1
}
set timeout 120
log_user 0
spawn [lindex $argv 0]
log_user 1
expect {
    -re {Accept[^\r\n]*license[^\r\n]*\[y/n/s\]} {
        send -- "y\r"
    }
    timeout {
        installer_error "license prompt timed out"
    }
    eof {
        installer_error "installer exited before license prompt"
    }
}
expect {
    -exact "to begin installation:" {
        send -- "\r"
    }
    timeout {
        installer_error "installation prompt timed out"
    }
    eof {
        installer_error "installer exited before installation"
    }
}
expect {
    eof {}
    timeout {
        installer_error "installation timed out"
    }
}
set result [wait]
if {[lindex $result 2] != 0 || [llength $result] > 4} {
    installer_error "cannot read installer exit status"
}
if {[lindex $result 3] != 0} {
    installer_error "installer failed with code [lindex $result 3]"
}
exit 0
EOF

rm -f "$ffsfile" "$ffsrun"

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# End
log "EVENT: ffsupdate done"
