# Omarchy Live Wallpaper

A standalone Omarchy service plugin that adds videos to the existing wallpaper
picker without replacing or editing the stock `omarchy.background` plugin.
When enabled, it integrates the video-aware picker with Omarchy's existing
**Style → Background** entry.

## Features

- Lists images and videos together from the active theme's wallpaper folders
- Supports MP4, MKV, WebM, MOV, and M4V
- Starts cached videos in about 100 ms using persistent Qt multimedia surfaces
- Keeps one warm, muted, looping player per connected monitor
- Reveals video only after the first valid frame, preventing black flashes
- Generates picker previews with Omarchy's existing `ffmpeg` installation
- Keeps a static poster as the lock-screen and transition fallback
- Stops playback when a static wallpaper or another theme is selected
- Resumes the selected video after the Omarchy shell restarts
- Preserves desktop double-click behavior through the video/input surface

## Demo videos

### Select and apply a video wallpaper

[![Select and apply a video wallpaper](https://github.com/yesheytenzin/live-wallpaper/releases/download/v3.0.2/select-video-wallpaper-preview.gif)](https://github.com/yesheytenzin/live-wallpaper/releases/download/v3.0.2/select-video-wallpaper.mp4)

[Watch the full 1080p video](https://github.com/yesheytenzin/live-wallpaper/releases/download/v3.0.2/select-video-wallpaper.mp4)

### Add wallpaper files and select a video

[![Add wallpaper files and select a video](https://github.com/yesheytenzin/live-wallpaper/releases/download/v3.0.2/add-and-select-video-wallpaper-preview.gif)](https://github.com/yesheytenzin/live-wallpaper/releases/download/v3.0.2/add-and-select-video-wallpaper.mp4)

[Watch the full 1080p video](https://github.com/yesheytenzin/live-wallpaper/releases/download/v3.0.2/add-and-select-video-wallpaper.mp4)

Both demonstrations show the plugin running on Omarchy.

## Install

```bash
omarchy plugin add https://github.com/yesheytenzin/live-wallpaper.git --enable --yes
```

No additional packages or privileged installation steps are required. Playback
uses Qt Multimedia from Omarchy's existing Qt runtime, and previews use the
existing `ffmpeg` command. The plugin does not start another Quickshell process.

## Use

Place videos beside image wallpapers in either location:

- `~/.config/omarchy/backgrounds/<theme-slug>/`
- `<theme>/backgrounds/`

Open **Style → Background** or double-click an empty part of the desktop. Video
entries use a generated frame in the picker and start moving after selection.

### Menu integration

Enabling the plugin updates the `style.background` action in
`~/.config/omarchy/extensions/omarchy-menu.jsonc`. The stock **Background**
name, icon, and aliases are preserved; only its picker action changes.

Disabling or removing the plugin through Omarchy unloads the service and removes
the menu override. It can also be removed manually without disabling playback:

```bash
~/.config/omarchy/plugins/tenzin.live-wallpaper/live-wallpaper.sh --unwire-menu
```

## Update

```bash
omarchy plugin update tenzin.live-wallpaper --yes
```

## Remove

Standard removal unloads the service and automatically removes its
**Style → Background** integration before deleting the plugin:

```bash
omarchy plugin remove tenzin.live-wallpaper --yes
```

The generated state and thumbnail cache are intentionally retained so a later
reinstall can resume the previous selection. For complete removal, run cleanup
first. This stops playback, restores the last static wallpaper, removes all
generated state/cache, and restores the stock Background action:

```bash
~/.config/omarchy/plugins/tenzin.live-wallpaper/live-wallpaper.sh --uninstall
omarchy plugin remove tenzin.live-wallpaper --yes
```

## Development

```bash
PLUGIN_DIR="$HOME/.config/omarchy/plugins/tenzin.live-wallpaper"
omarchy plugin validate "$PLUGIN_DIR"
/usr/lib/qt6/bin/qmllint -I "${OMARCHY_PATH:-/usr/share/omarchy}/shell" "$PLUGIN_DIR/Service.qml"
bash -n "$PLUGIN_DIR/live-wallpaper.sh"
```

The repository root is the plugin folder:

- `manifest.json` declares the standalone service entry point
- `Service.qml` owns persistent players, IPC, desktop input, and resume
- `live-wallpaper.sh` owns media discovery, `ffmpeg` previews, state, and cleanup

Runtime state is stored under `~/.local/state/omarchy/live-wallpaper/`; generated
previews are stored under `~/.cache/omarchy/live-wallpaper/`.

## License

Licensed under the MIT License. See [`LICENSE`](LICENSE).
