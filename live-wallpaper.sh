#!/bin/bash

set -u

readonly plugin_id="tenzin.live-wallpaper"
readonly plugin_dir="$HOME/.config/omarchy/plugins/$plugin_id"
readonly state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/live-wallpaper"
readonly cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/live-wallpaper"
readonly video_state="$state_dir/video"
readonly poster_state="$state_dir/poster"
readonly expected_state="$state_dir/expected"
readonly fallback_state="$state_dir/fallback"
readonly legacy_pid_state="$state_dir/pid"
readonly cleanup_helper="$state_dir/cleanup"

mkdir -p "$state_dir" "$cache_dir"

prepare_cleanup_helper() {
  cp -f "$plugin_dir/live-wallpaper.sh" "$cleanup_helper"
  chmod +x "$cleanup_helper"
}

is_video() {
  local ext
  ext="${1##*.}"
  ext=$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')
  case ",$ext," in
    ,mp4,|,mkv,|,webm,|,mov,|,m4v,) return 0 ;;
  esac
  return 1
}

stop_legacy_mpvpaper() {
  local pid
  [[ -s $legacy_pid_state ]] || return 0
  while IFS= read -r pid; do
    if [[ $pid =~ ^[0-9]+$ && $(cat "/proc/$pid/comm" 2>/dev/null) == mpvpaper ]]; then
      kill "$pid" 2>/dev/null || true
      sleep 0.05
      kill -KILL "$pid" 2>/dev/null || true
    fi
  done <"$legacy_pid_state"
  rm -f "$legacy_pid_state"
}

play_video() {
  local video="$1"
  for _ in {1..20}; do
    if omarchy-shell -q "$plugin_id" play "$video" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.05
  done
  return 1
}

stop_video() {
  omarchy-shell -q "$plugin_id" stop >/dev/null 2>&1 || true
  stop_legacy_mpvpaper
}

clear_live_wallpaper_state() {
  stop_video
  rm -f "$video_state" "$poster_state" "$expected_state" "$fallback_state"
}

first_static_background() {
  local theme theme_dir user_dir
  theme=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null)
  theme_dir="$HOME/.local/state/omarchy/current/theme/backgrounds"
  user_dir="$HOME/.config/omarchy/backgrounds/$theme"
  find -L "$theme_dir" "$user_dir" -maxdepth 2 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' \
       -o -iname '*.bmp' -o -iname '*.webp' \) -print -quit 2>/dev/null
}

remember_static_background() {
  [[ -s $fallback_state && -f $(<"$fallback_state") ]] && return 0
  local fallback="$current_background"
  if [[ -z $fallback || ! -f $fallback || $fallback == "$cache_dir/"* ]]; then
    fallback=$(first_static_background)
  fi
  [[ -n $fallback && -f $fallback ]] && printf '%s\n' "$fallback" >"$fallback_state"
}

restore_static_background() {
  local fallback=""
  stop_video
  [[ -s $fallback_state ]] && fallback=$(<"$fallback_state")
  if [[ -z $fallback || ! -f $fallback ]]; then
    fallback=$(first_static_background)
  fi
  if [[ -n $fallback && -f $fallback ]]; then
    omarchy theme bg set "$fallback" || true
  fi
  rm -f "$video_state" "$poster_state" "$expected_state" "$fallback_state"
}

resume_live_wallpaper() {
  [[ -s $video_state && -s $poster_state ]] || return 0
  local video poster
  video=$(<"$video_state")
  poster=$(<"$poster_state")
  [[ -f $video && -f $poster ]] || {
    clear_live_wallpaper_state
    return 0
  }
  [[ -s $expected_state ]] || printf '%s\n' "$poster" >"$expected_state"
  play_video "$video"
}

stop_if_changed() {
  [[ -s $expected_state ]] || return 0
  local current expected
  current=$(readlink -f "$HOME/.local/state/omarchy/current/background" 2>/dev/null || true)
  expected=$(<"$expected_state")
  [[ -n $current && $current == "$expected" ]] && return 0
  clear_live_wallpaper_state
}

ensure_menu_override() {
  local file="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
  local action="~/.config/omarchy/plugins/$plugin_id/live-wallpaper.sh"
  local entry="{\"icon\":\"\",\"label\":\"Background\",\"aliases\":[\"background\",\"wallpaper\"],\"action\":\"$action\"}"
  mkdir -p "$(dirname "$file")"
  if [[ ! -f $file ]]; then
    printf '{\n  "style.background": %s\n}\n' "$entry" >"$file"
  elif grep -qE '^[[:space:]]*"style\.background"[[:space:]]*:' "$file"; then
    sed -i -E \
      "s|^([[:space:]]*\"style\.background\"[[:space:]]*:[[:space:]]*).*$|\1$entry,|" \
      "$file"
  else
    sed -i "0,/^[[:space:]]*{/a\  \"style.background\": $entry," "$file"
  fi
  omarchy menu refresh >/dev/null 2>&1 || true
}

unwire_menu_override() {
  local file="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
  [[ -f $file ]] || return 0
  sed -i -E '\|^[[:space:]]*"style\.background".*tenzin\.live-wallpaper/live-wallpaper\.sh.*$|d' "$file"
  omarchy menu refresh >/dev/null 2>&1 || true
}

uninstall_plugin_state() {
  local fallback=""

  if [[ -s $video_state || -s $fallback_state ]]; then
    [[ -s $fallback_state ]] && fallback=$(<"$fallback_state")
    if [[ -z $fallback || ! -f $fallback || $fallback == "$cache_dir/"* ]]; then
      fallback=$(first_static_background)
    fi
  fi

  stop_video
  unwire_menu_override
  rm -rf "$state_dir" "$cache_dir"

  if [[ -n $fallback && -f $fallback ]]; then
    omarchy theme bg set "$fallback" || true
  fi
}

cleanup_after_unload() {
  local enabled=""

  for _ in {1..200}; do
    if [[ ! -d $plugin_dir ]]; then
      uninstall_plugin_state
      return 0
    fi
    sleep 0.01
  done

  enabled=$(omarchy plugin list --json 2>/dev/null \
    | jq -r --arg id "$plugin_id" '.[] | select(.id == $id) | .enabled' 2>/dev/null || true)

  [[ $enabled == false ]] && unwire_menu_override
}

thumbnail_for() {
  local media="$1" signature hash thumbnail tmp
  signature=$(stat -Lc '%s:%Y' "$media") || return 1
  hash=$(printf 'ffmpeg-v1:%s:%s' "$media" "$signature" | md5sum | cut -d ' ' -f 1)
  thumbnail="$cache_dir/$hash.jpg"
  if [[ ! -f $thumbnail ]]; then
    tmp="$thumbnail.$$.jpg"
    if ! ffmpeg -nostdin -hide_banner -loglevel error -ss 1 -i "$media" -an \
      -frames:v 1 -vf "scale=1536:-2:force_original_aspect_ratio=decrease" -q:v 3 -y "$tmp"; then
      rm -f "$tmp"
      ffmpeg -nostdin -hide_banner -loglevel error -i "$media" -an \
        -frames:v 1 -vf "scale=1536:-2:force_original_aspect_ratio=decrease" -q:v 3 -y "$tmp" || return 1
    fi
    mv -f "$tmp" "$thumbnail"
  fi
  printf '%s' "$thumbnail"
}

case "${1:-}" in
  --resume)
    prepare_cleanup_helper || true
    resume_live_wallpaper
    exit $?
    ;;
  --stop-if-changed)
    stop_if_changed
    exit 0
    ;;
  --stop)
    clear_live_wallpaper_state
    exit 0
    ;;
  --wire-menu)
    ensure_menu_override
    exit 0
    ;;
  --unwire-menu)
    unwire_menu_override
    exit 0
    ;;
  --cleanup-after-unload)
    cleanup_after_unload
    exit 0
    ;;
  --uninstall)
    uninstall_plugin_state
    exit 0
    ;;
esac

theme_name=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null)
theme_dir="$HOME/.local/state/omarchy/current/theme/backgrounds"
user_dir="$HOME/.config/omarchy/backgrounds/$theme_name"
current_background=$(readlink -f "$HOME/.local/state/omarchy/current/background" 2>/dev/null || true)
selected="$current_background"
[[ -s $video_state ]] && selected=$(<"$video_state")

selection_file=$(mktemp)
done_file=$(mktemp)
rows_file=$(mktemp)
trap 'rm -f "$selection_file" "$done_file" "$rows_file"' EXIT
rm -f "$done_file"

media_args=()
while IFS= read -r ext; do
  (( ${#media_args[@]} > 0 )) && media_args+=(-o)
  media_args+=(-iname "*.$ext")
done <<'EOF_EXTS'
jpg
jpeg
png
gif
bmp
webp
mp4
mkv
webm
mov
m4v
EOF_EXTS

find -L "$theme_dir" "$user_dir" -maxdepth 2 -type f \( "${media_args[@]}" \) -print0 2>/dev/null \
  | sort -z \
  | while IFS= read -r -d '' media; do
      if is_video "$media"; then
        thumbnail=$(thumbnail_for "$media") || continue
      else
        thumbnail="$media"
      fi
      printf '%s\t%s\n' "$media" "$thumbnail"
    done >"$rows_file"

[[ -s $rows_file ]] || {
  omarchy-notification-send "No wallpaper was found for theme" -t 2000
  exit 0
}

rows_b64=$(base64 -w 0 <"$rows_file")
if [[ $(omarchy-shell image-selector open "" "$rows_b64" "$selected" "$selection_file" "$done_file" false false) != ok ]]; then
  exit 1
fi

while [[ ! -e $done_file ]]; do sleep 0.01; done
[[ -s $selection_file ]] || exit 0
wallpaper=$(<"$selection_file")

if is_video "$wallpaper"; then
  poster=$(thumbnail_for "$wallpaper") || {
    omarchy-notification-send "Could not read video file" -t 2000
    exit 1
  }
  remember_static_background
  printf '%s\n' "$wallpaper" >"$video_state"
  printf '%s\n' "$poster" >"$poster_state"
  printf '%s\n' "$poster" >"$expected_state"
  if ! omarchy theme bg set "$poster" || ! play_video "$wallpaper"; then
    restore_static_background
    omarchy-notification-send "Could not set video wallpaper" -t 2000
    exit 1
  fi
else
  clear_live_wallpaper_state
  omarchy theme bg set "$wallpaper"
fi
