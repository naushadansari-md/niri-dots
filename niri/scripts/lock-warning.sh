#!/bin/sh
notify-send \
  --urgency=critical \
  --icon=preferences-desktop-screensaver \
  --expire-time=5000 \
  "About to lock screen…" \
  "Move mouse or press a key"
