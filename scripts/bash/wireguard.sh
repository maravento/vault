#!/bin/bash
# maravento.com
#
################################################################################
#
# WireGuard Install Server or Client | Uninstall
# FILE: wireguard.sh
#
# DESCRIPTION: Installs WireGuard as a server or as a client, generating the
# key pair and the interface configuration. Also uninstalls it.
#
# USAGE: sudo bash wireguard.sh
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# root check
if [ "$(id -u)" != "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock") || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot open $(basename "$script_lock") -abort" >&2
    exit 1
}
exec 200>"$script_lock"
if ! flock -n 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: script $(basename "$0") is already running -abort" >&2
    exit 1
fi

# dependencies
for dep in iproute2 util-linux; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep" 2>/dev/null)" != *"ok installed"* ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
        exit 1
    fi
done

# validation -- integer only; use directly with =~
UH_UINT='^(0|[1-9][0-9]*)$'
# start
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: wireguard start..."

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

# Function to install WireGuard as Server
install_wireguard_server() {
  if ! command -v wg &> /dev/null; then
    # WireGuard Install
    apt update || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot update package lists -abort" >&2
        exit 1
    }
    apt install -y wireguard wireguard-tools || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install WireGuard packages -abort" >&2
        exit 1
    }

    # qrcode (Optional)
    # e.g: sudo qrencode -t ansiutf8 < qr.conf
    apt install -y qrencode

    # testing
    modprobe wireguard || true

    # create dir
    mkdir -p /etc/wireguard
    cd /etc/wireguard || exit

    # restrict permissions while generating key material, restore afterward
    prev_umask=$(umask)
    umask 077

    # Generate private and public keys
    wg genkey | tee /etc/wireguard/private.key | wg pubkey | tee /etc/wireguard/public.key

    # Display keys to copy into configuration file
    server_private_key=$(cat /etc/wireguard/private.key)
    server_public_key=$(cat /etc/wireguard/public.key)

    echo "Public key: $server_public_key"

    # Verify that the keys have been read correctly
    if [ -z "$server_private_key" ] || [ -z "$server_public_key" ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: failed to read keys -abort" >&2
      exit 1
    fi

    # List numbered network interfaces, excluding 'lo'
    interfaces=$(ip -o link | awk '$2 != "lo:" {print $2, $(NF-2)}' | sed 's_: _ _')

    # Show numbered interfaces
    echo "Available network interfaces:"
    printf "%s\n" "$interfaces" | nl -s '. '

    # Prompt the user to choose an interface by number
    read -rp "Enter the public network interface number: " num
    if ! [[ "$num" =~ $UH_UINT ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: please enter a valid number -abort" >&2
        exit 1
    fi

    # Get the name of the selected interface
    public_eth=$(printf "%s\n" "$interfaces" | sed -n "${num}p" | awk '{print $1}')

    # Verify the selected public interface
    if [ -z "$public_eth" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no interface selected or invalid number -abort" >&2
        exit 1
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: selected public interface: $public_eth"

    # Create the wg0.conf configuration file
    cat > /etc/wireguard/wg0.conf << EOL
[Interface]
Address = 10.0.0.1/24
#SaveConfig = true
ListenPort = 51820
PrivateKey = $server_private_key
PostUp = iptables -I FORWARD -i wg0 -j ACCEPT; iptables -t nat -I POSTROUTING -o $public_eth -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $public_eth -j MASQUERADE

# This is an example. Each client should add their own public key and IP address.
# Uncomment these lines for clients and replace the values
#[Peer]
# PublicKey = <Client's Public Key>
# AllowedIPs = <Assigned Client IP>/32
EOL
    if [ $? -ne 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot write wg0.conf -abort" >&2
        exit 1
    fi

    # Permissions for files and keys
    if ! chmod 600 /etc/wireguard/{private.key,wg0.conf}; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot set private.key/wg0.conf permissions -abort" >&2
        exit 1
    fi
    if ! chmod 644 /etc/wireguard/public.key; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot set public.key permissions -abort" >&2
        exit 1
    fi

    # restore the umask that was active before key generation
    umask "$prev_umask"

    if ! printf 'net.ipv4.ip_forward=1\n' > /etc/sysctl.d/99-wireguard.conf; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot write 99-wireguard.conf -abort" >&2
        exit 1
    fi
    if ! sysctl --system >/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot apply sysctl settings -abort" >&2
        exit 1
    fi
    if ! wg-quick up wg0; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot bring up wg0 -abort" >&2
        exit 1
    fi
    if ! systemctl enable wg-quick@wg0; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot enable wg-quick@wg0 -abort" >&2
        exit 1
    fi
    if command -v ufw &>/dev/null; then
        if ! ufw allow 51820/udp; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: cannot open port 51820/udp, clients may not connect -alert"
        fi
    fi
    wg show
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: WireGuard installation complete"
  else
    # Read-only: wg alone does not prove a working server, and this branch changes nothing.
    if [[ -s /etc/wireguard/private.key && -s /etc/wireguard/public.key && -s /etc/wireguard/wg0.conf ]] \
       && systemctl is-enabled --quiet wg-quick@wg0; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: WireGuard is already installed -skip"
    else
      echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: WireGuard server installation is incomplete -abort" >&2
      return 1
    fi
  fi
}

# Function to install WireGuard as Client
install_wireguard_client() {
  if ! command -v wg &> /dev/null; then
    # WireGuard Install
    apt update || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot update package lists -abort" >&2
        exit 1
    }
    apt install -y wireguard wireguard-tools || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install WireGuard packages -abort" >&2
        exit 1
    }

    # Generate private and public keys for the client
    if ! client_private_key=$(wg genkey) || [ -z "$client_private_key" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot generate client private key -abort" >&2
        exit 1
    fi
    if ! client_public_key=$(echo "$client_private_key" | wg pubkey) || [ -z "$client_public_key" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot generate client public key -abort" >&2
        exit 1
    fi

    # Configure the WireGuard configuration file with the generated keys
    prev_umask=$(umask)
    umask 077
    echo "[Interface]
PrivateKey = $client_private_key
Address = <Client IP>/32
# DNS = 8.8.8.8 # Optional

[Peer]
PublicKey = <Server's Public Key>
Endpoint = <Server's Public IP>:51820 # Real IP
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25 # Optional" > /etc/wireguard/wg0.conf
    client_conf_rc=$?
    umask "$prev_umask"
    if [ "$client_conf_rc" -ne 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot write wg0.conf -abort" >&2
        exit 1
    fi

    # Permissions for files and keys
    if ! chmod 600 /etc/wireguard/wg0.conf; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot set wg0.conf permissions -abort" >&2
        exit 1
    fi

    # Show completion message
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: WireGuard client installation complete"
    echo
    echo "Client's Public Key: $client_public_key"
    echo
    echo "Please edit following file and replace placeholders:"
    echo "/etc/wireguard/wg0.conf"
    echo "  - Replace <Client IP>/32 with your assigned client IP (e.g., 10.0.0.2/32)"
    echo "  - Replace <Server's Public Key> with server's public key"
    echo "  - Replace <Server's Public IP>:51820 with server's IP address (e.g., 192.168.0.10:51820)"
    echo "Once you have made changes, enable and start WireGuard with:"
    echo "  sudo systemctl enable wg-quick@wg0"
    echo "  sudo wg-quick up wg0"
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: WireGuard is already installed -skip"
  fi
}

# WireGuard Uninstaller Feature
uninstall_wireguard() {
    local purge_failed=0
  if command -v wg &> /dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Uninstalling WireGuard..."

    # Stop WireGuard interface
    wg-quick down wg0 2>/dev/null || true

    # Disable the service
    if ! systemctl disable wg-quick@wg0; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: wg0 may be down, /etc/wireguard kept -alert"
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: disable failed, uninstall incomplete -abort" >&2
        return 1
    fi

    # Uninstall packages
    if ! apt purge -y wireguard wireguard-tools qrencode; then
        purge_failed=1
    fi

    # The keys go only after every step above worked
    if [ "$purge_failed" -gt 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: wg0 may be down, /etc/wireguard kept -alert"
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: purge failed, uninstall incomplete -abort" >&2
        return 1
    fi

    # Clean up unneeded packages
    apt autoremove -y

    # Delete configuration files and keys
    if ! rm -rf /etc/wireguard; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot remove /etc/wireguard -abort" >&2
        return 1
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: WireGuard has been successfully uninstalled"
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: WireGuard is not installed -skip"
  fi
}

# ------------------------------------------------------------------------------
# MENU
# ------------------------------------------------------------------------------

# Options
echo "What action do you want to perform?"
echo "1) Install WireGuard Server"
echo "2) Install WireGuard Client"
echo "3) Uninstall WireGuard"
read -rp "Select an option (1, 2 or 3): " option

case $option in
  1)
    install_wireguard_server || exit 1
    ;;
  2)
    install_wireguard_client
    ;;
  3)
    uninstall_wireguard || exit 1
    ;;
  *)
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: invalid option -abort" >&2
    exit 1
    ;;
esac

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: wireguard done"
