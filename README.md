# ProxmoxVLAN Setup

This script will automatically configure the network interfaces for Proxmox to support VLANs. 
It also supports an NGINX install to remove the necessity of adding the port after the proxmox ip

## Installation

To run the setup, simply execute the following command in your terminal:

```bash
bash -c "$(wget -qLO - https://github.com/420-H33-RO/proxmoxvlan/raw/main/interfaces.sh)"
