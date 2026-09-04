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
  readonly property var tabs: {
    var _ = janitor.reportRevision
    return Model.tabModel(root.strings, janitor.report)
  }
  readonly property var groups: Model.groupsForClass(root.rows, root.activeClass)

  property string activeClass: "cache"
  property var selected: ({})
  property var expanded: ({})
  property int selectedRevision: 0
  property int expandedRevision: 0
  property bool confirming: false
  property string focusSection: "list"
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
  readonly property int tabIndex: {
    if (root.activeClass === "stale") return 1
    if (root.activeClass === "review") return 2
    return 0
  }
  readonly property bool reviewSelected: {
    var _ = root.selectedRevision
    for (var i = 0; i < root.rows.length; i++) {
      if (root.rows[i].className === "review" && root.isSelected(root.rows[i].id))
        return true
    }
    return false
  }

  visible: janitor.loading || janitor.barBytes > 0 || root.opened
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function isSelected(id) {
    var _ = root.selectedRevision
    return !!(root.selected && root.selected[id])
  }

  function isExpanded(toolId) {
    var _ = root.expandedRevision
    return !!(root.expanded && root.expanded[toolId])
  }

  function copyMap(source) {
    var next = {}
    if (source) {
      for (var key in source) next[key] = source[key]
    }
    return next
  }

  function toggleId(id) {
    var next = root.copyMap(root.selected)
    next[id] = !next[id]
    root.selected = next
    root.selectedRevision += 1
  }

  function toggleGroup(group) {
    root.selected = Model.toggleToolSelection(group, root.selected)
    root.selectedRevision += 1
  }

  function toggleExpanded(toolId) {
    var next = root.copyMap(root.expanded)
    next[toolId] = !next[toolId]
    root.expanded = next
    root.expandedRevision += 1
  }

  function setExpanded(toolId, on) {
    var next = root.copyMap(root.expanded)
    next[toolId] = on
    root.expanded = next
    root.expandedRevision += 1
  }

  function resetSelection() {
    root.selected = Model.defaultSelected(root.rows)
    root.selectedRevision += 1
    root.cursorIndex = 0
  }

  function itemSummary(row) {
    return root.strings.zh ? row.summaryZh : row.summary
  }

  function groupChecked(group) {
    var _ = root.selectedRevision
    return Model.toolAllSelected(group, root.selected)
  }

  function selectClass(value) {
    root.activeClass = value
    root.cursorIndex = 0
    if (panelFlick) panelFlick.contentY = 0
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

  function currentGroup() {
    if (root.cursorIndex < 0 || root.cursorIndex >= root.groups.length) return null
    return root.groups[root.cursorIndex]
  }

  function moveCursor(dx, dy) {
    root.cursorActive = true
    if (dx !== 0 && root.focusSection === "tabs") {
      var nextTab = Math.max(0, Math.min(2, root.tabIndex + dx))
      root.selectClass(["cache", "stale", "review"][nextTab])
      return
    }
    if (dx > 0 && root.focusSection === "list") {
      var openGroup = root.currentGroup()
      if (openGroup && openGroup.items.length > 1) root.setExpanded(openGroup.toolId, true)
      return
    }
    if (dx < 0 && root.focusSection === "list") {
      var closeGroup = root.currentGroup()
      if (closeGroup) root.setExpanded(closeGroup.toolId, false)
      return
    }
    if (dy === 0) return
    if (root.focusSection === "tabs") {
      if (dy > 0) {
        root.focusSection = root.groups.length > 0 ? "list" : "action"
        root.cursorIndex = 0
      }
      return
    }
    if (root.focusSection === "action") {
      if (dy < 0) {
        root.focusSection = root.groups.length > 0 ? "list" : "tabs"
        root.cursorIndex = Math.max(0, root.groups.length - 1)
      }
      return
    }
    var next = root.cursorIndex + dy
    if (next < 0) {
      root.focusSection = "tabs"
      root.cursorIndex = 0
      return
    }
    if (next >= root.groups.length) {
      root.focusSection = "action"
      return
    }
    root.cursorIndex = next
  }

  function activateCursor() {
    if (root.confirming) {
      root.runClean()
      return
    }
    if (!root.cursorActive) {
      root.cursorActive = true
      return
    }
    if (root.focusSection === "action") {
      root.requestClean()
      return
    }
    if (root.focusSection === "tabs") return
    var group = root.currentGroup()
    if (group) root.toggleGroup(group)
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    confirming = false
    focusSection = "list"
    cursorIndex = 0
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
      onActivateRequested: root.activateCursor()
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") janitor.refresh(true)
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
              : (Model.formatBytes(Model.classBytes(janitor.report, root.activeClass))
                + " · " + Model.classLabel(root.strings, root.activeClass))
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

          Row {
            id: classSwitch
            width: parent.width
            spacing: Style.spacing.md
            readonly property real cellWidth: root.tabs.length > 0
              ? (width - spacing * (root.tabs.length - 1)) / root.tabs.length
              : 0

            Repeater {
              model: root.tabs

              Button {
                required property var modelData
                required property int index
                width: classSwitch.cellWidth
                text: modelData.label
                selected: root.activeClass === modelData.value
                hasCursor: root.cursorActive && root.focusSection === "tabs" && root.tabIndex === index
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: {
                  root.cursorActive = true
                  root.focusSection = "tabs"
                  root.selectClass(modelData.value)
                }
                onHovered: function(isHovered) {
                  if (isHovered) {
                    root.cursorActive = true
                    root.focusSection = "tabs"
                  }
                }
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
            visible: root.activeClass === "review" || root.reviewSelected
            width: parent.width
            text: root.strings.warningReview
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.groups.length === 0 && !janitor.loading
            width: parent.width
            text: Model.emptyForClass(root.strings, root.activeClass)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Repeater {
            model: root.groups

            Column {
              required property var modelData
              required property int index
              width: column.width
              spacing: Style.space(6)

              CursorSurface {
                id: groupRow
                width: parent.width
                implicitHeight: groupContent.implicitHeight + Style.spacing.rowPaddingX
                hasCursor: root.cursorActive && root.focusSection === "list" && root.cursorIndex === index
                foreground: root.foreground

                HoverHandler {
                  onHoveredChanged: if (hovered) {
                    root.cursorActive = true
                    root.focusSection = "list"
                    root.cursorIndex = index
                  }
                }

                RowLayout {
                  id: groupContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(8)

                  Text {
                    visible: modelData.items.length > 1
                    text: root.isExpanded(modelData.toolId) ? "󰅀" : "󰅂"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    Layout.alignment: Qt.AlignVCenter
                  }

                  Item {
                    Layout.fillWidth: true
                    implicitHeight: groupLabels.implicitHeight

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        root.cursorActive = true
                        root.focusSection = "list"
                        root.cursorIndex = index
                        if (modelData.items.length > 1) root.toggleExpanded(modelData.toolId)
                        else root.toggleGroup(modelData)
                      }
                    }

                    ColumnLayout {
                      id: groupLabels
                      width: parent.width
                      spacing: Style.space(1)

                      Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: modelData.toolName
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                        elide: Text.ElideRight
                      }

                      Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: Model.formatBytes(modelData.bytes)
                          + (modelData.items.length > 1 ? " · " + modelData.items.length : "")
                          + (modelData.items.length === 1 ? " · " + root.itemSummary(modelData.items[0]) : "")
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }
                  }

                  ToggleSwitch {
                    checked: root.groupChecked(modelData)
                    foreground: root.foreground
                    hasCursor: false
                    Layout.alignment: Qt.AlignVCenter
                    onToggled: {
                      root.cursorActive = true
                      root.focusSection = "list"
                      root.cursorIndex = index
                      root.toggleGroup(modelData)
                    }
                  }
                }
              }

              Column {
                visible: modelData.items.length > 1 && root.isExpanded(modelData.toolId)
                width: parent.width
                spacing: Style.space(6)
                leftPadding: Style.space(18)

                Repeater {
                  model: modelData.items

                  Toggle {
                    required property var modelData
                    width: parent.width - parent.leftPadding
                    label: root.itemSummary(modelData) + "  " + Model.formatBytes(modelData.bytes)
                    description: modelData.path
                    checked: root.isSelected(modelData.id)
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: root.toggleId(modelData.id)
                  }
                }
              }
            }
          }

          Button {
            width: parent.width
            text: root.strings.reclaim + " · " + Model.formatBytes(root.selectedBytes)
            enabled: root.selectedIds.length > 0 && !janitor.busy
            selected: root.cursorActive && root.focusSection === "action"
            hasCursor: root.cursorActive && root.focusSection === "action"
            foreground: root.foreground
            onClicked: root.requestClean()
            onHovered: function(isHovered) {
              if (isHovered) {
                root.cursorActive = true
                root.focusSection = "action"
              }
            }
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
}
