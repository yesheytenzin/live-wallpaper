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
- Also reachable via **Style → Background** in the Omarchy menu
  (replaces the default background action)

## Requirements

```bash
omarchy pkg add mpvpaper ffmpegthumbnailer
```

## Installation

```bash
omarchy plugin add https://github.com/yesheytenzin/omarchy-live-wallpaper.git --yes
```

The plugin id is `tenzin.live-wallpaper`.

> For Omarchy versions where the stock `omarchy.background` plugin is also
> present, keep it disabled so the two background services don't fight:
> `omarchy plugin disable omarchy.background`

## Usage

Put your videos anywhere the background picker scans:

- `~/.config/omarchy/backgrounds/<theme-slug>/` (user backgrounds)
- `<theme>/backgrounds/` (theme backgrounds, incl. a `live/` subfolder)

Open the wallpaper picker:

- Double-click the desktop, or
- Omarchy menu → **Style → Background**

Then just choose an image or a video. Done.

### Optional: route the menu action to the live picker

If the Style → Background menu entry still opens the stock image-only picker,
override it in `~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
"style.background": {"action":"~/.config/omarchy/plugins/tenzin.live-wallpaper/live-wallpaper.sh"}
```

## How it works

| Piece | Role |
|---|---|
| `manifest.json` | Plugin manifest (`tenzin.live-wallpaper`, shell service) |
| `Background.qml` | Cloned `omarchy.background` service; wires the picker and resume logic |
| `live-wallpaper.sh` | Collects images + videos, generates video posters/thumbnails, starts/stops `mpvpaper` |

State lives in `~/.local/state/omarchy/live-wallpaper/` (selected video, PID)
and generated posters/thumbnails in `~/.cache/omarchy/live-wallpaper/`.