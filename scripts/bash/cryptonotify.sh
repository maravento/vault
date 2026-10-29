#!/bin/bash
# maravento.com
#
################################################################################
#
# Top 5 Crypto Price Notifier
# FILE: cryptonotify.sh
#
# DESCRIPTION:
# Fetches the current USD prices of the top 5 cryptocurrencies by market
# cap and sends a desktop notification with their symbols and prices.
#
# USAGE:
# Run periodically via crontab.
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# path for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# no-root check
if [ "$(id -u)" == "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script should not be run as root -abort" >&2
    exit 1
fi

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$script_lock"
if ! flock -n 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: script $(basename "$0") is already running -abort" >&2
    exit 1
fi

# dependencies
for dep in curl jq libnotify-bin util-linux iproute2 libc-bin; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
        exit 1
    fi
done

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: cryptonotify start..."

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

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

check_ipv4_interfaces
check_internet

# desktop notification to the current user (X11 and Wayland, no sudo)
notify_send_self() {
    local current_uid
    current_uid=$(id -u)
    local dbus_address="unix:path=/run/user/${current_uid}/bus"
    local xdg_runtime_dir="/run/user/${current_uid}"
    local session_type
    session_type=$(loginctl show-session \
        "$(loginctl show-user "$(id -un)" 2>/dev/null | awk -F= '/^Sessions=/{print $2}')" \
        -p Type --value 2>/dev/null || echo "x11")
    if [[ "$session_type" == "wayland" ]]; then
        DBUS_SESSION_BUS_ADDRESS="$dbus_address" \
        WAYLAND_DISPLAY=wayland-1 \
        XDG_RUNTIME_DIR="$xdg_runtime_dir" \
        notify-send "$@" 2>/dev/null || true
    else
        DISPLAY=:0 \
        DBUS_SESSION_BUS_ADDRESS="$dbus_address" \
        XDG_RUNTIME_DIR="$xdg_runtime_dir" \
        notify-send "$@" 2>/dev/null || true
    fi
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

# Crypto Top 5
top5_response=$(curl -s --max-time 15 --connect-timeout 10 \
    -w "\n%{http_code}" \
    "https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=market_cap_desc&per_page=5&page=1")
top5_http_code=$(echo "$top5_response" | tail -n1)
top5=$(echo "$top5_response" | head -n -1)

if [ "$top5_http_code" != "200" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: CoinGecko market data unavailable (HTTP $top5_http_code) -abort" >&2
    notify_send_self -i dialog-error "Crypto Prices" "API error (HTTP $top5_http_code). Try again later."
    exit 1
fi

# Extract IDs in order from an array
mapfile -t ids < <(echo "$top5" | jq -r '.[].id')

if [ ${#ids[@]} -eq 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: CoinGecko returned no coins -abort" >&2
    notify_send_self -i dialog-error "Crypto Prices" "No data returned from API. Try again later."
    exit 1
fi

# Extract symbols in order, in another array, in uppercase
mapfile -t symbols < <(echo "$top5" | jq -r '.[].symbol' | awk '{print toupper($0)}')

# Build associative array for symbols (optional)
declare -A sym_map
for i in "${!ids[@]}"; do
    sym_map["${ids[$i]}"]="${symbols[$i]}"
done

# Get prices
ids_joined=$(IFS=, ; echo "${ids[*]}")
prices_response=$(curl -s --max-time 15 --connect-timeout 10 \
    -w "\n%{http_code}" \
    "https://api.coingecko.com/api/v3/simple/price?ids=$ids_joined&vs_currencies=usd")
prices_http_code=$(echo "$prices_response" | tail -n1)
prices=$(echo "$prices_response" | head -n -1)

if [ "$prices_http_code" != "200" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: CoinGecko prices unavailable (HTTP $prices_http_code) -abort" >&2
    notify_send_self -i dialog-error "Crypto Prices" "Price API error (HTTP $prices_http_code). Try again later."
    exit 1
fi

# Out
PRICE=""
for id in "${ids[@]}"; do
    price=$(echo "$prices" | jq -r --arg id "$id" '.[$id].usd')
    [[ -z "$price" || "$price" == "null" ]] && price="N/A"
    PRICE+="${sym_map[$id]}: \$${price}\n"
done

# Notify
echo -e "$PRICE"
notify_send_self -i checkbox "Crypto Prices" "$PRICE"

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: cryptonotify done"
