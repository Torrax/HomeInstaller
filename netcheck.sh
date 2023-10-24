#!/bin/bash

interfaces=$(ip -o link show | awk -F': ' '{print $2}')

ip -o addr show

echo "\nAvailable network interfaces:"
echo "$interfaces"
echo -n "\nPlease select an interface: "
read selected_interface

# Validate user input
if ! [[ $interfaces =~ $selected_interface ]]; then
  echo "Invalid selection. Exiting."
  exit 1
fi

# Get IP address, subnet mask, and gateway for the selected interface
ip_address=$(ip -o -4 addr list $selected_interface | awk '{print $4}')
gateway=$(ip route | grep default | awk '{print $3}')

# Write the details to a file
echo "Interface: $selected_interface" > network_details.txt
echo "IP Address: $ip_address" >> network_details.txt
echo "Gateway: $gateway" >> network_details.txt
