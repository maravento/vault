#!/bin/bash
# maravento.com
#
################################################################################
#
# CPU Limit (start / stop / status)
#
################################################################################

echo "CPU limit Starting. Wait..."
printf "\n"

## root check
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

set -uo pipefail

# check dependencies
pkgs='cpulimit'
missing=$(for p in $pkgs; do dpkg -s "$p" &>/dev/null || echo "$p"; done | xargs)
unavailable=""
for p in $missing; do
    apt-cache show "$p" &>/dev/null || unavailable+=" $p"
done
if [ -n "$unavailable" ]; then
    echo "❌ Missing dependencies not found in APT:"
    for u in $unavailable; do echo "   - $u"; done
    echo "💡 Please install them manually or enable the required repositories."
    exit 1
fi
if [ -n "$missing" ]; then
    echo "🔧 Releasing APT/DPKG locks..."
    rm -f /var/lib/apt/lists/lock
    rm -f /var/cache/apt/archives/lock
    rm -f /var/lib/dpkg/lock
    rm -f /var/lib/dpkg/lock-frontend
    dpkg --configure -a
    echo "📦 Installing: $missing"
    apt-get -qq update
    if ! apt-get -y install $missing; then
        echo "❌ Error installing: $missing"
        exit 1
    fi
else
    echo "✅ Dependencies OK"
fi

start_limit() {
    echo "Running processes:"
    ps -eo pid,comm --no-headers | grep -v kworker | sort -k2 | awk '{printf "  PID: %-8s %s\n", $1, $2}'
    echo ""
    # program name:
    read -p "Enter the program name: " program_name

    # Verify process exists
    if ! pgrep -f "$program_name" &>/dev/null; then
        echo "❌ No running process found for '$program_name'."
        exit 1
    fi

    pid_count=$(pgrep -f "$program_name" | wc -l)
    echo "✅ Found $pid_count process(es) matching '$program_name'."

    # CPU %
    read -p "Enter the CPU % number for '$program_name' (0-100): " cpu_limit

    # Check CPU %
    if ! [[ "$cpu_limit" =~ ^[0-9]+$ ]] || [ "$cpu_limit" -lt 0 ] || [ "$cpu_limit" -gt 100 ]; then
        echo "Invalid percentage. It must be a number between 0 and 100"
        exit 1
    fi

    # Apply cpulimit to each matching PID
    > /var/run/cpulimit_managed.pid
    while IFS= read -r pid; do
        cpulimit -l "$cpu_limit" -p "$pid" >/dev/null &
        cpulimit_pid=$!
        echo "$cpulimit_pid" >> /var/run/cpulimit_managed.pid
        echo "✅ $cpu_limit% CPU limit applied to '$program_name' (PID: $pid, cpulimit PID: $cpulimit_pid)"
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
    if [ -f /var/run/cpulimit_managed.pid ]; then
        saved_pid=$(cat /var/run/cpulimit_managed.pid)
        if kill -0 "$saved_pid" 2>/dev/null; then
            kill "$saved_pid"
        fi
        rm -f /var/run/cpulimit_managed.pid
    else
        pkill -x "cpulimit" 2>/dev/null || true
    fi
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
