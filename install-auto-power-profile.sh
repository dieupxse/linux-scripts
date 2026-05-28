#!/bin/bash

set -e

SCRIPT_PATH="/usr/local/bin/auto-power-profile.sh"
SERVICE_PATH="/etc/systemd/system/auto-power-profile.service"
RULE_PATH="/etc/udev/rules.d/99-power-profile.rules"

echo "Installing auto power profile switcher..."

# =========================
# Check dependency
# =========================

if ! command -v powerprofilesctl >/dev/null 2>&1; then
    echo "powerprofilesctl not found."
    echo "Please install power-profiles-daemon first:"
    echo
    echo "sudo apt install power-profiles-daemon"
    exit 1
fi

# =========================
# Create main script
# =========================

sudo tee "$SCRIPT_PATH" >/dev/null <<'EOF'
#!/bin/bash

AC_PATH="/sys/class/power_supply/AC/online"

[ -f "$AC_PATH" ] || exit 1

STATUS=$(cat "$AC_PATH")
CURRENT=$(powerprofilesctl get)

if [ "$STATUS" = "1" ]; then
    TARGET="balanced"
else
    TARGET="power-saver"
fi

if [ "$CURRENT" != "$TARGET" ]; then
    powerprofilesctl set "$TARGET"
    logger -t auto-power-profile "Switched to $TARGET"
fi
EOF

sudo chmod +x "$SCRIPT_PATH"

# =========================
# Create systemd service
# =========================

sudo tee "$SERVICE_PATH" >/dev/null <<'EOF'
[Unit]
Description=Auto Power Profile Switch
After=multi-user.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/auto-power-profile.sh

[Install]
WantedBy=multi-user.target
WantedBy=suspend.target
WantedBy=hibernate.target
WantedBy=hybrid-sleep.target
WantedBy=suspend-then-hibernate.target
EOF

# =========================
# Create udev rule
# =========================

sudo tee "$RULE_PATH" >/dev/null <<'EOF'
SUBSYSTEM=="power_supply", ATTR{online}=="0", RUN+="/usr/local/bin/auto-power-profile.sh"
SUBSYSTEM=="power_supply", ATTR{online}=="1", RUN+="/usr/local/bin/auto-power-profile.sh"
EOF

# =========================
# Reload services
# =========================

sudo systemctl daemon-reload

sudo systemctl enable auto-power-profile.service

sudo udevadm control --reload-rules
sudo udevadm trigger

# Apply current profile immediately
sudo "$SCRIPT_PATH"

echo
echo "Installation completed."
echo
echo "Current power profile:"
powerprofilesctl get
echo
echo "Realtime AC detection enabled."
echo "Boot/resume restore enabled."
echo
echo "View logs:"
echo "journalctl -t auto-power-profile"