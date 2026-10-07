import QtQuick
import Quickshell
import ".." as Btop

QtObject {
  id: root
  property int step: 0
  property real since: Date.now()

  function check(condition, message) {
    if (!condition) throw new Error(message)
  }

  property Btop.Telemetry probe: Btop.Telemetry {
    updateMs: 1000
    property int baseCalls: 0
    property int sensorCalls: 0
    function sampleBase() { baseCalls++ }
    function sampleSensors() { sensorCalls++ }
  }
  property Btop.Telemetry idleEngine: Btop.Telemetry {}
  property Btop.Telemetry primingProbe: Btop.Telemetry {
    _rediscover: false
    cpuUsage: 42
  }

  property Timer progress: Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      if (Date.now() - root.since < 200) return
      try {
        var probe = root.probe
        switch (root.step) {
        case 0:
          root.check(probe.baseCalls === 0 && probe.sensorCalls === 0, "polled before demand")
          probe._previousCpu = { busy: 10, total: 20 }
          probe._state.fdPrevious = { old: true }
          probe.cpuUsage = 42
          probe.active = true
          break
        case 1:
          root.check(probe.baseCalls === 2 && probe.sensorCalls === 2,
                     "expected immediate and 100 ms readings before the regular 1000 ms tick")
          root.check(probe._previousCpu === null && probe._state.fdPrevious === null,
                     "resume reused counters from before the pause")
          root.check(probe.cpuUsage === 42, "resume blanked the visible CPU reading")
          probe.active = false
          break
        case 2:
          probe.sample()
          root.check(probe.baseCalls === 2 && probe.sensorCalls === 2, "polled while idle")
          root.check(!probe.sampleTimer.running && !probe.warmupTimer.running
                     && !probe.discoveryTimer.running, "idle timer still running")
          probe.active = true
          probe.active = false
          break
        case 3:
          root.check(probe.baseCalls === 2, "queued resume sampled after demand ended")
          probe.active = true
          break
        case 4:
          root.check(probe.baseCalls === 4 && probe.sensorCalls === 4,
                     "second hover did not get another quick pair of readings")
          probe.active = false
          root.idleEngine._inventory = { raw: "fake", gpus: [], tools: {} }
          root.idleEngine.sampleBase()
          root.idleEngine.sampleSensors()
          root.idleEngine.discover()
          root.idleEngine._snapshot = { gpus: [] }
          root.idleEngine.sampleBackend()
          root.idleEngine._job = { kind: "late result" }
          root.idleEngine.finishBackend(0, "", "")
          root.check(!root.idleEngine.statsProcess.running
                     && !root.idleEngine.sensorProcess.running
                     && !root.idleEngine.discoveryProcess.running
                     && !root.idleEngine.worker.running, "late work started an idle reader")
          root.check(root.idleEngine._snapshot === null && root.idleEngine._job === null,
                     "late result left a pending backend chain")
          root.primingProbe.statsProcess.command = ["printf", "cpu\\t10\\t20\\nmemory\\t4\\t10\\n"]
          root.primingProbe.active = true
          break
        case 5:
          root.check(root.primingProbe.cpuUsage === 42,
                     "the baseline reading caused a loading flash")
          root.primingProbe.statsProcess.command = ["printf", "cpu\\t15\\t30\\nmemory\\t4\\t10\\n"]
          root.primingProbe.sample()
          break
        case 6:
          root.check(root.primingProbe.cpuUsage === 50, "fresh CPU readings were not published")
          root.primingProbe.active = false
          console.log("ok - sampling sleeps while idle and warms up without a loading flash")
          Qt.quit()
          return
        }
        root.step++
        root.since = Date.now()
      } catch (error) {
        console.error(error.message)
        Qt.exit(1)
      }
    }
  }
}
