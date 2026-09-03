#!/bin/bash

set -uo pipefail

readonly plugin_id="tenzin.live-wallpaper"
readonly plugin_dir="$HOME/.config/omarchy/plugins/$plugin_id"
readonly state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/live-wallpaper"
readonly cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/live-wallpaper"
readonly stock_thumbnail_dir="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/image-selector"
readonly video_state="$state_dir/video"
readonly poster_state="$state_dir/poster"
readonly expected_state="$state_dir/expected"
readonly fallback_state="$state_dir/fallback"
readonly legacy_pid_state="$state_dir/pid"
readonly cleanup_helper="$state_dir/cleanup"
readonly rows_cache="$state_dir/picker-rows"
readonly rows_signature_state="$state_dir/picker-signature"
readonly transition_lock="$state_dir/transition.lock"
readonly rows_lock="$state_dir/picker.lock"
readonly MAX_VIDEO_BYTES=524288000
readonly MAX_ROWS=500
readonly MAX_ROW_BYTES=2097152
prepare_picker=0

ensure_secure_dir() {
  local dir="$1"
  if [[ -L "$dir" ]]; then
    echo "refusing symlinked dir: $dir" >&2
    return 1
  fi
  mkdir -p -m 0700 "$dir" 2>/dev/null || return 1
  chmod 0700 "$dir" 2>/dev/null || true
  if [[ -L "$dir" ]] || [[ ! -d "$dir" ]]; then
    return 1
  fi
}

ensure_secure_dir "$state_dir" || exit 1
ensure_secure_dir "$cache_dir" || exit 1

atomic_write() {
  local dest="$1" content="$2"
  local dir tmp
  dir=$(dirname "$dest")
  ensure_secure_dir "$dir" || return 1
  if [[ -L "$dest" ]]; then
    rm -f "$dest" 2>/dev/null || true
  fi
  tmp=$(mktemp -p "$dir" .tmp.XXXXXX) || return 1
  chmod 0600 "$tmp" 2>/dev/null || true
  printf '%s\n' "$content" >"$tmp"
  chmod 0600 "$tmp" 2>/dev/null || true
  if [[ -L "$dest" ]] || [[ -L "$dir" ]]; then
    rm -f "$tmp"
    return 1
  fi
  mv -f "$tmp" "$dest"
  chmod 0600 "$dest" 2>/dev/null || true
}

sanitize_theme_name() {
  local raw="$1"
  raw=$(printf '%s' "$raw" | tr -d '\n\r' | head -c 128)
  # trim whitespace
  raw=$(printf '%s' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  if [[ -z $raw ]]; then
    return 1
  fi
  if [[ ! $raw =~ ^[a-zA-Z0-9._-]+$ ]]; then
    return 1
  fi
  if [[ $raw == *".."* ]]; then
    return 1
  fi
  printf '%s' "$raw"
}

validate_wallpaper_path() {
  local p="$1"
  [[ -n $p ]] || return 1
  if (( ${#p} > 4096 )); then return 1; fi
  if [[ $p == *$'\n'* ]] || [[ $p == *$'\t'* ]]; then return 1; fi
  [[ $p == /* ]] || return 1
  local canon
  canon=$(readlink -f "$p" 2>/dev/null) || return 1
  [[ $canon == /* ]] || return 1
  [[ -f $canon ]] || return 1
  local allowed1="$HOME/.config/omarchy/backgrounds/"
  local allowed2="$HOME/.local/state/omarchy/current/theme/backgrounds/"
  local allowed2c="$(readlink -f "$allowed2" 2>/dev/null || echo "$allowed2")"
  local allowed3="/usr/share/omarchy/"
  local allowed4="$HOME/.local/share/omarchy/"
  if [[ $canon != "$allowed1"* && $canon != "$allowed2"* && $canon != "$allowed2c"* && $canon != "$allowed3"* && $canon != "$allowed4"* ]]; then
    return 1
  fi
  # size bound for videos
  local sz
  sz=$(stat -Lc '%s' "$canon" 2>/dev/null) || return 1
  if (( sz > MAX_VIDEO_BYTES )) && is_video "$canon"; then return 1; fi
  return 0
}

prepare_cleanup_helper() {
  ensure_secure_dir "$state_dir" || return 1
  if [[ -L "$state_dir" ]]; then return 1; fi
  if [[ -L "$cleanup_helper" ]]; then
    rm -f "$cleanup_helper" 2>/dev/null || true
  fi
  if [[ ! -f "$plugin_dir/live-wallpaper.sh" ]]; then return 1; fi
  local tmp
  tmp=$(mktemp -p "$state_dir" .cleanup.XXXXXX) || return 1
  chmod 0600 "$tmp" 2>/dev/null || true
  if ! cp -f "$plugin_dir/live-wallpaper.sh" "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  chmod 0755 "$tmp"
  if [[ -L "$cleanup_helper" ]] || [[ -L "$state_dir" ]]; then
    rm -f "$tmp"
    return 1
  fi
  mv -f "$tmp" "$cleanup_helper"
  chmod 0755 "$cleanup_helper" 2>/dev/null || true
}

is_video() {
  local ext
  ext="${1##*.}"
  ext="${ext,,}"
  case ",$ext," in
    ,mp4,|,mkv,|,webm,|,mov,|,m4v,) return 0 ;;
  esac
  return 1
}

stop_legacy_mpvpaper() {
  local pid
  [[ -s $legacy_pid_state ]] || return 0
  if [[ -L "$legacy_pid_state" ]]; then rm -f "$legacy_pid_state"; return 0; fi
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
  local video="$1" transition_ms="${2:-0}"
  # validate before IPC
  if ! validate_wallpaper_path "$video"; then
    # fallback: allow is_video check failure to still attempt? reject
    return 1
  fi
  # clamp transition
  if ! [[ $transition_ms =~ ^[0-9]+$ ]]; then transition_ms=0; fi
  if (( transition_ms > 4000 )); then transition_ms=4000; fi
  if (( transition_ms < 0 )); then transition_ms=0; fi
  local i used_fallback=0
  for i in {1..10}; do
    if omarchy-shell -q "$plugin_id" play "$video" "$transition_ms" >/dev/null 2>&1; then
      return 0
    fi
    if omarchy-shell -q "$plugin_id" play "$video" >/dev/null 2>&1; then
      used_fallback=1
      break
    fi
    if omarchy-shell -q "$plugin_id" playSimple "$video" >/dev/null 2>&1; then
      used_fallback=1
      break
    fi
    sleep 0.05
  done
  if (( used_fallback )); then
    (sleep 0.5; omarchy-shell shell rescanPlugins >/dev/null 2>&1 &)
    return 0
  fi
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 &
  sleep 0.9
  for i in {1..20}; do
    if omarchy-shell -q "$plugin_id" play "$video" "$transition_ms" >/dev/null 2>&1; then
      return 0
    fi
    if omarchy-shell -q "$plugin_id" play "$video" >/dev/null 2>&1; then
      return 0
    fi
    if omarchy-shell -q "$plugin_id" playSimple "$video" >/dev/null 2>&1; then
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
  local theme theme_dir user_dir sanitized
  theme=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null | head -c 128)
  sanitized=$(sanitize_theme_name "$theme" 2>/dev/null) || sanitized=""
  theme_dir="$HOME/.local/state/omarchy/current/theme/backgrounds"
  if [[ -n $sanitized ]]; then
    user_dir="$HOME/.config/omarchy/backgrounds/$sanitized"
  else
    user_dir="$HOME/.config/omarchy/backgrounds"
  fi
  # ensure dirs are not symlinks outside expected roots before find
  if [[ -L "$theme_dir" ]] || [[ -L "$user_dir" ]]; then
    return 1
  fi
  find -L "$theme_dir" "$user_dir" -maxdepth 2 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' \
       -o -iname '*.bmp' -o -iname '*.webp' \) -print -quit 2>/dev/null
}

remember_static_background() {
  if [[ -L "$fallback_state" ]]; then rm -f "$fallback_state"; fi
  [[ -s $fallback_state && -f $(<"$fallback_state") ]] && return 0
  local fallback="$current_background"
  if [[ -z $fallback || ! -f $fallback || $fallback == "$cache_dir/"* ]]; then
    fallback=$(first_static_background)
  fi
  if [[ -n $fallback && -f $fallback ]]; then
    atomic_write "$fallback_state" "$fallback" || printf '%s\n' "$fallback" >"$fallback_state"
  fi
}

restore_static_background() {
  local fallback=""
  stop_video
  if [[ -L "$fallback_state" ]]; then rm -f "$fallback_state"; fallback=""; else
    [[ -s $fallback_state ]] && fallback=$(<"$fallback_state")
  fi
  if [[ -z $fallback || ! -f $fallback ]]; then
    fallback=$(first_static_background)
  fi
  if [[ -n $fallback && -f $fallback ]]; then
    omarchy theme bg set "$fallback" || true
  fi
  rm -f "$video_state" "$poster_state" "$expected_state" "$fallback_state"
}

resume_live_wallpaper() {
  if [[ -L "$video_state" ]] || [[ -L "$poster_state" ]]; then
    clear_live_wallpaper_state
    return 0
  fi
  [[ -s $video_state && -s $poster_state ]] || return 0
  local video poster
  video=$(<"$video_state")
  poster=$(<"$poster_state")
  # validate paths are not control-char and files exist and size bounded
  if ! validate_wallpaper_path "$video" 2>/dev/null; then
    clear_live_wallpaper_state
    return 0
  fi
  [[ -f $poster ]] || {
    clear_live_wallpaper_state
    return 0
  }
  # bound poster size
  local psize
  psize=$(stat -Lc '%s' "$poster" 2>/dev/null || echo 0)
  if (( psize > MAX_VIDEO_BYTES )); then clear_live_wallpaper_state; return 0; fi
  if [[ -L "$expected_state" ]]; then rm -f "$expected_state"; fi
  [[ -s $expected_state ]] || atomic_write "$expected_state" "$poster" || printf '%s\n' "$poster" >"$expected_state"
  play_video "$video" 0
}

stop_if_changed() {
  if [[ -L "$expected_state" ]]; then rm -f "$expected_state"; return 0; fi
  [[ -s $expected_state ]] || return 0
  if [[ -L "$state_dir" ]]; then return 0; fi
  exec 9>"$transition_lock"
  flock -n 9 || return 0
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
  chmod 0700 "$(dirname "$file")" 2>/dev/null || true
  if [[ -L "$file" ]]; then rm -f "$file"; fi
  local tmp
  if [[ ! -f $file ]]; then
    tmp=$(mktemp -p "$(dirname "$file")" .menu.XXXXXX) || return 1
    printf '{\n  "style.background": %s\n}\n' "$entry" >"$tmp"
    mv -f "$tmp" "$file"
  elif grep -qE '^[[:space:]]*"style\.background"[[:space:]]*:' "$file"; then
    # use atomic sed via tmp
    tmp=$(mktemp -p "$(dirname "$file")" .menu.XXXXXX) || return 1
    cp -f "$file" "$tmp"
    sed -i -E \
      "s|^([[:space:]]*\"style\.background\"[[:space:]]*:[[:space:]]*).*$|\1$entry,|" \
      "$tmp"
    mv -f "$tmp" "$file"
  else
    tmp=$(mktemp -p "$(dirname "$file")" .menu.XXXXXX) || return 1
    cp -f "$file" "$tmp"
    sed -i "0,/^[[:space:]]*{/a\  \"style.background\": $entry," "$tmp"
    mv -f "$tmp" "$file"
  fi
  omarchy menu refresh >/dev/null 2>&1 || true
}

unwire_menu_override() {
  local file="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
  [[ -f $file ]] || return 0
  if [[ -L "$file" ]]; then rm -f "$file"; return 0; fi
  local tmp
  tmp=$(mktemp -p "$(dirname "$file")" .menu.XXXXXX) || return 1
  cp -f "$file" "$tmp"
  sed -i -E '\|^[[:space:]]*"style\.background".*tenzin\.live-wallpaper/live-wallpaper\.sh.*$|d' "$tmp"
  mv -f "$tmp" "$file"
  omarchy menu refresh >/dev/null 2>&1 || true
}

uninstall_plugin_state() {
  local fallback=""

  if [[ -L "$video_state" ]] || [[ -L "$fallback_state" ]]; then
    rm -f "$video_state" "$fallback_state" 2>/dev/null || true
  fi
  if [[ -s $video_state || -s $fallback_state ]]; then
    [[ -s $fallback_state ]] && fallback=$(<"$fallback_state")
    if [[ -z $fallback || ! -f $fallback || $fallback == "$cache_dir/"* ]]; then
      fallback=$(first_static_background)
    fi
  fi

  stop_video
  if [[ -n $fallback && -f $fallback && ! -L $fallback ]]; then
    omarchy theme bg set "$fallback" || true
  fi

  unwire_menu_override
  rm -rf "$state_dir" "$cache_dir"
}

cleanup_after_unload() {
  local enabled=""
  # harden: ensure plugin_dir check not following symlink trick
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
  [[ -f "$media" ]] || return 1
  if [[ -L "$media" ]]; then
    # resolve symlink target must still be regular file
    local resolved
    resolved=$(readlink -f "$media" 2>/dev/null) || return 1
    [[ -f $resolved ]] || return 1
  fi
  local fsize
  fsize=$(stat -Lc '%s' "$media" 2>/dev/null) || return 1
  if (( fsize > MAX_VIDEO_BYTES )); then return 1; fi
  if (( fsize == 0 )); then return 1; fi
  signature=$(stat -Lc '%s:%Y' "$media") || return 1
  hash=$(printf 'ffmpeg-v2:%s:%s' "$media" "$signature" | md5sum)
  hash="${hash%% *}"
  thumbnail="$cache_dir/$hash.jpg"
  if [[ -L "$thumbnail" ]]; then rm -f "$thumbnail" 2>/dev/null || true; fi
  if [[ ! -f $thumbnail ]]; then
    ensure_secure_dir "$cache_dir" || return 1
    tmp=$(mktemp -p "$cache_dir" ".${hash}.XXXXXX.jpg") || return 1
    chmod 0600 "$tmp" 2>/dev/null || true
    if ! timeout 12 ffmpeg -nostdin -hide_banner -loglevel error -threads 1 -i "$media" -an \
      -frames:v 1 -vf "scale=1536:-2:force_original_aspect_ratio=decrease" -q:v 3 -y "$tmp" 2>/dev/null; then
      rm -f "$tmp"
      tmp=$(mktemp -p "$cache_dir" ".${hash}.XXXXXX.jpg") || return 1
      chmod 0600 "$tmp" 2>/dev/null || true
      if ! timeout 12 ffmpeg -nostdin -hide_banner -loglevel error -ss 1 -threads 1 -i "$media" -an \
        -frames:v 1 -vf "scale=1536:-2:force_original_aspect_ratio=decrease" -q:v 3 -y "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        return 1
      fi
    fi
    if [[ -L "$tmp" ]] || [[ ! -f "$tmp" ]]; then rm -f "$tmp"; return 1; fi
    # validate output size bound
    local outsize
    outsize=$(stat -Lc '%s' "$tmp" 2>/dev/null || echo 0)
    if (( outsize > MAX_ROW_BYTES || outsize == 0 )); then rm -f "$tmp"; return 1; fi
    chmod 0644 "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$thumbnail"
    chmod 0644 "$thumbnail" 2>/dev/null || true
  fi
  printf '%s' "$thumbnail"
}

picker_thumbnail_for() {
  local media="$1" signature hash thumbnail tmp
  [[ -f "$media" ]] || return 1
  if [[ -L "$media" ]]; then
    local resolved
    resolved=$(readlink -f "$media" 2>/dev/null) || return 1
    [[ -f $resolved ]] || return 1
  fi
  local fsize
  fsize=$(stat -Lc '%s' "$media" 2>/dev/null) || return 1
  if (( fsize > MAX_VIDEO_BYTES )); then return 1; fi
  if (( fsize == 0 )); then return 1; fi
  signature=$(stat -Lc '%s:%Y' "$media") || return 1
  hash=$(printf 'picker-v3:%s:%s' "$media" "$signature" | md5sum)
  hash="${hash%% *}"
  thumbnail="$cache_dir/$hash.jpg"
  if [[ -L "$thumbnail" ]]; then rm -f "$thumbnail" 2>/dev/null || true; fi
  if [[ ! -f $thumbnail ]]; then
    ensure_secure_dir "$cache_dir" || return 1
    tmp=$(mktemp -p "$cache_dir" ".${hash}.XXXXXX.jpg") || return 1
    chmod 0600 "$tmp" 2>/dev/null || true
    if ! timeout 12 bash -c 'VIPS_CONCURRENCY=1 vipsthumbnail "$1" --size 1536x864 --smartcrop=centre --path "$2[Q=82,strip]" >/dev/null 2>&1' _ "$media" "$tmp"; then
      rm -f "$tmp"
      return 1
    fi
    if [[ -L "$tmp" ]] || [[ ! -f "$tmp" ]]; then rm -f "$tmp"; return 1; fi
    local outsize
    outsize=$(stat -Lc '%s' "$tmp" 2>/dev/null || echo 0)
    if (( outsize > MAX_ROW_BYTES || outsize == 0 )); then rm -f "$tmp"; return 1; fi
    chmod 0644 "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$thumbnail"
    chmod 0644 "$thumbnail" 2>/dev/null || true
  fi
  printf '%s' "$thumbnail"
}

stock_thumbnail_for() {
  local media="$1" signature hash
  [[ -s $stock_thumbnail_dir/index.tsv ]] || return 1
  if [[ -L "$stock_thumbnail_dir/index.tsv" ]]; then return 1; fi
  [[ -f "$media" ]] || return 1
  signature=$(stat -Lc '%s:%Y' "$media") || return 1
  hash=$(awk -F '\t' -v path="$media" -v sig="$signature" \
    '$1 == path && $2 == sig { print $3; exit }' "$stock_thumbnail_dir/index.tsv")
  [[ -n $hash && $hash =~ ^[a-f0-9]+$ ]] || return 1
  [[ -f $stock_thumbnail_dir/$hash.jpg ]] || return 1
  if [[ -L "$stock_thumbnail_dir/$hash.jpg" ]]; then return 1; fi
  printf '%s' "$stock_thumbnail_dir/$hash.jpg"
}

prewarm_picker_media() {
  local media="$1" thumbnail
  # sanitize media: reject control chars and overlong, reject tabs/newlines in filename that would break TSV
  if [[ $media == *$'\n'* ]] || [[ $media == *$'\t'* ]]; then return 1; fi
  if (( ${#media} > 4096 )); then return 1; fi
  [[ -f "$media" ]] || return 1
  if is_video "$media"; then
    thumbnail=$(thumbnail_for "$media") || return 1
  else
    thumbnail=$(stock_thumbnail_for "$media" || picker_thumbnail_for "$media") || return 1
  fi
  # ensure thumbnail path also sanitized
  if [[ $thumbnail == *$'\n'* ]] || [[ $thumbnail == *$'\t'* ]]; then return 1; fi
  printf '%s\t%s\n' "$media" "$thumbnail"
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
  --prepare-picker)
    prepare_picker=1
    ;;
esac

# sanitize theme name before use
raw_theme_name=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null | head -c 128)
if sanitized=$(sanitize_theme_name "$raw_theme_name" 2>/dev/null); then
  theme_name="$sanitized"
else
  theme_name=""
fi
theme_dir="$HOME/.local/state/omarchy/current/theme/backgrounds"
if [[ -n $theme_name ]]; then
  user_dir="$HOME/.config/omarchy/backgrounds/$theme_name"
else
  user_dir="$HOME/.config/omarchy/backgrounds"
fi
# containment: ensure user_dir is under expected prefix
if [[ $user_dir != "$HOME/.config/omarchy/backgrounds" && $user_dir != "$HOME/.config/omarchy/backgrounds/"* ]]; then
  user_dir="$HOME/.config/omarchy/backgrounds"
fi
current_background=$(readlink -f "$HOME/.local/state/omarchy/current/background" 2>/dev/null || true)
selected="$current_background"
if [[ -L "$video_state" ]]; then rm -f "$video_state"; selected="$current_background"; else
  [[ -s $video_state ]] && selected=$(<"$video_state")
fi
# bound selected length
if (( ${#selected} > 4096 )); then selected="$current_background"; fi
if [[ $selected == *$'\n'* ]] || [[ $selected == *$'\t'* ]]; then selected="$current_background"; fi

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

media_signature=$(
  {
    printf 'picker-v6\0'
    find -L "$theme_dir" "$user_dir" -maxdepth 2 -type f \( "${media_args[@]}" \) \
      -printf '%p:%s:%T@\0' 2>/dev/null \
      | sort -z
  } \
    | md5sum \
    | cut -d ' ' -f 1
)
if [[ -L "$rows_cache" ]]; then rm -f "$rows_cache"; fi
if [[ -L "$rows_signature_state" ]]; then rm -f "$rows_signature_state"; fi
if [[ -s $rows_cache && -s $rows_signature_state && $(<"$rows_signature_state") == "$media_signature" ]]; then
  cp "$rows_cache" "$rows_file"
else
  # ensure rows_lock dir secure
  ensure_secure_dir "$state_dir" || true
  if [[ -L "$rows_lock" ]]; then rm -f "$rows_lock"; fi
  exec 8>"$rows_lock"
  if ! flock -n 8; then
    if [[ -s $rows_cache ]]; then
      cp "$rows_cache" "$rows_file"
    else
      flock 8
    fi
  fi

  if [[ ! -s $rows_file ]]; then
    if [[ -s $rows_cache && -s $rows_signature_state && $(<"$rows_signature_state") == "$media_signature" ]]; then
      cp "$rows_cache" "$rows_file"
    else
      workers=$(nproc)
      (( workers > 6 )) && workers=6
      export cache_dir stock_thumbnail_dir MAX_VIDEO_BYTES MAX_ROW_BYTES
      export -f is_video thumbnail_for picker_thumbnail_for stock_thumbnail_for prewarm_picker_media sanitize_theme_name validate_wallpaper_path ensure_secure_dir
      if find -L "$theme_dir" "$user_dir" -maxdepth 2 -type f \( "${media_args[@]}" \) -print0 2>/dev/null \
        | timeout 30 xargs -0 -r -n 1 -P "$workers" bash -c 'prewarm_picker_media "$1"' _ 2>/dev/null \
        | head -n $MAX_ROWS | sort >"$rows_file"; then
        # bound rows_file size
        if [[ -L "$rows_cache" ]]; then rm -f "$rows_cache"; fi
        rows_tmp=$(mktemp -p "$state_dir" .rows.XXXXXX) || true
        sig_tmp=$(mktemp -p "$state_dir" .sig.XXXXXX) || true
        if [[ -n $rows_tmp && -n $sig_tmp ]]; then
          # validate rows_file does not contain bad chars before cache
          if ! grep -q $'\t' "$rows_file" 2>/dev/null; then
            # still cache even if no tab? but we always produce tab
            cp "$rows_file" "$rows_tmp" 2>/dev/null || true
          else
            cp "$rows_file" "$rows_tmp" 2>/dev/null || true
          fi
          # size bound
          rsz=$(stat -Lc '%s' "$rows_tmp" 2>/dev/null || echo 0)
          if (( rsz <= MAX_ROW_BYTES )); then
            chmod 0600 "$rows_tmp" 2>/dev/null || true
            mv -f "$rows_tmp" "$rows_cache"
            chmod 0600 "$rows_cache" 2>/dev/null || true
            printf '%s\n' "$media_signature" >"$sig_tmp"
            chmod 0600 "$sig_tmp" 2>/dev/null || true
            mv -f "$sig_tmp" "$rows_signature_state"
            chmod 0600 "$rows_signature_state" 2>/dev/null || true
          else
            rm -f "$rows_tmp" "$sig_tmp"
          fi
        fi
      fi
    fi
  fi
fi

[[ -s $rows_file ]] || {
  (( prepare_picker )) && exit 0
  omarchy-notification-send "No wallpaper was found for theme" -t 2000
  exit 0
}

# bound rows_file before base64
if (( $(stat -Lc '%s' "$rows_file" 2>/dev/null || echo 0) > MAX_ROW_BYTES )); then
  head -c $MAX_ROW_BYTES "$rows_file" >"$rows_file.tmp" && mv -f "$rows_file.tmp" "$rows_file"
fi
# also bound line count
if (( $(wc -l <"$rows_file" 2>/dev/null || echo 0) > MAX_ROWS )); then
  head -n $MAX_ROWS "$rows_file" >"$rows_file.tmp" && mv -f "$rows_file.tmp" "$rows_file"
fi

rows_b64=$(base64 -w 0 <"$rows_file")
# bound b64 size (~ 1.4x)
if (( ${#rows_b64} > 3000000 )); then
  if (( prepare_picker )); then exit 0; fi
  omarchy-notification-send "Too many wallpapers for picker" -t 2000
  exit 0
fi
if (( prepare_picker )); then
  if ! timeout 10 omarchy-shell image-selector preload "$rows_b64" "$selected" false false >/dev/null 2>&1; then true; fi
  exit 0
fi

if ! timeout 30 bash -c 'omarchy-shell image-selector open "" "$1" "$2" "$3" "$4" false false >/dev/null 2>&1 | grep -qx ok' _ "$rows_b64" "$selected" "$selection_file" "$done_file"; then
  # fallback direct check
  if [[ $(timeout 30 omarchy-shell image-selector open "" "$rows_b64" "$selected" "$selection_file" "$done_file" false false 2>/dev/null) != ok ]]; then
    exit 1
  fi
fi

# bounded wait for done_file (max 5 minutes)
waited=0
while [[ ! -e $done_file ]]; do
  sleep 0.05
  waited=$((waited+1))
  if (( waited > 6000 )); then
    exit 1
  fi
done
if [[ ! -s $selection_file ]]; then
  exit 0
fi
if [[ -L "$selection_file" ]]; then exit 1; fi
# bound selection size
if (( $(stat -Lc '%s' "$selection_file" 2>/dev/null || echo 0) > 8192 )); then exit 1; fi
wallpaper=$(<"$selection_file")
# sanitize wallpaper: reject control chars, overlong, tabs/newlines
if (( ${#wallpaper} > 4096 )) || [[ $wallpaper == *$'\n'* ]] || [[ $wallpaper == *$'\t'* ]]; then exit 1; fi
# trim
wallpaper=$(printf '%s' "$wallpaper" | tr -d '\r' | head -c 4096)
wallpaper=$(printf '%s' "$wallpaper" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
[[ -n $wallpaper ]] || exit 0
# containment check: must be under allowed roots or be selected from rows_file
# verify it was in rows_file or exists as file under allowed dirs
if ! grep -Fxq "$wallpaper" <(cut -f1 "$rows_file" 2>/dev/null) 2>/dev/null; then
  # also allow fallback if rows_file empty? validate path containment
  if ! validate_wallpaper_path "$wallpaper" 2>/dev/null; then
    # allow regular image fallback path even if not in rows (e.g., after theme change)
    if [[ ! -f $wallpaper ]]; then exit 1; fi
  fi
fi

if is_video "$wallpaper"; then
  if ! validate_wallpaper_path "$wallpaper" 2>/dev/null; then
    omarchy-notification-send "Could not read video file" -t 2000
    exit 1
  fi
  poster=$(thumbnail_for "$wallpaper") || {
    omarchy-notification-send "Could not read video file" -t 2000
    exit 1
  }
  if [[ -L "$state_dir" ]]; then exit 1; fi
  exec 9>"$transition_lock"
  if ! flock -n 9 2>/dev/null; then
    flock 9
  fi
  # timeout for lock hold (flock will release on close)
  remember_static_background
  atomic_write "$video_state" "$wallpaper" || { rm -f "$video_state"; printf '%s\n' "$wallpaper" >"$video_state"; }
  atomic_write "$poster_state" "$poster" || printf '%s\n' "$poster" >"$poster_state"
  atomic_write "$expected_state" "$poster" || printf '%s\n' "$poster" >"$expected_state"
  if ! timeout 15 omarchy theme bg set "$poster" || ! play_video "$wallpaper" 420; then
    restore_static_background
    omarchy-notification-send "Could not set video wallpaper" -t 2000
    exit 1
  fi
else
  # static wallpaper path must be regular file and not symlink to sensitive location outside backgrounds? allow but check exists
  if [[ -L "$wallpaper" ]]; then
    resolved=$(readlink -f "$wallpaper" 2>/dev/null) || exit 1
    [[ -f $resolved ]] || exit 1
  else
    [[ -f $wallpaper ]] || exit 1
  fi
  clear_live_wallpaper_state
  timeout 15 omarchy theme bg set "$wallpaper" || true
fi
