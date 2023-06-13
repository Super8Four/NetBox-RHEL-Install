# NetBox Installation Script

**Note: This script has not been tested as of 6-13-2023. Please use it with caution and review it before running on a production system.**
**This is still a Work in progress**

This bash script automates the installation of NetBox, an open-source network documentation and management tool.

## Prerequisites

- CentOS 8 or RHEL 8 system
- Internet connectivity

## Usage

You have two options to install NetBox:

### Option 1: Manual Installation

1. Open a terminal and create a new shell script file, e.g., `netbox_install.sh`.
2. Copy the script from the `netbox_install.sh` file provided in this repository.
3. Save the file and close the text editor.
4. Make the script executable: `chmod +x netbox_install.sh`.
5. Run the script with superuser privileges: `sudo ./netbox_install.sh`.
6. Follow the prompts to provide the necessary information during the installation process.

Please note that this script is provided as a starting point and may require modifications to fit your specific environment and requirements.

### Option 2: Automated Installation

If you prefer a one-liner to download and install the script automatically, you can use the following command:

```bash
curl -O https://raw.githubusercontent.com/Super8Four/NetBox-RHEL-Install/main/Netbox-Install.sh
chmod +x Netbox-Install.sh
sudo ./Netbox-Install.sh
