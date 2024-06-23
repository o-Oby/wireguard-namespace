#!/bin/bash

# This script sets up, stops, and checks the status of a network namespace with a WireGuard VPN connection on a DietPi system.
# It ensures that IP forwarding is enabled, creates a network namespace if it doesn't already exist,
# sets up a veth pair, configures the veth interfaces with dynamic IP retrieval, sets up WireGuard with a retry mechanism,
# configures routing, and applies iptables rules for NAT.
#
# Usage:
#   ./wireguard-namespace.sh start|stop|status
#
# The script can be added to crontab to run at system startup:
#   @reboot /path/to/wireguard-namespace.sh start
#
# Before running the script, ensure that the WireGuard configuration file /etc/wireguard/protonvpn.conf
# exists and contains the correct keys and endpoint information. 
#
# After running the script, use the following command to run commands in the VPN namespace:
#   sudo ip netns exec vpn <command>
#
# Example:
#   sudo ip netns exec vpn curl ifconfig.me
#
# The script dynamically retrieves IP addresses for the veth interfaces and avoids hardcoding values.

set -e

# Enable IP forwarding
enable_ip_forwarding() {
  sudo sysctl -w net.ipv4.ip_forward=1
}

# Setup network namespace and veth pair
setup_namespace() {
  # Check if the network namespace already exists
  if ! ip netns list | grep -q "vpn"; then
    # Create the network namespace
    sudo ip netns add vpn
  fi

  # Check if the veth pair already exists
  if ! ip link show | grep -q "veth0"; then
    # Create the veth pair
    sudo ip link add veth0 type veth peer name veth1
    sudo ip link set veth1 netns vpn
  fi

  # Retrieve IP addresses assigned to veth0 and veth1
  VETH0_IP=$(ip -o -4 addr show veth0 | awk '{print $4}')
  VETH1_IP=$(sudo ip netns exec vpn ip -o -4 addr show veth1 | awk '{print $4}')

  # If veth0 IP is not assigned, assign it
  if [ -z "$VETH0_IP" ]; then
    VETH0_IP="10.200.200.1/24"
    sudo ip addr add $VETH0_IP dev veth0
    sudo ip link set veth0 up
  else
    sudo ip link set veth0 up
  fi

  # If veth1 IP is not assigned, assign it
  if [ -z "$VETH1_IP" ]; then
    VETH1_IP="10.200.200.2/24"
    sudo ip netns exec vpn ip addr add $VETH1_IP dev veth1
    sudo ip netns exec vpn ip link set veth1 up
    sudo ip netns exec vpn ip link set lo up
  else
    sudo ip netns exec vpn ip link set veth1 up
    sudo ip netns exec vpn ip link set lo up
  fi

  # Ensure correct DNS settings directly
  sudo sh -c "echo 'nameserver 1.1.1.1' > /etc/netns/vpn/resolv.conf"
}

# Function to setup WireGuard interface
setup_wireguard() {
  sudo ip netns exec vpn wg-quick up /etc/wireguard/protonvpn.conf
}

# Add routes in the VPN namespace if they do not exist
setup_routes() {
  WG_SERVER_IP=$(sudo grep 'Endpoint' /etc/wireguard/protonvpn.conf | awk '{print $3}' | cut -d':' -f1)
  
  if ! sudo ip netns exec vpn ip route show | grep -q "$WG_SERVER_IP via ${VETH0_IP%/*}"; then
    sudo ip netns exec vpn ip route add $WG_SERVER_IP via ${VETH0_IP%/*} dev veth1
  fi
  if ! sudo ip netns exec vpn ip route show | grep -q "default dev protonvpn"; then
    sudo ip netns exec vpn ip route add default dev protonvpn
  fi
}

# Apply iptables rules for NAT
setup_iptables() {
  sudo iptables -t nat -F POSTROUTING
  sudo iptables -F FORWARD

  sudo iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
  sudo iptables -t nat -A POSTROUTING -o protonvpn -j MASQUERADE
  sudo iptables -A FORWARD -i protonvpn -o veth0 -j ACCEPT
  sudo iptables -A FORWARD -i veth0 -o protonvpn -j ACCEPT
  sudo iptables -A FORWARD -o protonvpn -j ACCEPT
}

# Start VPN
start_vpn() {
  if ip netns list | grep -q "vpn"; then
    echo "VPN namespace 'vpn' is already active."
    return
  fi
  
  enable_ip_forwarding
  setup_namespace
  
  # Retry setting up WireGuard interface up to 3 times
  for i in {1..3}; do
    if setup_wireguard; then
      echo "WireGuard setup succeeded on attempt $i."
      break
    else
      echo "WireGuard setup failed on attempt $i. Retrying..."
      sleep 1
    fi
  done

  setup_routes
  setup_iptables

  # Verify DNS configuration
  sudo ip netns exec vpn cat /etc/resolv.conf

  # Test connectivity to VPN server and external IPs
  sudo ip netns exec vpn ping -c 3 $WG_SERVER_IP
  sudo ip netns exec vpn ping -c 3 1.1.1.1

  echo "Network namespace and VPN setup complete. Use 'sudo ip netns exec vpn <command>' to run commands in the VPN namespace."
}

# Stop VPN
stop_vpn() {
  if ip netns list | grep -q "vpn"; then
    sudo ip netns exec vpn wg-quick down /etc/wireguard/protonvpn.conf
    sudo ip netns delete vpn
    sudo ip link delete veth0
    sudo iptables -t nat -F POSTROUTING
    sudo iptables -F FORWARD
    echo "VPN stopped and network namespace removed."
  else
    echo "VPN namespace 'vpn' is not active."
  fi
}

# Check VPN status
status_vpn() {
  if ip netns list | grep -q "vpn"; then
    echo "VPN namespace 'vpn' is active."
    sudo ip netns exec vpn wg show
  else
    echo "VPN namespace 'vpn' is not active."
  fi
}

# Main script
case "$1" in
  start)
    start_vpn
    ;;
  stop)
    stop_vpn
    ;;
  status)
    status_vpn
    ;;
  *)
    echo "Usage: $0 {start|stop|status}"
    exit 1
    ;;
esac
