#!/bin/bash

# Ask the user if they want to modify network interfaces
read -p "Do you want to configure the network interfaces for vlans? (y/n): " configure_network

if [[ "$configure_network" == "y" || "$configure_network" == "Y" ]]; then
    # List all available network interfaces
    echo ''
    echo "Available network interfaces:"
    ip -br link show | awk '{print $1}'
    echo ''
    # Prompt user for inputs
    read -p "Enter the physical interface name (e.g., eno1): " phy_iface
    read -p "Enter the range of VLANs to allow (e.g., 2-4094): " vlan_range
    read -p "Enter the VLAN ID for the connection interface (e.g., 100): " vlan_id
    read -p "Enter the static IP address (e.g., 172.16.1.10): " static_ip
    read -p "Enter the subnet in CIDR format (e.g., /24): " subnet_cidr
    read -p "Enter the gateway (e.g., 172.16.1.1): " gateway

    # Combine IP address with subnet in CIDR format (e.g., 172.16.1.10/24)
    ip_with_subnet="$static_ip$subnet_cidr"

    # Create the new network configuration file in the /tmp directory
    cat <<EOF > /tmp/new_interfaces
auto lo
iface lo inet loopback

iface $phy_iface inet manual

auto vmbr0
iface vmbr0 inet manual
        bridge-ports $phy_iface
        bridge-stp off
        bridge-fd 0
        bridge-vlan-aware yes
        bridge-vids $vlan_range

auto vmbr0.$vlan_id
iface vmbr0.$vlan_id inet static
        address $ip_with_subnet
        gateway $gateway


source /etc/network/interfaces.d/*
EOF

    echo "Network configuration has been saved to /tmp/new_interfaces!"

    # Display the content of /tmp/new_interfaces to the user
    echo "Here is the new network configuration:"
    cat /tmp/new_interfaces

    # Ask the user if the configuration is good
    read -p "Does this configuration look good? (y/n): " confirmation

    if [[ "$confirmation" == "y" || "$confirmation" == "Y" ]]; then
        # Back up the current /etc/network/interfaces
        echo "Backing up /etc/network/interfaces to /etc/network/interfaces.bak..."
        cp /etc/network/interfaces /etc/network/interfaces.bak

        # Move /tmp/new_interfaces to /etc/network/interfaces
        echo "Moving /tmp/new_interfaces to /etc/network/interfaces..."
        mv /tmp/new_interfaces /etc/network/interfaces

        echo "Network configuration has been updated successfully!"
    else
        echo "No changes have been made. Please review the configuration and try again."
    fi
else
    echo "Skipping network interface configuration. Proceeding to NGINX installation..."
fi

# Ask if the user wants to install NGINX for access to Proxmox without port 8006
echo ''
read -p "Do you want to install NGINX to allow access to Proxmox without needing to specify the port? (y/n): " install_nginx

if [[ "$install_nginx" == "y" || "$install_nginx" == "Y" ]]; then
    rm /etc/apt/sources.list.d/ceph.list
    rm /etc/apt/sources.list.d/pve-enterprise.list
    # Check if NGINX is already installed
    if ! command -v nginx &> /dev/null; then
        # NGINX is not installed, install it
        echo "Installing NGINX..."
        apt update || { echo "Failed to update apt repositories. Exiting."; exit 1; }
        apt install -y nginx || { echo "Failed to install NGINX. Exiting."; exit 1; }
    else
        echo "NGINX is already installed."
    fi

    # Verify if the NGINX service exists and is enabled
    if systemctl is-enabled nginx &> /dev/null; then
        echo "NGINX service is already enabled."
    else
        echo "Enabling NGINX service..."
        systemctl enable nginx || { echo "Failed to enable NGINX service. Exiting."; exit 1; }
    fi

    # Get the Fully Qualified Domain Name (FQDN) of the server
    fqdn=$(hostname -f)

    # Create an NGINX reverse proxy configuration for Proxmox using the FQDN
    echo "Creating NGINX configuration to forward traffic to Proxmox on port 8006..."
    cat <<EOF > /etc/nginx/sites-available/proxmox
server {
    listen 80;
    server_name $fqdn;

    location / {
        proxy_pass https://localhost:8006/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    # Create a symlink for the NGINX configuration
    ln -s /etc/nginx/sites-available/proxmox /etc/nginx/sites-enabled/
    rm /etc/nginx/sites-enabled/default

    # Check if the symlink was created successfully
    if [[ -L /etc/nginx/sites-enabled/proxmox ]]; then
        echo "NGINX site configuration has been linked."
    else
        echo "Failed to create symlink for NGINX site configuration. Exiting."
        exit 1
    fi

    # Reload NGINX to apply the configuration
    echo "Reloading NGINX to apply the configuration..."
    systemctl reload nginx || { echo "Failed to reload NGINX. Exiting."; exit 1; }

    echo "NGINX has been installed and configured successfully. You can now access Proxmox using the ip directly"
else
    echo "NGINX installation skipped. The script will now exit."
fi
