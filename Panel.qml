import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "network-speed"
  ipcTarget: "network-speed"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var iconChoices: [
    { down: "↓", up: "↑" },
    { down: "▼", up: "▲" },
    { down: "⬇", up: "⬆" },
    { down: "⇓", up: "⇑" },
    { down: "⬊", up: "⬈" },
    { down: "•", up: "•" }
  ]

  property var themeColors: ({})
  readonly property var colorChoices: Model.themePalette(root.themeColors)

  readonly property string selectedInterface: String(setting("selectedInterface", "auto"))
  readonly property string downloadIcon: String(setting("downloadIcon", "↓"))
  readonly property string uploadIcon: String(setting("uploadIcon", "↑"))
  readonly property string byteColor: String(setting("byteColor", ""))
  readonly property string kiloColor: String(setting("kiloColor", ""))
  readonly property string megaColor: String(setting("megaColor", ""))
  readonly property int minThreshold: Math.max(0, Math.round(Number(setting("minThreshold", 0))))
  readonly property int speedWidth: Math.max(0, Math.round(Number(setting("speedWidth", 0))))
  readonly property int pollIntervalMs: Math.max(500, Number(setting("pollIntervalMs", 2000)))

  property real downloadRate: 0
  property real uploadRate: 0
  property var interfaceList: []
  property string resolvedLabel: "…"
  property var throughputPrev: ({})
  property var networkProcesses: []
  property var networkProcessPrev: ({})

  readonly property string downloadText: downloadRate < minThreshold ? "- B/s" : Model.formatRate(downloadRate)
  readonly property string uploadText: uploadRate < minThreshold ? "- B/s" : Model.formatRate(uploadRate)

  function tierColorForRate(rate) {
    var n = Number(rate) || 0
    if (n < 1024) return byteColor
    if (n < 1024 * 1024) return kiloColor
    return megaColor
  }

  readonly property string downloadTierColor: tierColorForRate(downloadRate)
  readonly property string uploadTierColor: tierColorForRate(uploadRate)

  readonly property var interfaceOptions: {
    var opts = [
      { value: "auto", label: "Auto (default route)" },
      { value: "all", label: "All interfaces" }
    ]
    for (var i = 0; i < interfaceList.length; i++)
      opts.push({ value: interfaceList[i], label: interfaceList[i] })
    return opts
  }

  function persistSettings(patch) {
    var next = Object.assign({}, root.settings, patch)
    root.settings = next
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = next
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, next)
  }

  function setSelectedInterface(value) {
    persistSettings({ selectedInterface: String(value || "auto") })
  }

  function setDownloadIcon(icon) { persistSettings({ downloadIcon: icon }) }
  function setUploadIcon(icon) { persistSettings({ uploadIcon: icon }) }
  function setByteColor(hex) { persistSettings({ byteColor: hex }) }
  function setKiloColor(hex) { persistSettings({ kiloColor: hex }) }
  function setMegaColor(hex) { persistSettings({ megaColor: hex }) }

  function setMinThreshold(value) { persistSettings({ minThreshold: Math.max(0, Math.round(Number(value) || 0)) }) }
  function setSpeedWidth(value) { persistSettings({ speedWidth: Math.max(0, Math.round(Number(value) || 0)) }) }

  function refreshNow() { pollProc.running = true }

  function handleSample(raw) {
    var sample = Model.parseSample(raw)
    root.interfaceList = sample.list
    var active = Model.resolveActive(sample, root.selectedInterface)
    root.resolvedLabel = active.label
    var now = Date.now() / 1000
    var state = Model.throughputState(root.throughputPrev, { key: root.selectedInterface, rx: active.rx, tx: active.tx }, now)
    root.throughputPrev = state
    root.downloadRate = state.downloadRate
    root.uploadRate = state.uploadRate
  }

  function refreshProcessesNow() { if (root.opened) processProc.running = true }

  function handleProcessSample(raw) {
    var now = Date.now()
    var state = Model.parseNetworkProcesses(raw, root.networkProcessPrev, now)
    root.networkProcessPrev = state.previous
    root.networkProcesses = state.list
  }

  function refreshThemeColorsNow() { themeColorsProc.running = true }

  function handleThemeColorsSample(raw) {
    root.themeColors = Model.parseThemeColors(raw)
  }

  onSelectedInterfaceChanged: throughputPrev = ({})
  onOpenedChanged: if (opened) { refreshProcessesNow(); refreshThemeColorsNow() }
  Component.onCompleted: refreshThemeColorsNow()

  Timer {
    interval: root.pollIntervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.refreshNow()
      root.refreshProcessesNow()
    }
  }

  Process {
    id: processProc
    command: ["bash", "-lc", "ss -H -tanpi 2>/dev/null"]
    stdout: StdioCollector {
      id: processOut
      waitForEnd: true
      onStreamFinished: root.handleProcessSample(text)
    }
  }

  Process {
    id: themeColorsProc
    command: ["bash", "-lc", "cat ~/.local/state/omarchy/current/theme/colors.toml 2>/dev/null"]
    stdout: StdioCollector {
      id: themeColorsOut
      waitForEnd: true
      onStreamFinished: root.handleThemeColorsSample(text)
    }
  }

  Process {
    id: pollProc
    command: ["bash", "-lc", Model.pollScript()]
    stdout: StdioCollector {
      id: pollOut
      waitForEnd: true
      onStreamFinished: root.handleSample(text)
    }
  }

  PopupCard {
    id: popup
    anchorItem: root.anchorItem
    bar: root.bar
    owner: root.barIdentity
    open: root.opened
    contentWidth: Style.space(320)
    contentHeight: Style.space(620)

    ScrollView {
      id: scrollArea
      anchors.fill: parent
      clip: true
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      ScrollBar.vertical.policy: column.implicitHeight > height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff

      ColumnLayout {
        id: column
        width: scrollArea.width - Style.space(16)
        spacing: Style.spacing.md

        Text {
          Layout.fillWidth: true
          text: "Network Speed"
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          Layout.fillWidth: true
          text: root.resolvedLabel + "  ·  " + root.downloadIcon + " " + root.downloadText + "  " + root.uploadIcon + " " + root.uploadText
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        PanelSeparator { Layout.fillWidth: true; foreground: Color.popups.text }

        PanelSectionHeader { text: "INTERFACE"; foreground: Color.popups.text }

        Dropdown {
          Layout.alignment: Qt.AlignLeft
          showLabel: false
          value: root.selectedInterface
          options: root.interfaceOptions
          foreground: Color.popups.text
          background: Color.popups.background
          popupBorder: Color.popups.border
          onChanged: function(value) { root.setSelectedInterface(value) }
        }

        PanelSeparator { Layout.fillWidth: true; foreground: Color.popups.text }

        PanelSectionHeader { text: "TOP APPS"; foreground: Color.popups.text }

        Text {
          Layout.fillWidth: true
          visible: root.networkProcesses.length === 0
          text: "No active connections detected yet."
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Repeater {
          model: root.networkProcesses.slice(0, 5)
          delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: Style.spacing.sm

            Text {
              Layout.fillWidth: true
              text: modelData.name + " (" + modelData.pid + ")"
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Text {
              text: "↓ " + Model.formatRate(modelData.rxRate) + "  ↑ " + Model.formatRate(modelData.txRate)
              color: Qt.darker(Color.popups.text, 1.2)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        PanelSeparator { Layout.fillWidth: true; foreground: Color.popups.text }

        PanelSectionHeader { text: "DOWNLOAD"; foreground: Color.popups.text }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.sm

          Repeater {
            model: root.iconChoices
            delegate: Rectangle {
              required property var modelData
              width: Style.space(30)
              height: Style.space(30)
              radius: Style.cornerRadius
              color: root.downloadIcon === modelData.down ? Style.selectedFillFor(Color.popups.text, Color.accent) : "transparent"
              border.width: root.downloadIcon === modelData.down ? 1 : 0
              border.color: Color.accent

              Text {
                anchors.centerIn: parent
                text: modelData.down
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.icon
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setDownloadIcon(modelData.down)
              }
            }
          }
        }

        PanelSeparator { Layout.fillWidth: true; foreground: Color.popups.text }

        PanelSectionHeader { text: "UPLOAD"; foreground: Color.popups.text }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.sm

          Repeater {
            model: root.iconChoices
            delegate: Rectangle {
              required property var modelData
              width: Style.space(30)
              height: Style.space(30)
              radius: Style.cornerRadius
              color: root.uploadIcon === modelData.up ? Style.selectedFillFor(Color.popups.text, Color.accent) : "transparent"
              border.width: root.uploadIcon === modelData.up ? 1 : 0
              border.color: Color.accent

              Text {
                anchors.centerIn: parent
                text: modelData.up
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.icon
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setUploadIcon(modelData.up)
              }
            }
          }
        }

        PanelSeparator { Layout.fillWidth: true; foreground: Color.popups.text }

        PanelSectionHeader { text: "LAYOUT"; foreground: Color.popups.text }

        NumberField {
          label: "Speed column width (px, 0 = auto-fit)"
          value: root.speedWidth
          from: 0
          to: 300
          stepSize: 2
          foreground: Color.popups.text
          accent: Color.accent
          onModified: function(value) { root.setSpeedWidth(value) }
        }

        PanelSeparator { Layout.fillWidth: true; foreground: Color.popups.text }

        PanelSectionHeader { text: "SPEED COLOR"; foreground: Color.popups.text }

        Text {
          Layout.fillWidth: true
          text: "Below this speed (in B/s), show \"- B/s\" instead of the number."
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        NumberField {
          label: "Minimum threshold (B/s)"
          value: root.minThreshold
          from: 0
          to: 1048576
          stepSize: 64
          foreground: Color.popups.text
          accent: Color.accent
          onModified: function(value) { root.setMinThreshold(value) }
        }

        Text {
          Layout.fillWidth: true
          text: "Shared for download and upload — colors the arrow, number, and unit by how fast it is."
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          text: "B/s"
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.sm

          Repeater {
            model: root.colorChoices.length
            delegate: Rectangle {
              required property int index
              readonly property string swatch: root.colorChoices[index]
              width: Style.space(22)
              height: Style.space(22)
              radius: width / 2
              color: swatch === "" ? "transparent" : swatch
              border.width: root.byteColor === swatch ? 2 : 1
              border.color: root.byteColor === swatch ? Color.accent : Qt.darker(Color.popups.text, 1.6)

              Text {
                visible: swatch === ""
                anchors.centerIn: parent
                text: "∅"
                color: Color.popups.text
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setByteColor(swatch)
              }
            }
          }
        }

        Text {
          text: "KB/s"
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.sm

          Repeater {
            model: root.colorChoices.length
            delegate: Rectangle {
              required property int index
              readonly property string swatch: root.colorChoices[index]
              width: Style.space(22)
              height: Style.space(22)
              radius: width / 2
              color: swatch === "" ? "transparent" : swatch
              border.width: root.kiloColor === swatch ? 2 : 1
              border.color: root.kiloColor === swatch ? Color.accent : Qt.darker(Color.popups.text, 1.6)

              Text {
                visible: swatch === ""
                anchors.centerIn: parent
                text: "∅"
                color: Color.popups.text
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setKiloColor(swatch)
              }
            }
          }
        }

        Text {
          text: "MB/s"
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.sm

          Repeater {
            model: root.colorChoices.length
            delegate: Rectangle {
              required property int index
              readonly property string swatch: root.colorChoices[index]
              width: Style.space(22)
              height: Style.space(22)
              radius: width / 2
              color: swatch === "" ? "transparent" : swatch
              border.width: root.megaColor === swatch ? 2 : 1
              border.color: root.megaColor === swatch ? Color.accent : Qt.darker(Color.popups.text, 1.6)

              Text {
                visible: swatch === ""
                anchors.centerIn: parent
                text: "∅"
                color: Color.popups.text
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setMegaColor(swatch)
              }
            }
          }
        }
      }
    }
  }
}
