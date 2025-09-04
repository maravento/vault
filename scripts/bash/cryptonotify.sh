#!/bin/bash

# Top 5 Crypto Price Notifier
# ---------------------------
# This script fetches the current USD prices of the top 5 cryptocurrencies by market capitalization
# directly from the CoinGecko API and sends a desktop notification with their symbols and prices.
# It maintains the order based on market cap descending.

# Usage:
# Add this script to your crontab to get periodic price updates, for example every 30 minutes:
# */30 * * * * /path_to/cryptonotify.sh

echo "Top 5 Crypto Price Notifier Starting. Wait..."
printf "\n"

local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}' || who | head -1 | awk '{print $1}')

# check no-root
if [ "$(id -u)" -eq 0 ]; then
    echo "❌ This script should not be run as root."
    exit 1
fi

# check script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi

# check SO
UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
if [[ "$UBUNTU_ID" != "ubuntu" || ( "$UBUNTU_VERSION" != "22.04" && "$UBUNTU_VERSION" != "24.04" ) ]]; then
    echo "Unsupported system. Use at your own risk"
    # exit 1
fi

# check dependencies
pkgs='curl jq libnotify-bin'
for pkg in $pkgs; do
  if ! dpkg -s "$pkg" &>/dev/null; then
    echo "❌ '$pkg' is not installed. Run:"
    echo "sudo apt install $pkg"
    exit 1
  fi
done

# Crypto Top 5
top5=$(curl -s "https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=market_cap_desc&per_page=5&page=1")

# Extract IDs in order from an array
mapfile -t ids < <(echo "$top5" | jq -r '.[].id')

# Extract symbols in order, in another array, in uppercase
mapfile -t symbols < <(echo "$top5" | jq -r '.[].symbol' | awk '{print toupper($0)}')

# Build associative array for symbols (optional)
declare -A sym_map
for i in "${!ids[@]}"; do
    sym_map["${ids[$i]}"]="${symbols[$i]}"
done

# Get prices
ids_joined=$(IFS=, ; echo "${ids[*]}")
prices=$(curl -s "https://api.coingecko.com/api/v3/simple/price?ids=$ids_joined&vs_currencies=usd")

# Out
PRICE=""
for id in "${ids[@]}"; do
    price=$(echo "$prices" | jq -r --arg id "$id" '.[$id].usd')
    [[ -z "$price" || "$price" == "null" ]] && price="Error"
    PRICE+="${sym_map[$id]}: \$${price}\n"
done

# Notify
echo -e "$PRICE"
DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u "$USER")/bus \
notify-send -i checkbox "Crypto Prices" "$PRICE"
