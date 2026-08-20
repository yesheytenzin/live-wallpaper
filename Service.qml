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

  function openSelector() {
    if (!pickerProc.running) pickerProc.running = true
  }

  function openThemeSwitcher() {
    if (!themeSwitchProc.running) themeSwitchProc.running = true
  }

  function play(path, transitionMs) {
    revealTimer.stop()
    readyScreens = ({})
    revealVideo = transitionMs <= 0
    videoPath = String(path || "").trim()
    playGeneration += 1
    if (!revealVideo) {
      revealGeneration = playGeneration
      revealTimer.interval = transitionMs
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

  Process {
    id: pickerProc
    command: [root.script]
  }

  Process {
    id: resumeProc
    command: [root.script, "--resume"]
  }

  Process {
    id: wireMenuProc
    command: [root.script, "--wire-menu"]
  }

  Process {
    id: preparePickerProc
    command: [root.script, "--prepare-picker"]
  }

  Process {
    id: changeCheckProc
    command: [root.script, "--stop-if-changed"]
  }

  Process {
    id: themeSwitchProc
    command: ["bash", "-c", "theme=$(omarchy-theme-switcher); [[ -n $theme ]] && omarchy-theme-set \"$theme\" >/dev/null 2>&1 &"]
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

  Component.onDestruction: Quickshell.execDetached([root.cleanupHelper, "--cleanup-after-unload"])

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
