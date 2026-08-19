# Omarchy Live Wallpaper

An Omarchy shell plugin that adds **video wallpaper** support to the desktop
background, right inside the wallpaper picker.

Pick a video or a static image side by side from the same wallpaper selector:
videos play as a live wallpaper via `mpvpaper`, while a static frame of the
video (or the chosen image) stays active as Omarchy's regular background —
used for the lock screen, transitions, and the shell background layer.

## Features

- One picker for images **and** videos (MP4, MKV, WebM, MOV, M4V)
- Videos are picked up from the **same folders** as image wallpapers — no
  separate directory needed
- Video preview thumbnails generated and cached automatically
- Selecting a video sets its generated poster as the static fallback image
- Selecting an image stops live playback and restores normal behavior
- Live wallpaper resumes automatically after login / `omarchy-shell` restart
- Live playback stops automatically when the theme or background is changed
  through any Omarchy command
- Works on all connected monitors with looping, muted audio, full-aspect
  rendering, and automatic pause when obscured
- Replaces `omarchy.background` through Omarchy's plugin lifecycle, so the
  stock **Style → Background** menu item keeps its name and is routed to the
  video-aware picker automatically

## Installation

```bash
omarchy pkg add mpvpaper ffmpegthumbnailer && omarchy plugin add https://github.com/yesheytenzin/omarchy-live-wallpaper.git --enable --yes
```

The plugin id is `tenzin.live-wallpaper`. Enabling it automatically disables
the stock background service it replaces.

## Usage

Put videos and images anywhere the background picker scans:

- `~/.config/omarchy/backgrounds/<theme-slug>/` (user backgrounds)
- `<theme>/backgrounds/` (theme backgrounds)

Open the wallpaper picker via **Style → Background** in the Omarchy menu, or
double-click the desktop. Then pick an image or a video.

## How it works

| Piece | Role |
|---|---|
| `manifest.json` | Plugin manifest (`tenzin.live-wallpaper` replaces `omarchy.background`) |
| `Background.qml` | Stock background renderer; adds the picker, resume, and auto-stop integration |
| `live-wallpaper.sh` | Collects images + videos, generates posters/thumbnails, starts/stops `mpvpaper` |

Live state lives in `~/.local/state/omarchy/live-wallpaper/` (selected video,
fallback poster, expected background, `mpvpaper` PIDs). Posters and video
previews are cached in `~/.cache/omarchy/live-wallpaper/` and invalidated when
a video file changes. The picker's **Style → Background** menu wiring is
self-installed on first use and can be removed by deleting the
`style.background` entry from `~/.config/omarchy/extensions/omarchy-menu.jsonc`.

## Uninstall

```bash
omarchy plugin remove tenzin.live-wallpaper --yes
omarchy plugin enable omarchy.background
```

Remove the `style.background` entry from
`~/.config/omarchy/extensions/omarchy-menu.jsonc` and delete
`~/.local/state/omarchy/live-wallpaper/` afterwards.