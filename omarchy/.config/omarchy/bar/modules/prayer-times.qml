import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Prayer times: the bar shows the prayer whose window is open (and when it
// ends), or the next one when between windows. Left click opens a timeline
// of the whole prayer day, Fajr to Fajr. Times come from
// ~/.config/omarchy/bar/scripts/prayer-times, which owns the calculation.
BarWidget {
  id: root
  moduleName: "prayer-times"

  readonly property string script: Quickshell.env("HOME") + "/.config/omarchy/bar/scripts/prayer-times"

  property var info: null
  property real nowMs: Date.now()
  property bool popupOpen: false

  function close() { popupOpen = false }
  function refresh() { if (!proc.running) proc.running = true }

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function fraction(ms) {
    if (!info) return 0
    return Math.max(0, Math.min(1, (ms - info.dayStart) / (info.dayEnd - info.dayStart)))
  }
  function remaining(ms) {
    var mins = Math.max(0, Math.floor((ms - nowMs) / 60000) + 1)
    return mins >= 60 ? Math.floor(mins / 60) + "h " + String(mins % 60).padStart(2, "0") + "m" : mins + "m"
  }

  readonly property color fg: Commons.Color.popups.text
  readonly property color accent: Commons.Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  visible: info !== null
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: proc
    command: [root.script, "--json"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.info = JSON.parse(text)
          root.nowMs = root.info.now
        } catch (e) {
          console.warn("prayer-times: bad output", e)
        }
      }
    }
  }

  // omarchy-shell prayer-times toggle (handy for a keybind)
  IpcHandler {
    target: "prayer-times"

    function toggle(): void { if (!root.popupOpen) root.refresh(); root.popupOpen = !root.popupOpen }
    function open(): void { root.refresh(); root.popupOpen = true }
    function close(): void { root.popupOpen = false }
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.info ? (root.vertical ? root.info.text.split(" ")[0].slice(0, 3) : root.info.text) : ""
    horizontalMargin: 8.75

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else {
        if (!root.popupOpen) root.refresh()
        root.popupOpen = !root.popupOpen
      }
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(560))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(14)

      readonly property real labelWidth: Style.space(64)
      readonly property real rangeWidth: Style.space(136)
      readonly property real trackWidth: width - labelWidth - rangeWidth - Style.space(16)
      readonly property real rowHeight: Style.space(26)

      // ---- Header
      Item {
        width: parent.width
        height: titleText.implicitHeight

        Text {
          id: titleText
          text: "PRAYER TIMES"
          color: root.alpha(root.fg, 0.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1.2
        }
        Text {
          anchors.right: parent.right
          text: root.info ? root.info.date : ""
          color: root.alpha(root.fg, 0.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      // ---- Hero: the open window, or what comes next
      Column {
        width: parent.width
        spacing: Style.space(2)

        Text {
          text: !root.info ? "" : root.info.current ? root.info.current.name : root.info.next.name
          color: root.info && root.info.current ? root.accent : root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.display
          font.bold: true
        }
        Text {
          text: !root.info ? ""
            : root.info.current
              ? "ends at " + root.info.current.endLabel + " · " + root.remaining(root.info.current.end) + " left"
              : "starts at " + root.info.next.label + " · in " + root.remaining(root.info.next.at)
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }
        Text {
          visible: root.info && root.info.current !== null
          text: root.info ? "then " + root.info.next.name + " at " + root.info.next.label : ""
          color: root.alpha(root.fg, 0.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      // ---- Timeline (Gantt), Fajr → next Fajr
      Item {
        id: chart
        width: parent.width
        height: rows.height + axis.height + Style.space(18)

        readonly property real trackX: column.labelWidth + Style.space(8)
        readonly property real trackW: column.trackWidth
        function xFor(ms) { return trackX + root.fraction(ms) * trackW }

        // Hour gridlines + labels every 3h
        Repeater {
          id: hours
          model: {
            if (!root.info) return []
            var out = []
            var t = new Date(root.info.dayStart)
            t.setMinutes(0, 0, 0)
            t.setHours(Math.ceil((t.getHours() + 1) / 3) * 3)
            for (; t.getTime() < root.info.dayEnd; t = new Date(t.getTime() + 3 * 3600000)) out.push(t.getTime())
            return out
          }

          Item {
            required property var modelData
            x: chart.xFor(modelData)
            y: Style.space(14)
            width: 1
            height: rows.height + axis.height

            Rectangle {
              width: 1
              height: rows.height
              color: root.alpha(root.fg, 0.08)
            }
            Text {
              y: rows.height + Style.space(4)
              anchors.horizontalCenter: parent.horizontalCenter
              text: Qt.formatTime(new Date(modelData), "hap")
              color: root.alpha(root.fg, 0.45)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // Sunrise / midnight markers
        Repeater {
          model: root.info ? root.info.markers : []

          Item {
            required property var modelData
            x: chart.xFor(modelData.at)
            width: 1
            height: rows.y + rows.height

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: modelData.name.toLowerCase() + " " + modelData.label
              color: root.alpha(root.fg, 0.55)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Column {
              y: Style.space(14)
              spacing: Style.space(3)
              Repeater {
                model: Math.floor(rows.height / Style.space(6))
                Rectangle { width: 1; height: Style.space(3); color: root.alpha(root.fg, 0.35) }
              }
            }
          }
        }

        Column {
          id: rows
          y: Style.space(14)
          width: parent.width

          Repeater {
            model: root.info ? root.info.windows : []

            Item {
              id: row
              required property var modelData
              readonly property bool isCurrent: root.info.current !== null && root.info.current.name === modelData.name
              readonly property bool isPast: modelData.end <= root.nowMs
              width: rows.width
              height: column.rowHeight

              Text {
                width: column.labelWidth
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.name
                color: row.isCurrent ? root.accent : root.alpha(root.fg, row.isPast ? 0.45 : 0.9)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: row.isCurrent
              }

              // Isha's later, still-valid stretch until Fajr
              Rectangle {
                visible: row.modelData.name === "Isha" && root.info.ishaGraceEnd !== null
                x: chart.xFor(row.modelData.end)
                width: root.info.ishaGraceEnd ? chart.xFor(root.info.ishaGraceEnd) - x : 0
                height: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: root.alpha(row.isCurrent ? root.accent : root.fg, 0.3)
              }

              Rectangle {
                x: chart.xFor(row.modelData.start)
                width: Math.max(Style.space(3), chart.xFor(row.modelData.end) - x)
                height: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                radius: height / 2
                color: row.isCurrent ? root.accent : root.alpha(root.fg, row.isPast ? 0.18 : 0.45)

                // Elapsed part of the open window
                Rectangle {
                  visible: row.isCurrent
                  width: parent.width * Math.max(0, Math.min(1, (root.nowMs - row.modelData.start) / (row.modelData.end - row.modelData.start)))
                  height: parent.height
                  radius: parent.radius
                  color: root.alpha(Commons.Color.background, 0.35)
                }
              }

              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.startLabel + " – " + row.modelData.endLabel
                color: row.isCurrent ? root.accent : root.alpha(root.fg, row.isPast ? 0.45 : 0.8)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }

        // Now
        Item {
          visible: root.info !== null && root.nowMs >= root.info.dayStart && root.nowMs < root.info.dayEnd
          x: chart.xFor(root.nowMs)
          y: rows.y - Style.space(4)
          width: 1
          height: rows.height + Style.space(8)

          Rectangle {
            width: Math.max(2, Style.space(2))
            height: parent.height
            anchors.horizontalCenter: parent.horizontalCenter
            color: Commons.Color.urgent
          }
          Rectangle {
            width: Style.space(7)
            height: width
            radius: width / 2
            anchors.horizontalCenter: parent.horizontalCenter
            color: Commons.Color.urgent
          }
        }

        Item { id: axis; height: Style.font.caption + Style.space(6); width: 1 }
      }

      // ---- Footnote
      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: !root.info ? "" : root.info.method
          + (root.info.ishaGraceEnd ? " · Isha ends at midnight; still valid until Fajr " + root.info.ishaGraceLabel + " (outlined)" : "")
        color: root.alpha(root.fg, 0.45)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
