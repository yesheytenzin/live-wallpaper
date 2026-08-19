#!/bin/bash

set -euo pipefail

readonly plugin_id="tenzin.live-wallpaper"
readonly repo_url="https://github.com/yesheytenzin/omarchy-live-wallpaper.git"
readonly plugin_dir="$HOME/.config/omarchy/plugins/$plugin_id"
readonly menu_file="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
readonly menu_action="~/.config/omarchy/plugins/$plugin_id/live-wallpaper.sh"

command -v omarchy >/dev/null 2>&1 || {
  echo "Omarchy is required to install this plugin." >&2
  exit 1
}

echo "Installing live wallpaper dependencies..."
omarchy pkg add mpvpaper ffmpegthumbnailer

if [[ -d $plugin_dir/.git ]]; then
  origin=$(git -C "$plugin_dir" remote get-url origin 2>/dev/null || true)
  if [[ $origin != "$repo_url" && $origin != "git@github.com:yesheytenzin/omarchy-live-wallpaper.git" ]]; then
    echo "Existing plugin checkout has an unexpected origin: $origin" >&2
    exit 1
  fi
  omarchy plugin update "$plugin_id" --yes
elif [[ -e $plugin_dir ]]; then
  echo "A non-git plugin already exists at $plugin_dir." >&2
  echo "Move or remove it, then run this installer again." >&2
  exit 1
else
  omarchy plugin add "$repo_url" --yes
fi

# Only one background service should own the desktop layer.
omarchy plugin disable omarchy.background >/dev/null 2>&1 || true
omarchy plugin enable "$plugin_id"

mkdir -p "$(dirname "$menu_file")"
if [[ ! -f $menu_file ]]; then
  printf '{\n  "style.background": {"action":"%s"}\n}\n' "$menu_action" >"$menu_file"
elif grep -q '^[[:space:]]*"style\.background"[[:space:]]*:' "$menu_file"; then
  sed -i \
    's|^[[:space:]]*"style\.background"[[:space:]]*:.*$|  "style.background": {"action":"'"$menu_action"'"},|' \
    "$menu_file"
else
  sed -i '0,/^[[:space:]]*{/a\  "style.background": {"action":"'"$menu_action"'"},' "$menu_file"
fi

omarchy menu refresh >/dev/null 2>&1 || true
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

echo
echo "Omarchy Live Wallpaper is installed."
echo "Open Style -> Background or double-click the desktop to choose a video."
