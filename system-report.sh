#!/bin/bash

echo "===================================================="
echo "   UBUNTU SYSTEM TUNING DIAGNOSTIC REPORT"
echo "===================================================="
echo "Generated on: $(date)"
echo ""

echo "----------------------------------------------------"
echo "1. POWER & THERMAL DAEMONS STATUS"
echo "----------------------------------------------------"
for svc in power-profiles-daemon tlp thermald; do
    if systemctl is-active --quiet $svc; then
        echo "[-] $svc: ACTIVE"
    else
        echo "[-] $svc: INACTIVE hoặc chưa cài đặt"
    fi
done

echo ""
echo "----------------------------------------------------"
echo "2. VIRTUAL MEMORY & SWAP CONFIGURATION"
echo "----------------------------------------------------"
echo -n "[-] vm.swappiness: " && cat /proc/sys/vm/swappiness 2>/dev/null || echo "N/A"
echo -n "[-] vm.vfs_cache_pressure: " && cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null || echo "N/A"
echo "[-] Current Swap devices:"
swapon --show 2>/dev/null || echo "No active swap found."

echo ""
echo "----------------------------------------------------"
echo "3. BOOT-TIME ANALYSIS (Top 10 slowest services)"
echo "----------------------------------------------------"
if command -v systemd-analyze &> /dev/null; then
    systemd-analyze 2>/dev/null
    echo ""
    systemd-analyze blame 2>/dev/null | head -n 10
else
    echo "systemd-analyze không khả dụng."
fi

echo ""
echo "----------------------------------------------------"
echo "4. APPLICATION PACKAGING COUNTS"
echo "----------------------------------------------------"
echo -n "[-] Native APT packages (installed by user): "
apt list --installed 2>/dev/null | wc -l
echo -n "[-] Snap packages: "
if command -v snap &> /dev/null; then snap list 2>/dev/null | tail -n +2 | wc -l; else echo "0 (Snap not installed)"; fi
echo -n "[-] Flatpak packages: "
if command -v flatpak &> /dev/null; then flatpak list 2>/dev/null | wc -l; else echo "0 (Flatpak not installed)"; fi

echo ""
echo "----------------------------------------------------"
echo "5. DEV/OPS LIMITS & KERNEL PARAMETERS"
echo "----------------------------------------------------"
sysctl fs.file-max fs.inotify.max_user_watches fs.inotify.max_user_instances net.core.somaxconn net.ipv4.tcp_max_syn_backlog 2>/dev/null

echo ""
echo "----------------------------------------------------"
echo "6. ENVIRONMENT & RECENT GNOME ERRORS (Last 50 lines)"
echo "----------------------------------------------------"
echo "[-] XDG_SESSION_TYPE: $XDG_SESSION_TYPE"
echo "[-] Checking GNOME Shell extensions..."
gnome-extensions list --enabled 2>/dev/null || echo "No extensions found or command failed."
echo ""
echo "[-] Extracting last 5 GNOME/Wayland related errors from journalctl:"
journalctl --user -b -0 --priority=err | grep -E -i 'gnome|wayland|display' | tail -n 5 || echo "No structural errors found."
echo "===================================================="
