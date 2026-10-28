#!/bin/bash
# maravento.com
#
################################################################################
#
# Suricata Update
# FILE: suricataupdate.sh
#
# USAGE:
# sudo bash suricataupdate.sh
#
# LOG: /var/log/suridata.log
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# path for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# root check
if [ "$(id -u)" != "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# logging
log_file="/var/log/suridata.log"
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

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock") || {
    log "ERROR: cannot open $(basename "$script_lock") -abort"
    exit 1
}
exec 200>"$script_lock"
if ! flock -n 200; then
    log "ERROR: script $(basename "$0") is already running -abort"
    exit 1
fi

# maintenance lock
maintenance_lock="/var/lock/suricata-maintenance.lock"
(umask 077; : >> "$maintenance_lock") || { log "ERROR: cannot open maintenance lock -abort"; exit 1; }
exec 202>"$maintenance_lock" || { log "ERROR: cannot open maintenance lock -abort"; exit 1; }
if ! flock -w 600 202; then
    log "ERROR: another maintenance task is still running -abort"
    exit 1
fi

# dependencies
for dep in suricata suricata-update systemd util-linux libc-bin grep coreutils iproute2; do
    if ! dpkg-query -W -f='${Status}' "$dep" 2>/dev/null | grep -q 'ok installed'; then
        log "ERROR: dependency '$dep' is not installed -abort"
        exit 1
    fi
done

# dependencies (external repo)
for dep in evebox; do
    if ! dpkg-query -W -f='${Status}' "$dep" 2>/dev/null | grep -q 'ok installed'; then
        log "ERROR: missing dependency '$dep' -abort"
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

log "EVENT: suricataupdate start..."

for service in suricata evebox; do
    if ! systemctl stop "$service"; then
        log "ERROR: cannot stop $service -abort"
        exit 1
    fi
    service_state=$(systemctl show "$service" --property=ActiveState --value) || {
        log "ERROR: cannot check $service state -abort"
        exit 1
    }
    case "$service_state" in
        inactive|failed) ;;
        *) log "ERROR: $service is not stopped -abort"; exit 1 ;;
    esac
done

if suricata-update --disable-conf=/etc/suricata/data/disable.conf \
                  --drop-conf=/etc/suricata/data/drop.conf \
                  --quiet >> "$log_file" 2>&1; then
    rules_file="/var/lib/suricata/rules/suricata.rules"

    if systemctl start suricata; then
        sleep 3
        if ! systemctl is-active --quiet suricata; then
            log "ERROR: Suricata not active after start -abort"
            exit 1
        fi
        active_rules=$(grep -c '^alert' "$rules_file" 2>/dev/null); [ -z "$active_rules" ] && active_rules="N/A"
        log "INFO: Suricata started, active rules: $active_rules"
        if systemctl start evebox; then
            if ! systemctl is-active --quiet evebox; then
                log "ERROR: EveBox not active after start -abort"
                exit 1
            fi
            log "INFO: EveBox started"
        else
            log "ERROR: EveBox failed to start -abort"
            exit 1
        fi
    else
        log "ERROR: failed to start Suricata -abort"
        exit 1
    fi
else
    log "ERROR: suricata-update failed -abort"
    exit 1
fi

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

log "EVENT: suricataupdate done"
