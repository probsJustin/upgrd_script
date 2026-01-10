#!/bin/bash

# Disable Lid Suspend Script for Ubuntu 22.04 / 24.04
# Prevents laptop from suspending when lid is closed (especially for HP laptops)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

LOGIND_CONF="/etc/systemd/logind.conf"
BACKUP_FILE="/etc/systemd/logind.conf.backup"

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
    echo -e "${GREEN}Detected Ubuntu $VERSION_ID${NC}"
else
    echo -e "${RED}Error: Cannot determine OS version${NC}"
    exit 1
fi

# Parse arguments
AC_ONLY=false
RESTORE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --ac-only)
            AC_ONLY=true
            shift
            ;;
        --restore)
            RESTORE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --ac-only   Only ignore lid close when on AC power (suspend on battery)"
            echo "  --restore   Restore original logind.conf from backup"
            echo "  -h, --help  Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

echo ""
echo "=== Lid Suspend Configuration ==="
echo ""

# Restore from backup if requested
if [[ "$RESTORE" == true ]]; then
    if [[ -f "$BACKUP_FILE" ]]; then
        echo -e "${YELLOW}Restoring original logind.conf...${NC}"
        cp "$BACKUP_FILE" "$LOGIND_CONF"
        systemctl restart systemd-logind
        echo -e "${GREEN}Original configuration restored${NC}"
        exit 0
    else
        echo -e "${RED}Error: No backup file found at $BACKUP_FILE${NC}"
        exit 1
    fi
fi

# Create backup if it doesn't exist
if [[ ! -f "$BACKUP_FILE" ]]; then
    echo -e "${YELLOW}Creating backup of logind.conf...${NC}"
    cp "$LOGIND_CONF" "$BACKUP_FILE"
    echo -e "${GREEN}Backup saved to $BACKUP_FILE${NC}"
else
    echo -e "${YELLOW}Backup already exists at $BACKUP_FILE${NC}"
fi

# Determine settings based on mode
if [[ "$AC_ONLY" == true ]]; then
    echo -e "${YELLOW}Mode: Ignore lid close on AC power only${NC}"
    LID_SWITCH="suspend"
    LID_SWITCH_EXT="ignore"
else
    echo -e "${YELLOW}Mode: Always ignore lid close${NC}"
    LID_SWITCH="ignore"
    LID_SWITCH_EXT="ignore"
fi

# Function to update or add a setting in logind.conf
update_setting() {
    local key=$1
    local value=$2

    if grep -q "^${key}=" "$LOGIND_CONF"; then
        # Setting exists and is uncommented - update it
        sed -i "s/^${key}=.*/${key}=${value}/" "$LOGIND_CONF"
    elif grep -q "^#${key}=" "$LOGIND_CONF"; then
        # Setting exists but is commented - uncomment and update
        sed -i "s/^#${key}=.*/${key}=${value}/" "$LOGIND_CONF"
    else
        # Setting doesn't exist - add it under [Login] section
        if grep -q "^\[Login\]" "$LOGIND_CONF"; then
            sed -i "/^\[Login\]/a ${key}=${value}" "$LOGIND_CONF"
        else
            # No [Login] section, append to end
            echo "" >> "$LOGIND_CONF"
            echo "[Login]" >> "$LOGIND_CONF"
            echo "${key}=${value}" >> "$LOGIND_CONF"
        fi
    fi
}

echo -e "${YELLOW}Updating logind.conf...${NC}"

# Update lid switch settings
update_setting "HandleLidSwitch" "$LID_SWITCH"
update_setting "HandleLidSwitchExternalPower" "$LID_SWITCH_EXT"
update_setting "HandleLidSwitchDocked" "ignore"

echo -e "${GREEN}Configuration updated${NC}"

# Show current settings
echo ""
echo -e "${YELLOW}Current lid switch settings:${NC}"
grep -E "^HandleLid" "$LOGIND_CONF" | while read -r line; do
    echo "  $line"
done

# Restart systemd-logind
echo ""
echo -e "${YELLOW}Restarting systemd-logind...${NC}"
echo -e "${YELLOW}(This may briefly interrupt your session)${NC}"
sleep 2
systemctl restart systemd-logind

echo -e "${GREEN}systemd-logind restarted${NC}"

# Verify settings
echo ""
echo "=== Verification ==="
echo ""
echo -e "${GREEN}Active lid settings:${NC}"
loginctl show-logind 2>/dev/null | grep HandleLid || echo "  (Could not query loginctl)"

echo ""
echo -e "${GREEN}Configuration complete!${NC}"
echo ""
echo "Notes:"
echo "  - Close the lid to test - laptop should stay awake"
echo "  - If it still suspends, check BIOS settings (F10 on HP laptops)"
echo "  - Look for 'Lid Switch' or 'Sleep on Lid Close' options in BIOS"
echo "  - To restore original settings: sudo $0 --restore"
echo ""

# Check for common issues
if [[ -d /proc/acpi/button/lid ]]; then
    LID_STATE=$(cat /proc/acpi/button/lid/*/state 2>/dev/null | awk '{print $2}')
    echo -e "${YELLOW}Current lid state: ${LID_STATE}${NC}"
fi
