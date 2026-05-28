#!/bin/bash

set -e

SCRIPT_PATH="/usr/local/bin/auto-power-profile.sh"
SERVICE_PATH="/etc/systemd/system/auto-power-profile.service"
RULE_PATH="/etc/udev/rules.d/99-power-profile.rules"

echo "Removing auto power profile switcher..."

# =========================
# Stop + disable service
# =========================

sudo systemctl disable auto-power-profile.service >/dev/null 2>&1 || true

# =========================
# Remove files
# =========================

sudo rm -f "$SCRIPT_PATH"
sudo rm -f "$SERVICE_PATH"
sudo rm -f "$RULE_PATH"

# =========================
# Reload system
# =========================

sudo systemctl daemon-reload

sudo udevadm control --reload-rules
sudo udevadm trigger

echo
echo "Uninstall completed."