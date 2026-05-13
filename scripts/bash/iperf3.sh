#!/bin/bash
# maravento.com
#
################################################################################
#
# iperf3 LAN Performance Test
# Description:  Interactive LAN throughput and latency tester (TCP/UDP/ping)
#
# Usage:        ./iperf3.sh
# Requirements: iperf3 (client and server)
#
# Before running, start the iperf3 server on each target host:
#               iperf3 -s
#
# Tests performed per target:
#   - Latency      ping (5 packets, configurable via PING_COUNT)
#   - TCP upload   iperf3 (configurable streams and duration)
#   - TCP download iperf3 reverse mode
#   - UDP          iperf3 (1 Gbps target)
#
# Output: logs saved to ./iperf3_logs/
#
################################################################################

set -uo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────
DURATION=30
PARALLEL=4
PING_COUNT=5
LOG_DIR="./iperf3_logs"
IPERF_CMD=""
IPERF_PORT=""
# ────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
BLU='\033[1;34m'
CYN='\033[0;36m'
NC='\033[0m'

trap 'echo -e "\n${YLW}[WARN]${NC}  Interrupted. Logs saved to: $LOG_DIR/"; exit 130' INT TERM

die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
info() { echo -e "${BLU}[INFO]${NC}  $*"; }
ok()   { echo -e "${GRN}[OK]${NC}    $*"; }
warn() { echo -e "${YLW}[WARN]${NC}  $*"; }
hdr()  { echo -e "\n${CYN}══════════════════════════════════════════════════${NC}"; \
         echo -e "${CYN}  $*${NC}"; \
         echo -e "${CYN}══════════════════════════════════════════════════${NC}"; }

# ─── Dependencies ───────────────────────────────────────────────────────────
check_deps() {
    command -v iperf3 &>/dev/null || die "iperf3 not found. Install with: sudo apt install iperf3"
}

# ─── Detect active local interfaces ─────────────────────────────────────────
get_interfaces() {
    ip -o link show up | awk -F': ' '{print $2}' | grep -v '^lo$'
}

# ─── Validate IP ─────────────────────────────────────────────────────────────
validate_ip() {
    local ip="$1"
    local pattern='^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
    [[ "$ip" =~ $pattern ]]
}

# ─── Sanitize IP for safe use in filenames ───────────────────────────────────
sanitize_label() {
    local raw="$1"
    echo "$raw" | tr -cs '[:alnum:]_.-' '_' | sed 's/^_//;s/_$//'
}

# ─── Detect if iperf3 is listening on target port ────────────────────────────
detect_iperf() {
    local ip="$1"

    if timeout 2 bash -c "echo > /dev/tcp/$ip/5201" 2>/dev/null; then
        IPERF_CMD="iperf3"
        IPERF_PORT=5201
        return 0
    fi

    if timeout 2 bash -c "echo > /dev/tcp/$ip/5001" 2>/dev/null; then
        warn "Host $ip has iperf v2 listening on port 5001, but this script requires iperf3 (port 5201)."
        warn "Start iperf3 on the server with: iperf3 -s"
        return 1
    fi

    return 1
}

# ─── Latency test (ping) ─────────────────────────────────────────────────────
run_ping() {
    local ip="$1"
    local log="$2"
    echo "" >> "$log"
    echo "── Latency (ping ${PING_COUNT} packets) ──────────────────" >> "$log"
    ping -c "$PING_COUNT" -i 0.5 "$ip" 2>&1 | tee -a "$log"
}

# ─── iperf TCP upload test ───────────────────────────────────────────────────
run_iperf3_tcp() {
    local ip="$1"
    local iface="$2"
    local log="$3"
    echo "" >> "$log"
    echo "── iperf TCP ($PARALLEL streams, ${DURATION}s) ──────────────────" >> "$log"
    if ! $IPERF_CMD -c "$ip" -p "$IPERF_PORT" -t "$DURATION" -P "$PARALLEL" \
            --bind-dev "$iface" 2>&1 | tee -a "$log"; then
        $IPERF_CMD -c "$ip" -p "$IPERF_PORT" -t "$DURATION" -P "$PARALLEL" \
            2>&1 | tee -a "$log"
    fi
}

# ─── iperf UDP test (iperf3 only) ────────────────────────────────────────────
run_iperf3_udp() {
    local ip="$1"
    local iface="$2"
    local log="$3"
    echo "" >> "$log"
    if [[ "$IPERF_CMD" != "iperf3" ]]; then
        echo "── iperf UDP: skipped (requires iperf3, detected $IPERF_CMD) ────" >> "$log"
        return 0
    fi
    echo "── iperf3 UDP (1 Gbps target, ${DURATION}s) ─────────────────────" >> "$log"
    if ! iperf3 -c "$ip" -p "$IPERF_PORT" -u -b 1G -t "$DURATION" \
            --bind-dev "$iface" 2>&1 | tee -a "$log"; then
        iperf3 -c "$ip" -p "$IPERF_PORT" -u -b 1G -t "$DURATION" \
            2>&1 | tee -a "$log"
    fi
}

# ─── iperf TCP download test (reverse) ──────────────────────────────────────
run_iperf3_reverse() {
    local ip="$1"
    local iface="$2"
    local log="$3"
    echo "" >> "$log"
    if [[ "$IPERF_CMD" != "iperf3" ]]; then
        echo "── iperf TCP Reverse: skipped (requires iperf3, detected $IPERF_CMD) ──" >> "$log"
        return 0
    fi
    echo "── iperf3 TCP Reverse - download ($PARALLEL streams, ${DURATION}s) ──" >> "$log"
    if ! $IPERF_CMD -c "$ip" -p "$IPERF_PORT" -t "$DURATION" -P "$PARALLEL" \
            -R --bind-dev "$iface" 2>&1 | tee -a "$log"; then
        $IPERF_CMD -c "$ip" -p "$IPERF_PORT" -t "$DURATION" -P "$PARALLEL" \
            -R 2>&1 | tee -a "$log"
    fi
}

# ─── Run complete test per target ────────────────────────────────────────────
run_tests() {
    local ip="$1"
    local iface="$2"
    local label="$3"
    local log="$LOG_DIR/${label}_$(date +%Y%m%d_%H%M%S).log"

    hdr "Test: $label | Interface: $iface | Server: $ip"
    {
        echo "Server: $ip"
        echo "Local Interface: $iface"
        echo "Date: $(date)"
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

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
    check_deps
    mkdir -p "$LOG_DIR"

    hdr "iperf3 LAN Performance Test"

    echo ""
    info "Active local interfaces:"
    mapfile -t IFACES < <(get_interfaces)

    if [[ ${#IFACES[@]} -eq 0 ]]; then
        die "No active network interfaces found (excluding loopback)."
    fi

    for i in "${!IFACES[@]}"; do
        echo "  [$((i+1))] ${IFACES[$i]}"
    done
    echo ""

    read -rp "Select interface [1-${#IFACES[@]}] (Enter = ${IFACES[0]}): " iface_idx
    if [[ -z "$iface_idx" ]]; then
        IFACE="${IFACES[0]}"
    elif [[ "$iface_idx" =~ ^[0-9]+$ ]] && (( iface_idx >= 1 && iface_idx <= ${#IFACES[@]} )); then
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
        read -rp "  Server IP: " t_ip
        [[ -z "$t_ip" ]] && break

        if ! validate_ip "$t_ip"; then
            warn "Invalid IP: '$t_ip'. Try again."
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
    if [[ "$dur_input" =~ ^[0-9]+$ ]]; then
        if (( dur_input < 5 )); then
            warn "Duration too low; using minimum of 5s."
            DURATION=5
        elif (( dur_input > 300 )); then
            warn "Duration capped at 300s."
            DURATION=300
        else
            DURATION="$dur_input"
        fi
    fi

    read -rp "Parallel TCP streams [${PARALLEL}]: " par_input
    if [[ "$par_input" =~ ^[0-9]+$ ]]; then
        if (( par_input < 1 )); then
            warn "Streams must be at least 1; using 1."
            PARALLEL=1
        elif (( par_input > 64 )); then
            warn "Streams capped at 64."
            PARALLEL=64
        else
            PARALLEL="$par_input"
        fi
    fi

    for ip in "${TARGET_IPS[@]}"; do
        local label
        label="$(sanitize_label "$ip")"

        echo ""
        info "Verifying connectivity with $ip..."
        if ! ping -c 2 -W 2 "$ip" &>/dev/null; then
            warn "No response from $ip. Skipping."
            continue
        fi
        ok "Host $ip reachable"

        info "Checking iperf on $ip..."

        if ! detect_iperf "$ip"; then
            warn "No iperf server detected on $ip. Skipping."
            continue
        fi

        ok "Using $IPERF_CMD on port $IPERF_PORT"

        run_tests "$ip" "$IFACE" "$label"
    done

    hdr "All tests completed"
    info "Logs saved to: $LOG_DIR/"
    ls -lh "$LOG_DIR/"
}

main "$@"
