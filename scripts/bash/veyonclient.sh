#!/bin/bash
# maravento.com
#
################################################################################
#
# Veyon Client Tunnel (veyonclient)
# FILE: veyonclient.sh
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

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# dependencies
for dep in cloudflared; do
    if ! command -v "$dep" &>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
        exit 1
    fi
done
if ! command -v veyon-master &>/dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: veyon-master is not installed -abort" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

# validation -- one variable per thing validated; use directly with =~
UH_UINT='^(0|[1-9][0-9]*)$'
UH_FQDN='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

is_valid_port() {
    [[ "$1" =~ $UH_UINT ]] && [ "${#1}" -le 5 ] \
        && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

echo "======================================"
echo " Veyon Client Tunnel"
echo "======================================"
echo "This connects Veyon Master to a remote"
echo "Veyon Service via Cloudflare Tunnel"
echo ""
echo "You will need:"
echo "  - The tunnel's public hostname"
echo "  - local port matching server-side tunnel"
echo ""
echo "After this script starts proxy, open Veyon"
echo "Master and connect to 127.0.0.1 on that port"
echo "Press Ctrl+C here to stop when finished"
echo "======================================"
echo ""

while true; do
    read -r -p "Tunnel subdomain (e.g. veyon.example.com): " hostname
    if [[ ! "$hostname" =~ $UH_FQDN ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: invalid subdomain: '$hostname' -retry"
        continue
    fi
    if ! getent hosts "$hostname" >/dev/null 2>&1; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: subdomain does not resolve: '$hostname' -retry"
        continue
    fi
    break
done

while true; do
    read -r -p "Local Veyon port (default 11100): " port
    port="${port:-11100}"
    if ! is_valid_port "$port"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: invalid port: '$port' -retry"
        continue
    fi
    break
done

echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: veyonclient start..."
echo "$(date '+%Y-%m-%d %H:%M:%S') Authenticating with Cloudflare Access (a browser window will open)..."
if ! cloudflared access login "https://$hostname"; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Cloudflare Access authentication failed -abort" >&2
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') Starting local proxy on 127.0.0.1:$port ..."
on_interrupt() {
    echo ""
    echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: veyonclient done"
    exit 0
}
trap on_interrupt INT
if ! cloudflared access tcp --hostname "$hostname" --url "127.0.0.1:$port"; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: local proxy failed -abort" >&2
    exit 1
fi
trap - INT

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: veyonclient done"
