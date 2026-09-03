pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtMultimedia
import qs.Commons

Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || home + "/.local/state"
  readonly property string script: home + "/.config/omarchy/plugins/tenzin.live-wallpaper/live-wallpaper.sh"
  readonly property string cleanupHelper: stateHome + "/omarchy/live-wallpaper/cleanup"
  property string videoPath: ""
  property var readyScreens: ({})
  property int playGeneration: 0
  property int revealGeneration: 0
  property bool revealVideo: true
  readonly property int maxVideoPathLen: 4096
  readonly property int maxTransitionMs: 4000
  readonly property string allowedConfigPrefix: home + "/.config/omarchy/backgrounds/"
  readonly property string allowedStatePrefix: home + "/.local/state/omarchy/current/theme/backgrounds/"
  readonly property string allowedSystemPrefix: "/usr/share/omarchy/"
  readonly property string allowedLocalSharePrefix: home + "/.local/share/omarchy/"

  function isValidVideoPath(p) {
    if (!p) return false
    var s = String(p)
    if (s.length === 0 || s.length > maxVideoPathLen) return false
    if (s.indexOf("\n") !== -1 || s.indexOf("\t") !== -1 || s.indexOf("\0") !== -1) return false
    // must be absolute
    if (s.charAt(0) !== "/") return false
    // reject path traversal attempts with .. (after decode, fileUrl encodes but we check raw)
    if (s.indexOf("..") !== -1) return false
    // allow only under known wallpaper roots (user config, state symlink, system themes)
    if (!(s.indexOf(allowedConfigPrefix) === 0 || s.indexOf(allowedStatePrefix) === 0
          || s.indexOf(allowedSystemPrefix) === 0 || s.indexOf(allowedLocalSharePrefix) === 0)) {
      return false
    }
    // extension allowlist
    var lower = s.toLowerCase()
    if (!(lower.endsWith(".mp4") || lower.endsWith(".mkv") || lower.endsWith(".webm") || lower.endsWith(".mov") || lower.endsWith(".m4v")))
      return false
    return true
  }

  function clampTransitionMs(v) {
    var n = Number(v)
    if (!isFinite(n)) return 0
    n = Math.floor(n)
    if (n < 0) return 0
    if (n > maxTransitionMs) return maxTransitionMs
    return n
  }

  function openSelector() {
    if (!pickerProc.running) pickerProc.running = true
  }

  function openThemeSwitcher() {
    if (!themeSwitchProc.running) themeSwitchProc.running = true
  }

  function play(path, transitionMs) {
    revealTimer.stop()
    readyScreens = ({})
    var raw = String(path || "").trim()
    // bound length early
    if (raw.length > maxVideoPathLen) raw = raw.substring(0, maxVideoPathLen)
    var ms = clampTransitionMs(transitionMs)
    // validate; reject invalid paths silently (do not set videoPath)
    if (raw !== "" && !isValidVideoPath(raw)) {
      // invalid path -> treat as stop to avoid arbitrary file load
      videoPath = ""
      playGeneration += 1
      revealVideo = false
      console.warn("live-wallpaper: rejected invalid video path", raw)
      return
    }
    revealVideo = ms <= 0
    videoPath = raw
    playGeneration += 1
    if (!revealVideo) {
      revealGeneration = playGeneration
      revealTimer.interval = ms
      revealTimer.restart()
    }
  }

  function stop() {
    revealTimer.stop()
    revealVideo = false
    videoPath = ""
    readyScreens = ({})
    playGeneration += 1
  }

  function markFrameReady(screenName) {
    if (readyScreens[screenName]) return
    var next = {}
    for (var key in readyScreens) next[key] = readyScreens[key]
    next[screenName] = true
    readyScreens = next
  }

  // Watchdogs: abort hung processes after 15s
  Timer {
    id: pickerWatchdog
    interval: 15000
    repeat: false
    onTriggered: if (pickerProc.running) pickerProc.running = false
  }
  Timer {
    id: resumeWatchdog
    interval: 15000
    repeat: false
    onTriggered: if (resumeProc.running) resumeProc.running = false
  }
  Timer {
    id: wireMenuWatchdog
    interval: 15000
    repeat: false
    onTriggered: if (wireMenuProc.running) wireMenuProc.running = false
  }
  Timer {
    id: preparePickerWatchdog
    interval: 15000
    repeat: false
    onTriggered: if (preparePickerProc.running) preparePickerProc.running = false
  }
  Timer {
    id: changeCheckWatchdog
    interval: 8000
    repeat: false
    onTriggered: if (changeCheckProc.running) changeCheckProc.running = false
  }
  Timer {
    id: themeSwitchWatchdog
    interval: 15000
    repeat: false
    onTriggered: if (themeSwitchProc.running) themeSwitchProc.running = false
  }

  Process {
    id: pickerProc
    command: ["timeout", "30", root.script]
    onRunningChanged: if (running) pickerWatchdog.restart(); else pickerWatchdog.stop()
  }

  Process {
    id: resumeProc
    command: ["timeout", "15", root.script, "--resume"]
    onRunningChanged: if (running) resumeWatchdog.restart(); else resumeWatchdog.stop()
  }

  Process {
    id: wireMenuProc
    command: ["timeout", "15", root.script, "--wire-menu"]
    onRunningChanged: if (running) wireMenuWatchdog.restart(); else wireMenuWatchdog.stop()
  }

  Process {
    id: preparePickerProc
    command: ["timeout", "30", root.script, "--prepare-picker"]
    onRunningChanged: if (running) preparePickerWatchdog.restart(); else preparePickerWatchdog.stop()
  }

  Process {
    id: changeCheckProc
    command: ["timeout", "8", root.script, "--stop-if-changed"]
    onRunningChanged: if (running) changeCheckWatchdog.restart(); else changeCheckWatchdog.stop()
  }

  Process {
    id: themeSwitchProc
    // keep fixed string but wrap with timeout; inner bash already quotes "$theme"
    command: ["bash", "-c", "timeout 12 bash -c 'theme=$(timeout 8 omarchy-theme-switcher); [[ -n $theme ]] && timeout 8 omarchy-theme-set \"$theme\" >/dev/null 2>&1 &'"]
    onRunningChanged: if (running) themeSwitchWatchdog.restart(); else themeSwitchWatchdog.stop()
  }

  Timer {
    id: revealTimer
    repeat: false
    onTriggered: {
      if (root.revealGeneration === root.playGeneration && root.videoPath !== "")
        root.revealVideo = true
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: {
      if (!changeCheckProc.running) changeCheckProc.running = true
    }
  }

  IpcHandler {
    target: "tenzin.live-wallpaper"

    function play(path: string, transitionMs: int): void { root.play(path, transitionMs) }
    function playSimple(path: string): void { root.play(path, 0) }
    function stop(): void { root.stop() }
    function status(): string {
      return JSON.stringify({
        active: root.videoPath !== "",
        video: root.videoPath,
        readyScreens: Object.keys(root.readyScreens).length,
        revealed: root.revealVideo,
        generation: root.playGeneration
      })
    }
  }

  Component.onCompleted: {
    wireMenuProc.running = true
    resumeProc.running = true
    preparePickerProc.running = true
  }

  // Safe cleanup: verify helper is regular file not symlink before exec, via bash guard
  Component.onDestruction: Quickshell.execDetached(["bash", "-c", 'p="$1"; [[ ! -L "$p" && -f "$p" && -x "$p" ]] && exec "$p" --cleanup-after-unload', "bash", root.cleanupHelper])

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      property bool frameDecoded: false
      property int playerGeneration: -1
      property int acceptedGeneration: -1

      function syncPlayer() {
        var generation = root.playGeneration
        playerGeneration = generation
        acceptedGeneration = -1
        frameDecoded = false
        player.stop()
        player.source = ""
        if (root.videoPath === "") {
          return
        }
        // validated in root.play, double-check before use
        if (!root.isValidVideoPath(root.videoPath)) {
          console.warn("live-wallpaper: blocked invalid source in syncPlayer")
          return
        }
        player.source = Util.fileUrl(root.videoPath)
        player.play()
        Qt.callLater(function() {
          if (panel.playerGeneration === generation && root.playGeneration === generation)
            panel.acceptedGeneration = generation
        })
      }

      screen: modelData
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore

      WlrLayershell.namespace: "tenzin-live-wallpaper"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      MediaPlayer {
        id: player
        videoOutput: videoOutput
        loops: MediaPlayer.Infinite
        onErrorOccurred: function(error, errorString) {
          console.warn("live-wallpaper: MediaPlayer error", error, errorString, "source", player.source)
          // fail closed: clear source to avoid retry loop, keep static fallback
          if (panel.playerGeneration === root.playGeneration) {
            panel.frameDecoded = false
            // do not auto-retry invalid media
          }
        }
      }

      VideoOutput {
        id: videoOutput
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        visible: root.videoPath !== "" && panel.frameDecoded && root.revealVideo
      }

      Connections {
        target: root
        function onPlayGenerationChanged() { panel.syncPlayer() }
        function onRevealVideoChanged() {
          if (root.revealVideo && panel.frameDecoded && panel.playerGeneration === root.playGeneration)
            player.play()
        }
      }

      Connections {
        target: videoOutput.videoSink
        function onVideoFrameChanged() {
          if (root.videoPath !== "" && !panel.frameDecoded
              && panel.acceptedGeneration === root.playGeneration
              && panel.playerGeneration === root.playGeneration) {
            panel.frameDecoded = true
            if (!root.revealVideo) player.pause()
            root.markFrameReady(panel.modelData.name)
          }
        }
      }

      Component.onCompleted: syncPlayer()

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onDoubleClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.openThemeSwitcher()
          else root.openSelector()
          mouse.accepted = true
        }
      }
    }
  }
}
