#!/usr/bin/env bash

set -e

APP_NAME="onscreen-tracker"

echo "Removing $APP_NAME..."

# ==========================================
# Stop services
# ==========================================

systemctl --user stop onscreen.service 2>/dev/null || true
systemctl --user stop onscreen-sleep.service 2>/dev/null || true

systemctl --user disable onscreen.service 2>/dev/null || true
systemctl --user disable onscreen-sleep.service 2>/dev/null || true

# ==========================================
# Remove systemd services
# ==========================================

rm -f "$HOME/.config/systemd/user/onscreen.service"
rm -f "$HOME/.config/systemd/user/onscreen-sleep.service"

systemctl --user daemon-reload

# ==========================================
# Remove binaries
# ==========================================

rm -f "$HOME/.local/bin/onscreen"
rm -f "$HOME/.local/bin/onscreen-daemon.sh"

# ==========================================
# Remove sleep hook
# ==========================================

rm -f "$HOME/.local/share/systemd/user-sleep/onscreen-sleep-hook.sh"

# ==========================================
# Remove data
# ==========================================

rm -rf "$HOME/.local/share/onscreen"

# ==========================================
# Cleanup empty dirs
# ==========================================

rmdir "$HOME/.local/share/systemd/user-sleep" 2>/dev/null || true

# ==========================================
# Remove bash aliases (optional cleanup)
# ==========================================

sed -i '/onscreen-tracker/d' "$HOME/.bashrc" 2>/dev/null || true

echo
echo "========================================"
echo "Removed successfully"
echo "========================================"
echo
echo "Removed:"
echo "- onscreen command"
echo "- daemon"
echo "- systemd services"
echo "- sleep hook"
echo "- history data"
echo