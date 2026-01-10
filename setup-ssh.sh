#!/bin/bash

# SSH Setup Script for Ubuntu 22.04 / 24.04
# Ensures SSH is installed, running, and accessible from the local network

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
    exit 1
fi

# Check Ubuntu version
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        echo -e "${RED}Error: This script is designed for Ubuntu only${NC}"
        exit 1
    fi

    MAJOR_VERSION=$(echo "$VERSION_ID" | cut -d. -f1)
    if [[ "$MAJOR_VERSION" != "22" && "$MAJOR_VERSION" != "24" ]]; then
        echo -e "${YELLOW}Warning: This script is designed for Ubuntu 22.04 or 24.04${NC}"
        echo -e "${YELLOW}Detected: Ubuntu $VERSION_ID - proceeding anyway...${NC}"
    else
        echo -e "${GREEN}Detected Ubuntu $VERSION_ID${NC}"
    fi
else
    echo -e "${RED}Error: Cannot determine OS version${NC}"
    exit 1
fi

echo ""
echo "=== SSH Setup Script ==="
echo ""

# Update package list
echo -e "${YELLOW}Updating package list...${NC}"
apt-get update -qq

# Install OpenSSH Server if not present
if dpkg -l | grep -q openssh-server; then
    echo -e "${GREEN}OpenSSH Server is already installed${NC}"
else
    echo -e "${YELLOW}Installing OpenSSH Server...${NC}"
    apt-get install -y openssh-server
    echo -e "${GREEN}OpenSSH Server installed${NC}"
fi

# Enable and start SSH service
echo -e "${YELLOW}Enabling SSH service...${NC}"
systemctl enable ssh
systemctl start ssh

# Check if SSH is running
if systemctl is-active --quiet ssh; then
    echo -e "${GREEN}SSH service is running${NC}"
else
    echo -e "${RED}Error: SSH service failed to start${NC}"
    exit 1
fi

# Configure UFW firewall if installed
if command -v ufw &> /dev/null; then
    echo -e "${YELLOW}Configuring UFW firewall...${NC}"

    # Check if UFW is active
    if ufw status | grep -q "Status: active"; then
        # Allow SSH through firewall
        ufw allow ssh
        echo -e "${GREEN}SSH allowed through UFW firewall${NC}"
    else
        echo -e "${YELLOW}UFW is installed but not active${NC}"
        echo -e "${YELLOW}Enabling UFW and allowing SSH...${NC}"
        ufw allow ssh
        ufw --force enable
        echo -e "${GREEN}UFW enabled with SSH allowed${NC}"
    fi
else
    echo -e "${YELLOW}UFW firewall not installed - skipping firewall configuration${NC}"
    echo -e "${YELLOW}If you have another firewall, ensure port 22 is open${NC}"
fi

# Ensure SSH config allows password authentication (for initial setup)
SSH_CONFIG="/etc/ssh/sshd_config"
if grep -q "^PasswordAuthentication no" "$SSH_CONFIG"; then
    echo -e "${YELLOW}Enabling password authentication...${NC}"
    sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' "$SSH_CONFIG"
    systemctl restart ssh
    echo -e "${GREEN}Password authentication enabled${NC}"
fi

# Get network information
echo ""
echo "=== Connection Information ==="
echo ""

# Get local IP addresses
echo -e "${GREEN}Local IP addresses:${NC}"
ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | while read -r ip; do
    echo "  ssh $(whoami)@$ip"
done

# Alternative using hostname
HOSTNAME_IP=$(hostname -I | awk '{print $1}')
if [[ -n "$HOSTNAME_IP" ]]; then
    echo ""
    echo -e "${GREEN}Primary connection:${NC}"
    echo "  ssh <username>@$HOSTNAME_IP"
fi

echo ""
echo -e "${GREEN}SSH setup complete!${NC}"
echo ""
echo "Notes:"
echo "  - SSH is listening on port 22"
echo "  - Password authentication is enabled"
echo "  - For better security, consider setting up SSH keys and disabling password auth"
echo ""
