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
# Daemon
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
ACCUMULATED=0
LAST_TS=0
LAST_AC=1
CYCLE_DATE=""
START_BATTERY=0
STATE

fi

source "$STATE_FILE"

ACCUMULATED=${ACCUMULATED:-0}
LAST_TS=${LAST_TS:-0}
LAST_AC=${LAST_AC:-1}
CYCLE_DATE=${CYCLE_DATE:-""}
START_BATTERY=${START_BATTERY:-0}

save_state() {

cat > "$STATE_FILE" <<STATE
ACCUMULATED=$ACCUMULATED
LAST_TS=$LAST_TS
LAST_AC=$LAST_AC
CYCLE_DATE="$CYCLE_DATE"
START_BATTERY=$START_BATTERY
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
# ==========================================

get_ac_status() {

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
# Battery %
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
# Restore State
# ==========================================

CURRENT_AC=$(get_ac_status)

LAST_TS=$(now_ts)

LAST_AC="$CURRENT_AC"

save_state

# ==========================================
# Main Loop
# ==========================================

while true; do

CURRENT_AC=$(get_ac_status)

NOW=$(now_ts)

DELTA=$((NOW - LAST_TS))

# Ignore suspend/reboot delta

if [ "$DELTA" -gt 15 ]; then
    DELTA=0
fi

# Plugged -> reset cycle

if [ "$CURRENT_AC" = "1" ] && [ "$LAST_AC" = "0" ]; then

    END_BATTERY=$(get_battery_percent)

    if [ "$ACCUMULATED" -gt 0 ]; then

        echo "$CYCLE_DATE|$ACCUMULATED|$START_BATTERY|$END_BATTERY" >> "$HISTORY_FILE"

    fi

    ACCUMULATED=0
    CYCLE_DATE=""
    START_BATTERY=0
fi

# Unplugged

if [ "$CURRENT_AC" = "0" ]; then

    if [ -z "$CYCLE_DATE" ]; then

        CYCLE_DATE=$(format_date)

        START_BATTERY=$(get_battery_percent)

    fi

    ACCUMULATED=$((ACCUMULATED + DELTA))
fi

LAST_TS="$NOW"
LAST_AC="$CURRENT_AC"

save_state

sleep 2

done
EOF

chmod +x "$BIN_DIR/onscreen-daemon.sh"

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

ACCUMULATED=${ACCUMULATED:-0}
LAST_TS=${LAST_TS:-0}
LAST_AC=${LAST_AC:-1}
CYCLE_DATE=${CYCLE_DATE:-""}
START_BATTERY=${START_BATTERY:-0}

format_time() {

SECONDS=$1

H=$((SECONDS / 3600))
M=$(((SECONDS % 3600) / 60))
S=$((SECONDS % 60))

printf "%02dh %02dm %02ds" "$H" "$M" "$S"
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

TOTAL=$ACCUMULATED

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
# Service
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
# Enable Service
# ==========================================

systemctl --user daemon-reload

systemctl --user enable --now onscreen.service

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