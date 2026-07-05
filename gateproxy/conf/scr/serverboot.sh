#!/bin/bash
# maravento.com
#
################################################################################
#
# Server Boot
#
################################################################################

# logging
log_file="/var/log/serverboot.log"
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
(umask 077; : >> "$SCRIPT_LOCK")
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    log "Script $(basename "$0") is already running"
    exit 1
fi

log "===================================================="
log "serverboot start.."

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

log "Waiting for network interfaces..."

net_ready=0
for i in $(seq 1 10); do
    if network_ready; then
        net_ready=1
        log "Attempt $i/10: $iface_count interface(s) UP (required $required) - READY"
        while IFS= read -r iface; do
            [[ -n "$iface" ]] && log "$iface"
        done <<< "$iface_list"
        break
    fi

    log "Attempt $i/10: $iface_count interface(s) UP (required $required) - waiting..."
    while IFS= read -r iface; do
        [[ -n "$iface" ]] && log "$iface"
    done <<< "$iface_list"

    sleep 5
done

if ((net_ready)); then
    log "Network ready."
else
    log "WARNING: network not ready after 10 retries ($iface_count/$required interfaces UP) - aborting serverboot"
    while IFS= read -r iface; do
        [[ -n "$iface" ]] && log "$iface"
    done <<< "$iface_list"
    exit 1
fi

### SERVERS
log "DHCP..."
systemctl reload pydhcpd.service
sleep 5
log "Squid Reload..."
systemctl reload squid.service
sleep 5
log "Apache2 Restart..."
systemctl restart apache2.service
sleep 5
log "Samba Restart..."
systemctl restart smbd.service
sleep 5
log "Winbind Reload..."
systemctl restart winbind.service
sleep 5
log "Rsyslog Reload..."
systemctl restart syslog.socket rsyslog.service
sleep 5

log "Server Start (firewall/ACL sequence)..."
if [[ -d /etc/uhotspot ]]; then
    log "uhotspotd Restart..."
    if systemctl restart uhotspotd.service; then
        log "uhotspotd Restart: OK"
    else
        log "uhotspotd Restart: FAILED (check journalctl -u uhotspotd.service)"
    fi

    if [[ -x /etc/uhotspot/tools/uleases.sh && -x /etc/uhotspot/tools/uiptables.sh ]]; then
        if /etc/uhotspot/tools/uleases.sh; then
            log "Uleases Load: OK"
        else
            log "Uleases Load: FAILED (check /var/log/uhotspot.log)"
        fi

        if /etc/uhotspot/tools/uiptables.sh; then
            log "Firewall Load: OK"
        else
            log "Firewall Load: FAILED (check /var/log/uhotspot.log)"
        fi
    else
        log "WARNING: uleases.sh/uiptables.sh not found or not executable - firewall/ACL sequence skipped"
    fi
else
    log "WARNING: /etc/uhotspot not found - uhotspotd/firewall/ACL sequence skipped"
fi

log "serverboot done at: $(date)"
