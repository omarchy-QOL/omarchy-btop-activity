import QtQuick

Rectangle {
  id: root

  property string metrics: ""
  property string fontFamily: ""
  property int fontSize: 12
  property color foreground: "white"
  property real uiScale: 1
  readonly property real paddingX: Math.round(10 * uiScale)
  readonly property real paddingY: Math.round(7 * uiScale)

  implicitWidth: Math.ceil(paddingX + border.width
    + Math.max(340 * uiScale, readings.implicitWidth)
    + 10 * uiScale + legend.width)
  implicitHeight: Math.ceil(Math.max(
    readings.implicitHeight + 2 * (paddingY + border.width),
    legend.height + border.width))
  border.width: 1

  Text {
    id: readings
    x: root.paddingX + root.border.width
    y: root.paddingY + root.border.width
    text: root.metrics
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    horizontalAlignment: Text.AlignLeft
  }

  Item {
    id: legend
    anchors.top: parent.top
    anchors.right: parent.right
    width: Math.ceil(commands.implicitWidth + 2 * (root.paddingX + root.border.width))
    height: Math.ceil(commands.implicitHeight + 2 * (root.paddingY + root.border.width))

    Text {
      id: commands
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: root.paddingY + root.border.width
      anchors.rightMargin: root.paddingX + root.border.width
      text: "L-click: btop\nR-click: menu"
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      horizontalAlignment: Text.AlignRight
    }

    Rectangle {
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      width: root.border.width
      color: root.border.color
    }

    Rectangle {
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      height: root.border.width
      color: root.border.color
    }
  }
}
