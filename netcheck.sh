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

ip_address=$(ip -o -4 addr list $selected_interface | awk '{print $4}' | cut -d/ -f1)
gateway=$(ip route | grep default | grep $selected_interface | awk '{print $3}')

# Write the details to a file
echo "Interface: $selected_interface" > network_details.txt
echo "IP Address: $ip_address" >> network_details.txt
echo "Gateway: $gateway" >> network_details.txt
