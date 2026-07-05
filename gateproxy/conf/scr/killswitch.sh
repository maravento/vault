#!/bin/bash
# maravento.com
#
################################################################################
#
# Iptables Kill Switch
#
# Warning
# Use it only in case of attack or illegal access to your network
#
# NOTE on logging:
# - killswitch.sh belongs to the iptables ruleset — shares
#   /var/log/iptables.log with scr/iptables.sh (rotation is self-installed
#   there, /etc/logrotate.d/iptables).
#
################################################################################

# logging
log_file="/var/log/iptables.log"
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

# Verify: iptables -L -n / iptables -nvL / iptables -Ln -t mangle / iptables -Ln -t nat
# Ports: /etc/services
# check: https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt

# Start
log "killswitch start..."

### VARIABLES
# interfaces
wan="eth0"
lan="eth1"
# IP/Netmask
local="192.168.0.0"
netmask="24"
####################
### KERNEL RULES ###
####################
### Zero all packets and counters ###
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
### Global Policies IPv4
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP
### Global Policies IPv6
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT DROP
### Blackhole IPv4
ip route replace blackhole 0.0.0.0/0 2>/dev/null || true
### Blackhole IPv6
ip -6 route replace blackhole ::/0 2>/dev/null || true
### Flush conntrack (existing connections bypass DROP policies)
conntrack -F 2>/dev/null || true

# End
log "killswitch done at: $(date)"
