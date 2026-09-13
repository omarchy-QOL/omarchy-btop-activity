import QtQuick
import Quickshell
import qs.Commons

PopupWindow {
  id: root

  required property Item anchorItem
  required property var bar
  property string metrics: ""
  property string fontFamily: Style.font.family
  property bool hovered: false
  property bool _ready: false
  property bool _suppressed: false
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null

  function dismiss() { _suppressed = true }

  onHoveredChanged: {
    _ready = false
    _suppressed = false
  }

  visible: !!anchorWindow && hovered && _ready && !_suppressed
  color: "transparent"
  implicitWidth: content.implicitWidth
  implicitHeight: content.implicitHeight

  Timer {
    interval: 400
    running: root.hovered && !root._suppressed
    onTriggered: root._ready = true
  }

  anchor {
    id: popupAnchor
    window: root.anchorWindow
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.width: 1
    rect.height: 1

    onAnchoring: {
      if (!root.anchorWindow || !root.anchorItem || !root.bar) return
      var target = root.anchorItem
      var x = target.width / 2 - root.implicitWidth / 2
      var y = target.height + 6
      if (root.bar.position === "bottom") {
        y = -root.implicitHeight - 6
      } else if (root.bar.position === "left") {
        x = target.width + 6
        y = target.height / 2 - root.implicitHeight / 2
      } else if (root.bar.position === "right") {
        x = -root.implicitWidth - 6
        y = target.height / 2 - root.implicitHeight / 2
      }
      var point = root.anchorWindow.contentItem.mapFromItem(target, x, y)
      popupAnchor.rect.x = Math.round(point.x)
      popupAnchor.rect.y = Math.round(point.y)
    }
  }

  TooltipContent {
    id: content
    anchors.fill: parent
    metrics: root.metrics
    fontFamily: root.fontFamily
    fontSize: Style.font.body
    uiScale: Style.spaceReal(1)
    foreground: Color.tooltip.text
    color: Color.tooltip.background
    border.color: Color.tooltip.border
    radius: Style.cornerRadius
  }
}
