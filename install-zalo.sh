#!/usr/bin/env bash

# =========================================================
# Zalo AppImage Installer for Linux
# Supports:
# - Debian / Ubuntu / Linux Mint
# - Arch Linux / Manjaro
# - Fedora / RHEL / Rocky / AlmaLinux
# =========================================================

set -e

APP_NAME="Zalo"

APPIMAGE_URL="https://github.com/hthienloc/zalo-for-linux/releases/download/26.5.10/Zalo-26.5.10+ZaDark-26.2-5051532.AppImage"

ICON_URL="https://upload.wikimedia.org/wikipedia/commons/9/91/Icon_of_Zalo.svg"

INSTALL_DIR="/opt/zalo"
APPIMAGE_PATH="$INSTALL_DIR/Zalo.AppImage"

BIN_DIR="/usr/local/bin"
BIN_PATH="$BIN_DIR/zalo"

DESKTOP_FILE="/usr/share/applications/zalo.desktop"

ICON_DIR="/usr/share/pixmaps"
ICON_PATH="$ICON_DIR/zalo.png"

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

detect_package_manager() {
    if command -v apt >/dev/null 2>&1; then
        PKG_MANAGER="apt"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER="pacman"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
    else
        PKG_MANAGER="unknown"
    fi
}

install_dependencies() {
    log "Kiểm tra dependencies..."

    case "$PKG_MANAGER" in
        apt)
            apt update
            apt install -y wget curl fuse3 desktop-file-utils
            ;;

        pacman)
            pacman -Sy --noconfirm wget curl fuse3 desktop-file-utils
            ;;

        dnf)
            dnf install -y wget curl fuse3 desktop-file-utils
            ;;

        yum)
            yum install -y wget curl fuse3 desktop-file-utils
            ;;

        *)
            warn "Không xác định được package manager."
            warn "Hãy đảm bảo đã cài:"
            warn "- wget"
            warn "- fuse3"
            warn "- desktop-file-utils"
            ;;
    esac
}

create_directories() {
    log "Tạo thư mục..."

    mkdir -p "$INSTALL_DIR"
    mkdir -p "$BIN_DIR"
    mkdir -p "$ICON_DIR"
}

download_appimage() {
    log "Tải Zalo AppImage..."

    wget -O "$APPIMAGE_PATH" "$APPIMAGE_URL"

    chmod +x "$APPIMAGE_PATH"
}

download_icon() {
    log "Tải icon..."

    wget -O "$ICON_PATH" "$ICON_URL"
}

create_launcher() {
    log "Tạo launcher command..."

    cat > "$BIN_PATH" <<EOF
#!/usr/bin/env bash
exec "$APPIMAGE_PATH" --no-sandbox "\$@"
EOF

    chmod +x "$BIN_PATH"
}

create_desktop_file() {
    log "Tạo shortcut menu..."

    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Name=Zalo
GenericName=Zalo Chat
Comment=Zalo Desktop App
Exec=$BIN_PATH
Icon=$ICON_PATH
Terminal=false
Type=Application
Categories=Network;Chat;InstantMessaging;
StartupNotify=true
EOF

    chmod 644 "$DESKTOP_FILE"
}

update_database() {
    log "Cập nhật desktop database..."

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
    fi
}

create_user_desktop_shortcuts() {
    log "Tạo shortcut Desktop cho user..."

    for USER_HOME in /home/*; do
        if [ -d "$USER_HOME/Desktop" ]; then

            USERNAME=$(basename "$USER_HOME")

            cp "$DESKTOP_FILE" "$USER_HOME/Desktop/zalo.desktop"

            chmod +x "$USER_HOME/Desktop/zalo.desktop"

            chown "$USERNAME:$USERNAME" "$USER_HOME/Desktop/zalo.desktop" || true

            # Trusted shortcut cho GNOME/Cinnamon
            if command -v gio >/dev/null 2>&1; then
                sudo -u "$USERNAME" gio set \
                    "$USER_HOME/Desktop/zalo.desktop" \
                    metadata::trusted true 2>/dev/null || true
            fi
        fi
    done
}

show_done() {
    echo ""
    echo "=========================================="
    echo "Cài đặt Zalo hoàn tất!"
    echo "=========================================="
    echo ""
    echo "Cách mở ứng dụng:"
    echo "- Menu Applications"
    echo "- Hoặc chạy lệnh:"
    echo ""
    echo "    zalo"
    echo ""
}

# =========================================================
# Main
# =========================================================

echo ""
echo "=========================================="
echo " Zalo AppImage Installer"
echo "=========================================="
echo ""

require_root
detect_package_manager

log "Package manager: $PKG_MANAGER"

install_dependencies
create_directories
download_appimage
download_icon
create_launcher
create_desktop_file
update_database
create_user_desktop_shortcuts

show_done
