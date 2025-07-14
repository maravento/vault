#!/bin/bash
# maravento.com

# CPU Limit (start / stop / status)

echo "CPU limit Starting. Wait..."
printf "\n"

# check root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# check SO
UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
if [[ "$UBUNTU_ID" != "ubuntu" || ( "$UBUNTU_VERSION" != "22.04" && "$UBUNTU_VERSION" != "24.04" ) ]]; then
    echo "Unsupported system. Use at your own risk"
    # exit 1
fi

# check dependencies
pkgs='cpulimit'
missing=$(for p in $pkgs; do dpkg -s "$p" &>/dev/null || echo "$p"; done)
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
    echo "🔧 Releasing APT/DKPG locks..."
    killall -q apt apt-get dpkg 2>/dev/null
    rm -f /var/lib/apt/lists/lock
    rm -f /var/cache/apt/archives/lock
    rm -f /var/lib/dpkg/lock
    rm -f /var/lib/dpkg/lock-frontend
    rm -rf /var/lib/apt/lists/*
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
    # program name:
    read -p "Enter the program name: " program_name

    # PID capture
    pid=$(pgrep -f "$program_name")
    if [ -z "$pid" ]; then
        echo "PID was not found '$program_name'."
        exit 1
    fi

    # CPU %
    read -p "Enter the CPU % number for '$program_name' (0-100): " cpu_limit

    # Check CPU %
    if ! [[ "$cpu_limit" =~ ^[0-9]+$ ]] || [ "$cpu_limit" -lt 0 ] || [ "$cpu_limit" -gt 100 ]; then
        echo "Invalid percentage. It must be a number between 0 and 100"
        exit 1
    fi

    # Apply cpulimit to the program's PID
    cpulimit -l "$cpu_limit" -p "$pid" &
    echo "$cpu_limit% has been applied to the '$program_name' (PID: $pid)."
}

status_limit() {
  # Check CPU Limit
  if pgrep -x "cpulimit" >/dev/null; then
    # If PID check process
    if pgrep -ax "cpulimit" | awk '{print $1}' >/dev/null; then
      process=$(ps ho command --pid $(pgrep -ax "cpulimit" | awk '{print $6}'))
      echo "CPU Limit Active over $process"
    else
      echo "CPU Limit Active, but cannot get the associated process"
    fi
  else
    echo "No CPU Limit is currently active"
  fi
}

stop_limit() {
    # stop cpulimit
    pkill -x "cpulimit"
    echo "All CPU Limit have been stopped"
}

# start|stop|status

case "$1" in
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
