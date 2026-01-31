#!/bin/sh
set -e

swayidle -w \
  timeout 295 "$HOME/.config/niri/scripts/lock-warning.sh" \
  timeout 300 'swaylock -f' \
  timeout 600 'niri msg output * dpms off' \
  resume 'niri msg output * dpms on' \
  before-sleep 'swaylock -f'
