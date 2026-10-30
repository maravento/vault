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

# no-root check
if [ "$(id -u)" == "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script should not be run as root -abort" >&2
    exit 1
fi

# dependencies
for dep in iperf3 iputils-ping iproute2 coreutils; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep" 2>/dev/null)" != *"ok installed"* ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

# validation -- one variable per thing validated; use directly with =~
UH_IPV4='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'
UH_UINT='^(0|[1-9][0-9]*)$'

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

trap 'printf "%s ${RED}ERROR:${NC} interrupted; logs in %s -abort\n" "$(date "+%Y-%m-%d %H:%M:%S")" "$LOG_DIR/" >&2; exit 130' INT TERM

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

# OUTPUT HELPERS
# Single place for the colored ERROR, INFO, [OK], WARNING and header lines
die() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${RED}ERROR:${NC} $* -abort" >&2; exit 1; }
info() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${BLU}INFO:${NC} $*"; }
ok() { echo -e "${GRN}[OK]${NC} $*"; }
warn() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${YLW}WARNING:${NC} $*"; }
hdr() { echo -e "\n${CYN}--------------------------------------------------${NC}"; \
         echo -e "${CYN} $*${NC}"; \
         echo -e "${CYN}--------------------------------------------------${NC}"; }

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

select_lan_interface() {
    local -a ifaces
    local i choice addrs
    mapfile -t ifaces < <(list_ipv4_ifaces)
    if [ "${#ifaces[@]}" -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no active interface with global IPv4 -abort" >&2
        return 1
    fi
    if [ "${#ifaces[@]}" -eq 1 ]; then
        lan_iface_answer="${ifaces[0]}"
        return 0
    fi
    echo "Available LAN interfaces:" >&2
    for i in "${!ifaces[@]}"; do
        addrs=$(ip -4 -o addr show dev "${ifaces[$i]}" scope global | awk '{print $4}' | paste -sd' ')
        printf ' [%d] %s (UP, %s)\n' "$((i+1))" "${ifaces[$i]}" "$addrs" >&2
    done
    while true; do
        read -r -p "Select LAN Interface [1-${#ifaces[@]}]: " choice || {
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot read LAN selection -abort" >&2
            return 1
        }
        if [[ "$choice" =~ $UH_UINT ]] && [ "${#choice}" -le 5 ] \
            && [ "$choice" -ge 1 ] && [ "$choice" -le "${#ifaces[@]}" ]; then
            lan_iface_answer="${ifaces[$((choice-1))]}"
            return 0
        fi
        info "invalid LAN selection -retry" >&2
    done
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
        warn "iperf v2 detected on $ip:5001"
        warn "start iperf3 -s on $ip:5201 -alert"
        return 1
    fi

    warn "cannot reach iperf3 at $ip:5201 -alert"
    return 1
}

# LATENCY TEST
# Pings the target and appends the result to the log
run_ping() {
    local ip="$1"
    local log="$2"
    echo "" >> "$log"
    echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: latency test (ping ${PING_COUNT})" >> "$log"
    ping -c "$PING_COUNT" -i 0.5 "$ip" 2>&1 | tee -a "$log"
}

# TCP UPLOAD
# Measures upload throughput, retrying without --bind-dev on failure
run_iperf3_tcp() {
    local ip="$1"
    local iface="$2"
    local log="$3"
    echo "" >> "$log"
    echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: iperf TCP test (${PARALLEL} streams)" >> "$log"
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
        echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: iperf UDP skipped; iperf3 unavailable" >> "$log"
        return 0
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: iperf UDP test" >> "$log"
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
        echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: iperf TCP reverse skipped" >> "$log"
        return 0
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: iperf TCP reverse test" >> "$log"
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

    select_lan_interface || exit 1
    IFACE="$lan_iface_answer"
    ok "Interface selected: $IFACE"

    echo ""
    echo "Enter target server IPs. Empty line to finish:"
    echo ""

    declare -a TARGET_IPS

    while true; do
        read -rp " Server IP: " t_ip
        [[ -z "$t_ip" ]] && break

        if ! [[ "$t_ip" =~ $UH_IPV4 ]]; then
            info "invalid server IPv4 -retry"
            continue
        fi

        TARGET_IPS+=("$t_ip")
        ok "Added: $t_ip"
    done

    if [[ ${#TARGET_IPS[@]} -eq 0 ]]; then
        die "no server entered"
    fi

    echo ""
    read -rp "Test duration in seconds [${DURATION}]: " dur_input
    if [[ "$dur_input" =~ $UH_UINT ]]; then
        if [ "${#dur_input}" -gt 3 ] || [ "$dur_input" -gt 300 ]; then
            info "duration capped at 300s -fixed"
            DURATION=300
        elif [ "$dur_input" -lt 5 ]; then
            info "duration raised to 5s -fixed"
            DURATION=5
        else
            DURATION="$dur_input"
        fi
    fi

    read -rp "Parallel TCP streams [${PARALLEL}]: " par_input
    if [[ "$par_input" =~ $UH_UINT ]]; then
        if [ "${#par_input}" -gt 2 ] || [ "$par_input" -gt 64 ]; then
            info "streams capped at 64 -fixed"
            PARALLEL=64
        elif [ "$par_input" -lt 1 ]; then
            info "streams raised to 1 -fixed"
            PARALLEL=1
        else
            PARALLEL="$par_input"
        fi
    fi

    for ip in "${TARGET_IPS[@]}"; do
        local label
        label="$(sanitize_label "$ip")"

        echo ""
        echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: checking connectivity to $ip..."
        if ! ping -c 2 -W 2 "$ip" &>/dev/null; then
            warn "no ping reply from $ip -alert"
            continue
        fi
        ok "Host $ip reachable"

        echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: Checking iperf on $ip..."

        if ! detect_iperf "$ip"; then
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
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: iperf3 start..."

main "$@"

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: iperf3 done"
