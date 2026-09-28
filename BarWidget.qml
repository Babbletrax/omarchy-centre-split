import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.babbletrax.centre-split"

  property string currentLayout: "dwindle"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property string displayText: Model.barLabel(root.currentLayout)

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (!registerProcess.running) registerProcess.running = true
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

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

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  Component.onCompleted: refresh()

  Process {
    id: registerProcess
    command: [Qt.resolvedUrl("apply").toString().replace("file://", ""), "restore"]
    onExited: {
      if (!statusProcess.running) statusProcess.running = true
    }
  }

  Process {
    id: statusProcess
    command: [Qt.resolvedUrl("apply").toString().replace("file://", ""), "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text || "{}")
          if (data.layout) root.currentLayout = String(data.layout)
        } catch (e) {}
      }
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

  IpcHandler {
    target: "io.github.babbletrax.centre-split"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.refresh() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : root.displayText
    labelVisible: !root.vertical
    tooltipText: "Workspace split — 1/4 · 1/2 · 1/4"
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
        var gap = 1.5
        var x = 0.5
        var widths = [0.25, 0.5, 0.25]
        for (var i = 0; i < 3; i++) {
          var w = (width - 1 - gap * 2) * widths[i]
          ctx.fillRect(x, 0.5, w, height - 1)
          ctx.strokeRect(x, 0.5, w, height - 1)
          x += w + gap
        }
      }
    }
  }
}
