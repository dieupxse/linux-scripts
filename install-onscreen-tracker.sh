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
IDLE_ACCUMULATED=0
LAST_BATTERY=0
SHUTDOWN_TS=0
STATE
fi

source "$STATE_FILE"

ACCUMULATED=${ACCUMULATED:-0}
LAST_TS=${LAST_TS:-0}
LAST_AC=${LAST_AC:-1}
CYCLE_DATE=${CYCLE_DATE:-""}
START_BATTERY=${START_BATTERY:-0}
IDLE_ACCUMULATED=${IDLE_ACCUMULATED:-0}
LAST_BATTERY=${LAST_BATTERY:-0}
SHUTDOWN_TS=${SHUTDOWN_TS:-0}

save_state() {
    local tmp
    tmp=$(mktemp "$STATE_DIR/.state.XXXXXX")
    cat > "$tmp" <<STATE
ACCUMULATED=$ACCUMULATED
LAST_TS=$LAST_TS
LAST_AC=$LAST_AC
CYCLE_DATE="$CYCLE_DATE"
START_BATTERY=$START_BATTERY
IDLE_ACCUMULATED=$IDLE_ACCUMULATED
LAST_BATTERY=$LAST_BATTERY
SHUTDOWN_TS=$SHUTDOWN_TS
STATE
    mv -f "$tmp" "$STATE_FILE"
}

now_ts()     { date +%s; }
format_date(){ date '+%Y-%m-%d %H:%M:%S'; }

# ==========================================
# AC Detection
# ==========================================

get_ac_status() {
    # Priority: Mains
    for supply in /sys/class/power_supply/*; do
        [ -d "$supply" ] || continue
        local type
        type=$(cat "$supply/type" 2>/dev/null)
        if [ "$type" = "Mains" ] && [ -f "$supply/online" ]; then
            cat "$supply/online"
            return
        fi
    done
    # Fallback: USB-C / USB-PD
    for supply in /sys/class/power_supply/*; do
        [ -d "$supply" ] || continue
        local type
        type=$(cat "$supply/type" 2>/dev/null)
        case "$type" in USB|USB_C|USB_PD)
            [ -f "$supply/online" ] && { cat "$supply/online"; return; }
        esac
    done
    # Fallback: battery status
    for bat in /sys/class/power_supply/BAT*; do
        [ -d "$bat" ] || continue
        local status
        status=$(cat "$bat/status" 2>/dev/null)
        case "$status" in
            Charging|Full) echo 1; return ;;
            Discharging)   echo 0; return ;;
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

# If SHUTDOWN_TS is set, the daemon was stopped cleanly via ExecStop.
# Calculate the gap between shutdown and now and add it to idle time.

if [ "$SHUTDOWN_TS" -gt 0 ]; then
    BOOT_GAP=$(( $(now_ts) - SHUTDOWN_TS ))
    [ "$BOOT_GAP" -gt 0 ] && IDLE_ACCUMULATED=$((IDLE_ACCUMULATED + BOOT_GAP))
    SHUTDOWN_TS=0
fi

CURRENT_AC=$(get_ac_status)
LAST_BATTERY=$(get_battery_percent)
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
    CURRENT_BATTERY=$(get_battery_percent)

    # ---- Suspend / hibernate / wake detection ----
    # DELTA > 60 means the loop was frozen — system was suspended.
    # Accumulate the gap as idle time.
    # If battery increased during the gap, the charger was connected
    # while sleeping → close session using pre-suspend battery as end value.

    if [ "$DELTA" -gt 60 ]; then

        IDLE_ACCUMULATED=$((IDLE_ACCUMULATED + DELTA))

        if [ "$LAST_AC" = "0" ] && \
           [ "$CURRENT_BATTERY" -gt "$LAST_BATTERY" ] && \
           [ "$ACCUMULATED" -gt 0 ] && \
           [ -n "$CYCLE_DATE" ]; then

            echo "$CYCLE_DATE|$ACCUMULATED|$START_BATTERY|$LAST_BATTERY|$IDLE_ACCUMULATED" \
                >> "$HISTORY_FILE"

            ACCUMULATED=0
            IDLE_ACCUMULATED=0
            CYCLE_DATE=""
            START_BATTERY=0
        fi

        DELTA=0
    fi

    # ---- Plugged in → end session ----

    if [ "$CURRENT_AC" = "1" ] && [ "$LAST_AC" = "0" ]; then

        if [ "$ACCUMULATED" -gt 0 ]; then
            echo "$CYCLE_DATE|$ACCUMULATED|$START_BATTERY|$CURRENT_BATTERY|$IDLE_ACCUMULATED" \
                >> "$HISTORY_FILE"
        fi

        ACCUMULATED=0
        IDLE_ACCUMULATED=0
        CYCLE_DATE=""
        START_BATTERY=0
    fi

    # ---- On battery → accumulate active time ----

    if [ "$CURRENT_AC" = "0" ]; then

        if [ -z "$CYCLE_DATE" ]; then
            CYCLE_DATE=$(format_date)
            START_BATTERY=$CURRENT_BATTERY
        fi

        ACCUMULATED=$((ACCUMULATED + DELTA))
    fi

    LAST_BATTERY=$CURRENT_BATTERY
    LAST_TS="$NOW"
    LAST_AC="$CURRENT_AC"

    save_state
    sleep 2

done
EOF

chmod +x "$BIN_DIR/onscreen-daemon.sh"

# ==========================================
# Flush script  (called by ExecStop)
# Saves shutdown timestamp so the daemon can
# calculate idle gap on next boot.
# ==========================================

cat > "$BIN_DIR/onscreen-flush.sh" <<'EOF'
#!/usr/bin/env bash

STATE_DIR="$HOME/.local/share/onscreen"
STATE_FILE="$STATE_DIR/state"

[ -f "$STATE_FILE" ] || exit 0

source "$STATE_FILE"

tmp=$(mktemp "$STATE_DIR/.state.XXXXXX")
cat > "$tmp" <<STATE
ACCUMULATED=${ACCUMULATED:-0}
LAST_TS=${LAST_TS:-0}
LAST_AC=${LAST_AC:-1}
CYCLE_DATE="${CYCLE_DATE:-}"
START_BATTERY=${START_BATTERY:-0}
IDLE_ACCUMULATED=${IDLE_ACCUMULATED:-0}
LAST_BATTERY=${LAST_BATTERY:-0}
SHUTDOWN_TS=$(date +%s)
STATE
mv -f "$tmp" "$STATE_FILE"
EOF

chmod +x "$BIN_DIR/onscreen-flush.sh"

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
IDLE_ACCUMULATED=${IDLE_ACCUMULATED:-0}
LAST_BATTERY=${LAST_BATTERY:-0}
SHUTDOWN_TS=${SHUTDOWN_TS:-0}

# hh:mm:ss
format_time() {
    local total_secs=$1
    local H=$((total_secs / 3600))
    local M=$(((total_secs % 3600) / 60))
    local S=$((total_secs % 60))
    printf "%02dh %02dm %02ds" "$H" "$M" "$S"
}

# hh:mm  (compact, for tables)
format_time_hm() {
    local total_secs=$1
    local H=$((total_secs / 3600))
    local M=$(((total_secs % 3600) / 60))
    printf "%02dh %02dm" "$H" "$M"
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

# ==========================================
# show_current  (--today / default)
# ==========================================

show_current() {

    local date_show="${CYCLE_DATE:-$(date '+%Y-%m-%d')}"
    local current_battery
    current_battery=$(get_current_battery)

    if [ "${LAST_AC:-1}" = "1" ]; then
        echo "🔌 Charging — not tracking"
        echo "   Battery : ${current_battery}%"
        return
    fi

    echo "🔋 On battery — tracking"
    echo "   Session  : $date_show"
    echo "   Active   : $(format_time "$ACCUMULATED")"

    if [ "${IDLE_ACCUMULATED:-0}" -gt 0 ]; then
        echo "   Idle     : $(format_time "$IDLE_ACCUMULATED")  (sleep / suspend / shutdown)"
    fi

    echo "   Battery  : ${START_BATTERY}% → ${current_battery}%"

    local drain=$((START_BATTERY - current_battery))

    if [ "$ACCUMULATED" -ge 60 ] && [ "$drain" -gt 0 ]; then

        local rate_x10=$(( (drain * 36000) / ACCUMULATED ))
        local rate_int=$((rate_x10 / 10))
        local rate_dec=$((rate_x10 % 10))
        local remaining_mins=$(( (current_battery * 600) / rate_x10 ))
        local r_h=$((remaining_mins / 60))
        local r_m=$((remaining_mins % 60))

        echo "   Drain    : ${drain}% total  |  ${rate_int}.${rate_dec}% / hr"
        echo "   Remaining: ~${r_h}h ${r_m}m"

    elif [ "$ACCUMULATED" -lt 60 ]; then
        echo "   Drain    : (need >60s to estimate)"
    else
        echo "   Drain    : 0% — battery not decreasing"
    fi
}

# ==========================================
# show_history  (--history)
# ==========================================

show_history() {

    local limit=${1:-10}

    declare -a h_date h_secs h_start h_end h_idle

    if [ -f "$HISTORY_FILE" ] && [ -s "$HISTORY_FILE" ]; then
        while IFS='|' read -r DATE TOTAL START_BAT END_BAT IDLE; do
            h_date+=("$DATE")
            h_secs+=("$TOTAL")
            h_start+=("$START_BAT")
            h_end+=("$END_BAT")
            h_idle+=("${IDLE:-0}")
        done < <(tail -n "$limit" "$HISTORY_FILE" | tac)
    fi

    # Prepend ongoing session
    local has_ongoing=0
    local current_bat
    current_bat=$(get_current_battery)

    if [ "${LAST_AC:-1}" = "0" ] && [ "$ACCUMULATED" -gt 0 ] && [ -n "$CYCLE_DATE" ]; then
        h_date=("$CYCLE_DATE" "${h_date[@]}")
        h_secs=("$ACCUMULATED" "${h_secs[@]}")
        h_start=("$START_BATTERY" "${h_start[@]}")
        h_end=("$current_bat" "${h_end[@]}")
        h_idle=("${IDLE_ACCUMULATED:-0}" "${h_idle[@]}")
        has_ongoing=1
    fi

    local count=${#h_date[@]}

    if [ "$count" -eq 0 ]; then
        echo "  No history"
        return
    fi

    local max_secs=1
    for i in "${!h_secs[@]}"; do
        [ "${h_secs[$i]}" -gt "$max_secs" ] && max_secs="${h_secs[$i]}"
    done

    local BAR_WIDTH=20

    make_bar() {
        local filled=$1 total=$2 bar=""
        local i
        for ((i=0; i<filled; i++));     do bar+="█"; done
        for ((i=filled; i<total; i++)); do bar+="░"; done
        echo "$bar"
    }

    echo
    echo "  🗂   Session history  (last $count)"
    echo "  $(printf '%.0s─' $(seq 1 74))"
    printf "  %-18s  %-${BAR_WIDTH}s  %-14s  %-18s  %-10s  %s\n" \
        "Started" "Duration" "Active" "Battery" "Rate" "Idle"
    echo "  $(printf '%.0s─' $(seq 1 74))"

    for i in "${!h_date[@]}"; do

        local secs=${h_secs[$i]}
        local start=${h_start[$i]}
        local end=${h_end[$i]}
        local idle=${h_idle[$i]:-0}
        local date_label drain rate_str idle_str tag

        date_label=$(date -d "${h_date[$i]}" '+%a %d/%m %H:%M' 2>/dev/null \
                     || echo "${h_date[$i]}")

        local filled=$(( (secs * BAR_WIDTH) / max_secs ))
        [ "$filled" -lt 1 ] && filled=1
        local bar
        bar=$(make_bar "$filled" "$BAR_WIDTH")

        drain=$(( start - end ))
        local battery_str
        battery_str=$(printf "%3d%%→%3d%% (-%d%%)" "$start" "$end" "$drain")

        if [ "$secs" -ge 60 ] && [ "$drain" -gt 0 ]; then
            local rate_x10=$(( (drain * 36000) / secs ))
            rate_str=$(printf "%d.%d%%/hr" $((rate_x10/10)) $((rate_x10%10)))
        elif [ "$drain" -le 0 ]; then
            rate_str="—"
        else
            rate_str="~"
        fi

        if [ "$idle" -gt 60 ]; then
            idle_str=$(format_time_hm "$idle")
        else
            idle_str="—"
        fi

        tag=""
        [ "$i" -eq 0 ] && [ "$has_ongoing" -eq 1 ] && tag="  🔋"

        printf "  %-18s  %s  %-14s  %-18s  %-10s  %s%s\n" \
            "$date_label" "$bar" "$(format_time "$secs")" \
            "$battery_str" "$rate_str" "$idle_str" "$tag"
    done

    echo "  $(printf '%.0s─' $(seq 1 74))"

    local grand_total=0
    local grand_idle=0
    for i in "${!h_secs[@]}"; do
        grand_total=$((grand_total + h_secs[$i]))
        grand_idle=$((grand_idle + ${h_idle[$i]:-0}))
    done

    local avg_secs=$(( grand_total / count ))
    local idle_footer=""
    [ "$grand_idle" -gt 0 ] && idle_footer="  │  idle total: $(format_time_hm "$grand_idle")"

    printf "  %-18s  %-${BAR_WIDTH}s  %-14s  avg %s/session%s\n" \
        "$count sessions" "" "$(format_time "$grand_total")" \
        "$(format_time_hm "$avg_secs")" "$idle_footer"
    echo
}

# ==========================================
# show_week  (--week / -w)
# ==========================================

show_week() {

    local now week_ago
    now=$(date +%s)
    week_ago=$((now - 604800))

    declare -A day_secs day_bat_start day_bat_end day_ongoing day_idle

    if [ -f "$HISTORY_FILE" ] && [ -s "$HISTORY_FILE" ]; then
        while IFS='|' read -r DATE TOTAL START_BAT END_BAT IDLE; do
            local ts day
            ts=$(date -d "$DATE" +%s 2>/dev/null || echo 0)
            [ "$ts" -lt "$week_ago" ] && continue
            day=$(date -d "$DATE" '+%Y-%m-%d')
            day_secs[$day]=$(( ${day_secs[$day]:-0} + TOTAL ))
            day_idle[$day]=$(( ${day_idle[$day]:-0} + ${IDLE:-0} ))
            [ -z "${day_bat_start[$day]}" ] && day_bat_start[$day]=$START_BAT
            day_bat_end[$day]=$END_BAT
        done < "$HISTORY_FILE"
    fi

    # Ongoing session
    local current_bat ongoing_day=""
    current_bat=$(get_current_battery)

    if [ "${LAST_AC:-1}" = "0" ] && [ "$ACCUMULATED" -gt 0 ] && [ -n "$CYCLE_DATE" ]; then
        local ts
        ts=$(date -d "$CYCLE_DATE" +%s 2>/dev/null || echo 0)
        if [ "$ts" -ge "$week_ago" ]; then
            ongoing_day=$(date '+%Y-%m-%d')
            day_secs[$ongoing_day]=$(( ${day_secs[$ongoing_day]:-0} + ACCUMULATED ))
            day_idle[$ongoing_day]=$(( ${day_idle[$ongoing_day]:-0} + ${IDLE_ACCUMULATED:-0} ))
            [ -z "${day_bat_start[$ongoing_day]}" ] && day_bat_start[$ongoing_day]=$START_BATTERY
            day_bat_end[$ongoing_day]=$current_bat
            day_ongoing[$ongoing_day]=1
        fi
    fi

    local max_secs=1
    for d in "${!day_secs[@]}"; do
        [ "${day_secs[$d]}" -gt "$max_secs" ] && max_secs="${day_secs[$d]}"
    done

    local BAR_WIDTH=24
    local grand_total=0
    local grand_idle=0

    make_bar() {
        local filled=$1 total=$2 bar=""
        local i
        for ((i=0; i<filled; i++));     do bar+="█"; done
        for ((i=filled; i<total; i++)); do bar+="░"; done
        echo "$bar"
    }

    echo
    echo "  📅  Last 7 days"
    echo "  $(printf '%.0s─' $(seq 1 65))"

    for i in 6 5 4 3 2 1 0; do

        local day label secs idle bar battery_info idle_str tag
        day=$(date -d "$i days ago" '+%Y-%m-%d')
        label=$(date -d "$day" '+%a %d/%m')
        secs=${day_secs[$day]:-0}
        idle=${day_idle[$day]:-0}

        grand_total=$((grand_total + secs))
        grand_idle=$((grand_idle + idle))

        if [ "$secs" -eq 0 ]; then
            printf "  %-9s  %s  —\n" "$label" "$(printf '%.0s ' $(seq 1 $BAR_WIDTH))"
            continue
        fi

        local filled=$(( (secs * BAR_WIDTH) / max_secs ))
        [ "$filled" -lt 1 ] && filled=1
        bar=$(make_bar "$filled" "$BAR_WIDTH")

        battery_info=""
        if [ -n "${day_bat_start[$day]}" ]; then
            local drain=$(( day_bat_start[$day] - day_bat_end[$day] ))
            battery_info=$(printf "%3d%%→%3d%% (-%d%%)" \
                "${day_bat_start[$day]}" "${day_bat_end[$day]}" "$drain")
        fi

        idle_str=""
        [ "$idle" -gt 60 ] && idle_str="  +$(format_time_hm "$idle") idle"

        tag=""
        [ "${day_ongoing[$day]:-0}" = "1" ] && tag="  🔋"

        printf "  %-9s  %s  %s  %-18s%s%s\n" \
            "$label" "$bar" "$(format_time "$secs")" \
            "$battery_info" "$idle_str" "$tag"
    done

    echo "  $(printf '%.0s─' $(seq 1 65))"

    local idle_footer=""
    [ "$grand_idle" -gt 0 ] && idle_footer="  │  idle: $(format_time_hm "$grand_idle")"

    printf "  %-9s  %s  %s%s\n" \
        "Total" "$(printf '%.0s ' $(seq 1 $BAR_WIDTH))" \
        "$(format_time "$grand_total")" "$idle_footer"
    echo
}

# ==========================================
# show_watch  (--watch)
# ==========================================

show_watch() {

    local interval=${1:-2}

    if ! command -v watch &>/dev/null; then
        echo "  'watch' not found. Install with: sudo apt install procps"
        exit 1
    fi

    local self
    self=$(command -v onscreen)

    if [ -z "$self" ]; then
        echo "  Cannot locate 'onscreen' in PATH"
        exit 1
    fi

    watch --color -n "$interval" -t "$self --live"
}

# ==========================================
# Dispatch
# ==========================================

case "$1" in

    --live)
        source "$STATE_FILE"
        ACCUMULATED=${ACCUMULATED:-0}
        LAST_TS=${LAST_TS:-0}
        LAST_AC=${LAST_AC:-1}
        CYCLE_DATE=${CYCLE_DATE:-""}
        START_BATTERY=${START_BATTERY:-0}
        IDLE_ACCUMULATED=${IDLE_ACCUMULATED:-0}
        LAST_BATTERY=${LAST_BATTERY:-0}
        SHUTDOWN_TS=${SHUTDOWN_TS:-0}
        show_current
        ;;

    --watch*)
        interval=2
        if [[ "$1" =~ --watch=([0-9]+) ]]; then
            interval="${BASH_REMATCH[1]}"
        elif [[ "${2}" =~ ^[0-9]+$ ]]; then
            interval="$2"
        fi
        show_watch "$interval"
        ;;

    --today|"")
        show_current
        ;;

    --history)
        show_history
        ;;

    --week|-w)
        show_week
        ;;

    *)
        echo "Usage:"
        echo "  onscreen"
        echo "  onscreen --today"
        echo "  onscreen --watch          # realtime, refresh 2s"
        echo "  onscreen --watch=5        # realtime, refresh 5s"
        echo "  onscreen --history"
        echo "  onscreen --week  |  -w"
        exit 0
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
ExecStop=%h/.local/bin/onscreen-flush.sh
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
echo "  onscreen"
echo "  onscreen --today"
echo "  onscreen --watch"
echo "  onscreen --watch=5"
echo "  onscreen --history"
echo "  onscreen --week  |  -w"
echo
echo "Restart terminal or run:"
echo
echo "  source ~/.bashrc"
echo