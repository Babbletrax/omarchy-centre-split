import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Centre Split panel. Presentation only: every action is forwarded to the bar
// widget, which owns the helper process, the logging, and the error state.
Panel {
  id: root
  moduleName: "io.github.babbletrax.centre-split"
  // The panel owns the single IpcHandler for this plugin id. ipcTarget is left
  // empty on purpose: the Panel base class creates a handler for it whenever it
  // is set, even with manageIpc: false, and that disabled handler registers
  // first and shadows the real one. The bar widget keeps only the shape
  // contract the bar's summon routing needs.
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var widget: hostWidget
  readonly property int workspaceId: widget ? widget.workspaceId : 0
  readonly property var shape: widget ? widget.shape : ({ windows: 0, bucket: 0, variant: 0 })
  readonly property string layout: widget ? widget.layout : "dwindle"
  readonly property bool splitActive: layout === Model.LAYOUT
  readonly property string lastError: widget ? widget.lastError : ""
  readonly property string lastEvent: widget ? widget.lastEvent : ""
  readonly property bool busy: widget ? widget.busy : false

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(root.contentForeground, 1.35)

  function refresh() {
    if (widget && widget.refresh) widget.refresh()
  }

  onOpenedChanged: if (opened) root.refresh()

  // Single IpcHandler for this plugin id, on the panel, matching the built-in
  // panels: everything routes through the bar widget, which owns the helper.
  IpcHandler {
    target: "io.github.babbletrax.centre-split"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function shape(cmd: string): void { if (root.widget) { if (cmd === "cyclevariant") root.widget.cycleVariant(); else root.widget.applyToWorkspace("current") } }
    function apply(): void { if (root.widget) root.widget.applyToWorkspace("current") }
    function release(): void { if (root.widget) root.widget.releaseWorkspace("current") }
    function reapply(): void { if (root.widget) root.widget.reapply() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(body.implicitHeight + Style.space(28))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Column {
        id: body
        width: parent.width
        spacing: Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(16)

        Text {
          width: parent.width
          text: "CENTRE SPLIT"
          color: root.dim
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          font.letterSpacing: 1
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Workspace " + (root.workspaceId || "?")
            + (root.splitActive ? " is split: " + Model.shapeSummary(root.shape) : " is on dwindle")
            + "."
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "The shape is picked automatically by how many windows are open, and rotates to the next variant each time that count changes. Cycle manually with Super+Shift+J, or the button below."
          color: Qt.darker(root.contentForeground, 1.2)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
        }

        // ---- Shape. One layout is registered with Hyprland; the shape for
        //      the current window count is reported here, read-only, plus a
        //      manual cycle action (mirrors SUPER+SHIFT+J / cyclevariant).
        Text {
          width: parent.width
          text: "SHAPE"
          color: root.dim
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
        }

        Rectangle {
          id: shapeCard
          width: body.width
          height: shapeRow.implicitHeight + Style.space(14)
          radius: 6
          color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)
          border.width: 1
          border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.18)

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.widget) root.widget.cycleVariant()
          }

          Row {
            id: shapeRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(12)

            Canvas {
              width: 72
              height: 26
              onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var fg = root.contentForeground
                ctx.strokeStyle = fg
                ctx.fillStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.35)
                ctx.lineWidth = 1
                var n = Math.max(1, Number(root.shape && root.shape.bucket) || 1)
                var gap = 2
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

            Column {
              width: shapeRow.width - 72 - Style.space(12)
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: Model.shapeSummary(root.shape)
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Click to cycle to the next shape for this window count."
                color: Qt.darker(root.contentForeground, 1.3)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        // ---- Actions for the focused workspace.
        Row {
          spacing: Style.space(18)

          Text {
            text: root.splitActive ? "Re-split this workspace" : "Split this workspace"
            color: root.busy ? root.dim : root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            font.underline: splitHover.containsMouse && !root.busy
            MouseArea {
              id: splitHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.widget) root.widget.applyToWorkspace("current")
            }
          }

          Text {
            visible: root.splitActive
            text: "Back to dwindle"
            color: root.busy ? root.dim : root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            font.underline: releaseHover.containsMouse && !root.busy
            MouseArea {
              id: releaseHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.widget) root.widget.releaseWorkspace("current")
            }
          }
        }

        Row {
          spacing: Style.space(18)

          Text {
            text: "Every workspace"
            color: root.busy ? root.dim : root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            font.underline: defaultHover.containsMouse && !root.busy
            MouseArea {
              id: defaultHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.widget) root.widget.setDefault()
            }
          }

          Text {
            text: "Reapply"
            color: root.busy ? root.dim : root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            font.underline: reapplyHover.containsMouse && !root.busy
            MouseArea {
              id: reapplyHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.widget) root.widget.reapply()
            }
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          visible: root.lastError !== ""
          text: root.lastError
          color: bar ? bar.urgent : root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          visible: root.lastEvent !== "" && root.lastError === ""
          text: root.lastEvent
          color: root.dim
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}