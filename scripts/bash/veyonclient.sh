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
# VEYON 4.X KEY SETUP:
# 1. Master (Local): Run Veyon Configurator as administrator and create
#    a key pair.
# 2. Select the private key, click "Set access group", and assign the
#    authorized group for Veyon Master users (e.g., users).
# 3. Export only the public key and import it onto the remote computers.
# 4. On all machines, go to General > Authentication, set Authentication
#    Method to "Key file authentication", and click Apply.
#
# USAGE:
# COMMAND               ACTION
# bash veyonclient.sh   Start the client tunnel (no sudo)
#
# 1. Enter the tunnel hostname (e.g., veyon.example.com).
# 2. Choose a local port (press Enter for default 11101, or specify another
#    if busy).
# 3. Authenticate in Cloudflare and leave the script running once it prints
#    "Start Websocket listener".
# 4. Register the remote host locally: open Veyon Configurator, go to
#    Locations & computers, add a location, and add a computer (e.g., Name:
#    myPC, Host address/IP: 127.0.0.1:11101, matching the exact address and
#    port printed by the script). Click Apply.
# 5. Open Veyon Master locally and select myPC under that location.
#
################################################################################

set -uo pipefail

# no-root check
if [ "$(id -u)" == "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: run as a normal user -abort" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# dependencies
for dep in cloudflared date getent ss; do
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

# validation - one variable per thing validated; use directly with =~
UH_UINT='^(0|[1-9][0-9]*)$'
UH_FQDN='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$'

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
echo "  - a free local TCP port for the proxy"
echo ""

echo "======================================"
echo ""

while true; do
    read -r -p "Tunnel subdomain (e.g. veyon.example.com): " hostname || exit 1
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

local_port_default=11101
while true; do
    read -r -p "Local Veyon port (default $local_port_default): " port || exit 1
    port="${port:-$local_port_default}"
    if ! is_valid_port "$port"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: invalid port: '$port' -retry"
        continue
    fi
    if ! listeners=$(ss -Hltn "sport = :$port"); then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot check local port -abort" >&2
        exit 1
    fi
    if [[ -n "$listeners" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: port $port already in use -retry"
        continue
    fi
    break
done

echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: veyonclient start..."
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Cloudflare login, a browser will open..."
if ! cloudflared access login --quiet "https://$hostname"; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Cloudflare Access authentication failed -abort" >&2
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Starting local proxy on 127.0.0.1:$port ..."
echo "Add 127.0.0.1:$port in Veyon Configurator, then select it in Veyon Master."
on_interrupt() {
    echo ""
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: veyonclient done"
    exit 0
}
trap on_interrupt INT
if ! cloudflared access tcp --hostname "$hostname" --url "127.0.0.1:$port" 2>&1 |
    {
        listener_announced=false
        while IFS= read -r line || [[ -n "$line" ]]; do
            printf '%s\n' "$line"
            if ! "$listener_announced" && [[ "$line" == *"Start Websocket listener"* ]]; then
                printf '%s\n' 'Press Ctrl+C to stop the tunnel.'
                listener_announced=true
            fi
        done
    } >&2; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: local proxy failed -abort" >&2
    exit 1
fi
trap - INT

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: veyonclient done"
