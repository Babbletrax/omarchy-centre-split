import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  function applyBin() {
    return Qt.resolvedUrl("apply").toString().replace("file://", "")
  }

  Component.onCompleted: restoreProcess.running = true

  Process {
    id: restoreProcess
    command: [root.applyBin(), "restore"]
  }
}
