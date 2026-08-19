# Omarchy Live Wallpaper

A user-owned Omarchy shell plugin that adds **video wallpaper** support to the
desktop background, right inside the built-in Omarchy picker.

Pick a video or a static image side by side from the same wallpaper selector:
videos play as a live wallpaper via `mpvpaper`, while the static frame of the
video (or the chosen image) stays active as Omarchy's regular background —
used for the lock screen, transitions, and the shell background layer.

## Features

- One picker for images **and** videos (MP4, MKV, WebM, MOV, M4V)
- Video thumbnails generated automatically with `ffmpegthumbnailer`
- Selecting a video sets its generated poster as the static fallback
- Selecting an image stops the live wallpaper and switches back to static
- Live wallpaper resumes automatically after `omarchy-shell` restarts
- Uses Omarchy's plugin replacement lifecycle for `omarchy.background`

## One-command installation

```bash
omarchy pkg add mpvpaper ffmpegthumbnailer && omarchy plugin add https://github.com/yesheytenzin/omarchy-live-wallpaper.git --enable --yes
```

This installs both dependencies and enables the plugin. Omarchy automatically
disables the stock background service because this plugin declares it as the
service it replaces.

The plugin id is `tenzin.live-wallpaper`.

## Usage

Put your videos anywhere the background picker scans:

- `~/.config/omarchy/backgrounds/<theme-slug>/` (user backgrounds)
- `<theme>/backgrounds/` (theme backgrounds, incl. a `live/` subfolder)

Double-click the desktop to open the image and video wallpaper picker.

The regular **Style → Background** item remains unchanged and continues to use
Omarchy's stock image-only picker.

## How it works

| Piece | Role |
|---|---|
| `manifest.json` | Plugin manifest (`tenzin.live-wallpaper`, shell service) |
| `Background.qml` | Cloned `omarchy.background` service; wires the picker and resume logic |
| `live-wallpaper.sh` | Collects images + videos, generates video posters/thumbnails, starts/stops `mpvpaper` |

State lives in `~/.local/state/omarchy/live-wallpaper/` (selected video, PID)
and generated posters/thumbnails in `~/.cache/omarchy/live-wallpaper/`.
