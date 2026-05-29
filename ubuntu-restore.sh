#!/usr/bin/env bash
# =============================================================================
#  ubuntu-restore.sh
#  Khôi phục lại toàn bộ những gì ubuntu-debloat.sh đã thay đổi
#  Tương thích: Ubuntu 26.04 LTS (Resolute Raccoon) — GNOME Desktop
#
#  Chạy: chmod +x ubuntu-restore.sh && sudo ./ubuntu-restore.sh
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
log_skip()    { echo -e "  ${YELLOW}↷${NC}  $1 (bỏ qua)"; }

apt_install() {
    log_info "Cài: $*"
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" 2>/dev/null || log_warn "Không thể cài: $*"
}

service_enable() {
    for svc in "$@"; do
        systemctl enable "$svc" 2>/dev/null || true
        systemctl start  "$svc" 2>/dev/null || true
        log_ok "Enabled & started: $svc"
    done
}

# ── Kiểm tra quyền ───────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}✘  Script cần chạy với sudo: sudo ./ubuntu-restore.sh${NC}"
    exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${BOLD}${YELLOW}"
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║      Ubuntu 26.04 — Restore Script        ║"
echo "  ║  Khôi phục lại trạng thái Ubuntu gốc      ║"
echo "  ╚═══════════════════════════════════════════╝"
echo -e "${NC}"
log_warn "Script này sẽ cài lại toàn bộ services Canonical đã gỡ."
echo -e "  Nhấn ${BOLD}Enter${NC} để tiếp tục, hoặc ${BOLD}Ctrl+C${NC} để hủy."
read -r

apt-get update -qq

# =============================================================================
log_section "BƯỚC 1 — Khôi phục Snap"
# =============================================================================

log_info "Gỡ APT pin block snapd..."
rm -f /etc/apt/preferences.d/nosnap.pref
apt-mark unhold snapd 2>/dev/null || true
log_ok "Đã xóa nosnap.pref"

log_info "Cài lại snapd..."
apt_install snapd

log_info "Enable snapd services..."
service_enable snapd.service snapd.socket snapd.seeded.service

log_info "Đợi snapd sẵn sàng..."
sleep 3
snap wait system seed.loaded 2>/dev/null || sleep 5

log_info "Cài lại các Snap mặc định của Ubuntu 26.04..."
snap install snap-store        2>/dev/null || log_warn "snap-store: thử lại sau"
snap install firefox           2>/dev/null || log_warn "firefox snap: thử lại sau"
snap install firmware-updater  2>/dev/null || log_warn "firmware-updater: thử lại sau"
snap install desktop-security-center 2>/dev/null || log_warn "desktop-security-center: thử lại sau"

log_info "Gỡ Firefox .deb (Mozilla PPA) nếu đang dùng..."
if dpkg -l firefox 2>/dev/null | grep -q "^ii" && \
   apt-cache policy firefox 2>/dev/null | grep -q "mozillateam"; then
    apt-get purge -y firefox 2>/dev/null || true
    rm -f /etc/apt/preferences.d/mozilla-firefox
    # Xóa PPA mozillateam
    add-apt-repository --remove ppa:mozillateam/ppa -y 2>/dev/null || true
    log_ok "Đã xóa Firefox .deb và Mozilla PPA"
fi

# =============================================================================
log_section "BƯỚC 2 — Khôi phục Telemetry & Crash Reporting"
# =============================================================================

log_info "Cài lại telemetry packages..."
apt_install ubuntu-report popularity-contest whoopsie apport apport-gtk

log_info "Enable whoopsie service..."
service_enable whoopsie.service 2>/dev/null || true

# =============================================================================
log_section "BƯỚC 3 — Khôi phục Ubuntu Pro Client"
# =============================================================================

log_info "Cài lại ubuntu-pro-client..."
apt_install ubuntu-pro-client ubuntu-pro-client-l10n

log_info "Enable Ubuntu Pro services..."
service_enable ubuntu-advantage.service 2>/dev/null || true
service_enable ubuntu-pro-timer.timer    2>/dev/null || true

# =============================================================================
log_section "BƯỚC 4 — Khôi phục Landscape Client"
# =============================================================================

log_info "Cài lại landscape-client..."
apt_install landscape-client landscape-common

# =============================================================================
log_section "BƯỚC 5 — Khôi phục MOTD"
# =============================================================================

log_info "Restore quyền thực thi MOTD scripts..."
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
        chmod +x "$f"
        log_ok "chmod +x $f"
    fi
done

log_info "Bật lại motd-news..."
service_enable motd-news.service motd-news.timer 2>/dev/null || true

if [[ -f /etc/default/motd-news ]]; then
    sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/motd-news
    log_ok "motd-news ENABLED=1"
fi

# =============================================================================
log_section "BƯỚC 6 — Khôi phục GNOME Tracker"
# =============================================================================

log_info "Unmask tracker services cho user: $REAL_USER ..."
sudo -u "$REAL_USER" systemctl --user unmask \
    tracker-miner-fs-3.service \
    tracker-extract-3.service \
    tracker-writeback-3.service \
    tracker-xdg-portal-3.service \
    2>/dev/null || true

sudo -u "$REAL_USER" systemctl --user enable \
    tracker-miner-fs-3.service \
    tracker-extract-3.service \
    2>/dev/null || true

sudo -u "$REAL_USER" systemctl --user start \
    tracker-miner-fs-3.service \
    tracker-extract-3.service \
    2>/dev/null || true

log_ok "Tracker đã unmask và start"

# =============================================================================
log_section "BƯỚC 7 — Khôi phục Bundled Apps"
# =============================================================================

log_info "Cài lại games GNOME..."
apt_install gnome-mahjongg gnome-mines gnome-sudoku aisleriot

log_info "Cài lại apps..."
apt_install gnome-todo gnome-calendar simple-scan

# =============================================================================
log_section "BƯỚC 8 — Khôi phục Systemd Services"
# =============================================================================

service_enable canonical-livepatch.service            2>/dev/null || true
service_enable update-notifier-download.timer         2>/dev/null || true

# Bật lại apt auto-update timers
systemctl enable apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
systemctl start  apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
log_ok "apt-daily timers enabled"

# =============================================================================
log_section "BƯỚC 9 — Dọn dẹp sau restore"
# =============================================================================

log_info "apt update + autoremove..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y 2>/dev/null || true
apt-get clean

# =============================================================================
log_section "✅  HOÀN TẤT — Báo cáo"
# =============================================================================

echo ""
echo -e "${BOLD}  Kết quả kiểm tra:${NC}"
echo ""

# Snap
if command -v snap &>/dev/null 2>&1; then
    echo -e "  ${GREEN}✔${NC}  Snapd: ĐÃ CÀI LẠI"
    echo -e "         Snap packages: $(snap list 2>/dev/null | wc -l) items"
else
    echo -e "  ${YELLOW}⚠${NC}  Snapd: chưa cài được — thử reboot rồi chạy lại"
fi

# whoopsie
if dpkg -l whoopsie &>/dev/null 2>&1; then
    echo -e "  ${GREEN}✔${NC}  Whoopsie: ĐÃ CÀI LẠI"
fi

# ubuntu-pro
if dpkg -l ubuntu-pro-client &>/dev/null 2>&1; then
    echo -e "  ${GREEN}✔${NC}  Ubuntu Pro Client: ĐÃ CÀI LẠI"
fi

# Tracker
if sudo -u "$REAL_USER" systemctl --user is-enabled tracker-miner-fs-3.service 2>/dev/null | grep -q "enabled"; then
    echo -e "  ${GREEN}✔${NC}  GNOME Tracker: ĐÃ KHÔI PHỤC"
fi

echo ""
echo -e "  ${CYAN}RAM hiện tại:${NC}"
free -h | grep Mem
echo ""
echo -e "  ${BOLD}${GREEN}Restore hoàn thành! Vui lòng khởi động lại để áp dụng đầy đủ.${NC}"
echo ""
