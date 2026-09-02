#!/bin/bash
# maravento.com
#
################################################################################
#
# CPU Limit (start / stop / status)
#
################################################################################

set -uo pipefail

## root check
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root -- abort"
    exit 1
fi

echo "CPU limit Starting. Wait..."

# DEPENDENCIES
for dep in cpulimit procps util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "ERROR: dependency '$dep' is not installed -- abort" >&2
        exit 1
    fi
done

# VALIDATION -- integer only; use directly with =~
_UH_UINT='^(0|[1-9][0-9]*)$'
start_limit() {
    # prevent overlapping runs
    SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
    (umask 077; : >> "$SCRIPT_LOCK")
    exec 200>"$SCRIPT_LOCK"
    if ! flock -n 200; then
        echo "ERROR: script $(basename "$0") is already running -- abort"
        exit 1
    fi

    echo "Running processes:"
    ps -eo pid,comm --no-headers | grep -v kworker | sort -k2 | awk '{printf " PID: %-8s %s\n", $1, $2}'
    echo ""
    # program name:
    read -r -p "Enter the program name: " program_name

    if [ -z "$program_name" ]; then
        echo "ERROR: Program name cannot be empty."
        exit 1
    fi

    # Sanitize program name to prevent regex abuse
    if [[ "$program_name" =~ [^a-zA-Z0-9_\-\.] ]]; then
        echo "Invalid program name: only alphanumeric characters, hyphens, underscores and dots are allowed."
        exit 1
    fi

    # Verify process exists
    if ! pgrep -f "$program_name" &>/dev/null; then
        echo "No running process found for '$program_name'."
        exit 1
    fi

    pid_count=$(pgrep -f "$program_name" | wc -l)
    echo "Found $pid_count process(es) matching '$program_name'."

    # CPU %
    read -r -p "Enter the CPU % number for '$program_name' (0-100): " cpu_limit

    # Check CPU %
    if ! [[ "$cpu_limit" =~ $_UH_UINT ]] || [ "$cpu_limit" -lt 0 ] || [ "$cpu_limit" -gt 100 ]; then
        echo "Invalid percentage. It must be a number between 0 and 100"
        exit 1
    fi

    # Apply cpulimit to each matching PID
    >> /run/cpulimit_managed.pid
    while IFS= read -r pid; do
        cpulimit -l "$cpu_limit" -p "$pid" >/dev/null 200>&- &
        cpulimit_pid=$!
        echo "$cpulimit_pid" >> /run/cpulimit_managed.pid
        echo "$cpu_limit% CPU limit applied to '$program_name' (PID: $pid, cpulimit PID: $cpulimit_pid)"
    done < <(pgrep -f "$program_name")
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
            echo "CPU Limit active, but cannot determine the associated process"
        fi
    done < <(pgrep -ax "cpulimit")
}

stop_limit() {
    if [ -f /run/cpulimit_managed.pid ]; then
        while IFS= read -r saved_pid; do
            if kill -0 "$saved_pid" 2>/dev/null; then
                kill "$saved_pid"
            fi
        done < /run/cpulimit_managed.pid
        rm -f /run/cpulimit_managed.pid
    else
        pkill -x "cpulimit" 2>/dev/null || true
    fi
    pkill -x "cpulimit" 2>/dev/null || true
    echo "All CPU Limit have been stopped"
}

# start|stop|status

case "${1:-}" in
    start)
        start_limit
        ;;
    stop)
        stop_limit
        ;;
    status)
        status_limit
        ;;
    *)
        echo "Uso: $0 {start|stop|status}"
        exit 1
        ;;
esac

exit 0
