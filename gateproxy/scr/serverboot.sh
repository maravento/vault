#!/bin/bash
# maravento.com
#
################################################################################
#
# Server Boot
# FILE: scr/serverboot.sh
#
# USAGE:
# sudo ./serverboot.sh
#
# LOG: /var/log/serverboot.log
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# root check
if [ "$(id -u)" != "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# logging
log_file="/var/log/serverboot.log"
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
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot open $(basename "$script_lock") -abort" >&2
    exit 1
}
exec 200>"$script_lock"
if ! flock -n 200; then
    log "ERROR: script $(basename "$0") is already running -abort"
    exit 1
fi

# dependencies (samba/winbind excluded -- Samba install is optional in gpsetup.sh)
for dep in iproute2 systemd squid-openssl apache2 rsyslog util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: dependency '$dep' is not installed -abort"
        exit 1
    fi
done

log "EVENT: serverboot start..."

# ------------------------------------------------------------------------------
# NETWORK
# ------------------------------------------------------------------------------

# Wait until the required network topology is available.
#
# Interfaces are considered ready only when they have:
#   UP        = administratively enabled
#   LOWER_UP  = physical link detected
#
# Rules:
#   - No bonding: at least 2 active interfaces.
#   - Bonding: at least 4 active interfaces
#     (bond + two slaves + another interface, usually WAN).
#
# Loopback (lo) is ignored.

network_ready() {
    local dev iface flags

    iface_count=0
    required=2
    iface_list=""

    # If bonding is configured, require four active interfaces.
    [[ -f /sys/class/net/bonding_masters ]] && required=4

    for dev in /sys/class/net/*; do
        iface=$(basename "$dev")
        [[ "$iface" == "lo" ]] && continue

        flags=$(ip -o link show "$iface" 2>/dev/null | grep -oP '(?<=<)[^>]+')

        if [[ "$flags" == *UP* && "$flags" == *LOWER_UP* ]]; then
            ((iface_count++))
            iface_list+="$iface"$'\n'
        fi
    done

    ((iface_count >= required))
}

log "EVENT: Waiting for network interfaces..."

net_ready=0
for i in $(seq 1 10); do
    if network_ready; then
        net_ready=1
        log "INFO: network check $i/10: $iface_count interfaces up; $required required"
        while IFS= read -r iface; do
            [[ -n "$iface" ]] && log "INFO: interface $iface is up"
        done <<< "$iface_list"
        break
    fi

    log "INFO: network check $i/10: $iface_count interfaces up; $required required"
    while IFS= read -r iface; do
        [[ -n "$iface" ]] && log "INFO: interface $iface is up"
    done <<< "$iface_list"

    sleep 5
done

if ((net_ready)); then
    log "INFO: Network ready"
else
    log "ERROR: $iface_count interfaces up; at least $required required -abort"
    exit 1
fi

# ------------------------------------------------------------------------------
# SERVERS
# ------------------------------------------------------------------------------

# Start the configured server services
service_failures=()
run_service_action() {
    local action="$1"
    shift
    if ! systemctl "$action" "$@"; then
        local failure="$* $action failed"
        log "WARNING: $failure -alert"
        service_failures+=("$failure")
    fi
}

log "EVENT: Reloading pydhcpd.service..."
run_service_action reload pydhcpd.service
sleep 5
log "EVENT: Reloading squid.service..."
run_service_action reload squid.service
sleep 5
log "EVENT: Restarting apache2.service..."
run_service_action restart apache2.service
sleep 5
if systemctl list-unit-files smbd.service &>/dev/null; then
    log "EVENT: Restarting smbd.service..."
    run_service_action restart smbd.service
    sleep 5
fi
if systemctl list-unit-files winbind.service &>/dev/null; then
    log "EVENT: Restarting winbind.service..."
    run_service_action restart winbind.service
    sleep 5
fi
log "EVENT: Restarting syslog.socket and rsyslog.service..."
run_service_action restart syslog.socket rsyslog.service
sleep 5

if (( ${#service_failures[@]} > 0 )); then
    log "ERROR: ${#service_failures[@]} service action(s) failed -abort"
    exit 1
fi

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

log "EVENT: serverboot done"
