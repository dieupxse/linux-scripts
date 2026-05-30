# 🛠️ Linux System Utilities & Automation Scripts

Kho lưu trữ này cung cấp bộ công cụ Shell Script (`.sh`) giúp tự động hóa các tác vụ quản trị, tối ưu hóa hiệu năng phần cứng, giám sát tài nguyên và tích hợp ứng dụng bên thứ ba trên môi trường Linux. Các kịch bản được thiết kế tối ưu nhất cho **Ubuntu/Debian** và hỗ trợ mở rộng cho các Distro phổ biến khác.

---

## 📋 Danh sách công cụ tổng quan

| Nhóm chức năng | Tệp tin (Scripts) | Quyền hạn | Vùng tác động |
| :--- | :--- | :--- | :--- |
| **Quản lý AppImage** | `install-appimage.sh`<br>`uninstall-appimage.sh` | `sudo` | `/opt/`, `/usr/share/applications/` |
| **Quản lý Nguồn điện** | `install-auto-power-profile.sh` | `sudo` | `/etc/udev/rules.d/`, `systemd` |
| **Giám sát Màn hình** | `install-onscreen-tracker.sh`<br>`uninstall-onscreen-tracker.sh` | `user` | `$HOME/.local/share/onscreen/` |
| **Tích hợp Zalo** | `install-zalo.sh`<br>`remove-zalo.sh` | `sudo` | `/opt/zalo/`, `Desktop Shortcuts` |
| **Chẩn đoán Hệ thống** | `system-report.sh` | `user` / `sudo` | Tối ưu Kernel, Boot-time, Log UI |
| **Tối ưu & Khôi phục Ubuntu** | `ubuntu-debloat.sh`<br>`ubuntu-restore.sh` | `sudo` | Gỡ bỏ/trả lại package và dịch vụ Canonical |
| **Khởi tạo Webserver Docker** | `init-webserver-docker.sh` | `sudo` | Docker, MySQL, Nginx, Certbot, net-tools |
| **Tài liệu Tham khảo** | `Ubuntu-Optimize-On-Thinkpad.xlsx` | `user` | Hướng dẫn tối ưu Ubuntu cho ThinkPad |

---

## 📖 Giải thích chi tiết và Hướng dẫn sử dụng

Cấp quyền chạy cho tất cả các tệp lệnh trước khi sử dụng:
```bash
chmod +x *.sh
```

### 1. Quản lý Ứng dụng AppImage Tổng Thể
Tự động tích hợp sâu các tệp `.AppImage` vào Menu Ứng dụng của hệ thống (trích xuất icon, tạo file `.desktop`).

* **Cài đặt ứng dụng:**
  ```bash
  sudo ./install-appimage.sh <đường-dẫn-file.AppImage>
  # Ví dụ: sudo ./install-appimage.sh ~/Downloads/DBeaver.AppImage
  ```
* **Gỡ cài đặt (Quét thông minh):**
  ```bash
  ./uninstall-appimage.sh "<Từ-khóa-tên-ứng-dụng>"
  # Ví dụ: ./uninstall-appimage.sh "DBeaver"
  ```

### 2. Tự động chuyển đổi Chế độ Nguồn điện (`auto-power-profile`)
Sử dụng `udev` rule và `systemd` để lắng nghe sự kiện phần cứng. Tự động chuyển sang chế độ `balanced` khi cắm sạc và `power-saver` khi dùng pin để tối ưu thời lượng pin.

* **Cài đặt:**
  ```bash
  sudo ./install-auto-power-profile.sh
  ```
  *(Yêu cầu hệ thống đã cài đặt `power-profiles-daemon`)*

### 3. Giám sát thời gian sử dụng màn hình (`onscreen-tracker`)
Chạy ngầm ở quyền user (không cần root), theo dõi thời gian on-screen và % pin tiêu hao. Tự động tạm dừng đếm giờ khi gập máy (Sleep/Hibernate).

* **Cài đặt:**
  ```bash
  ./install-onscreen-tracker.sh
  source ~/.bashrc
  ```
* **Tra cứu dữ liệu:**
  * `onscreen` : Xem thời gian dùng màn hình chu kỳ hiện tại.
  * `onscreen --today` : Tổng thời gian làm việc trong ngày.
  * `onscreen --history` : Xem bảng thống kê các ngày trước.
* **Gỡ cài đặt:**
  ```bash
  ./uninstall-onscreen-tracker.sh
  ```

### 4. Tích hợp Ứng dụng Zalo (Tối ưu Dark Mode)
Tự động tải bản build Zalo AppImage (tích hợp ZaDark) từ cộng đồng, thiết lập môi trường cài đặt và cấu hình lối tắt được cấp quyền tin cậy (`metadata::trusted`) trực tiếp ra Desktop.

* **Cài đặt:**
  ```bash
  sudo ./install-zalo.sh
  ```
* **Gỡ cài đặt sạch sẽ:**
  ```bash
  sudo ./remove-zalo.sh
  ```

### 5. Chẩn đoán & Tinh chỉnh Hệ thống (`system-report.sh`)
Kiểm tra sức khỏe hệ thống: Phân tích xung đột các daemon nguồn (TLP, thermald), cấu hình Ram/Swap (`swappiness`), hiển thị Top 10 dịch vụ làm chậm quá trình khởi động máy, thông số Kernel limits và check log lỗi giao diện GNOME/Wayland.

* **Sử dụng:**
  ```bash
  ./system-report.sh
  ```

### 6. Tối ưu & Khôi phục Ubuntu (`ubuntu-debloat.sh`, `ubuntu-restore.sh`)
Loại bỏ các package và dịch vụ Canonical không cần thiết, rồi khôi phục cấu hình gốc khi cần.

* **Tối ưu hệ thống:**
  ```bash
  sudo ./ubuntu-debloat.sh
  ```
* **Khôi phục lại:**
  ```bash
  sudo ./ubuntu-restore.sh
  ```

### 7. Khởi tạo Webserver Docker (`init-webserver-docker.sh`)
Thiết lập một máy chủ Ubuntu chuẩn với Docker, MySQL, Nginx, Certbot và net-tools.

* **Cài đặt toàn bộ stack:**
  ```bash
  sudo ./init-webserver-docker.sh
  ```
* **Điểm chính:**
  - Cập nhật hệ thống và cài đặt các thư viện cần thiết
  - Cài Docker Engine, Docker Compose plugin và containerd
  - Cài MySQL Server và MySQL Client
  - Cài Nginx và khởi động dịch vụ
  - Cài Certbot với plugin Nginx để cấp chứng chỉ SSL
  - Cài net-tools để hỗ trợ kiểm tra mạng

* **Lời khuyên sau khi chạy xong:**
  1. `sudo mysql_secure_installation`
  2. `sudo ufw allow OpenSSH`
  3. `sudo ufw allow 'Nginx Full'`
  4. `sudo certbot --nginx -d example.com`

---

## ⚠️ Khuyến cáo an toàn
* Hãy đọc kỹ mã nguồn trước khi chạy các script có yêu cầu quyền `sudo` trên môi trường Server/Production quan trọng.
* Khi dùng tính năng gỡ AppImage, **không** nhập các từ khóa quá ngắn hoặc chung chung (như `app`, `bin`, `test`) để tránh script quét trúng và xóa nhầm các thư mục hệ thống trùng tên.