#!/usr/bin/env bash

set -e

APPIMAGE="$1"
TARGET_DIR="$2"

if [[ -z "$APPIMAGE" ]]; then
    echo "Usage:"
    echo "  ./install-app.sh <file.AppImage> [targetFolder]"
    exit 1
fi

if [[ ! -f "$APPIMAGE" ]]; then
    echo "File not found: $APPIMAGE"
    exit 1
fi

if [[ "$APPIMAGE" != *.AppImage ]]; then
    echo "Input file must be an AppImage"
    exit 1
fi

# ===== App Info =====
APP_FILENAME=$(basename "$APPIMAGE")
APP_NAME="${APP_FILENAME%.AppImage}"

# Convert name to lowercase + remove spaces
APP_ID=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g')

# ===== Default Target =====
if [[ -z "$TARGET_DIR" ]]; then
    TARGET_DIR="/opt/$APP_ID"
fi

INSTALL_PATH="$TARGET_DIR/$APP_FILENAME"

echo "==> Installing: $APP_NAME"
echo "==> Target: $TARGET_DIR"

# ===== Create Target =====
sudo mkdir -p "$TARGET_DIR"

# ===== Move AppImage =====
sudo mv "$APPIMAGE" "$INSTALL_PATH"

# ===== Make Executable =====
sudo chmod +x "$INSTALL_PATH"

# ===== Temp Extract =====
TMP_DIR=$(mktemp -d)

echo "==> Extracting AppImage..."

pushd "$TMP_DIR" > /dev/null

"$INSTALL_PATH" --appimage-extract > /dev/null 2>&1 || true

ICON_FILE=$(find squashfs-root \
    \( -iname "*.png" -o -iname "*.svg" -o -iname "*.xpm" \) \
    | head -n 1)

DESKTOP_FILE=$(find squashfs-root \
    -iname "*.desktop" \
    | head -n 1)

popd > /dev/null

# ===== Install Icon =====
ICON_TARGET=""

if [[ -n "$ICON_FILE" ]]; then
    ICON_EXT="${ICON_FILE##*.}"
    ICON_TARGET="/usr/share/pixmaps/${APP_ID}.${ICON_EXT}"

    echo "==> Installing icon..."

    sudo cp "$TMP_DIR/$ICON_FILE" "$ICON_TARGET"
else
    echo "==> No icon found"
fi

# ===== Create Desktop Entry =====
DESKTOP_TARGET="/usr/share/applications/${APP_ID}.desktop"

echo "==> Creating desktop entry..."

if [[ -n "$DESKTOP_FILE" ]]; then
    # Reuse desktop file from AppImage
    sudo cp "$TMP_DIR/$DESKTOP_FILE" "$DESKTOP_TARGET"

    sudo sed -i "s|^Exec=.*|Exec=${INSTALL_PATH}|g" "$DESKTOP_TARGET"

    if [[ -n "$ICON_TARGET" ]]; then
        sudo sed -i "s|^Icon=.*|Icon=${ICON_TARGET}|g" "$DESKTOP_TARGET"
    fi
else
    # Fallback desktop file
    sudo tee "$DESKTOP_TARGET" > /dev/null <<EOF
[Desktop Entry]
Name=$APP_NAME
Exec=$INSTALL_PATH
Icon=$ICON_TARGET
Terminal=false
Type=Application
Categories=Utility;
EOF
fi

sudo chmod 644 "$DESKTOP_TARGET"

# ===== Cleanup =====
rm -rf "$TMP_DIR"

# ===== Update Desktop Database =====
echo "==> Updating desktop database..."

if command -v update-desktop-database >/dev/null 2>&1; then
    sudo update-desktop-database /usr/share/applications
fi

# ===== Update Icon Cache =====
echo "==> Updating icon cache..."

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi

# Refresh GNOME Shell (optional)
if command -v gio >/dev/null 2>&1; then
    gio set "$DESKTOP_TARGET" metadata::trusted true >/dev/null 2>&1 || true
fi

echo ""
echo "✅ AppImage installed successfully!"
echo "App: $APP_NAME"
echo "Executable: $INSTALL_PATH"
echo "Desktop Entry: $DESKTOP_TARGET"
