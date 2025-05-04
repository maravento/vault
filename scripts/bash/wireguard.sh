#!/bin/bash
# maravento.com

# WireGuard Install Server or Client | Uninstall

echo "WireGuard Install | Remove Starting. Wait..."
printf "\n"

# checking root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root" 1>&2
  exit 1
fi

# checking script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi

# Function to install WireGuard as Server
install_wireguard_server() {
  if ! command -v wg &> /dev/null; then
    # WireGuard Install
    apt update
    apt install -y wireguard wireguard-tools

    # qrcode (Optional)
    # e.g: sudo qrencode -t ansiutf8 < qr.conf
    apt install -y qrencode

    # testing
    modprobe wireguard

    # create dir
    cd /etc/wireguard || exit

    # umask for file permissions
    umask 077

    # Generate private and public keys
    wg genkey | tee /etc/wireguard/private.key | wg pubkey | tee /etc/wireguard/public.key

    # Display keys to copy into configuration file
    SERVER_PRIVATE_KEY=$(cat /etc/wireguard/private.key)
    SERVER_PUBLIC_KEY=$(cat /etc/wireguard/public.key)

    echo "Private key: $SERVER_PRIVATE_KEY"
    echo "Public key: $SERVER_PUBLIC_KEY"

    # Verify that the keys have been read correctly
    if [ -z "$SERVER_PRIVATE_KEY" ] || [ -z "$SERVER_PUBLIC_KEY" ]; then
      echo "Error: Failed to read keys"
      exit 1
    fi

    # List numbered network interfaces, excluding 'lo'
    interfaces=$(ip -o link | awk '$2 != "lo:" {print $2, $(NF-2)}' | sed 's_: _ _')

    # Show numbered interfaces
    echo "Available network interfaces:"
    echo "$interfaces" | nl -s '. '

    # Prompt the user to choose an interface by number
    read -p "Enter the public network interface number: " num

    # Get the name of the selected interface
    public_eth=$(echo "$interfaces" | sed -n "${num}p" | awk '{print $1}')

    # Verify the selected public interface
    if [ -z "$public_eth" ]; then
        echo "Error: No interface selected or invalid number."
        exit 1
    fi

    echo "Selected public interface: $public_eth"

    # Create the wg0.conf configuration file
    cat > /etc/wireguard/wg0.conf << EOL
[Interface]
Address = 10.0.0.1/24
#SaveConfig = true
ListenPort = 51820
PrivateKey = $SERVER_PRIVATE_KEY
PostUp = iptables -I FORWARD -i wg0 -j ACCEPT; iptables -t nat -I POSTROUTING -o $public_eth -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $public_eth -j MASQUERADE

# This is an example. Each client should add their own public key and IP address. 
# Uncomment these lines for clients and replace the values
#[Peer]
# PublicKey = <Client's Public Key>
# AllowedIPs = <Assigned Client IP>/32
EOL

    # Permissions for files and keys
    chmod 600 /etc/wireguard/{private.key,wg0.conf}
    chmod 644 /etc/wireguard/public.key

    # Enable IPv4 persistent redirection
    sed -i '/^#*net.ipv4.ip_forward/c\net.ipv4.ip_forward=1' /etc/sysctl.conf
    sysctl -p

    # Launch the WireGuard interface
    wg-quick up wg0

    # Enable WireGuard service
    systemctl enable wg-quick@wg0
    
    # port
    ufw allow 51820/udp

    # show status
    wg show
    echo "WireGuard installation complete"
  else
    echo "WireGuard is already installed"
  fi
}

# Function to install WireGuard as Client
install_wireguard_client() {
  if ! command -v wg &> /dev/null; then
    # WireGuard Install
    apt update
    apt install -y wireguard wireguard-tools

    # Generate private and public keys for the client
    CLIENT_PRIVATE_KEY=$(wg genkey)
    CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)

    # Configure the WireGuard configuration file with the generated keys
    echo "[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = <Client IP>/32
# DNS = 8.8.8.8 # Optional

[Peer]
PublicKey = <Server's Public Key>
Endpoint = <Server's Public IP>:51820 # Real IP
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25 # Optional" > /etc/wireguard/wg0.conf

    # Permissions for files and keys
    chmod 600 /etc/wireguard/wg0.conf

    # Enable WireGuard service
    systemctl enable wg-quick@wg0

    # Show completion message
    echo "WireGuard client installation complete."
    echo
    echo "Client's Private Key: $CLIENT_PRIVATE_KEY"
    echo "Client's Public Key: $CLIENT_PUBLIC_KEY"
    echo
    echo "Please edit the following file and replace the placeholders:"
    echo "/etc/wireguard/wg0.conf"
    echo "  - Replace <Client IP>/32 with your assigned client IP (e.g., 10.0.0.2/32)."
    echo "  - Replace <Client's Private Key> with the client's private key."
    echo "  - Replace <Server's Public Key> with the server's public key."
    echo "  - Replace <Server's Public IP:Port> with the server's IP address (e.g., 192.168.1.1:51820)."
    echo "Once you have made the changes, start WireGuard with:"
    echo "  sudo wg-quick up wg0"
  else
    echo "WireGuard is already installed"
  fi
}

# WireGuard Uninstaller Feature
uninstall_wireguard() {
  if command -v wg &> /dev/null; then
    echo "Uninstalling WireGuard..."

    # Stop WireGuard interface
    wg-quick down wg0

    # Disable the service
    systemctl disable wg-quick@wg0

    # Uninstall packages
    apt purge -y wireguard wireguard-tools qrencode

    # Clean up unneeded packages
    apt autoremove -y
    
    # Delete configuration files and keys
    rm -rf /etc/wireguard

    echo "WireGuard has been successfully uninstalled"
  else
    echo "WireGuard is not installed"
  fi
}

# Options
echo "What action do you want to perform?"
echo "1) Install WireGuard Server"
echo "2) Install WireGuard Client"
echo "3) Uninstall WireGuard"
read -p "Select an option (1, 2 or 3): " option

case $option in
  1)
    install_wireguard_server
    ;;
  2)
    install_wireguard_client
    ;;
  3)
    uninstall_wireguard
    ;;
  *)
    echo "Invalid option"
    ;;
esac

