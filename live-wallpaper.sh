#!/bin/bash

set -u

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/live-wallpaper"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/live-wallpaper"
video_state="$state_dir/video"
pid_state="$state_dir/pid"

mkdir -p "$state_dir" "$cache_dir"

stop_live_wallpaper() {
  if [[ -s $pid_state ]]; then
    local pid
    pid=$(<"$pid_state")
    if [[ $pid =~ ^[0-9]+$ && $(cat "/proc/$pid/comm" 2>/dev/null) == mpvpaper ]]; then
      kill "$pid" 2>/dev/null || true
      for _ in {1..10}; do kill -0 "$pid" 2>/dev/null || break; sleep 0.05; done
      kill -KILL "$pid" 2>/dev/null || true
    fi
  fi
  rm -f "$pid_state"
}

start_live_wallpaper() {
  local video="$1"

  stop_live_wallpaper
  mpvpaper -p -o "no-audio loop panscan=1.0" '*' "$video" >/dev/null 2>&1 &
  printf '%s\n' "$!" >"$pid_state"
}

if [[ ${1:-} == --resume ]]; then
  [[ -s $video_state ]] || exit 0
  video=$(<"$video_state")
  [[ -f $video ]] && start_live_wallpaper "$video"
  exit 0
fi

theme_name=$(<"$HOME/.local/state/omarchy/current/theme.name")
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

while IFS= read -r -d '' media; do
  case ${media,,} in
    *.mp4|*.mkv|*.webm|*.mov|*.m4v)
      signature=$(stat -Lc '%s:%Y' "$media") || continue
      hash=$(printf '%s:%s' "$media" "$signature" | md5sum | cut -d ' ' -f 1)
      thumbnail="$cache_dir/$hash.jpg"
      if [[ ! -f $thumbnail ]]; then
        ffmpegthumbnailer -i "$media" -o "$thumbnail" -s 1536 -t 10 -q 8 >/dev/null 2>&1 || continue
      fi
      ;;
    *)
      thumbnail="$media"
      ;;
  esac
  printf '%s\t%s\n' "$media" "$thumbnail" >>"$rows_file"
done < <(
  find -L "$theme_dir" "$user_dir" -maxdepth 2 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' \
       -o -iname '*.bmp' -o -iname '*.webp' -o -iname '*.mp4' -o -iname '*.mkv' \
       -o -iname '*.webm' -o -iname '*.mov' -o -iname '*.m4v' \) \
    -print0 2>/dev/null | sort -z
)

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

case ${wallpaper,,} in
  *.mp4|*.mkv|*.webm|*.mov|*.m4v)
    signature=$(stat -Lc '%s:%Y' "$wallpaper") || exit 1
    hash=$(printf '%s:%s' "$wallpaper" "$signature" | md5sum | cut -d ' ' -f 1)
    poster="$cache_dir/$hash.jpg"
    [[ -f $poster ]] || ffmpegthumbnailer -i "$wallpaper" -o "$poster" -s 1536 -t 10 -q 8 >/dev/null 2>&1 || exit 1
    printf '%s\n' "$wallpaper" >"$video_state"
    omarchy-theme-bg-set "$poster"
    start_live_wallpaper "$wallpaper"
    ;;
  *)
    stop_live_wallpaper
    rm -f "$video_state"
    omarchy-theme-bg-set "$wallpaper"
    ;;
esac
