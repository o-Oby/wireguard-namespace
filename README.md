# Wireguard Namespace Setup Script

This script sets up a network namespace with a WireGuard VPN connection on a DietPi system. It ensures that IP forwarding is enabled, creates a network namespace if it doesn't already exist, sets up a veth pair, configures the veth interfaces with dynamic IP retrieval, sets up WireGuard with a retry mechanism, configures routing, and applies iptables rules for NAT. Additionally, it provides functionality to start, stop, and check the status of the VPN.

## Requirements

Before running the script, ensure that the following dependencies are installed:

- WireGuard
- iptables
- resolvconf
- sudo
- iproute2
- gawk (awk)
- grep
- bash

You can install all dependencies with the following command:

```bash
sudo apt update && sudo apt install -y wireguard wireguard-tools iptables resolvconf sudo iproute2 gawk grep bash
```

## Usage

1. Ensure that the WireGuard configuration file `/etc/wireguard/protonvpn.conf` exists and contains the correct keys and endpoint information. For ProtonVPN, the full WireGuard configuration file can be created at https://account.protonvpn.com/downloads

    Below is a template for the `protonvpn.conf` file:

    ```ini
    [Interface]
    PrivateKey = <YourPrivateKey>
    Address = <YourAddress>
    DNS = <YourDNS>

    [Peer]
    PublicKey = <ServerPublicKey>
    AllowedIPs = 0.0.0.0/0
    Endpoint = <ServerEndpoint>
    ```

2. Download the script and make it executable:

    ```bash
    chmod +x wireguard-namespace.sh
    ```

3. Run the script with the desired action:

    ```bash
    sudo ./wireguard-namespace.sh start|stop|status
    ```

4. The script can be added to crontab to run at system startup:

    ```bash
    @reboot /path/to/wireguard-namespace.sh start
    ```

5. After running the script, use the following command to run commands in the VPN namespace:

    ```bash
    sudo ip netns exec vpn <command>
    ```

    Example:

    ```bash
    sudo ip netns exec vpn curl ifconfig.me
    ```

## Script Overview

### Steps Performed by the Script

1. Enable IP forwarding.
2. Create a network namespace if it doesn't already exist.
3. Create a veth pair if it doesn't already exist.
4. Retrieve and assign IP addresses to the veth interfaces.
5. Set DNS to 1.1.1.1 in the VPN namespace.
6. Setup the WireGuard interface with a retry mechanism.
7. Configure routing and apply iptables rules for NAT.
8. Verify DNS configuration and test connectivity.

### Actions

- `start`: Sets up the network namespace and starts the VPN connection. If the VPN namespace is already active, it will print a message indicating so.
- `stop`: Stops the VPN connection and removes the network namespace.
- `status`: Checks and prints the status of the VPN namespace and the WireGuard interface.

## Notes

- This script dynamically retrieves IP addresses for the veth interfaces and avoids hardcoding values.
- Ensure that the `/etc/wireguard/protonvpn.conf` file is properly configured before running the script.

## License

This project is licensed under the MIT License.
