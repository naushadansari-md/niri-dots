#!/bin/bash
set -e

WALLPAPERS="${XDG_CONFIG_HOME:-$HOME/.config}/niri/wallpapers"
CACHE="$HOME/.cache"
RASI_FILE="$CACHE/current_wallpaper.rasi"
BLURRED="$CACHE/blurred_wallpaper.png"
NIRI_CONFIG="$HOME/.config/niri/layout.kdl"

BLUR="20x10"   # set 0x0 to disable


# -----------------------------------------------------
# Pick random wallpaper
# -----------------------------------------------------

mapfile -t imgs < <(find "$WALLPAPERS" -type f)
wallpaper="${imgs[RANDOM % ${#imgs[@]}]}"

# -----------------------------------------------------
# Apply wal + wallpaper
# -----------------------------------------------------

wal -n -i "$wallpaper"
swww img "$wallpaper"

# -----------------------------------------------------
# Load pywal colors
# -----------------------------------------------------

source "$HOME/.cache/wal/colors.sh"

# -----------------------------------------------------
# Restart Waybar (apply pywal colors)
# -----------------------------------------------------

pkill -SIGUSR2 waybar || waybar >/dev/null 2>&1 &


# -----------------------------------------------------
# Apply Dunst Color
# -----------------------------------------------------

# Symlink dunst config
ln -sf ~/.cache/wal/config ~/.config/mako/config

# Restart dunst with the new color scheme
pgrep -x mako >/dev/null && pkill mako || mako &


# -----------------------------------------------------
# Generate blurred wallpaper
# -----------------------------------------------------

magick "$wallpaper" -resize 75% "$BLURRED"

if [[ "$BLUR" != "0x0" ]]; then
  magick "$BLURRED" -blur "$BLUR" "$BLURRED"
fi

# -----------------------------------------------------
# Create rasi file
# -----------------------------------------------------

echo "* { current-image: url(\"$BLURRED\", height); }" > "$RASI_FILE"


if [[ -f "$NIRI_CONFIG" ]]; then
  sed -i \
    -e "s|^\s*active-color\s\+\"[^\"]*\"|active-color \"$color4\"|" \
    -e "s|^\s*inactive-color\s\+\"[^\"]*\"|inactive-color \"$color8\"|" \
    -e "s|^\s*active-gradient\s\+.*|active-gradient from=\"$color4\" to=\"$color5\" angle=45 relative-to=\"workspace-view\" in=\"oklch longer hue\"|" \
    -e "s|^\s*inactive-gradient\s\+.*|inactive-gradient from=\"$color8\" to=\"$color0\" angle=45 relative-to=\"workspace-view\" in=\"oklch longer hue\"|" \
    -e "s|^\s*urgent-color\s\+\"[^\"]*\"|urgent-color \"$color1\"|" \
    "$NIRI_CONFIG"

  echo "Niri focus-ring themed"
else
  echo "WARNING: Niri config not found: $NIRI_CONFIG"
fi


# -----------------------------------------------------
# Reload Niri
# -----------------------------------------------------

niri msg || true
