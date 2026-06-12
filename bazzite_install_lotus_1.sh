#!/bin/bash
echo "=========================================================="
echo "   BUOC 1: CAU HINH MOI TRUONG & CAI DAT THU VIEN NEN     "
echo "=========================================================="

# 1. Tự động phát hiện Shell hiện tại của người dùng
# Sử dụng biến $SHELL hoặc lệnh ps để nhận diện chính xác nhất
CURRENT_SHELL=$(basename "$SHELL")
echo "[1/3] Dang phat hien Shell he thong... Nhận diện: $CURRENT_SHELL"

# Định nghĩa các biến môi trường cần thiết cho Fcitx5
ENV_CONFIG="
# Fcitx5 Environment Variables
export XMODIFIERS=\"@im=fcitx\"
export GTK_IM_MODULE=\"fcitx\"
export QT_IM_MODULE=\"fcitx\"
"

# Ghi vào file cấu hình tương ứng dựa trên Shell được tìm thấy
case "$CURRENT_SHELL" in
    bash)
        TARGET_FILE="$HOME/.bashrc"
        echo "--> Dang ghi cau hinh vao $TARGET_FILE"
        sed -i '/Fcitx5 Environment Variables/,$d' "$TARGET_FILE" 2>/dev/null
        echo "$ENV_CONFIG" >> "$TARGET_FILE"
        ;;
    zsh)
        TARGET_FILE="$HOME/.zshrc"
        echo "--> Dang ghi cau hinh vao $TARGET_FILE"
        sed -i '/Fcitx5 Environment Variables/,$d' "$TARGET_FILE" 2>/dev/null
        echo "$ENV_CONFIG" >> "$TARGET_FILE"
        ;;
    fish)
        TARGET_FILE="$HOME/.config/fish/config.fish"
        echo "--> Dang ghi cau hinh vao $TARGET_FILE (Dinh dang Fish Shell)"
        mkdir -p "$(dirname "$TARGET_FILE")"
        # Định dạng biến môi trường riêng cho Fish Shell
        sed -i '/Fcitx5 Environment Variables/,$d' "$TARGET_FILE" 2>/dev/null
        cat << 'EOF' >> "$TARGET_FILE"
# Fcitx5 Environment Variables
set -gx XMODIFIERS "@im=fcitx"
set -gx GTK_IM_MODULE "fcitx"
set -gx QT_IM_MODULE "fcitx"
EOF
        ;;
    *)
        # Trường hợp không nhận diện được, ghi đè vào cả .bashrc và .profile để đảm bảo an toàn
        echo "--> Shell lạ ($CURRENT_SHELL). Dang ghi cau hinh mac dinh vao .bashrc va .profile..."
        sed -i '/Fcitx5 Environment Variables/,$d' ~/.bashrc ~/.profile 2>/dev/null
        echo "$ENV_CONFIG" >> ~/.bashrc
        echo "$ENV_CONFIG" >> ~/.profile
        ;;
esac

# Luôn ghi thêm vào .profile để hỗ trợ phần quản lý hiển thị (Display Manager) lúc đăng nhập
sed -i '/Fcitx5 Environment Variables/,$d' ~/.profile 2>/dev/null
echo "$ENV_CONFIG" >> ~/.profile

# 2. Cấu hình tự khởi động (Autostart) cho Fcitx5
echo "[2/3] Cau hinh Fcitx5 tu dong khoi chay cung he thong..."
mkdir -p ~/.config/autostart
cat << 'EOF' > ~/.config/autostart/org.fcitx.Fcitx5.desktop
[Desktop Entry]
Name=Fcitx 5
GenericName=Input Method
Comment=Start Input Method
Exec=fcitx5
Icon=org.fcitx.Fcitx5
Terminal=false
Type=Application
Categories=System;Utility;
X-GNOME-Autostart-Phase=Applications
X-GNOME-Autostart-Delay=2
X-KDE-autostart-phase=1
X-KDE-autostart-after=panel
EOF

# 3. Cài đặt các gói phụ thuộc qua rpm-ostree
echo "[3/3] Dang cai dat cac thu vien can thiet qua rpm-ostree..."
echo "Vui long nhap mat khau sudo khi duoc yeu cau:"
sudo rpm-ostree install fcitx5 fcitx5-configtool fcitx5-gtk fcitx5-qt cmake gcc-c++ extra-cmake-modules fcitx5-devel libuuid-devel libxkbcommon-devel git

echo "----------------------------------------------------------"
echo " HOAN THANH BUOC 1!"
echo " BAZZITE CAN DUOC KHOI DONG LAI DE QUA TRINH CAI DAT CO HIEU LUC."
echo " Vui long go lenh 'reboot' de khoi dong lai may."
echo " Sau khi may len lai, hay chay tiep file '2_install_lotus.sh'."
echo "----------------------------------------------------------"