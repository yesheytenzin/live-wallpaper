pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string script: home + "/.config/omarchy/plugins/tenzin.live-wallpaper/live-wallpaper.sh"

  function openSelector() {
    if (!pickerProc.running) pickerProc.running = true
  }

  function openThemeSwitcher() {
    if (!themeSwitchProc.running) themeSwitchProc.running = true
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
    id: dependencyNoticeProc
    command: [root.script, "--notify-dependencies"]
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

  Component.onCompleted: {
    resumeProc.running = true
    wireMenuProc.running = true
    dependencyNoticeProc.running = true
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData

      screen: modelData
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore

      WlrLayershell.namespace: "tenzin-live-wallpaper-input"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

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
