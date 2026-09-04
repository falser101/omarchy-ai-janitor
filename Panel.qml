import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.falser101.ai-janitor"
  ipcTarget: "io.github.falser101.ai-janitor"
  manageIpc: false

  readonly property string localeName: Quickshell.env("LANG") || ""
  readonly property var strings: Model.strings(root.localeName)
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var rows: {
    var _ = janitor.reportRevision
    return Model.flattenItems(janitor.report)
  }

  property var selected: ({})
  property int selectedRevision: 0
  property bool confirming: false
  property int cursorIndex: 0
  property bool cursorActive: false

  readonly property var selectedIds: {
    var _ = root.selectedRevision
    return Model.selectedList(root.selected)
  }
  readonly property double selectedBytes: {
    var _ = root.selectedRevision
    return Model.selectedBytes(root.rows, root.selected)
  }
  readonly property string barLabel: {
    if (janitor.loading && janitor.barBytes <= 0) return "AI"
    if (janitor.barBytes <= 0) return ""
    return "AI " + Model.formatBytes(janitor.barBytes)
  }

  visible: janitor.loading || janitor.barBytes > 0 || root.opened
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function isSelected(id) {
    var _ = root.selectedRevision
    return !!(root.selected && root.selected[id])
  }

  function toggleId(id) {
    var next = {}
    for (var key in root.selected) next[key] = root.selected[key]
    next[id] = !next[id]
    root.selected = next
    root.selectedRevision += 1
  }

  function resetSelection() {
    root.selected = Model.defaultSelected(root.rows)
    root.selectedRevision += 1
  }

  function itemSummary(row) {
    return root.strings.zh ? row.summaryZh : row.summary
  }

  function confirmMessage() {
    var count = root.selectedIds.length
    var size = Model.formatBytes(root.selectedBytes)
    if (root.strings.zh)
      return "将 " + count + " 项（" + size + "）移到回收站？可从回收站还原。"
    return "Move " + count + " items (" + size + ") to trash? You can restore them from Trash."
  }

  function requestClean() {
    if (root.selectedIds.length === 0 || janitor.busy) return
    root.confirming = true
  }

  function runClean() {
    root.confirming = false
    janitor.cleanIds(root.selectedIds)
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    confirming = false
    if (panelFlick) panelFlick.contentY = 0
    janitor.refresh(true)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Connections {
    target: janitor
    function onReportRevisionChanged() { root.resetSelection() }
  }

  Service {
    id: janitor
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { janitor.refresh(true); return "ok" }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barLabel
    labelVisible: true
    hasVisualContent: text !== ""
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.strings.tooltip
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) janitor.refresh(true)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.confirming) root.confirming = false
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: {
        if (root.confirming) root.runClean()
        else if (root.cursorActive && root.cursorIndex >= 0 && root.cursorIndex < root.rows.length)
          root.toggleId(root.rows[root.cursorIndex].id)
        else root.requestClean()
      }
      onMoveRequested: function(dx, dy) {
        if (root.rows.length === 0) return
        root.cursorActive = true
        root.cursorIndex = Math.max(0, Math.min(root.rows.length - 1, root.cursorIndex + dy))
      }
      onTextKey: function(t) {
        if (t === "r" || t === "R") janitor.refresh(true)
        else if (t === " ") {
          if (root.cursorActive && root.cursorIndex >= 0 && root.cursorIndex < root.rows.length)
            root.toggleId(root.rows[root.cursorIndex].id)
        }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: root.strings.title
            meta: janitor.loading
              ? root.strings.scanning
              : (Model.formatBytes(janitor.cacheBytes) + " " + root.strings.cache
                + " · " + Model.formatBytes(janitor.staleBytes) + " " + root.strings.stale
                + " · " + Model.formatBytes(janitor.reviewBytes) + " " + root.strings.review)
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: "󰃢"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Text {
            visible: janitor.lastError !== ""
            width: parent.width
            text: janitor.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: janitor.actionStatus === "ok" && janitor.lastError === ""
            width: parent.width
            text: root.strings.done
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: root.rows.length === 0 && !janitor.loading
            width: parent.width
            text: root.strings.empty
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Repeater {
            model: root.rows

            Toggle {
              required property var modelData
              required property int index
              width: column.width
              label: root.itemSummary(modelData) + "  " + Model.formatBytes(modelData.bytes)
              description: Model.classLabel(root.strings, modelData.className) + " · " + modelData.path
              checked: root.isSelected(modelData.id)
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.cursorIndex === index
              onClicked: root.toggleId(modelData.id)
            }
          }

          Text {
            visible: root.reviewSelected
            width: parent.width
            text: root.strings.warningReview
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Button {
            width: parent.width
            text: root.strings.reclaim + " · " + Model.formatBytes(root.selectedBytes)
            enabled: root.selectedIds.length > 0 && !janitor.busy
            foreground: root.foreground
            onClicked: root.requestClean()
          }
        }
      }

      ConfirmDialog {
        anchors.fill: parent
        z: 10
        opened: root.confirming
        message: root.confirmMessage()
        cancelText: root.strings.cancel
        confirmText: root.strings.confirm
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: root.confirming = false
        onConfirmed: root.runClean()
      }
    }
  }

  readonly property bool reviewSelected: {
    var _ = root.selectedRevision
    for (var i = 0; i < root.rows.length; i++) {
      if (root.rows[i].className === "review" && root.isSelected(root.rows[i].id))
        return true
    }
    return false
  }
}
