#!/bin/bash
# maravento.com
#
################################################################################
#
# CPU Limit (start / stop / status)
# FILE: cpulimit.sh
#
# DESCRIPTION: Caps the CPU usage of a program with cpulimit. Asks for the
# program name and the percentage to allow.
#
# USAGE:
# COMMAND                         ACTION
# sudo bash cpulimit.sh --start   Start
# sudo bash cpulimit.sh --stop    Stop
# sudo bash cpulimit.sh --status  Show status
#
################################################################################

set -uo pipefail

# root check
if [ "$(id -u)" -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# awk is a command, not a package: check it before its first use
command -v awk >/dev/null 2>&1 || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: awk not found -abort" >&2; exit 1; }

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
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: waiting for an interface with IPv4..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no interface with IPv4 -abort" >&2
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
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: waiting for internet..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no internet connection -abort" >&2
    exit 1
}

# dependencies
net_checked=0
for dep in cpulimit procps util-linux iproute2 libc-bin coreutils grep; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep" 2>/dev/null)" != *"ok installed"* ]]; then
        if [ "$net_checked" -eq 0 ]; then
            if ! command -v ip >/dev/null 2>&1; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: installing iproute2"
                apt-get install -y iproute2 >/dev/null 2>&1 || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install iproute2 -abort" >&2; exit 1; }
                # the download proves link and internet; only IPv4 is left to check
                check_ipv4_interfaces
            else
                check_ipv4_interfaces
                check_internet
            fi
            apt-get update -qq || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot update package lists -abort" >&2; exit 1; }
            net_checked=1
        fi
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: installing $dep"
        if ! apt-get install -y "$dep" >/dev/null 2>&1; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install $dep -abort" >&2
            exit 1
        fi
    fi
done

# validation - integer only; use directly with =~
UH_UINT='^(0|[1-9][0-9]*)$'

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

# Confirms the PID still belongs to cpulimit: the PID file can outlive its
# process and the number may have been reused by an unrelated program.
_pid_is_cpulimit() {
    local pid="$1"
    [[ -n "$pid" && "$pid" =~ $UH_UINT ]] || return 1
    [[ "$(cat "/proc/$pid/comm" 2>/dev/null)" == "cpulimit" ]]
}
start_limit() {
    # prevent overlapping runs
    script_lock="/var/lock/$(basename "$0" .sh).lock"
    (umask 077; : >> "$script_lock")
    exec 200>"$script_lock"
    if ! flock -n 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: script $(basename "$0") is already running -abort" >&2
        exit 1
    fi

    echo "Running processes:"
    ps -eo pid,comm --no-headers | grep -v kworker | sort -k2 | awk '{printf " PID: %-8s %s\n", $1, $2}'
    echo ""
    # program name:
    read -r -p "Enter the program name: " program_name

    if [ -z "$program_name" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: program name cannot be empty -abort" >&2
        exit 1
    fi

    # Sanitize program name to prevent regex abuse
    if [[ "$program_name" =~ [^a-zA-Z0-9_.-] ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: invalid program name; use letters, digits, ._- -abort" >&2
        exit 1
    fi
    # A dot must match a dot, not any character
    program_re="${program_name//./\\.}"

    # Verify process exists
    if ! pgrep -f "^(/[^[:space:]]*/)?$program_re([[:space:]]|$)" &>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no running process for '$program_name' -abort" >&2
        exit 1
    fi

    pid_count=$(pgrep -f "^(/[^[:space:]]*/)?$program_re([[:space:]]|$)" | wc -l)
    echo "Found $pid_count process(es) matching '$program_name'"

    # CPU %
    read -r -p "Enter the CPU % number for '$program_name' (1-100): " cpu_limit

    # Check CPU %
    if ! [[ "$cpu_limit" =~ $UH_UINT ]] || [ "${#cpu_limit}" -gt 3 ] \
        || [ "$cpu_limit" -lt 1 ] || [ "$cpu_limit" -gt 100 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: invalid CPU percentage; use 1-100 -abort" >&2
        exit 1
    fi

    # Apply cpulimit to each matching PID
    >> /run/cpulimit_managed.pid
    while IFS= read -r pid; do
        cpulimit -l "$cpu_limit" -p "$pid" >/dev/null 200>&- &
        cpulimit_pid=$!
        echo "$cpulimit_pid" >> /run/cpulimit_managed.pid
        echo "$cpu_limit% CPU limit applied to '$program_name' (PID: $pid, cpulimit PID: $cpulimit_pid)"
    done < <(pgrep -f "^(/[^[:space:]]*/)?$program_re([[:space:]]|$)")
}

status_limit() {
    if ! pgrep -x "cpulimit" >/dev/null; then
        echo "No CPU Limit is currently active"
        return
    fi
    while IFS= read -r line; do
        target_pid=$(echo "$line" | grep -oP '(?<=-p )\d+')
        if [ -n "$target_pid" ]; then
            process=$(ps -p "$target_pid" -o comm= 2>/dev/null || echo "unknown")
            echo "CPU Limit active over PID $target_pid ($process)"
        else
            echo "CPU Limit active, but cannot determine associated process"
        fi
    done < <(pgrep -ax "cpulimit")
}

stop_limit() {
    if [ -f /run/cpulimit_managed.pid ]; then
        while IFS= read -r saved_pid; do
            if _pid_is_cpulimit "$saved_pid"; then
                kill "$saved_pid" 2>/dev/null || true
            fi
        done < /run/cpulimit_managed.pid
    fi
    pkill -x "cpulimit" 2>/dev/null || true
    sleep 1
    local rc
    pgrep -x "cpulimit" >/dev/null 2>&1
    rc=$?
    case "$rc" in
        1)
            rm -f /run/cpulimit_managed.pid
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: all cpulimit processes stopped"
            ;;
        0)
            echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: cpulimit still running -alert" >&2
            return 1
            ;;
        *)
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot verify cpulimit -abort" >&2
            return 1
            ;;
    esac
}

# ------------------------------------------------------------------------------
# ACTIONS
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: cpulimit start..."

# start|stop|status

case "${1:-}" in
    --start)
        start_limit
        ;;
    --stop)
        stop_limit || exit 1
        ;;
    --status)
        status_limit
        ;;
    *)
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: invalid option -abort" >&2
        echo "Usage: $0 {--start|--stop|--status}"
        exit 1
        ;;
esac

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: cpulimit done"

exit 0
