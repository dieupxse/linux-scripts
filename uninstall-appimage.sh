#!/usr/bin/env bash

set -e

INPUT_NAME="$1"

if [[ -z "$INPUT_NAME" ]]; then
    echo "Usage:"
    echo "  ./uninstall-appimage.sh <AppName>"
    echo "Example:"
    echo "  ./uninstall-appimage.sh \"Terminator\""
    echo "  ./uninstall-appimage.sh \"Simplenote\""
    exit 1
fi

# Chuẩn hóa từ khóa tìm kiếm sang chữ thường và thay khoảng trắng bằng dấu gạch ngang
SEARCH_KEY=$(echo "$INPUT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g')

echo "==> Quét tìm các thành phần AppImage khớp với từ khóa: \"$SEARCH_KEY\"..."

# ===== 1. Quét tìm thư mục cài đặt trong /opt/ =====
OPT_DIRS=()
if [ -d "/opt" ]; then
    # Tìm kiếm không phân biệt hoa thường (-iname) ở cấp độ thư mục con trực tiếp
    while IFS= read -r -d '' dir; do
        OPT_DIRS+=("$dir")
    done < <(find /opt -maxdepth 1 -type d -iname "*${SEARCH_KEY}*" -not -path /opt -print0 2>/dev/null)
fi

# ===== 2. Quét tìm tệp .desktop trong /usr/share/applications/ =====
DESKTOP_FILES=()
if [ -d "/usr/share/applications" ]; then
    while IFS= read -r -d '' file; do
        DESKTOP_FILES+=("$file")
    done < <(find /usr/share/applications -maxdepth 1 -type f -iname "*${SEARCH_KEY}*.desktop" -print0 2>/dev/null)
fi

# ===== 3. Quét tìm tệp biểu tượng Icon trong /usr/share/pixmaps/ =====
ICON_FILES=()
if [ -d "/usr/share/pixmaps" ]; then
    while IFS= read -r -d '' file; do
        ICON_FILES+=("$file")
    done < <(find /usr/share/pixmaps -maxdepth 1 -type f -iname "*${SEARCH_KEY}*" -print0 2>/dev/null)
fi

# ===== KIỂM TRA TỔNG THỂ XEM CÓ THÀNH PHẦN NÀO TỒN TẠI KHÔNG =====
TOTAL_FOUND=$((${#OPT_DIRS[@]} + ${#DESKTOP_FILES[@]} + ${#ICON_FILES[@]}))

if [ "$TOTAL_FOUND" -eq 0 ]; then
    echo "❌ Không tìm thấy bất kỳ thành phần nào của AppImage khớp với tên: \"$INPUT_NAME\""
    exit 1
fi

# ===== HIỂN THỊ CHI TIẾT TÊN VÀ ĐƯỜNG DẪN TRƯỚC KHI XÓA =====
echo "--------------------------------------------------------"
echo " Danh sách các thành phần ĐƯỢC TÌM THẤY và sẽ bị GỠ BỎ:"
echo "--------------------------------------------------------"

if [ ${#OPT_DIRS[@]} -gt 0 ]; then
    echo "[Thư mục cài đặt /opt]:"
    for dir in "${OPT_DIRS[@]}"; do
        echo "  • $dir"
    done
fi

if [ ${#DESKTOP_FILES[@]} -gt 0 ]; then
    echo "[Ứng dụng / Shortcut]:"
    for file in "${DESKTOP_FILES[@]}"; do
        echo "  • $file"
    done
fi

if [ ${#ICON_FILES[@]} -gt 0 ]; then
    echo "[Biểu tượng / Icon]:"
    for file in "${ICON_FILES[@]}"; do
        echo "  • $file"
    done
fi
echo "--------------------------------------------------------"

# ===== THỰC HIỆN CONFIRM Y/N =====
read -p "⚠️ Bạn có chắc chắn muốn xóa hoàn toàn các thành phần trên không? (y/N): " CONFIRM

# Nếu người dùng nhập khác Y hoặc y (hoặc nhấn Enter bỏ qua) -> Huỷ lệnh
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "❌ Đã hủy quá trình gỡ cài đặt. Không có tệp tin nào bị thay đổi."
    exit 0
fi

# ===== TIẾN HÀNH XÓA BỎ HOÀN TOÀN =====
echo ""
echo "==> Đang tiến hành xóa..."

# Xóa các tệp .desktop shortcut
for file in "${DESKTOP_FILES[@]}"; do
    echo "  [-] Đang xóa tệp shortcut: $file"
    sudo rm -f "$file"
done

# Xóa các tệp biểu tượng icon
for file in "${ICON_FILES[@]}"; do
    echo "  [-] Đang xóa tệp biểu tượng: $file"
    sudo rm -f "$file"
done

# Xóa các thư mục cài đặt chính trong /opt/
for dir in "${OPT_DIRS[@]}"; do
    echo "  [-] Đang xóa thư mục dữ liệu: $dir"
    sudo rm -rf "$dir"
done

# ===== CẬP NHẬT LẠI CACHE HỆ THỐNG =====
echo "==> Đang cập nhật lại cơ sở dữ liệu ứng dụng..."
if command -v update-desktop-database >/dev/null 2>&1; then
    sudo update-desktop-database /usr/share/applications
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi

echo ""
echo "✅ Quá trình gỡ bỏ hoàn toàn ứng dụng mốc \"$INPUT_NAME\" đã thành công!"
