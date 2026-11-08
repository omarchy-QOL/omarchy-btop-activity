import QtQuick
import QtTest
import "../components" as Components
import "../lib/IconGlyph.js" as IconGlyph

TestCase {
  name: "SelectedIcon"

  Components.SelectedIcon {
    id: icon
    iconStyle: "Meters"
    foreground: "white"
    fontFamily: "sans-serif"
  }

  function test_loading_does_not_dim_meters() {
    var meters = icon.children[0]
    icon.cpuUsage = -1
    icon.memoryUsage = -1
    compare(meters.opacity, 1)
    icon.cpuUsage = 42
    icon.memoryUsage = 50
    compare(meters.cpuUsage, 42)
    compare(meters.opacity, 1)
  }

  function test_glyph_styles() {
    compare(IconGlyph.forStyle("CPU"), "\u{f035b}")
    compare(IconGlyph.forStyle("Pulse"), "\uf21e")
    compare(IconGlyph.forStyle("Meters"), "")
    compare(IconGlyph.forStyle("Custom"), "")
    compare(IconGlyph.invalid, "\u{f1238}")
  }
}
