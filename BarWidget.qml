import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import "Model.js" as Model

// Centre Split bar widget: a miniature of the selected shape, plus the panel
// that drives it. This file owns the helper calls, the error surface, the log
// lines, and the shell IPC contract; Panel.qml is only presentation.
BarWidget {
  id: root
  moduleName: "io.github.babbletrax.centre-split"

  property int workspaceId: 0
  property string layout: "dwindle"
  property var shape: ({ windows: 0, bucket: 0, variant: 0 })
  property bool busy: false
  property string lastError: ""
  property string lastEvent: ""
  property string lastEventAt: ""
  property var callback: null
  property var pendingArgs: null

  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  readonly property string helperPath: Qt.resolvedUrl("apply").toString().replace(/^file:\/\//, "")

  readonly property bool splitActive: root.layout === Model.LAYOUT
  readonly property string displayText: root.splitActive ? Model.shapeSummary(root.shape) : "Split"

  // ---- Logging in the shape the first-party services use, so plugin trouble
  //      shows up in `omarchy debug` and in the shell log.
  function logEvent(event, details) {
    var suffix = (details === undefined || details === null || details === "") ? "" : ": " + String(details)
    root.lastEventAt = new Date().toISOString()
    root.lastEvent = event + suffix
    console.log("omarchy centre-split " + root.lastEventAt + " " + root.lastEvent)
  }

  // ---- Native system notification. The helper raises these for its own
  //      actions; this covers the case where the helper cannot run at all.
  function notifyNative(urgency, headline, body) {
    var args = [root.omarchyPath + "/bin/omarchy-notification-send", "-u", urgency,
                "-t", urgency === "critical" ? "12000" : "8000", headline]
    if (body !== undefined && body !== "") args.push(body)
    Quickshell.execDetached(args)
  }

  function runHelper(args, onDone) {
    if (root.busy) {
      // The helper takes a couple of seconds (it pauses while Hyprland settles
      // each rule change). Queue the newest request instead of dropping the
      // click that caused it.
      root.pendingArgs = args
      root.logEvent("queued", args.join(" "))
      return false
    }
    root.busy = true
    root.callback = onDone
    actionProcess.command = [root.helperPath].concat(args)
    actionProcess.running = true
    return true
  }

  function refresh() {
    if (!statusProcess.running) statusProcess.running = true
  }

  function applyToWorkspace(workspace) {
    // "current" is resolved by the helper at call time: the widget's cached
    // workspace id goes stale the moment you switch workspaces, and acting on
    // a stale id splits a workspace you are not even looking at.
    var ws = (workspace === undefined || workspace === null || workspace === ""
              || workspace === "current") ? "current" : String(Number(workspace) || 0)
    if (ws === "0") {
      root.lastError = "No workspace to split"
      root.logEvent("apply-skipped", "no workspace")
      return
    }
    root.runHelper(["apply", ws])
  }

  // Manually advance the shape variant for however many windows are on the
  // focused workspace right now (same action as the SUPER+SHIFT+J keybind).
  function cycleVariant() {
    root.runHelper(["cyclevariant"])
  }

  function releaseWorkspace(workspace) {
    var ws = (workspace === undefined || workspace === null || workspace === ""
              || workspace === "current") ? "current" : String(Number(workspace) || 0)
    if (ws === "0") return
    root.runHelper(["release", ws])
  }

  function setDefault() {
    root.runHelper(["default"])
  }

  // After a Hyprland config reload the runtime registration is gone; this puts
  // the layouts and saved choices back.
  function reapply() {
    root.runHelper(["restore"])
  }

  // ---- Panel plumbing, per the bar-widget contract.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  Component.onCompleted: root.refresh()

  Process {
    id: statusProcess
    command: [root.helperPath, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text || "{}")
          if (data.workspace !== undefined) root.workspaceId = Number(data.workspace) || 0
          if (data.layout) root.layout = String(data.layout)
          if (data.shape) root.shape = data.shape
          if (data.error) root.lastError = String(data.error)
        } catch (e) {
          root.logEvent("status-parse-failed", String(e))
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") root.logEvent("status-stderr", text.trim())
    }
    onExited: function (code) {
      if (code !== 0) root.logEvent("status-failed", "exit=" + code)
    }
  }

  Process {
    id: actionProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var data = null
        try {
          data = JSON.parse(text || "{}")
        } catch (e) {
          root.lastError = "Unexpected reply from the Centre Split helper"
          root.logEvent("action-parse-failed", String(e))
        }
        if (data) {
          if (data.error) {
            root.lastError = String(data.error)
            root.logEvent("action-error", String(data.error))
          } else {
            root.lastError = ""
            if (data.workspace !== undefined) root.workspaceId = Number(data.workspace) || root.workspaceId
            if (data.layout) root.layout = String(data.layout)
            if (data.shape) root.shape = data.shape
            root.logEvent("action-ok", String(data.note || ""))
          }
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") root.logEvent("action-stderr", text.trim())
    }
    onExited: function (code) {
      root.busy = false
      if (code !== 0 && root.lastError === "") {
        // Nothing came back: the helper could not run, so the helper cannot
        // report it either. Raise the native notification from here.
        root.lastError = "Centre Split helper failed (exit " + code + ")"
        root.logEvent("helper-failed", "exit=" + code)
        root.notifyNative("normal", "Centre split", root.lastError)
      }
      if (root.callback) {
        var fn = root.callback
        root.callback = null
        fn(code)
      }
      if (root.pendingArgs) {
        var queued = root.pendingArgs
        root.pendingArgs = null
        root.logEvent("running-queued", queued.join(" "))
        actionProcess.command = [root.helperPath].concat(queued)
        root.busy = true
        actionProcess.running = true
        return
      }
      root.refresh()
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // No IpcHandler here: Panel.qml owns the single handler for this plugin id.
  // The bar's summon routing only needs the shape contract below.

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : root.displayText
    labelVisible: !root.vertical
    tooltipText: root.lastError !== ""
      ? "Centre split — " + root.lastError
      : "Centre split — " + Model.shapeSummary(root.shape)
    horizontalMargin: 8.75
    verticalPadding: 8.75
    onPressed: function (b) {
      root.togglePanel()
    }

    Canvas {
      id: thumb
      visible: root.vertical || root.displayText === ""
      anchors.centerIn: parent
      width: 18
      height: 12
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var fg = button.foreground
        ctx.strokeStyle = fg
        ctx.fillStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.35)
        ctx.lineWidth = 1
        // No fixed preset list any more: draw a generic N-up thumbnail from
        // the bucket (window count), which is all the widget actually knows.
        var n = Math.max(1, Number(root.shape && root.shape.bucket) || 1)
        var gap = 1.5
        var x = 0.5
        var inner = width - 1 - gap * (n - 1)
        var w = inner / n
        for (var i = 0; i < n; i++) {
          ctx.fillRect(x, 0.5, w, height - 1)
          ctx.strokeRect(x, 0.5, w, height - 1)
          x += w + gap
        }
      }
    }
  }
}