#!/usr/bin/env bash

set -e

APP_NAME="onscreen-tracker"

echo "Installing $APP_NAME..."

# ==========================================
# Ubuntu/Debian Check
# ==========================================

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="$ID"
    OS_NAME="$NAME"
else
    echo "Unsupported OS"
    exit 1
fi

case "$OS_ID" in
    ubuntu|debian|linuxmint|pop|zorin)
        ;;
    *)
        echo "This installer supports Ubuntu/Debian based distros only"
        exit 1
        ;;
esac

echo "Detected OS: $OS_NAME"

# ==========================================
# Directories
# ==========================================

BIN_DIR="$HOME/.local/bin"
DATA_DIR="$HOME/.local/share/onscreen"
SYSTEMD_DIR="$HOME/.config/systemd/user"

mkdir -p "$BIN_DIR"
mkdir -p "$DATA_DIR"
mkdir -p "$SYSTEMD_DIR"

# ==========================================
# Main Daemon
# ==========================================

cat > "$BIN_DIR/onscreen-daemon.sh" <<'EOF'
#!/usr/bin/env bash

STATE_DIR="$HOME/.local/share/onscreen"

STATE_FILE="$STATE_DIR/state"
HISTORY_FILE="$STATE_DIR/history"

mkdir -p "$STATE_DIR"

touch "$STATE_FILE"
touch "$HISTORY_FILE"

# ==========================================
# Initialize State
# ==========================================

if [ ! -s "$STATE_FILE" ]; then

cat > "$STATE_FILE" <<STATE
START_TS=0
ACCUMULATED=0
RUNNING=0
LAST_AC=1
CYCLE_DATE=""
START_BATTERY=0
END_BATTERY=0
STATE

fi

source "$STATE_FILE"

START_TS=${START_TS:-0}
ACCUMULATED=${ACCUMULATED:-0}
RUNNING=${RUNNING:-0}
LAST_AC=${LAST_AC:-1}
START_BATTERY=${START_BATTERY:-0}
END_BATTERY=${END_BATTERY:-0}
CYCLE_DATE=${CYCLE_DATE:-""}

save_state() {

cat > "$STATE_FILE" <<STATE
START_TS=$START_TS
ACCUMULATED=$ACCUMULATED
RUNNING=$RUNNING
LAST_AC=$LAST_AC
CYCLE_DATE="$CYCLE_DATE"
START_BATTERY=$START_BATTERY
END_BATTERY=$END_BATTERY
STATE
}

now_ts() {
date +%s
}

format_date() {
date '+%Y-%m-%d %H:%M:%S'
}

# ==========================================
# AC Detection
# 1 = Plugged
# 0 = Battery
# ==========================================

get_ac_status() {

# Preferred detection

for supply in /sys/class/power_supply/*; do

    [ -d "$supply" ] || continue

    TYPE=$(cat "$supply/type" 2>/dev/null)

    case "$TYPE" in

        Mains|USB|USB_C|USB_PD)

            if [ -f "$supply/online" ]; then
                cat "$supply/online"
                return
            fi
            ;;

    esac

done

# Fallback battery status

for bat in /sys/class/power_supply/BAT*; do

    [ -d "$bat" ] || continue

    STATUS=$(cat "$bat/status" 2>/dev/null)

    case "$STATUS" in

        Charging|Full)
            echo 1
            return
            ;;

        Discharging)
            echo 0
            return
            ;;

    esac

done

echo 1
}

# ==========================================
# Battery Percentage
# ==========================================

get_battery_percent() {

for bat in /sys/class/power_supply/BAT*; do

    if [ -f "$bat/capacity" ]; then
        cat "$bat/capacity"
        return
    fi

done

echo 0
}

# ==========================================
# Start Count
# ==========================================

start_count() {

if [ "$RUNNING" -eq 0 ]; then

    START_TS=$(now_ts)

    RUNNING=1

    if [ -z "$CYCLE_DATE" ]; then

        CYCLE_DATE=$(format_date)

        START_BATTERY=$(get_battery_percent)

    fi

    save_state
fi
}

# ==========================================
# Pause Count
# ==========================================

pause_count() {

if [ "$RUNNING" -eq 1 ]; then

    NOW=$(now_ts)

    ACCUMULATED=$((ACCUMULATED + NOW - START_TS))

    RUNNING=0

    save_state
fi
}

# ==========================================
# Reset Cycle
# ==========================================

reset_cycle() {

TOTAL="$ACCUMULATED"

if [ "$RUNNING" -eq 1 ]; then

    NOW=$(now_ts)

    TOTAL=$((TOTAL + NOW - START_TS))
fi

END_BATTERY=$(get_battery_percent)

if [ "$TOTAL" -gt 0 ]; then

    echo "$CYCLE_DATE|$TOTAL|$START_BATTERY|$END_BATTERY" >> "$HISTORY_FILE"

fi

START_TS=0
ACCUMULATED=0
RUNNING=0
CYCLE_DATE=""
START_BATTERY=0
END_BATTERY=0

save_state
}

# ==========================================
# Restore Correctly After Reboot
# ==========================================

CURRENT_AC=$(get_ac_status)

if [ "$CURRENT_AC" = "0" ]; then

    if [ "$RUNNING" -eq 1 ]; then

        START_TS=$(now_ts)

    fi

fi

LAST_AC="$CURRENT_AC"

save_state

# ==========================================
# Main Loop
# ==========================================

while true; do

CURRENT_AC=$(get_ac_status)

# Charger plugged

if [ "$CURRENT_AC" = "1" ] && [ "$LAST_AC" = "0" ]; then

    pause_count

    reset_cycle
fi

# Charger unplugged

if [ "$CURRENT_AC" = "0" ] && [ "$LAST_AC" = "1" ]; then

    start_count
fi

# Continue counting while on battery

if [ "$CURRENT_AC" = "0" ]; then
    start_count
else
    pause_count
fi

LAST_AC="$CURRENT_AC"

save_state

sleep 2

done
EOF

chmod +x "$BIN_DIR/onscreen-daemon.sh"

# ==========================================
# Sleep Hook
# ==========================================

mkdir -p "$HOME/.local/share/systemd/user-sleep"

cat > "$HOME/.local/share/systemd/user-sleep/onscreen-sleep-hook.sh" <<'EOF'
#!/usr/bin/env bash

STATE_FILE="$HOME/.local/share/onscreen/state"

[ -f "$STATE_FILE" ] || exit 0

source "$STATE_FILE"

START_TS=${START_TS:-0}
ACCUMULATED=${ACCUMULATED:-0}
RUNNING=${RUNNING:-0}
LAST_AC=${LAST_AC:-1}
START_BATTERY=${START_BATTERY:-0}
END_BATTERY=${END_BATTERY:-0}
CYCLE_DATE=${CYCLE_DATE:-""}

save_state() {

cat > "$STATE_FILE" <<STATE
START_TS=$START_TS
ACCUMULATED=$ACCUMULATED
RUNNING=$RUNNING
LAST_AC=$LAST_AC
CYCLE_DATE="$CYCLE_DATE"
START_BATTERY=$START_BATTERY
END_BATTERY=$END_BATTERY
STATE
}

case "$1" in

    pre)

        if [ "$RUNNING" -eq 1 ]; then

            NOW=$(date +%s)

            ACCUMULATED=$((ACCUMULATED + NOW - START_TS))

            RUNNING=0

            save_state
        fi
        ;;

    post)

        AC=1

        for supply in /sys/class/power_supply/*; do

            TYPE=$(cat "$supply/type" 2>/dev/null)

            case "$TYPE" in

                Mains|USB|USB_C|USB_PD)

                    if [ -f "$supply/online" ]; then
                        AC=$(cat "$supply/online")
                        break
                    fi
                    ;;

            esac

        done

        if [ "$AC" = "0" ]; then

            START_TS=$(date +%s)

            RUNNING=1

            save_state
        fi
        ;;

esac
EOF

chmod +x "$HOME/.local/share/systemd/user-sleep/onscreen-sleep-hook.sh"

# ==========================================
# CLI
# ==========================================

cat > "$BIN_DIR/onscreen" <<'EOF'
#!/usr/bin/env bash

STATE_DIR="$HOME/.local/share/onscreen"

STATE_FILE="$STATE_DIR/state"
HISTORY_FILE="$STATE_DIR/history"

if [ ! -f "$STATE_FILE" ]; then
    echo "Onscreen tracker not initialized"
    exit 1
fi

source "$STATE_FILE"

START_TS=${START_TS:-0}
ACCUMULATED=${ACCUMULATED:-0}
RUNNING=${RUNNING:-0}
START_BATTERY=${START_BATTERY:-0}
CYCLE_DATE=${CYCLE_DATE:-""}

format_time() {

SECONDS=$1

H=$((SECONDS / 3600))
M=$(((SECONDS % 3600) / 60))
S=$((SECONDS % 60))

printf "%02dh %02dm %02ds" "$H" "$M" "$S"
}

current_total() {

TOTAL=$ACCUMULATED

if [ "$RUNNING" -eq 1 ]; then

    NOW=$(date +%s)

    TOTAL=$((TOTAL + NOW - START_TS))
fi

echo "$TOTAL"
}

get_current_battery() {

for bat in /sys/class/power_supply/BAT*; do

    if [ -f "$bat/capacity" ]; then
        cat "$bat/capacity"
        return
    fi

done

echo 0
}

show_current() {

TOTAL=$(current_total)

DATE_SHOW="$CYCLE_DATE"

if [ -z "$DATE_SHOW" ]; then
    DATE_SHOW=$(date '+%Y-%m-%d')
fi

CURRENT_BATTERY=$(get_current_battery)

echo "Date: $DATE_SHOW $(format_time "$TOTAL") ${START_BATTERY}% - ${CURRENT_BATTERY}%"
}

show_history() {

if [ ! -s "$HISTORY_FILE" ]; then
    echo "No history"
    exit 0
fi

tail -n 7 "$HISTORY_FILE" | tac | while IFS='|' read -r DATE TOTAL START_BAT END_BAT; do

    echo "Date: $DATE $(format_time "$TOTAL") ${START_BAT}% - ${END_BAT}%"

done
}

show_week() {

if [ ! -s "$HISTORY_FILE" ]; then
    echo "No history"
    exit 0
fi

NOW=$(date +%s)

WEEK_AGO=$((NOW - 604800))

TOTAL_WEEK=0

while IFS='|' read -r DATE TOTAL START_BAT END_BAT; do

    TS=$(date -d "$DATE" +%s 2>/dev/null || echo 0)

    if [ "$TS" -ge "$WEEK_AGO" ]; then
        TOTAL_WEEK=$((TOTAL_WEEK + TOTAL))
    fi

done < "$HISTORY_FILE"

echo "Last 7 days: $(format_time "$TOTAL_WEEK")"
}

case "$1" in

    --today|"")
        show_current
        ;;

    --history)
        show_history
        ;;

    --week|--w)
        show_week
        ;;

    *)
        echo "Usage:"
        echo "onscreen"
        echo "onscreen --today"
        echo "onscreen --history"
        echo "onscreen --week"
        echo "onscreen --w"
        ;;
esac
EOF

chmod +x "$BIN_DIR/onscreen"

# ==========================================
# Main Service
# ==========================================

cat > "$SYSTEMD_DIR/onscreen.service" <<EOF
[Unit]
Description=OnScreen Battery Usage Tracker

[Service]
ExecStart=%h/.local/bin/onscreen-daemon.sh
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
EOF

# ==========================================
# Sleep Service
# ==========================================

cat > "$SYSTEMD_DIR/onscreen-sleep.service" <<EOF
[Unit]
Description=Onscreen Sleep Hook

[Service]
Type=oneshot
ExecStart=%h/.local/share/systemd/user-sleep/onscreen-sleep-hook.sh pre
ExecStop=%h/.local/share/systemd/user-sleep/onscreen-sleep-hook.sh post
RemainAfterExit=yes

[Install]
WantedBy=suspend.target
WantedBy=hibernate.target
EOF

# ==========================================
# PATH
# ==========================================

if ! grep -q '.local/bin' "$HOME/.bashrc"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi

# ==========================================
# Reset old state
# ==========================================

rm -f "$DATA_DIR/state"

# ==========================================
# Enable Services
# ==========================================

systemctl --user daemon-reload

systemctl --user enable --now onscreen.service
systemctl --user enable onscreen-sleep.service

echo
echo "========================================"
echo "Installed successfully"
echo "========================================"
echo
echo "Commands:"
echo
echo "onscreen"
echo "onscreen --today"
echo "onscreen --history"
echo "onscreen --week"
echo "onscreen --w"
echo
echo "Restart terminal or run:"
echo
echo "source ~/.bashrc"
echo