# Omarchy Live Wallpaper

A standalone Omarchy service plugin that adds videos to the existing wallpaper
picker without replacing or editing the stock `omarchy.background` plugin.
The **Style → Background** label, icon, aliases, and theme behavior stay intact.

## Features

- Lists images and videos together from the active theme's wallpaper folders
- Supports MP4, MKV, WebM, MOV, and M4V
- Generates cached video-frame previews for Omarchy's image picker
- Plays selected videos through `mpvpaper` on every connected monitor
- Keeps a static poster as Omarchy's lock-screen and transition fallback
- Stops playback when a static wallpaper or another theme is selected
- Resumes the selected video after the Omarchy shell restarts
- Preserves desktop double-click behavior through a transparent input layer

## Install

The plugin needs `mpvpaper` for playback and `ffmpegthumbnailer` for previews.
Install both dependencies and the plugin with one command:

```bash
omarchy pkg add mpvpaper ffmpegthumbnailer && omarchy plugin add https://github.com/yesheytenzin/live-wallpaper.git --enable --yes
```

The plugin runs unsandboxed with normal user permissions. It does not invoke
`sudo`, start another Quickshell process, or install anything by itself.

## Use

Place videos beside image wallpapers in either location:

- `~/.config/omarchy/backgrounds/<theme-slug>/`
- `<theme>/backgrounds/`

Open **Style → Background** or double-click an empty part of the desktop. Video
entries use a generated frame in the picker and start moving after selection.

## Update

```bash
omarchy plugin update tenzin.live-wallpaper --yes
```

## Remove

Run cleanup before removing the plugin. This stops `mpvpaper`, removes generated
state/cache, and restores the stock **Style → Background** action:

```bash
~/.config/omarchy/plugins/tenzin.live-wallpaper/live-wallpaper.sh --uninstall && omarchy plugin remove tenzin.live-wallpaper --yes
```

The external packages are intentionally left installed because they may be used
by other applications. Remove them separately only if they are no longer needed.

## Development

```bash
PLUGIN_DIR="$HOME/.config/omarchy/plugins/tenzin.live-wallpaper"
omarchy plugin validate "$PLUGIN_DIR"
qmllint -I "${OMARCHY_PATH:-/usr/share/omarchy}/shell" "$PLUGIN_DIR/Service.qml"
bash -n "$PLUGIN_DIR/live-wallpaper.sh"
```

The repository root is the plugin folder:

- `manifest.json` declares the standalone `service` entry point
- `Service.qml` owns menu wiring, desktop double-click input, resume, and change detection
- `live-wallpaper.sh` owns media discovery, previews, playback, state, and cleanup

Runtime state is stored under `~/.local/state/omarchy/live-wallpaper/`; generated
previews are stored under `~/.cache/omarchy/live-wallpaper/`.
