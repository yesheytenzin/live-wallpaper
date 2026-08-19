import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "tenzin.live-wallpaper"

  readonly property string installer: Quickshell.env("HOME") + "/.config/omarchy/plugins/tenzin.live-wallpaper/live-wallpaper.sh --install-dependencies"
  property bool dependenciesInstalled: true

  function refresh() {
    if (!dependencyCheck.running) dependencyCheck.running = true
  }

  function installDependencies() {
    if (!root.bar) return
    root.bar.run("omarchy-launch-floating-terminal-with-presentation " + root.installer)
  }

  visible: !dependenciesInstalled
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: dependencyCheck
    command: ["bash", "-lc", "command -v mpvpaper >/dev/null && command -v ffmpegthumbnailer >/dev/null"]
    onExited: function(exitCode) {
      root.dependenciesInstalled = exitCode === 0
    }
  }

  Timer {
    interval: root.dependenciesInstalled ? 30000 : 3000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰏔"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: "Install Live Wallpaper dependencies"
    onPressed: root.installDependencies()
  }
}
