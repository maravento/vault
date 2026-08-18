#!/bin/bash
# maravento.com
#
################################################################################
#
# Veyon Client Tunnel (veyonclient)
# Connects Veyon Master to a remote Veyon Service through a Cloudflare
# Tunnel Access-protected TCP hostname (see cftunnel.sh for the server side).
#
# Usage: bash veyonclient.sh
#
# PREREQUISITES:
# ==============
# - cloudflared installed on this machine (the one running Veyon Master).
# - A Cloudflare Tunnel already deployed and running on the remote side
#   (see cftunnel.sh), with its public hostname pointing to
#   tcp://<remote-veyon-ip>:<port>.
# - A Cloudflare Zero Trust Access Application protecting that hostname.
#
# WHAT THIS SCRIPT DOES:
# =======================
# 1. Checks that cloudflared and veyon-master are installed.
# 2. Asks for the tunnel's public hostname and verifies it resolves.
# 3. Asks for the local port to forward (11100 remote control, 11099
#    monitoring feed).
# 4. Authenticates against Cloudflare Access once via 'cloudflared access
#    login' (opens a browser window). Running the login step separately
#    avoids 'cloudflared access tcp' hanging after browser approval on a
#    fresh, unauthenticated machine.
# 5. Starts 'cloudflared access tcp' in the foreground, forwarding
#    127.0.0.1:<port> into the tunnel. Open Veyon Master and connect to
#    127.0.0.1 on that port; close this terminal (Ctrl+C) when done.
#
################################################################################

set -uo pipefail

# VALIDATION -- one variable per thing validated; use directly with =~
_UH_UINT='^(0|[1-9][0-9]*)$'
_UH_FQDN='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'

is_valid_port() {
    [[ "$1" =~ $_UH_UINT ]] && (( $1 >= 1 && $1 <= 65535 ))
}

# DEPENDENCIES
for dep in cloudflared; do
    if ! command -v "$dep" &>/dev/null; then
        echo "[ERROR] Required dependency '$dep' is not installed."
        exit 1
    fi
done
if ! command -v veyon-master &>/dev/null; then
    echo "[ERROR] veyon-master is not installed."
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
    if [[ ! "$hostname" =~ $_UH_FQDN ]]; then
        echo "[WARNING] Invalid subdomain: '$hostname'"
        continue
    fi
    if ! getent hosts "$hostname" >/dev/null 2>&1; then
        echo "[WARNING] Subdomain does not resolve: '$hostname'"
        continue
    fi
    break
done

while true; do
    read -r -p "Local Veyon port (default 11100): " port
    port="${port:-11100}"
    if ! is_valid_port "$port"; then
        echo "[WARNING] Invalid port: '$port'"
        continue
    fi
    break
done

echo "Authenticating with Cloudflare Access (a browser window will open)..."
cloudflared access login "https://$hostname"

echo "Starting local proxy on 127.0.0.1:$port ..."
cloudflared access tcp --hostname "$hostname" --url "127.0.0.1:$port"
