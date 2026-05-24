#!/bin/bash
# maravento.com
#
################################################################################
#
# Top 5 Crypto Price Notifier
# ---------------------------
# This script fetches the current USD prices of the top 5 cryptocurrencies by market capitalization
# directly from the CoinGecko API and sends a desktop notification with their symbols and prices.
# It maintains the order based on market cap descending.

# Usage:
# Add this script to your crontab to get periodic price updates, for example every 30 minutes:
# */30 * * * * /path_to/cryptonotify.sh
#
################################################################################

echo "Top 5 Crypto Price Notifier Starting. Wait..."
printf "\n"

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# check no-root
if [ "$(id -u)" -eq 0 ]; then
    echo "❌ This script should not be run as root."
    exit 1
fi

set -uo pipefail

# check dependencies
pkgs='curl jq libnotify-bin'
for pkg in $pkgs; do
  if ! dpkg -s "$pkg" &>/dev/null; then
    echo "❌ '$pkg' is not installed. Run:"
    echo "sudo apt install $pkg"
    exit 1
  fi
done

current_uid=$(id -u)

# Desktop notification helper (X11 and Wayland)
_notify() {
    local bus="unix:path=/run/user/${current_uid}/bus"
    local xdg_runtime="/run/user/${current_uid}"
    local session_type
    session_type=$(loginctl show-session \
        "$(loginctl show-user "$(id -un)" 2>/dev/null | awk -F= '/^Sessions=/{print $2}')" \
        -p Type --value 2>/dev/null || echo "x11")
    if [[ "$session_type" == "wayland" ]]; then
        DBUS_SESSION_BUS_ADDRESS="$bus" \
        WAYLAND_DISPLAY=wayland-1 \
        XDG_RUNTIME_DIR="$xdg_runtime" \
        notify-send "$@" 2>/dev/null || true
    else
        DISPLAY=:0 \
        DBUS_SESSION_BUS_ADDRESS="$bus" \
        XDG_RUNTIME_DIR="$xdg_runtime" \
        notify-send "$@" 2>/dev/null || true
    fi
}

# Crypto Top 5
top5_response=$(curl -s --max-time 15 --connect-timeout 10 \
    -w "\n%{http_code}" \
    "https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=market_cap_desc&per_page=5&page=1")
top5_http_code=$(echo "$top5_response" | tail -n1)
top5=$(echo "$top5_response" | head -n -1)

if [ "$top5_http_code" != "200" ]; then
    echo "❌ CoinGecko API error (HTTP $top5_http_code). Cannot fetch market data."
    _notify -i dialog-error "Crypto Prices" "API error (HTTP $top5_http_code). Try again later."
    exit 1
fi

# Extract IDs in order from an array
mapfile -t ids < <(echo "$top5" | jq -r '.[].id')

if [ ${#ids[@]} -eq 0 ]; then
    echo "❌ No data returned from CoinGecko API."
    _notify -i dialog-error "Crypto Prices" "No data returned from API. Try again later."
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
    echo "❌ CoinGecko prices API error (HTTP $prices_http_code)."
    _notify -i dialog-error "Crypto Prices" "Price API error (HTTP $prices_http_code). Try again later."
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
_notify -i checkbox "Crypto Prices" "$PRICE"
