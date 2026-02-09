#!/bin/sh
set -eu

WARN="$HOME/.config/niri/lock-warning.sh"

# ----- Customize your timeouts here (seconds) -----
# On AC:
AC_WARN=595
AC_LOCK=600
AC_OFF=900

# On battery:
BAT_WARN=295
BAT_LOCK=300
BAT_OFF=420
# -----------------------------------------------

get_ac_online() {
  # Find an AC adapter (type "Mains") and read its online state (1/0)
  for d in /sys/class/power_supply/*; do
    [ -r "$d/type" ] || continue
    if [ "$(cat "$d/type")" = "Mains" ] && [ -r "$d/online" ]; then
      cat "$d/online"
      return 0
    fi
  done
  # If no AC device found, assume "on battery"
  echo 0
}

start_swayidle() {
  mode="$1" # "AC" or "BAT"
  if [ "$mode" = "AC" ]; then
    WARN_T="$AC_WARN"; LOCK_T="$AC_LOCK"; OFF_T="$AC_OFF"
  else
    WARN_T="$BAT_WARN"; LOCK_T="$BAT_LOCK"; OFF_T="$BAT_OFF"
  fi

  echo "Starting swayidle mode=$mode warn=$WARN_T lock=$LOCK_T off=$OFF_T" >&2

  # Replace this shell with swayidle so we can cleanly stop it
  exec swayidle -w \
    timeout "$WARN_T" "$WARN" \
    timeout "$LOCK_T" 'swaylock -f' \
    timeout "$OFF_T"  'niri msg output "*" power off' \
    resume            'niri msg output "*" power on' \
    before-sleep      'swaylock -f'
}

run_loop() {
  last=""
  while :; do
    online="$(get_ac_online)"
    mode="BAT"
    [ "$online" = "1" ] && mode="AC"

    if [ "$mode" != "$last" ]; then
      last="$mode"
      # Start swayidle in background, keep PID, and restart on power change
      ( start_swayidle "$mode" ) &
      pid=$!
    fi

    # Wait for power change (simple poll). 2s is responsive without being heavy.
    sleep 2

    online2="$(get_ac_online)"
    mode2="BAT"; [ "$online2" = "1" ] && mode2="AC"
    if [ "$mode2" != "$last" ]; then
      # Power state changed -> restart swayidle
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      last="" # force restart next loop iteration
    fi
  done
}

run_loop
