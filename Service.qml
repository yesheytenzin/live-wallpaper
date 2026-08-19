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
  readonly property string script: home + "/.config/omarchy/plugins/tenzin.live-wallpaper/live-wallpaper.sh"
  property string videoPath: ""
  property var readyScreens: ({})

  function openSelector() {
    if (!pickerProc.running) pickerProc.running = true
  }

  function openThemeSwitcher() {
    if (!themeSwitchProc.running) themeSwitchProc.running = true
  }

  function play(path) {
    readyScreens = ({})
    videoPath = String(path || "").trim()
  }

  function stop() {
    videoPath = ""
    readyScreens = ({})
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
    id: changeCheckProc
    command: [root.script, "--stop-if-changed"]
  }

  Process {
    id: themeSwitchProc
    command: ["bash", "-c", "theme=$(omarchy-theme-switcher); [[ -n $theme ]] && omarchy-theme-set \"$theme\" >/dev/null 2>&1 &"]
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

    function play(path: string): void { root.play(path) }
    function stop(): void { root.stop() }
    function status(): string {
      return JSON.stringify({
        active: root.videoPath !== "",
        video: root.videoPath,
        readyScreens: Object.keys(root.readyScreens).length
      })
    }
  }

  Component.onCompleted: {
    wireMenuProc.running = true
    resumeProc.running = true
  }

  Component.onDestruction: Quickshell.execDetached([root.script, "--unwire-menu"])

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      property bool frameReady: false

      function syncPlayer() {
        frameReady = false
        player.stop()
        if (root.videoPath === "") {
          player.source = ""
          return
        }
        player.source = Util.fileUrl(root.videoPath)
        player.play()
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
        visible: root.videoPath !== "" && panel.frameReady
      }

      Connections {
        target: root
        function onVideoPathChanged() { panel.syncPlayer() }
      }

      Connections {
        target: videoOutput.videoSink
        function onVideoFrameChanged() {
          if (root.videoPath !== "") {
            panel.frameReady = true
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
