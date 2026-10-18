#!/bin/bash
# maravento.com
#
################################################################################
#
# Iptables Kill Switch
#
# USAGE:
# sudo ./killswitch.sh
#
# LOG: /var/log/iptables.log, shared with scr/iptables.sh
#      Rotation is self-installed there, /etc/logrotate.d/iptables
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
log_file="/var/log/iptables.log"
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

# dependencies
for dep in iptables iproute2 conntrack util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: dependency '$dep' is not installed -abort"
        exit 1
    fi
done

# Start
log "killswitch start..."

# ------------------------------------------------------------------------------
# KERNEL RULES
# ------------------------------------------------------------------------------

# Zero all packets and counters
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -t raw -F
iptables -t raw -X
iptables -t security -F
iptables -t security -X
iptables -Z
iptables -t nat -Z
iptables -t mangle -Z
# Global Policies IPv4
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP
# Global Policies IPv6
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT DROP
# Blackhole IPv4
ip route replace blackhole 0.0.0.0/0 2>/dev/null || true
# Blackhole IPv6
ip -6 route replace blackhole ::/0 2>/dev/null || true
# Flush conntrack (existing connections bypass DROP policies)
conntrack -F 2>/dev/null || true

# End
log "killswitch done at: $(date '+%Y-%m-%d %H:%M:%S')"
