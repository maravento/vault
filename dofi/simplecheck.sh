#!/bin/bash
# maravento.com
#
################################################################################
#
# Simple DNS Domain Checker
# -------------------------
# This lightweight script checks whether domains listed in a local file
# resolve via DNS using the `host` command. It is optimized for small to medium
# domain lists where fast, one-pass resolution is sufficient.
#
# Results:
# - `exists.txt`: Domains that successfully resolved
# - `not_exists.txt`: Domains that did not resolve
#
# Usage:
# ./simplecheck.sh [list_file]
# Defaults to 'mylist.txt' if no argument is given.
#
# Configuration:
# - Parallel execution is based on available CPU cores x 4, capped at 200.
#
# Notes:
# - Unlike more advanced scripts, this version does not retry failed domains
#   or perform input sanitization. It assumes the input list is already clean.
# - Ideal for quick checks or small domain validation tasks.
#
# NOTE on logging:
# - Writes to /var/log/dofi.log (shared with domcheck.sh, append-only, no
#   rotation configured by this script). Set up logrotate for this file if
#   disk usage matters.
# - To clear it manually: truncate -s 0 /var/log/dofi.log
#
################################################################################

# logging
log_file="/var/log/dofi.log"
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" | tee -a "$log_file" 2>/dev/null || true
}

trap 'log "Process interrupted by user"; exit 1' INT

# Start
log "simplecheck start..."

list="${1:-mylist.txt}"

if [ ! -f "$list" ]; then
    log "The file '$list' does not exist."
    exit 1
fi

if ! command -v host >/dev/null 2>&1; then
    log "Error: 'host' command not found. Please install it (e.g., dnsutils/bind-tools)."
    exit 1
fi

if [ -s exists.txt ] || [ -s not_exists.txt ]; then
    log "Warning: exists.txt and/or not_exists.txt already contain data and will be overwritten."
fi

> exists.txt
> not_exists.txt

PROCS=$(($(nproc) * 4))

dnslookup="dnslookup.txt"
: > "$dnslookup"

check_domain() {
    original="$1"
    clean="$original"
    while [[ "$clean" == .* ]]; do
        clean="${clean#.}"
    done
    if timeout 5 host "$clean" > /dev/null 2>&1; then
        log "$original exists"
        echo "EXISTS $original" >> "$dnslookup"
    else
        log "$original does NOT exist"
        echo "NOT_EXISTS $original" >> "$dnslookup"
    fi
}
export -f check_domain
export -f log
export dnslookup
export log_file

cat "$list" | xargs -n 1 -P "$PROCS" -I {} bash -c 'check_domain "$@"' -- {}

sed '/^NOT_EXISTS/d' "$dnslookup" | awk '{print $2}' > exists.txt
sed '/^EXISTS/d' "$dnslookup" | awk '{print $2}' > not_exists.txt
rm -f "$dnslookup"

# End
log "simplecheck done at: $(date)"
