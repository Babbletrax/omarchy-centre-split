import QtQuick
import Quickshell
import Quickshell.Io

// Headless registrar for Centre Split.
//
// Only runs when the plugin is listed in plugins[] of shell.json (enabling a
// bar widget places it on the bar and does not add that entry). The bar widget
// restores on load as well, so this service is a belt-and-braces path for
// setups that enable the plugin without the widget.
Item {
  id: root

  property string lastEvent: ""
  property string lastEventAt: ""

  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  readonly property string helperPath: Qt.resolvedUrl("apply").toString().replace(/^file:\/\//, "")

  function logEvent(event) {
    root.lastEventAt = new Date().toISOString()
    root.lastEvent = event
    console.log("omarchy centre-split " + root.lastEventAt + " service: " + event)
  }

  Component.onCompleted: {
    logEvent("restore-start")
    restoreProcess.running = true
  }

  Process {
    id: restoreProcess
    command: [root.helperPath, "restore"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text || "{}")
          if (data.error) {
            root.logEvent("restore-failed: " + data.error)
          } else {
            root.logEvent("restore-ok applied=" + data.applied + " skipped=" + data.skipped)
          }
        } catch (e) {
          root.logEvent("restore-parse-failed")
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") root.logEvent("restore-stderr: " + text.trim())
    }
    onExited: function (code) {
      if (code !== 0) {
        // Hyprland may not be up yet at shell start; the bar widget retries on
        // its own load, and the panel has a Reapply action.
        root.logEvent("restore-exit=" + code)
        Quickshell.execDetached([
          root.omarchyPath + "/bin/omarchy-notification-send",
          "-u", "low",
          "Centre split",
          "Could not restore the split layout (exit " + code + "). Use Reapply in the panel."
        ])
      }
    }
  }
}