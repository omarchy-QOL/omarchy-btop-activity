import QtQuick
import Quickshell
import ".." as Btop

QtObject {
  id: root
  property var intervals: [100, 250, 500, 1000]
  property int step: 0

  // Count timer requests without starting hardware readers.
  property Btop.Telemetry telemetry: Btop.Telemetry {
    property int baseCalls: 0
    property int sensorCalls: 0
    updateMs: root.intervals[root.step]
    active: true
    function sampleBase() { baseCalls++ }
    function sampleSensors() { sensorCalls++ }
  }

  property Timer check: Timer {
    interval: 1100
    repeat: true
    running: true
    onTriggered: {
      var base = root.telemetry.baseCalls
      var sensors = root.telemetry.sensorCalls
      var expected = interval / root.telemetry.updateMs
      if (base !== sensors || base < Math.max(1, Math.floor(expected) - 1)
          || base > Math.ceil(expected) + 2) {
        console.error("unaligned sampling at " + root.telemetry.updateMs
          + " ms: base=" + base + ", GPU=" + sensors)
        Qt.exit(1)
        return
      }
      if (root.step === root.intervals.length - 1) {
        console.log("ok - CPU RAM and GPU share the selected polling interval")
        Qt.quit()
        return
      }
      root.telemetry.baseCalls = 0
      root.telemetry.sensorCalls = 0
      root.step++
    }
  }
}
