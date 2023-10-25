#!/bin/bash

# Get the names of all network interfaces
interfaces=$(ip -o link show | awk -F': ' '{print $2}')

echo -e "Network Info:"
ip -o addr show

# Print out the interfaces and prompt the user to select one
echo -e "\n\nAvailable network interfaces:"
echo "$interfaces"
echo -e "\nPlease select an interface: "
read selected_interface

# Validate user input
if ! [[ $interfaces =~ $selected_interface ]]; then
  echo "Invalid selection. Exiting."
  exit 1
fi

ip_address=$(ip -o -4 addr list $selected_interface | awk '{print $4}')
gateway=$(ip route | grep default | grep $selected_interface | awk '{print $3}')

# Write the details to a file
echo "Interface: $selected_interface"
echo "IP Address: $ip_address"
echo "Gateway: $gateway"


new_ip="0.0.0.0"
while [[ $new_ip == "0.0.0.0" ]]; do
    # Prompt the user for a new IP address
    echo -e "\nWe will set a static IP for this system to make it easier to access."
    echo -e "Please enter a new IP address (e.g., $ip_address): "
    read new_ip

    if ! [[ $new_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+$ ]]; then
        echo "Invalid IP address format. Please try again."
        new_ip="0.0.0.0"
    fi
done


# Create a Netplan configuration file
cat <<EOL | sudo tee /etc/netplan/01-netcfg.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    $selected_interface:
      dhcp4: no
      addresses:
        - $new_ip
      gateway4: $gateway
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOL

# Apply the new network configuration
sudo netplan apply

# Verify the new settings
echo -e "\nNew Network Configuration:"
ip -o addr show $selected_interface

# Write the details to a file
echo "Interface: $selected_interface" >> /opt/.net.txt
echo "IP Address: $new_ip" >> /opt/.net.txt
echo "Gateway: $gateway" >> /opt/.net.txt
