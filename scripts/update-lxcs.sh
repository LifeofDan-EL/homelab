#!/usr/bin/env bash

# LXC Update Script - Non-Interactive Version
# Updates LXCs without requiring user input

LOG_FILE="/var/log/lxc-updates.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "========================================" | tee -a "$LOG_FILE"
echo "LXC Update Script Started: $DATE" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

SUCCESS_COUNT=0
FAIL_COUNT=0

# Update Docker (101)
echo "" | tee -a "$LOG_FILE"
echo "Updating Docker (CT 101)..." | tee -a "$LOG_FILE"
if pct exec 101 -- bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get update && apt-get upgrade -y" >> "$LOG_FILE" 2>&1; then
    echo "  ✓ Docker updated successfully" | tee -a "$LOG_FILE"
    ((SUCCESS_COUNT++))
else
    echo "  ✗ Docker update failed" | tee -a "$LOG_FILE"
    ((FAIL_COUNT++))
fi

# Update Vaultwarden (102)
echo "" | tee -a "$LOG_FILE"
echo "Updating Vaultwarden (CT 102)..." | tee -a "$LOG_FILE"
if pct exec 102 -- bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get update && apt-get upgrade -y" >> "$LOG_FILE" 2>&1; then
    echo "  ✓ Vaultwarden updated successfully" | tee -a "$LOG_FILE"
    ((SUCCESS_COUNT++))
else
    echo "  ✗ Vaultwarden update failed" | tee -a "$LOG_FILE"
    ((FAIL_COUNT++))
fi

# Update Zigbee2MQTT (103)
echo "" | tee -a "$LOG_FILE"
echo "Updating Zigbee2MQTT (CT 103)..." | tee -a "$LOG_FILE"
if pct exec 103 -- bash -c "
    systemctl stop zigbee2mqtt
    cd /opt/zigbee2mqtt
    git fetch
    git pull
    npm ci --production
    npm run build
    systemctl start zigbee2mqtt
" >> "$LOG_FILE" 2>&1; then
    echo "  ✓ Zigbee2MQTT updated successfully" | tee -a "$LOG_FILE"
    ((SUCCESS_COUNT++))
else
    echo "  ✗ Zigbee2MQTT update failed" | tee -a "$LOG_FILE"
    ((FAIL_COUNT++))
fi

# Update MQTT/Mosquitto (104)
echo "" | tee -a "$LOG_FILE"
echo "Updating MQTT (CT 104)..." | tee -a "$LOG_FILE"
if pct exec 104 -- bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get update && apt-get upgrade -y" >> "$LOG_FILE" 2>&1; then
    echo "  ✓ MQTT updated successfully" | tee -a "$LOG_FILE"
    ((SUCCESS_COUNT++))
else
    echo "  ✗ MQTT update failed" | tee -a "$LOG_FILE"
    ((FAIL_COUNT++))
fi

# Update Jellyfin (107)
echo "" | tee -a "$LOG_FILE"
echo "Updating Jellyfin (CT 107)..." | tee -a "$LOG_FILE"
if pct exec 107 -- bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get update && apt-get upgrade -y" >> "$LOG_FILE" 2>&1; then
    echo "  ✓ Jellyfin updated successfully" | tee -a "$LOG_FILE"
    ((SUCCESS_COUNT++))
else
    echo "  ✗ Jellyfin update failed" | tee -a "$LOG_FILE"
    ((FAIL_COUNT++))
fi

echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "Update Summary:" | tee -a "$LOG_FILE"
echo "  Successful: $SUCCESS_COUNT" | tee -a "$LOG_FILE"
echo "  Failed: $FAIL_COUNT" | tee -a "$LOG_FILE"
echo "  Total Containers: $((SUCCESS_COUNT + FAIL_COUNT))" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

exit 0