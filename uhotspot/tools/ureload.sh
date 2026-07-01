#!/bin/bash
# /etc/uhotspot/tools/ureload.sh
# Reload wrapper — invoked by uhotspot.sh after ACL changes
LOG_FILE="/var/log/uhotspot.log"
TS() { date '+%Y-%m-%d %H:%M:%S'; }
RLOG() { echo "$(TS) $*" >> "$LOG_FILE"; }
set -euo pipefail
# UHOTSPOT_RELOAD_ACTIVE is NOT set here. When called from the daemon
# (check_and_reload_if_changed), the daemon already exports it before invoking
# this script, so uleases.sh inherits it and skips its own cron-guard check
# (correct — the daemon is in control of the reload, and it's the same
# process tree). When called from the @hourly cron the variable is absent,
# so uleases.sh coordinates via its own cycle-lock check before doing any
# real work.
RLOG "ureload start..."

# Guard against cascading failures: if uhotspotd is not active (crashed,
# stopped, or never finished starting), nothing downstream should run blindly.
# systemctl is-active only reports "active" while the process is alive AND
# past its own startup checks — a failed startup (e.g. verify_installation
# aborting) or a stop/crash both make this check fail, covering both
# directions ("did it stop" and "did it actually start") with one call.
if ! systemctl is-active --quiet uhotspotd; then
    RLOG "ERROR: uhotspotd is not active — aborting (uleases.sh/uiptables.sh not invoked)"
    exit 1
fi

# uleases.sh logs its own output directly to LOG_FILE via ulog(); its stdout
# here is a duplicate and is discarded. stderr is still captured in case of
# an uncaught bash error (e.g. unbound variable, command not found) that
# never reaches ulog.
if ! /etc/uhotspot/tools/uleases.sh >/dev/null 2>>"$LOG_FILE"; then
    RLOG "ERROR: uleases.sh failed — aborting"
    exit 1
fi

# uiptables.sh is optional (user-provided)
UIPTABLES="/etc/uhotspot/tools/uiptables.sh"
if [[ -x "$UIPTABLES" ]]; then
    if ! "$UIPTABLES" >> "$LOG_FILE" 2>&1; then
        RLOG "ERROR: uiptables.sh failed"
        exit 1
    fi
fi
RLOG "ureload done"
echo "────────────────────────────────────────────────────────────────────────" >> "$LOG_FILE" 2>/dev/null
