import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.babbletrax.centre-split"
  ipcTarget: "io.github.babbletrax.centre-split"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property int workspaceId: 0
  property string currentLayout: "dwindle"
  property string pendingLayout: ""
  property string statusText: ""

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var layouts: Model.presets()

  function applyBin() {
    return Qt.resolvedUrl("apply").toString().replace("file://", "")
  }

  function refresh() {
    if (!statusProcess.running) statusProcess.running = true
  }

  function applyLayout(hyprName) {
    if (root.workspaceId < 1) return
    root.pendingLayout = hyprName
    applyProcess.command = [applyBin(), "apply", String(root.workspaceId), hyprName]
    applyProcess.running = true
  }

  function applyDefault(hyprName) {
    root.pendingLayout = hyprName
    applyProcess.command = [applyBin(), "default", hyprName]
    applyProcess.running = true
  }

  function releaseWorkspace() {
    applyLayout("dwindle")
  }

  Process {
    id: statusProcess
    command: [root.applyBin(), "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text || "{}")
          if (data.workspace) root.workspaceId = Number(data.workspace)
          if (data.layout) root.currentLayout = String(data.layout)
          if (root.hostWidget && data.layout) root.hostWidget.currentLayout = String(data.layout)
        } catch (e) {}
      }
    }
  }

  Process {
    id: applyProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text || "{}")
          if (data.workspace) root.workspaceId = Number(data.workspace)
          if (data.layout) root.currentLayout = String(data.layout)
          if (root.hostWidget && data.layout) root.hostWidget.currentLayout = String(data.layout)
          root.statusText = "Workspace " + root.workspaceId + " → " + Model.barLabel(root.currentLayout)
        } catch (e) {
          root.statusText = "Could not apply layout"
        }
      }
    }
    onExited: function (code) {
      if (code !== 0) root.statusText = "hyprctl refused the layout"
      root.refresh()
    }
  }

  onOpenedChanged: if (opened) root.refresh()

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(body.implicitHeight + Style.space(24))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Column {
        id: body
        width: parent.width
        spacing: Style.space(12)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(16)

        Text {
          width: parent.width
          text: "CENTRE SPLIT"
          color: Qt.darker(root.contentForeground, 1.4)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          font.letterSpacing: 1
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Workspace " + (root.workspaceId || "?") + " is " + Model.barLabel(root.currentLayout) + "."
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Dwindle’s usual three-window split is a half on the left and two quarters stacked on the right. 1/4 · 1/2 · 1/4 puts the half in the middle."
          color: Qt.darker(root.contentForeground, 1.25)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
        }

        Repeater {
          model: root.layouts

          Rectangle {
            required property var modelData
            width: body.width
            height: row.implicitHeight + Style.space(14)
            radius: 6
            color: Model.presetById(root.currentLayout).hypr === modelData.hypr
              ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.16)
              : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06)
            border.width: 1
            border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.18)

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.applyLayout(modelData.hypr)
            }

            Row {
              id: row
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(12)

              Canvas {
                width: 72
                height: 28
                onPaint: {
                  var ctx = getContext("2d")
                  ctx.reset()
                  var fg = root.contentForeground
                  ctx.strokeStyle = fg
                  ctx.fillStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.35)
                  ctx.lineWidth = 1
                  var gap = 2
                  var x = 0.5
                  var slots = modelData.slots
                  var inner = width - 1 - gap * (slots.length - 1)
                  for (var i = 0; i < slots.length; i++) {
                    var w = inner * slots[i]
                    ctx.fillRect(x, 0.5, w, height - 1)
                    ctx.strokeRect(x, 0.5, w, height - 1)
                    x += w + gap
                  }
                }
              }

              Column {
                width: row.width - 72 - Style.space(12)
                spacing: Style.space(2)
                Text {
                  width: parent.width
                  text: modelData.name
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: modelData.detail
                  color: Qt.darker(root.contentForeground, 1.3)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                }
              }
            }
          }
        }

        Row {
          spacing: Style.space(16)

          Text {
            text: "All workspaces → 1/4 · 1/2 · 1/4"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            font.underline: defaultHover.containsMouse
            MouseArea {
              id: defaultHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.applyDefault("lua:centre-split")
            }
          }

          Text {
            text: "This workspace → dwindle"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            font.underline: dwindleHover.containsMouse
            MouseArea {
              id: dwindleHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.releaseWorkspace()
            }
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          visible: root.statusText !== ""
          text: root.statusText
          color: Qt.darker(root.contentForeground, 1.2)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
        }
      }
    }
  }
}
