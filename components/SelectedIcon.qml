pragma ComponentBehavior: Bound

import QtQuick
import "../lib/IconGlyph.js" as IconGlyph

Item {
  id: root

  required property string iconStyle
  required property color foreground
  required property string fontFamily
  property string customIconUrl: ""
  property bool customIconInvalid: false
  property real cpuUsage: 0
  property real memoryUsage: 0
  property real iconSize: 12
  property real glyphSize: iconSize

  implicitWidth: iconSize
  implicitHeight: iconSize

  ActivityIcon {
    anchors.centerIn: parent
    visible: root.iconStyle === "Meters"
    iconSize: root.iconSize
    cpuUsage: root.cpuUsage
    memoryUsage: root.memoryUsage
    color: root.foreground
  }

  Image {
    anchors.centerIn: parent
    visible: root.iconStyle === "Custom" && root.customIconUrl !== ""
    width: root.iconSize
    height: width
    source: root.customIconUrl
    sourceSize.width: 32
    sourceSize.height: 32
    fillMode: Image.PreserveAspectFit
    smooth: true
  }

  Text {
    anchors.centerIn: parent
    text: IconGlyph.forStyle(root.iconStyle)
    visible: text !== ""
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.glyphSize
  }

  Text {
    anchors.centerIn: parent
    visible: root.customIconInvalid
    text: "!"
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.glyphSize
    font.bold: true
  }
}
