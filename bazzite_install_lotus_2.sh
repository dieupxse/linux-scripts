#!/bin/bash
echo "=========================================================="
echo "   BUOC 2: BIEN DICH VA CAI DAT BO GO LOTUS               "
echo "=========================================================="

# 1. Tải mã nguồn và biên dịch bằng CMake/Make
echo "[1/2] Dang tai ma nguon va tien hanh bien dich fcitx5-lotus..."

# Di chuyển vào thư mục tạm /tmp để tránh rác hệ thống
cd /tmp
# Xóa thư mục cũ nếu có để tránh xung đột phiên bản
rm -rf fcitx5-lotus

# Tải source code chính thức từ kho lưu trữ của Lotus
git clone https://github.com/LotusInputMethod/fcitx5-lotus.git
cd fcitx5-lotus

# Khởi tạo cấu hình và build project
cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=/usr/lib .
make

# Tiến hành cài đặt các file thực thi vào hệ thống
echo "Vui long nhap mat khau sudo de cai dat bo go vao thiet bi:"
sudo make install

# 2. Kích hoạt dịch vụ hệ thống của Lotus (Lotus Server)
# Bản chất Lotus giao tiếp qua socket/uinput nên cần service này chạy ngầm theo user
echo "[2/2] Dang kich hoat dich vu chay nen fcitx5-lotus-server..."
sudo systemctl enable --now fcitx5-lotus-server@$(whoami).service

echo "=========================================================="
echo "   CAI DAT HOAN TOAN THANH CONG!                          "
echo "=========================================================="
echo "Huong dan kick-off bo go:"
echo "1. Mo ung dung 'Fcitx5 Configuration' trong Menu app len."
echo "2. Tim tu khoa 'Lotus' o khung 'Available Input Method' (ben phai)."
echo "3. Bam nut mui ten '<' de dua 'Lotus' sang khung ben trai."
echo "4. Nhan Apply/OK de luu lai va bat dau go tieng Viet."
echo "=========================================================="