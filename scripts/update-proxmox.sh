#!/usr/bin/env bash

# Proxmox VE Host Update Script
# Updates Proxmox VE, kernel, and system packages

LOG_FILE="/var/log/proxmox-updates.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "========================================" | tee -a "$LOG_FILE"
echo "Proxmox VE Update Script Started: $DATE" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

# Get current version before update
echo "" | tee -a "$LOG_FILE"
echo "Current Proxmox VE version:" | tee -a "$LOG_FILE"
pveversion | tee -a "$LOG_FILE"

# Update package lists
echo "" | tee -a "$LOG_FILE"
echo "Updating package lists..." | tee -a "$LOG_FILE"
if apt-get update >> "$LOG_FILE" 2>&1; then
    echo "  ✓ Package lists updated" | tee -a "$LOG_FILE"
else
    echo "  ✗ Failed to update package lists" | tee -a "$LOG_FILE"
    exit 1
fi

# Check for available updates
echo "" | tee -a "$LOG_FILE"
echo "Checking for available updates..." | tee -a "$LOG_FILE"
UPDATES=$(apt list --upgradable 2>/dev/null | grep -c upgradable)
if [ "$UPDATES" -eq 0 ]; then
    echo "  ℹ No updates available" | tee -a "$LOG_FILE"
    echo "========================================" | tee -a "$LOG_FILE"
    exit 0
fi
echo "  ℹ $UPDATES package(s) available for update" | tee -a "$LOG_FILE"

# Show what will be updated
echo "" | tee -a "$LOG_FILE"
echo "Packages to be updated:" | tee -a "$LOG_FILE"
apt list --upgradable 2>/dev/null | grep upgradable | tee -a "$LOG_FILE"

# Perform the upgrade
echo "" | tee -a "$LOG_FILE"
echo "Performing system upgrade..." | tee -a "$LOG_FILE"
if DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y >> "$LOG_FILE" 2>&1; then
    echo "  ✓ System upgraded successfully" | tee -a "$LOG_FILE"
else
    echo "  ✗ System upgrade failed" | tee -a "$LOG_FILE"
    exit 1
fi

# Clean up old packages
echo "" | tee -a "$LOG_FILE"
echo "Cleaning up..." | tee -a "$LOG_FILE"
if apt-get autoremove -y >> "$LOG_FILE" 2>&1; then
    echo "  ✓ Old packages removed" | tee -a "$LOG_FILE"
else
    echo "  ⚠ Cleanup had issues (non-critical)" | tee -a "$LOG_FILE"
fi

if apt-get autoclean >> "$LOG_FILE" 2>&1; then
    echo "  ✓ Package cache cleaned" | tee -a "$LOG_FILE"
else
    echo "  ⚠ Cache cleanup had issues (non-critical)" | tee -a "$LOG_FILE"
fi

# Get version after update
echo "" | tee -a "$LOG_FILE"
echo "Updated Proxmox VE version:" | tee -a "$LOG_FILE"
pveversion | tee -a "$LOG_FILE"

# Check if reboot is required
echo "" | tee -a "$LOG_FILE"
if [ -f /var/run/reboot-required ]; then
    echo "⚠ REBOOT REQUIRED" | tee -a "$LOG_FILE"
    echo "  A system reboot is needed to complete the update." | tee -a "$LOG_FILE"
    echo "  Run: reboot" | tee -a "$LOG_FILE"
else
    # Check for new kernel
    CURRENT_KERNEL=$(uname -r)
    LATEST_KERNEL=$(dpkg -l | grep 'pve-kernel-' | grep '^ii' | awk '{print $2}' | sort -V | tail -1 | sed 's/pve-kernel-//')
    
    if [ "$CURRENT_KERNEL" != "$LATEST_KERNEL" ]; then
        echo "⚠ NEW KERNEL AVAILABLE" | tee -a "$LOG_FILE"
        echo "  Current kernel: $CURRENT_KERNEL" | tee -a "$LOG_FILE"
        echo "  Latest kernel: $LATEST_KERNEL" | tee -a "$LOG_FILE"
        echo "  A reboot is recommended to use the new kernel." | tee -a "$LOG_FILE"
        echo "  Run: reboot" | tee -a "$LOG_FILE"
    else
        echo "✓ No reboot required" | tee -a "$LOG_FILE"
    fi
fi

echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "Proxmox VE Update Complete: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

exit 0