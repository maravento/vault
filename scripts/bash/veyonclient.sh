#!/bin/bash
# maravento.com
#
################################################################################
#
# Veyon Client Tunnel (veyonclient)
#
# DESCRIPTION:
# Connects Veyon Master to a remote Veyon Service through a Cloudflare
# Tunnel Access-protected TCP hostname (see cftunnel.sh for the server
# side). Requires cloudflared installed locally and a tunnel already
# deployed on the remote side.
#
# USAGE:
# bash veyonclient.sh
#
################################################################################

set -uo pipefail

# validation -- one variable per thing validated; use directly with =~
UH_UINT='^(0|[1-9][0-9]*)$'
UH_FQDN='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'

is_valid_port() {
    [[ "$1" =~ $UH_UINT ]] && (( $1 >= 1 && $1 <= 65535 ))
}

# dependencies
for dep in cloudflared; do
    if ! command -v "$dep" &>/dev/null; then
        echo "ERROR: dependency '$dep' is not installed -- abort"
        exit 1
    fi
done
if ! command -v veyon-master &>/dev/null; then
    echo "ERROR: veyon-master is not installed -- abort"
    exit 1
fi

echo "======================================"
echo " Veyon Client Tunnel"
echo "======================================"
echo "This connects Veyon Master to a remote"
echo "Veyon Service via Cloudflare Tunnel."
echo ""
echo "You will need:"
echo "  - The tunnel's public hostname"
echo "  - The local port matching the server-side tunnel"
echo ""
echo "After this script starts the proxy, open Veyon"
echo "Master and connect to 127.0.0.1 on that port."
echo "Press Ctrl+C here to stop when finished."
echo "======================================"
echo ""

while true; do
    read -r -p "Tunnel subdomain (e.g. veyon.example.com): " hostname
    if [[ ! "$hostname" =~ $UH_FQDN ]]; then
        echo "INFO: invalid subdomain: '$hostname' -- retry"
        continue
    fi
    if ! getent hosts "$hostname" >/dev/null 2>&1; then
        echo "INFO: subdomain does not resolve: '$hostname' -- retry"
        continue
    fi
    break
done

while true; do
    read -r -p "Local Veyon port (default 11100): " port
    port="${port:-11100}"
    if ! is_valid_port "$port"; then
        echo "INFO: invalid port: '$port' -- retry"
        continue
    fi
    break
done

echo "Authenticating with Cloudflare Access (a browser window will open)..."
cloudflared access login "https://$hostname"

echo "Starting local proxy on 127.0.0.1:$port ..."
cloudflared access tcp --hostname "$hostname" --url "127.0.0.1:$port"
