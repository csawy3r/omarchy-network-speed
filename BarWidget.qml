import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "network-speed"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function injectPanel() {
    var panel = panelLoader.item
    if (!panel) return
    panel.bar = root.bar
    panel.settings = root.settings
    panel.anchorItem = surface
    panel.hostWidget = root
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  implicitWidth: row.implicitWidth + Style.spacing.controlGap * 2
  implicitHeight: bar ? bar.barSize : Style.bar.sizeHorizontal

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    visible: false
    source: Qt.resolvedUrl("Panel.qml")
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // Widest plausible reading per direction, used only to pin a constant
  // column width so the bar doesn't reflow every poll as digit count
  // changes (e.g. "12 B/s" vs "999.9 MB/s" vs "- B/s").
  TextMetrics {
    id: downloadMetrics
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
    text: (panelLoader.item ? panelLoader.item.downloadIcon : "↓") + " 999.99 GB/s"
  }

  TextMetrics {
    id: uploadMetrics
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
    text: (panelLoader.item ? panelLoader.item.uploadIcon : "↑") + " 999.99 GB/s"
  }

  Item {
    id: surface
    anchors.fill: parent

    Row {
      id: row
      anchors.centerIn: parent
      spacing: Style.spacing.controlGap

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: (panelLoader.item && panelLoader.item.speedWidth > 0) ? panelLoader.item.speedWidth : downloadMetrics.width
        horizontalAlignment: Text.AlignLeft
        elide: Text.ElideRight
        text: (panelLoader.item ? panelLoader.item.downloadIcon : "↓") + " " + (panelLoader.item ? panelLoader.item.downloadText : "…")
        color: {
          var c = panelLoader.item ? panelLoader.item.downloadTierColor : ""
          return c && c !== "" ? c : (root.bar ? root.bar.foreground : Color.foreground)
        }
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: (panelLoader.item && panelLoader.item.speedWidth > 0) ? panelLoader.item.speedWidth : uploadMetrics.width
        horizontalAlignment: Text.AlignLeft
        elide: Text.ElideRight
        text: (panelLoader.item ? panelLoader.item.uploadIcon : "↑") + " " + (panelLoader.item ? panelLoader.item.uploadText : "…")
        color: {
          var c = panelLoader.item ? panelLoader.item.uploadTierColor : ""
          return c && c !== "" ? c : (root.bar ? root.bar.foreground : Color.foreground)
        }
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: if (panelLoader.item) panelLoader.item.toggle()
    }
  }
}
