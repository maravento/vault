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
# If Veyon Master is missing, installs the latest Veyon GitHub release on
# Ubuntu 24.04 or 26.04 using sudo. Downloads to the working directory.
# Other systems skip the installation.
#
# VEYON 4.X KEY SETUP:
# 1. Master (Local): Run Veyon Configurator as administrator and create
#    a key pair.
# 2. Select the private key, click "Set access group", and assign the
#    authorized group for Veyon Master users (e.g., users).
# 3. Export only the public key and copy it to the remote computers.
# 4. On each remote computer, open a terminal in the public key directory.
#    Set the key file owner and group before importing it.
#    sudo chown "$(id -un):$(id -gn)" -- "master_public_key.pem"
# 5. Import the public key in Veyon Configurator on each remote computer.
# 6. On all machines, go to General > Authentication, set Authentication
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
log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

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
            log "INFO: waiting for an interface with IPv4..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    log "ERROR: no interface with IPv4 -abort"
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
            log "INFO: waiting for internet..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    log "ERROR: no internet connection -abort"
    exit 1
}

# dependencies (Veyon GitHub release)
install_veyon() (
    local ID='' VERSION_ID=''
    local dep arch suffix asset deb_url digest deb_file
    local release_api='https://api.github.com/repos/veyon/veyon/releases/latest'
    local release_download='https://github.com/veyon/veyon/releases/download/'

    if [[ -r /etc/os-release ]]; then
        . /etc/os-release
    fi
    case "${ID}:${VERSION_ID}" in
        ubuntu:24.04|ubuntu:26.04) ;;
        *)
            log "INFO: automatic Veyon install unsupported on this OS -skip" >&2
            return 0
            ;;
    esac

    for dep in apt-get awk curl dpkg ip jq mktemp rm sha256sum sleep sudo; do
        if ! command -v "$dep" &>/dev/null; then
            log "ERROR: '$dep' is required to install Veyon -abort" >&2
            return 1
        fi
    done

    if ! arch=$(dpkg --print-architecture); then
        log "ERROR: cannot determine the Debian architecture -abort" >&2
        return 1
    fi
    suffix="-ubuntu.${VERSION_ID}_${arch}.deb"
    check_ipv4_interfaces
    check_internet

    if ! asset=$(curl -fsSL --proto '=https' --proto-redir '=https' \
        --connect-timeout 10 --max-time 30 "$release_api" |
        jq -er --arg suffix "$suffix" '
            [.assets[] | select(.state == "uploaded" and
                (.name | startswith("veyon_") and endswith($suffix)))] |
            select(length == 1) | .[0] | [.browser_download_url, .digest] | @tsv
        '); then
        log "ERROR: no matching Veyon release package found -abort" >&2
        return 1
    fi
    read -r deb_url digest <<< "$asset"
    if [[ "$deb_url" != "$release_download"*"$suffix" ||
        ! "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
        log "ERROR: invalid Veyon release URL or checksum -abort" >&2
        return 1
    fi

    if ! deb_file=$(mktemp --suffix=.deb -- "$PWD/veyon.XXXXXXXXXX"); then
        log "ERROR: cannot create local Veyon package -abort" >&2
        return 1
    fi
    trap 'rm -f -- "$deb_file"' EXIT

    log "INFO: downloading Veyon for Ubuntu $VERSION_ID..."
    if ! curl -fsSL --proto '=https' --proto-redir '=https' \
        --connect-timeout 10 --max-time 180 --output "$deb_file" "$deb_url"; then
        log "ERROR: Veyon package download failed -abort" >&2
        return 1
    fi
    if ! printf '%s  %s\n' "${digest#sha256:}" "$deb_file" |
        sha256sum --check --status; then
        log "ERROR: Veyon package checksum mismatch -abort" >&2
        return 1
    fi

    if ! sudo -k apt-get -o Binary::file::APT::Sandbox::User=root \
        -o Binary::copy::APT::Sandbox::User=root \
        install --no-remove -y -- "$deb_file" </dev/null; then
        log "ERROR: Veyon package installation failed -abort" >&2
        return 1
    fi
    if ! command -v veyon-master &>/dev/null; then
        log "ERROR: veyon-master unavailable after installation -abort" >&2
        return 1
    fi
)

if ! command -v veyon-master &>/dev/null; then
    install_veyon || exit 1
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
