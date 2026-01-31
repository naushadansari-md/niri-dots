#!/usr/bin/env bash
set -euo pipefail

# ---------------- CONFIG ----------------
ROFI="rofi -dmenu -i -markup-rows -p Launcher"
LOW_BATTERY_THRESHOLD=20

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/niri-launcher"
mkdir -p "$CACHE_DIR"

WIFI_CACHE="$CACHE_DIR/wifi-scan"
WIFI_CACHE_TTL=30

# ---------------- GENERIC HELPERS ----------------
is_number() { [[ "$1" =~ ^[0-9]+$ ]]; }

# ---------------- WIFI ----------------
wifi_state() { nmcli -t -f WIFI g | awk '{print $1}'; }
wifi_device() { nmcli -t -f DEVICE,TYPE d | awk -F: '$2=="wifi"{print $1; exit}'; }
wifi_connected_ssid() { nmcli -t -f ACTIVE,SSID dev wifi | awk -F: '$1=="yes"{print $2; exit}'; }

wifi_cache_valid() {
    [ -f "$WIFI_CACHE" ] && [ $(( $(date +%s) - $(stat -c %Y "$WIFI_CACHE") )) -lt "$WIFI_CACHE_TTL" ]
}

wifi_scan_async() {
    local dev
    dev="$(wifi_device)" || return
    (
        nmcli -t -f IN-USE,SIGNAL,SSID dev wifi list ifname "$dev" 2>/dev/null \
        | sed '/::/d' > "${WIFI_CACHE}.tmp" &&
        mv "${WIFI_CACHE}.tmp" "$WIFI_CACHE"
    ) & disown
}

# Wi-Fi menu sorted by signal strength
wifi_menu() {
    local current ssid signal icon
    current=$(wifi_connected_ssid)
    wifi_scan_async
    [ -f "$WIFI_CACHE" ] || return
    # Sort by signal descending
    sort -t: -k2 -nr "$WIFI_CACHE" | while IFS=: read -r inuse signal ssid; do
        [[ -z "$ssid" ]] && continue
        ssid="${ssid//\"/}"
        [[ "$ssid" == "$current" ]] && icon="✅" || icon="❌"
        echo "$icon $ssid ($signal%)"
    done
}

# ---------------- BLUETOOTH ----------------
bt_state() { bluetoothctl show 2>/dev/null | grep -q "Powered: yes" && echo "on" || echo "off"; }

# Bluetooth menu sorted: connected first
bt_menu() {
    mapfile -t devices < <(bluetoothctl devices 2>/dev/null)
    connected=()
    disconnected=()
    for dev in "${devices[@]}"; do
        read -r _ mac name <<< "$dev"
        [ -z "$mac" ] && continue
        bluetoothctl info "$mac" | grep -q "Connected: yes" && status="connected" || status="disconnected"
        battery=$(bluetoothctl info "$mac" 2>/dev/null | awk -F': ' '/Battery Percentage/ {print $2}')
        [[ -n "$battery" ]] && battery=" - ${battery}%" || battery=""
        line="$status|$mac|$name$battery"
        if [ "$status" = "connected" ]; then
            connected+=("$line")
        else
            disconnected+=("$line")
        fi
    done

    for item in "${connected[@]}" "${disconnected[@]}"; do
        IFS='|' read -r status mac label <<< "$item"
        icon="❌"
        [ "$status" = "connected" ] && icon="✅"
        echo "$icon $label|$mac"
    done
}

notify_low_battery() {
    bluetoothctl devices | while read -r _ mac name; do
        connected=$(bluetoothctl info "$mac" | grep -q "Connected: yes" && echo "yes" || echo "no")
        [ "$connected" != "yes" ] && continue
        battery=$(bluetoothctl info "$mac" | awk -F': ' '/Battery Percentage/ {print $2}')
        [ -z "$battery" ] && continue
        flag="$CACHE_DIR/bt-low-$mac"
        if [ "$battery" -le "$LOW_BATTERY_THRESHOLD" ]; then
            [ -f "$flag" ] && continue
            notify-send -u critical -a "Niri Launcher" "🔋 Bluetooth low battery" "$name: ${battery}%"
            touch "$flag"
        else
            rm -f "$flag"
        fi
    done
}

# ---------------- POWER PROFILE ----------------
power_profile_menu() {
    local current profile mark icon
    if command -v powerprofilesctl >/dev/null 2>&1; then
        current=$(powerprofilesctl get 2>/dev/null)
    else
        current="unknown"
    fi

    for profile in performance balanced "power-saver"; do
        case "$profile" in
            performance) icon="⚡" ;;
            balanced)    icon="🔋" ;;
            "power-saver") icon="🛌" ;;
        esac
        [ "$profile" = "$current" ] && mark="✅" || mark="  "
        echo "$mark $icon $profile"
    done
}

# ---------------- AIRPLANE MODE ----------------
toggle_airplane_mode() {
    local wifi bt
    wifi=$(wifi_state)
    bt=$(bt_state)
    if [ "$wifi" = "enabled" ] || [ "$bt" = "on" ]; then
        nmcli radio all off
        bluetoothctl power off
        notify-send -a "Niri Launcher" "✈️ Airplane Mode" "Wireless interfaces disabled"
    else
        nmcli radio all on
        bluetoothctl power on
        notify-send -a "Niri Launcher" "✈️ Airplane Mode" "Wireless interfaces enabled"
    fi
}

# ---------------- MAIN MENU ----------------
main_menu() {
    local wifi_status bt_status power_profile airplane_status
    wifi_status=$(wifi_state)
    [[ "$wifi_status" == "enabled" ]] && wifi_status="enabled" || wifi_status="disabled"
    bt_status=$(bt_state)
    [[ "$bt_status" == "on" ]] && bt_status="on" || bt_status="off"
    if command -v powerprofilesctl >/dev/null 2>&1; then
        power_profile=$(powerprofilesctl get 2>/dev/null)
    else
        power_profile="unknown"
    fi
    [[ "$wifi_status" == "disabled" && "$bt_status" == "off" ]] && airplane_status="off" || airplane_status="on"

    echo "📡 Wi-Fi: $wifi_status"
    echo "🔵 Bluetooth: $bt_status"
    echo "✈️ Airplane Mode: $airplane_status"
    echo "⚡ Power Profile: $power_profile"
    echo "----"
    echo "📡 Wi-Fi Networks"
    echo "🎧 Bluetooth Devices"
    echo "⏻ Power Options"
    echo "🔄 Refresh"
    echo "❌ Exit"
}

power_menu() {
    echo "⏻ Shutdown"
    echo "🔁 Reboot"
    echo "🚪 Logout"
}

# ---------------- MAIN LOOP ----------------
while true; do
    notify_low_battery

    choice=$(main_menu | $ROFI)
    [ -z "$choice" ] && exit

    case "$choice" in
        "📡 Wi-Fi:"*) 
            [ "$(wifi_state)" = "enabled" ] && nmcli radio wifi off || nmcli radio wifi on ;;
        "🔵 Bluetooth:"*) 
            [ "$(bt_state)" = "on" ] && bluetoothctl power off || bluetoothctl power on ;;
        "✈️ Airplane Mode:"*) 
            toggle_airplane_mode ;;
        "⚡ Power Profile:"*) 
            sel=$(power_profile_menu | $ROFI -p "Power Profile")
            [ -z "$sel" ] && continue
            powerprofilesctl set "${sel##* }"
            notify-send -a "Niri Launcher" "⚡ Power Profile" "Switched to ${sel##* }" ;;
        "📡 Wi-Fi Networks") 
            [ "$(wifi_state)" != "enabled" ] && nmcli radio wifi on && sleep 1
            sel=""
            while [ -z "$sel" ]; do
                sel=$(wifi_menu | rofi -dmenu -i -p "Wi-Fi")
            done
            ssid="${sel##* }"
            nmcli device wifi connect "$ssid" || {
                pass=$($ROFI -password -p "Password")
                [ -n "$pass" ] && nmcli device wifi connect "$ssid" password "$pass"
            } ;;
        "🎧 Bluetooth Devices") 
            [ "$(bt_state)" != "on" ] && bluetoothctl power on
            sel=""
            while [ -z "$sel" ]; do
                sel=$(bt_menu | rofi -dmenu -i -p "Bluetooth")
            done
            IFS='|' read -r _ mac <<< "$sel"
            bluetoothctl info "$mac" | grep -q "Connected: yes" \
                && bluetoothctl disconnect "$mac" \
                || bluetoothctl connect "$mac" ;;
        "⏻ Power Options") 
            sel=$(power_menu | $ROFI -p "Power")
            case "$sel" in
                "⏻ Shutdown") systemctl poweroff ;;
                "🔁 Reboot")   systemctl reboot ;;
                "🚪 Logout")   niri msg exit ;;
            esac ;;
        "🔄 Refresh") 
            continue ;;
        "❌ Exit") 
            exit ;;
    esac
done
