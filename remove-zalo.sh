#!/usr/bin/env bash

# =========================================================
# Zalo AppImage Uninstaller
# Supports:
# - Debian / Ubuntu / Linux Mint
# - Arch Linux / Manjaro
# - Fedora / RHEL / Rocky / AlmaLinux
# =========================================================

set -e

APP_NAME="Zalo"

INSTALL_DIR="/opt/zalo"
APPIMAGE_PATH="$INSTALL_DIR/Zalo.AppImage"

BIN_PATH="/usr/local/bin/zalo"

DESKTOP_FILE="/usr/share/applications/zalo.desktop"

ICON_PATH="/usr/share/pixmaps/zalo.png"

# =========================================================
# Helpers
# =========================================================

log() {
    echo -e "\e[1;32m[INFO]\e[0m $1"
}

warn() {
    echo -e "\e[1;33m[WARN]\e[0m $1"
}

error() {
    echo -e "\e[1;31m[ERROR]\e[0m $1"
}

require_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Vui lòng chạy bằng sudo hoặc root"
        exit 1
    fi
}

remove_desktop_shortcuts() {
    log "Xóa shortcut Desktop của user..."

    for USER_HOME in /home/*; do
        if [ -d "$USER_HOME/Desktop" ]; then
            rm -f "$USER_HOME/Desktop/zalo.desktop"
        fi
    done
}

remove_files() {

    log "Xóa AppImage..."
    rm -f "$APPIMAGE_PATH"

    log "Xóa launcher..."
    rm -f "$BIN_PATH"

    log "Xóa desktop entry..."
    rm -f "$DESKTOP_FILE"

    log "Xóa icon..."
    rm -f "$ICON_PATH"

    log "Xóa thư mục cài đặt..."
    rm -rf "$INSTALL_DIR"
}

update_database() {

    log "Cập nhật desktop database..."

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
    fi
}

show_done() {

    echo ""
    echo "=========================================="
    echo "Gỡ cài đặt Zalo hoàn tất!"
    echo "=========================================="
    echo ""
}

# =========================================================
# Main
# =========================================================

echo ""
echo "=========================================="
echo " Zalo AppImage Uninstaller"
echo "=========================================="
echo ""

require_root

remove_desktop_shortcuts
remove_files
update_database

show_done
