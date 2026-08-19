# Omarchy Live Wallpaper

A standalone Omarchy service plugin that adds videos to the existing wallpaper
picker without replacing or editing the stock `omarchy.background` plugin.
It does not modify user configuration during installation or startup.

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

Double-click an empty part of the desktop to open the video-aware picker. Video
entries use a generated frame in the picker and start moving after selection.

### Optional menu integration

The plugin does not change the Omarchy menu automatically. To explicitly make
**Style → Background** open the video-aware picker, run:

```bash
~/.config/omarchy/plugins/tenzin.live-wallpaper/live-wallpaper.sh --wire-menu
```

This command modifies
`~/.config/omarchy/extensions/omarchy-menu.jsonc`. It preserves the stock
**Background** name, icon, and aliases while replacing that entry's action.

To remove the menu override:

```bash
~/.config/omarchy/plugins/tenzin.live-wallpaper/live-wallpaper.sh --unwire-menu
```

## Update

```bash
omarchy plugin update tenzin.live-wallpaper --yes
```

## Remove

Run cleanup before removing the plugin. This stops playback, restores the last
static wallpaper, removes generated state/cache, and restores the stock
**Style → Background** action:

```bash
~/.config/omarchy/plugins/tenzin.live-wallpaper/live-wallpaper.sh --uninstall && omarchy plugin remove tenzin.live-wallpaper --yes
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


## License

Licensed under the MIT License. See [`LICENSE`](LICENSE).
Runtime state is stored under `~/.local/state/omarchy/live-wallpaper/`; generated
previews are stored under `~/.cache/omarchy/live-wallpaper/`.
