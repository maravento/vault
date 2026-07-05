#!/bin/bash
# /etc/uhotspot/tools/ureload.sh
# Reload wrapper — invoked by uhotspotd after ACL changes, or via @hourly cron.
# Runs uleases.sh (lease/ACL rebuild) then uiptables.sh (firewall rules), in
# that order. Aborts if either is missing or fails.
#
# NOTE on logging:
# - Writes to /var/log/uhotspot.log (shared with uleases.sh). Rotation is
#   self-installed by uleases.sh (/etc/logrotate.d/uhotspot).

# logging
log_file="/var/log/uhotspot.log"
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" | tee -a "$log_file" 2>/dev/null || true
}

## root check
if [ "$(id -u)" != "0" ]; then
    log "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    log "Script $(basename "$0") is already running"
    exit 1
fi

set -euo pipefail
# UHOTSPOT_RELOAD_ACTIVE: not set here. The daemon exports it before calling
# this script (so uleases.sh skips its own cron-guard); the @hourly cron
# leaves it unset (so uleases.sh uses its own cycle-lock instead).

# Start
log "ureload start..."

# Abort if uhotspotd isn't active — nothing downstream should run blindly.
if ! systemctl is-active --quiet uhotspotd; then
    log "ERROR: uhotspotd is not active — aborting (uleases.sh/uiptables.sh not invoked)"
    exit 1
fi

# Both scripts log their own output via log(); stdout here is a duplicate
# and is discarded, stderr is kept for uncaught bash errors.
run_step() {
    local script="$1" name="$2"
    if [[ ! -x "$script" ]]; then
        log "WARNING: $name not found or not executable: $script — aborting"
        exit 1
    fi
    if ! "$script" >/dev/null 2>>"$log_file"; then
        log "WARNING: $name failed — aborting"
        exit 1
    fi
}

run_step "/etc/uhotspot/tools/uleases.sh" "uleases.sh"
run_step "/etc/uhotspot/tools/uiptables.sh" "uiptables.sh"

# End
log "ureload done at: $(date)"
