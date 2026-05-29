#!/usr/bin/env bash
# =============================================================================
#  ubuntu-debloat.sh
#  Loại bỏ hoàn toàn các service/package Canonical không cần thiết
#  Tương thích: Ubuntu 26.04 LTS (Resolute Raccoon) — GNOME Desktop
#
#  Chạy: chmod +x ubuntu-debloat.sh && sudo ./ubuntu-debloat.sh
# =============================================================================

set -euo pipefail

# ── Màu sắc terminal ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
log_section() { echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════${NC}"; echo -e "${BOLD}${BLUE}  $1${NC}"; echo -e "${BOLD}${BLUE}══════════════════════════════════════════${NC}"; }
log_ok()      { echo -e "  ${GREEN}✔${NC}  $1"; }
log_info()    { echo -e "  ${CYAN}→${NC}  $1"; }
log_warn()    { echo -e "  ${YELLOW}⚠${NC}  $1"; }
log_skip()    { echo -e "  ${YELLOW}↷${NC}  $1 (không tìm thấy — bỏ qua)"; }

apt_purge() {
    # Purge chỉ những package thực sự đang cài
    local pkgs=()
    for p in "$@"; do
        if dpkg -l "$p" &>/dev/null 2>&1; then
            pkgs+=("$p")
        fi
    done
    if [ ${#pkgs[@]} -gt 0 ]; then
        sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y "${pkgs[@]}" 2>/dev/null || true
        log_ok "Đã purge: ${pkgs[*]}"
    else
        log_skip "$*"
    fi
}

service_disable() {
    for svc in "$@"; do
        if systemctl list-units --full --all | grep -q "$svc"; then
            sudo systemctl stop "$svc"    2>/dev/null || true
            sudo systemctl disable "$svc" 2>/dev/null || true
            log_ok "Disabled: $svc"
        else
            log_skip "$svc"
        fi
    done
}

# ── Kiểm tra quyền ───────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}✘  Script cần chạy với sudo: sudo ./ubuntu-debloat.sh${NC}"
    exit 1
fi

# Lưu lại $HOME của user thật (không phải root)
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║      Ubuntu 26.04 — Debloat Script        ║"
echo "  ║  Loại bỏ services Canonical không cần     ║"
echo "  ╚═══════════════════════════════════════════╝"
echo -e "${NC}"
log_warn "Script này sẽ thay đổi hệ thống. Đã lưu backup chưa?"
echo -e "  Nhấn ${BOLD}Enter${NC} để tiếp tục, hoặc ${BOLD}Ctrl+C${NC} để hủy."
read -r

# Lưu trạng thái trước khi chạy để restore có thể dùng
BACKUP_DIR="/etc/ubuntu-debloat-backup"
sudo mkdir -p "$BACKUP_DIR"
log_info "Lưu trạng thái backup vào $BACKUP_DIR ..."
dpkg --get-selections > "$BACKUP_DIR/dpkg-selections.txt"
systemctl list-unit-files --state=enabled > "$BACKUP_DIR/systemd-enabled.txt" 2>/dev/null || true
log_ok "Backup trạng thái xong"

# =============================================================================
log_section "BƯỚC 1 — Gỡ Snap ecosystem"
# =============================================================================

log_info "Kiểm tra snapd..."
if command -v snap &>/dev/null && snap list &>/dev/null 2>&1; then
    log_info "Đang xóa tất cả snap packages theo thứ tự..."

    # Lấy danh sách snap đang cài và xóa từng cái
    SNAP_LIST=$(snap list 2>/dev/null | tail -n +2 | awk '{print $1}' || true)

    # Xóa user snaps trước (theo priority)
    for snap_pkg in firefox thunderbird snap-store desktop-security-center \
                    firmware-updater prompting-client snapd-desktop-integration \
                    gnome-46-2404 gnome-42-2204 gtk-common-themes mesa-2404 \
                    core24 core22 core20 bare; do
        if echo "$SNAP_LIST" | grep -q "^${snap_pkg}$"; then
            snap remove --purge "$snap_pkg" 2>/dev/null || true
            log_ok "Removed snap: $snap_pkg"
        fi
    done

    # Xóa bất kỳ snap nào còn sót
    REMAINING=$(snap list 2>/dev/null | tail -n +2 | awk '{print $1}' || true)
    for snap_pkg in $REMAINING; do
        snap remove --purge "$snap_pkg" 2>/dev/null || true
        log_ok "Removed snap: $snap_pkg"
    done
else
    log_skip "snapd"
fi

log_info "Dừng snapd services..."
service_disable snapd.service snapd.socket snapd.seeded.service

log_info "Purge snapd package..."
apt_purge snapd

log_info "Xóa thư mục snap còn lại..."
rm -rf "$REAL_HOME/snap" 2>/dev/null || true
rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd /usr/lib/snapd 2>/dev/null || true
log_ok "Đã xóa thư mục snap"

log_info "Khóa snapd — ngăn APT cài lại..."
apt-mark hold snapd 2>/dev/null || true
cat > /etc/apt/preferences.d/nosnap.pref << 'EOF'
Package: snapd
Pin: release a=*
Pin-Priority: -1
EOF
log_ok "Đã pin snapd priority = -1"

log_info "Cài Firefox .deb từ Mozilla PPA (thay Snap Firefox)..."
if ! dpkg -l firefox 2>/dev/null | grep -q "^ii"; then
    add-apt-repository ppa:mozillateam/ppa -y 2>/dev/null || true
    cat > /etc/apt/preferences.d/mozilla-firefox << 'EOF'
Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
EOF
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y firefox 2>/dev/null || true
    log_ok "Đã cài Firefox .deb"
else
    log_ok "Firefox .deb đã có sẵn"
fi

# =============================================================================
log_section "BƯỚC 2 — Gỡ Telemetry & Crash Reporting"
# =============================================================================

log_info "Purge telemetry packages..."
apt_purge ubuntu-report popularity-contest whoopsie apport apport-gtk apport-symptoms

# =============================================================================
log_section "BƯỚC 3 — Gỡ Ubuntu Pro / Advantage Client"
# =============================================================================

log_info "Dừng Ubuntu Pro services..."
service_disable ubuntu-advantage.service ubuntu-pro-timer.timer ua-timer.timer

log_info "Purge ubuntu-pro-client..."
apt_purge ubuntu-pro-client ubuntu-pro-client-l10n ubuntu-advantage-tools

# =============================================================================
log_section "BƯỚC 4 — Gỡ Landscape Client"
# =============================================================================

apt_purge landscape-client landscape-common

# =============================================================================
log_section "BƯỚC 5 — Tắt MOTD spam"
# =============================================================================

log_info "Disable MOTD Canonical scripts..."
MOTD_SCRIPTS=(
    /etc/update-motd.d/10-help-text
    /etc/update-motd.d/50-motd-news
    /etc/update-motd.d/80-livepatch
    /etc/update-motd.d/88-esm-announce
    /etc/update-motd.d/91-contract-ua-esm-status
    /etc/update-motd.d/92-unattended-upgrades
    /etc/update-motd.d/95-hwe-eol
)
for f in "${MOTD_SCRIPTS[@]}"; do
    if [[ -f "$f" ]]; then
        chmod -x "$f"
        log_ok "chmod -x $f"
    fi
done

log_info "Disable motd-news service..."
service_disable motd-news.service motd-news.timer

log_info "Tắt motd-news trong config..."
if [[ -f /etc/default/motd-news ]]; then
    sed -i 's/ENABLED=1/ENABLED=0/' /etc/default/motd-news
    log_ok "motd-news ENABLED=0"
fi

# =============================================================================
log_section "BƯỚC 6 — Disable GNOME Tracker (File Indexer)"
# =============================================================================

log_info "Mask tracker services cho user: $REAL_USER ..."
sudo -u "$REAL_USER" systemctl --user mask \
    tracker-miner-fs-3.service \
    tracker-extract-3.service \
    tracker-writeback-3.service \
    tracker-xdg-portal-3.service \
    2>/dev/null || true

sudo -u "$REAL_USER" systemctl --user stop \
    tracker-miner-fs-3.service \
    tracker-extract-3.service \
    2>/dev/null || true

log_info "Reset tracker database..."
sudo -u "$REAL_USER" tracker3 reset --filesystem --rss 2>/dev/null || true
rm -rf "$REAL_HOME/.cache/tracker3" 2>/dev/null || true
log_ok "Tracker đã mask + database xóa"

# =============================================================================
log_section "BƯỚC 7 — Gỡ Bundled Apps không cần thiết"
# =============================================================================

log_info "Gỡ games..."
apt_purge gnome-mahjongg gnome-mines gnome-sudoku aisleriot

log_info "Gỡ apps ít dùng..."
apt_purge gnome-todo gnome-calendar simple-scan

# =============================================================================
log_section "BƯỚC 8 — Disable Systemd Services Canonical"
# =============================================================================

service_disable canonical-livepatch.service
service_disable update-notifier-download.timer

# =============================================================================
log_section "BƯỚC 9 — Dọn dẹp cuối"
# =============================================================================

log_info "autoremove + clean..."
DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y 2>/dev/null || true
apt-get clean
apt-get autoclean

log_info "Xóa crash reports..."
rm -rf /var/crash/* 2>/dev/null || true

log_info "Vacuum journal logs (giữ 7 ngày)..."
journalctl --vacuum-time=7d 2>/dev/null || true

# =============================================================================
log_section "✅  HOÀN TẤT — Báo cáo"
# =============================================================================

echo ""
echo -e "${BOLD}  Kết quả kiểm tra:${NC}"
echo ""

# Snap
if ! command -v snap &>/dev/null 2>&1; then
    echo -e "  ${GREEN}✔${NC}  Snapd: ĐÃ GỠ"
else
    echo -e "  ${YELLOW}⚠${NC}  Snapd: vẫn còn (kiểm tra lại)"
fi

# whoopsie
if ! dpkg -l whoopsie &>/dev/null 2>&1; then
    echo -e "  ${GREEN}✔${NC}  Whoopsie (crash reporter): ĐÃ GỠ"
fi

# ubuntu-pro
if ! dpkg -l ubuntu-pro-client &>/dev/null 2>&1; then
    echo -e "  ${GREEN}✔${NC}  Ubuntu Pro Client: ĐÃ GỠ"
fi

# Tracker
if sudo -u "$REAL_USER" systemctl --user is-enabled tracker-miner-fs-3.service 2>/dev/null | grep -q "masked"; then
    echo -e "  ${GREEN}✔${NC}  GNOME Tracker: ĐÃ MASK"
fi

echo ""
echo -e "  ${CYAN}RAM hiện tại:${NC}"
free -h | grep Mem
echo ""
echo -e "  ${BOLD}${GREEN}Debloat hoàn thành! Khởi động lại để áp dụng đầy đủ.${NC}"
echo -e "  ${CYAN}Để khôi phục: sudo ./ubuntu-restore.sh${NC}"
echo ""
