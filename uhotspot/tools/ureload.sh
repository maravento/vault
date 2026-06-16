#!/bin/bash
# /etc/uhotspot/tools/ureload.sh
# Reload wrapper — invoked by uhotspot.sh after ACL changes

LOG_FILE="/var/log/uhotspot.log"
TS=$(date '+%Y-%m-%d %H:%M:%S')

set -uo pipefail

export UHOTSPOT_RELOAD_ACTIVE=1

echo "$TS INFO: ureload: running uleases.sh..." >> "$LOG_FILE"
if ! /etc/uhotspot/tools/uleases.sh >> "$LOG_FILE" 2>&1; then
    echo "$TS ERROR: ureload: uleases.sh failed — aborting" >> "$LOG_FILE"
    exit 1
fi

# uiptables.sh is optional (user-provided)
UIPTABLES="/etc/uhotspot/tools/uiptables.sh"
if [[ -x "$UIPTABLES" ]]; then
    echo "$TS INFO: ureload: running uiptables.sh..." >> "$LOG_FILE"
    if ! "$UIPTABLES" >> "$LOG_FILE" 2>&1; then
        echo "$TS ERROR: ureload: uiptables.sh failed" >> "$LOG_FILE"
        exit 1
    fi
else
    echo "$TS INFO: ureload: uiptables.sh not found or not executable — skipping" >> "$LOG_FILE"
fi

echo "$TS INFO: ureload: done" >> "$LOG_FILE"
