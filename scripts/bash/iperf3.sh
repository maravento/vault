#!/bin/bash
# maravento.com
#
################################################################################
#
# iperf3 LAN Performance Test
# FILE: iperf3.sh
#
# DESCRIPTION: Interactive LAN throughput and latency tester (ping/TCP/UDP).
# Prompts for the local interface, target server IPs, duration and
# parallel streams; the iperf3 server must already be running on each
# target. Not run as root.
#
# USAGE: ./iperf3.sh
#
# OUTPUT: logs saved under ./iperf3_logs/
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# validation -- one variable per thing validated; use directly with =~
UH_IPV4='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'
UH_UINT='^(0|[1-9][0-9]*)$'

# no-root check
if [ "$(id -u)" == "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script should not be run as root -abort" >&2
    exit 1
fi

# dependencies
for dep in iperf3 iputils-ping iproute2 coreutils; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

# CONFIGURATION
# Test parameters and log path, meant to be edited by the user
DURATION=30
PARALLEL=4
PING_COUNT=5
LOG_DIR="./iperf3_logs"
IPERF_CMD=""
IPERF_PORT=""

# COLORS
# Escape codes used by the output helpers
RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
BLU='\033[1;34m'
CYN='\033[0;36m'
NC='\033[0m'

trap 'echo -e "\n${YLW}WARNING:${NC} Interrupted. Logs saved to: $LOG_DIR/"; exit 130' INT TERM

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

# OUTPUT HELPERS
# Single place for the colored ERROR, INFO, [OK], WARNING and header lines
die() { echo -e "${RED}ERROR:${NC} $*" >&2; exit 1; }
info() { echo -e "${BLU}INFO:${NC} $*"; }
ok() { echo -e "${GRN}[OK]${NC} $*"; }
warn() { echo -e "${YLW}WARNING:${NC} $*"; }
hdr() { echo -e "\n${CYN}--------------------------------------------------${NC}"; \
         echo -e "${CYN} $*${NC}"; \
         echo -e "${CYN}--------------------------------------------------${NC}"; }

# INTERFACES
# Lists the interfaces that are up, loopback excluded
get_interfaces() {
    ip -o link show up | awk -F': ' '{print $2}' | grep -v '^lo$'
}

# VALIDATE IP
# Matches a string against the IPv4 pattern
validate_ip() {
    local ip="$1"
    [[ "$ip" =~ $UH_IPV4 ]]
}

# SANITIZE LABEL
# Turns an address into a string safe for a log filename
sanitize_label() {
    local raw="$1"
    echo "$raw" | tr -cs '[:alnum:]_.-' '_' | sed 's/^_//;s/_$//'
}

# DETECT IPERF
# Finds whether the target answers on the iperf3 or the iperf port
detect_iperf() {
    local ip="$1"

    if timeout 2 bash -c "echo > /dev/tcp/$ip/5201" 2>/dev/null; then
        IPERF_CMD="iperf3"
        IPERF_PORT=5201
        return 0
    fi

    if timeout 2 bash -c "echo > /dev/tcp/$ip/5001" 2>/dev/null; then
        warn "Host $ip has iperf v2 listening on port 5001, but this script requires iperf3 (port 5201)"
        warn "Start iperf3 on server with: iperf3 -s"
        return 1
    fi

    return 1
}

# LATENCY TEST
# Pings the target and appends the result to the log
run_ping() {
    local ip="$1"
    local log="$2"
    echo "" >> "$log"
    echo "$(date '+%Y-%m-%d %H:%M:%S') STATUS: latency test (ping ${PING_COUNT})" >> "$log"
    ping -c "$PING_COUNT" -i 0.5 "$ip" 2>&1 | tee -a "$log"
}

# TCP UPLOAD
# Measures upload throughput, retrying without --bind-dev on failure
run_iperf3_tcp() {
    local ip="$1"
    local iface="$2"
    local log="$3"
    echo "" >> "$log"
    echo "$(date '+%Y-%m-%d %H:%M:%S') STATUS: iperf TCP test (${PARALLEL} streams)" >> "$log"
    if ! $IPERF_CMD -c "$ip" -p "$IPERF_PORT" -t "$DURATION" -P "$PARALLEL" \
            --bind-dev "$iface" 2>&1 | tee -a "$log"; then
        $IPERF_CMD -c "$ip" -p "$IPERF_PORT" -t "$DURATION" -P "$PARALLEL" \
            2>&1 | tee -a "$log"
    fi
}

# UDP TEST
# Measures UDP throughput, skipped when only iperf is available
run_iperf3_udp() {
    local ip="$1"
    local iface="$2"
    local log="$3"
    echo "" >> "$log"
    if [[ "$IPERF_CMD" != "iperf3" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') STATUS: iperf UDP skipped; iperf3 unavailable" >> "$log"
        return 0
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') STATUS: iperf UDP test" >> "$log"
    if ! iperf3 -c "$ip" -p "$IPERF_PORT" -u -b 1G -t "$DURATION" \
            --bind-dev "$iface" 2>&1 | tee -a "$log"; then
        iperf3 -c "$ip" -p "$IPERF_PORT" -u -b 1G -t "$DURATION" \
            2>&1 | tee -a "$log"
    fi
}

# TCP DOWNLOAD
# Measures download throughput with iperf3 in reverse mode
run_iperf3_reverse() {
    local ip="$1"
    local iface="$2"
    local log="$3"
    echo "" >> "$log"
    if [[ "$IPERF_CMD" != "iperf3" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') STATUS: iperf TCP reverse skipped" >> "$log"
        return 0
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') STATUS: iperf TCP reverse test" >> "$log"
    if ! $IPERF_CMD -c "$ip" -p "$IPERF_PORT" -t "$DURATION" -P "$PARALLEL" \
            -R --bind-dev "$iface" 2>&1 | tee -a "$log"; then
        $IPERF_CMD -c "$ip" -p "$IPERF_PORT" -t "$DURATION" -P "$PARALLEL" \
            -R 2>&1 | tee -a "$log"
    fi
}

# RUN TESTS
# Runs latency, upload, download and UDP against one target
run_tests() {
    local ip="$1"
    local iface="$2"
    local label="$3"
    local log="$LOG_DIR/${label}_$(date +%Y%m%d_%H%M%S).log"

    hdr "Test: $label | Interface: $iface | Server: $ip"
    {
        echo "Server: $ip"
        echo "Local Interface: $iface"
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Test Duration: ${DURATION}s"
        echo "Parallel Streams: $PARALLEL"
    } | tee "$log"

    run_ping "$ip" "$log"
    run_iperf3_tcp "$ip" "$iface" "$log"
    run_iperf3_reverse "$ip" "$iface" "$log"
    run_iperf3_udp "$ip" "$iface" "$log"

    echo ""
    ok "Log saved to: $log"
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

main() {
    mkdir -p "$LOG_DIR"

    hdr "iperf3 LAN Performance Test"

    echo ""
    info "Active local interfaces:"
    mapfile -t IFACES < <(get_interfaces)

    if [[ ${#IFACES[@]} -eq 0 ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no active network interfaces -abort" >&2
        exit 1
    fi

    for i in "${!IFACES[@]}"; do
        echo "[$((i+1))] ${IFACES[$i]}"
    done
    echo ""

    read -rp "Select interface [1-${#IFACES[@]}] (Enter = ${IFACES[0]}): " iface_idx
    if [[ -z "$iface_idx" ]]; then
        IFACE="${IFACES[0]}"
    elif [[ "$iface_idx" =~ $UH_UINT ]] \
         && [ "${#iface_idx}" -le 5 ] \
         && [ "$iface_idx" -ge 1 ] && [ "$iface_idx" -le "${#IFACES[@]}" ]; then
        IFACE="${IFACES[$((iface_idx-1))]}"
    else
        die "Invalid selection"
    fi
    ok "Interface selected: $IFACE"

    echo ""
    info "Enter target server IPs. Empty line to finish:"
    echo ""

    declare -a TARGET_IPS

    while true; do
        read -rp " Server IP: " t_ip
        [[ -z "$t_ip" ]] && break

        if ! validate_ip "$t_ip"; then
            warn "Invalid IP: '$t_ip'. Try again"
            continue
        fi

        TARGET_IPS+=("$t_ip")
        ok "Added: $t_ip"
    done

    if [[ ${#TARGET_IPS[@]} -eq 0 ]]; then
        die "No server entered."
    fi

    echo ""
    read -rp "Test duration in seconds [${DURATION}]: " dur_input
    if [[ "$dur_input" =~ $UH_UINT ]]; then
        if [ "${#dur_input}" -gt 3 ] || [ "$dur_input" -gt 300 ]; then
            warn "Duration capped at 300s"
            DURATION=300
        elif [ "$dur_input" -lt 5 ]; then
            warn "Duration too low; using minimum of 5s"
            DURATION=5
        else
            DURATION="$dur_input"
        fi
    fi

    read -rp "Parallel TCP streams [${PARALLEL}]: " par_input
    if [[ "$par_input" =~ $UH_UINT ]]; then
        if [ "${#par_input}" -gt 2 ] || [ "$par_input" -gt 64 ]; then
            warn "Streams capped at 64"
            PARALLEL=64
        elif [ "$par_input" -lt 1 ]; then
            warn "Streams must be at least 1; using 1"
            PARALLEL=1
        else
            PARALLEL="$par_input"
        fi
    fi

    for ip in "${TARGET_IPS[@]}"; do
        local label
        label="$(sanitize_label "$ip")"

        echo ""
        echo "$(date '+%Y-%m-%d %H:%M:%S') Verifying connectivity with $ip..."
        if ! ping -c 2 -W 2 "$ip" &>/dev/null; then
            warn "No response from $ip. Skipping"
            continue
        fi
        ok "Host $ip reachable"

        echo "$(date '+%Y-%m-%d %H:%M:%S') Checking iperf on $ip..."

        if ! detect_iperf "$ip"; then
            warn "No iperf server detected on $ip. Skipping"
            continue
        fi

        ok "Using $IPERF_CMD on port $IPERF_PORT"

        run_tests "$ip" "$IFACE" "$label"
    done

    hdr "All tests completed"
    info "Logs saved to: $LOG_DIR/"
    ls -lh "$LOG_DIR/"
}

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') iperf3 start..."

main "$@"

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') iperf3 done at: $(date '+%Y-%m-%d %H:%M:%S')"
