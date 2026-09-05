import QtQuick
import Quickshell
import Quickshell.Io
import "lib/Telemetry.js" as Model

QtObject {
  id: root

  property int updateMs: 2000
  property real cpuUsage: -1
  property real memoryUsage: -1
  property real memoryUsed: -1
  property real memoryTotal: -1
  property var cpuTemperature: null
  property string cpuTemperatureKind: ""
  property var gpus: []
  readonly property bool available: cpuUsage >= 0 && memoryUsage >= 0
  readonly property int gpuInterval: Math.max(1000, updateMs)
  readonly property string directory: decodeURIComponent(
    Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, ""))
  readonly property string sampler: directory + "/helpers/sample-telemetry.awk"
  property var backendErrors: ({})

  property var _previousCpu: null
  property var _inventory: ({ raw: "", gpus: [], tools: {} })
  property var _state: ({
    metadata: {}, attempted: {}, retryAfter: {},
    amdIds: null, xpuInfo: {}, fdPrevious: null
  })
  property var _snapshot: null
  property var _job: null
  property var _before: ({})
  property real _lastGpuResult: 0
  property real _lastSample: 0
  property bool _discardSnapshot: false
  property real _discoverAfter: 0
  property bool _rediscover: true

  function discover() {
    if (discoveryProcess.running || sensorProcess.running ||
        _snapshot !== null || Date.now() < _discoverAfter) return
    _rediscover = false
    _discoverAfter = Date.now() + 1000
    discoveryProcess.running = true
  }

  function sampleBase() {
    var now = Date.now()
    if (_lastSample && (now < _lastSample ||
        now - _lastSample > Math.max(5000, updateMs * 3))) {
      _rediscover = true
      _discoverAfter = 0
      _previousCpu = null
      _state.fdPrevious = null
      _state.retryAfter = {}
      _discardSnapshot = _snapshot !== null || sensorProcess.running
    }
    _lastSample = now
    if (!statsProcess.running) statsProcess.running = true
    if (_rediscover) discover()
    gpus = Model.publish(gpus, [], now, Math.max(5000, gpuInterval * 2))
    if (_lastGpuResult &&
        Date.now() - _lastGpuResult > Math.max(5000, gpuInterval * 2)) {
      gpus = _inventory.gpus.map(function(g) {
        return Model.emptyGpu(g, root._state.metadata)
      })
      cpuTemperature = null
      _lastGpuResult = 0
    }
  }

  function sampleSensors() {
    if (discoveryProcess.running || sensorProcess.running ||
        !_inventory.raw) return
    sensorProcess.command = [
      "timeout", "--kill-after=0.5s", "2s",
      "awk", "-v", "mode=sensors", "-v", "inventory=" + _inventory.raw, "-f", sampler
    ]
    sensorProcess.running = true
  }

  function sampleBackend() {
    if (_discardSnapshot) {
      _snapshot = null
      _job = null
      _discardSnapshot = false
      Qt.callLater(discover)
      return
    }
    _job = Model.nextJob(_snapshot.gpus, _inventory.tools,
      _state, directory, Date.now())
    if (_job === null) {
      gpus = Model.publish(_snapshot.gpus, gpus,
        Date.now(), Math.max(5000, gpuInterval * 2))
      _snapshot = null
      if (_rediscover) Qt.callLater(discover)
      return
    }
    _before = {}
    _snapshot.gpus.forEach(function(g) {
      root._before[g.id] = g.name + "|" + g.memoryKind
    })
    _job.started = Date.now()
    var vendor = ""
    if (_job.kind === "nvidia") vendor = "0x10de"
    else if (_job.kind === "amd-list" || _job.kind === "amd" ||
        _job.kind === "rocm") vendor = "0x1002"
    else if (_job.kind === "intel" || _job.kind.indexOf("xpu") === 0)
      vendor = "0x8086"
    var paths = _snapshot.gpus.filter(function(g) {
      return root._job.kind === "fastfetch" ||
        (vendor ? g.vendor === vendor : root._job.ids.indexOf(g.id) >= 0)
    }).map(function(g) { return g.path })
    worker.command = [
      "timeout", "--signal=TERM", "--kill-after=0.5s", "3s"
    ].concat(["bash", directory + "/helpers/query-telemetry.sh"],
      paths, ["--"], _job.command)
    worker.stdinEnabled = _job.kind === "fastfetch"
    worker.running = true
  }

  function finishBackend(exitCode, raw, error) {
    if (exitCode === 75) {
      raw.trim().split("\n").forEach(function(line) {
        var path = line.split("\t")[1]
        var index = root._snapshot.gpus.findIndex(function(g) { return g.path === path })
        if (index < 0) return
        var gpu = Model.emptyGpu(root._snapshot.gpus[index], root._state.metadata)
        gpu.status = line.split("\t")[0]
        root._snapshot.gpus[index] = gpu
      })
      _rediscover = true
      gpus = Model.publish(_snapshot.gpus, gpus,
        Date.now(), Math.max(5000, gpuInterval * 2))
      Qt.callLater(sampleBackend)
      return
    }
    var failed = exitCode !== 0
    if (!failed) {
      try { Model.applyBackend(_job, raw, _snapshot.gpus, _state) }
      catch (exception) {
        failed = true
        error = String(exception)
      }
    }
    var errors = Object.assign({}, backendErrors)
    if (failed) errors[_job.kind] = error.trim() || "exit " + exitCode
    else delete errors[_job.kind]
    backendErrors = errors
    _job.ids.forEach(function(id) {
      var gpu = root._snapshot.gpus.find(function(g) { return g.id === id })
      var kind = root._job.kind
      var source = Model.sources[kind]
      var changed = gpu && (root._before[id] !== gpu.name + "|" + gpu.memoryKind
        || Model.fields.some(function(field) {
          return gpu.sources[field] === source &&
            gpu.updated[field] >= root._job.started
        }))
      var provided = kind === "intel" || kind === "fdinfo" ? ["usage"] : Model.fields
      if (gpu && source) provided.forEach(function(field) {
        if (!failed && gpu.sources[field] === source &&
            gpu.updated[field] >= root._job.started) {
          delete gpu.failed[field]
        } else {
          gpu.failed[field] = source
          if (gpu.sources[field] === source) gpu[field] = null
        }
      })
      if (kind === "fdinfo" && !failed) return // First sample primes counters.
      if (kind === "amd-list") {
        changed = Object.values(root._state.amdIds || {}).indexOf(id) >= 0
        kind = "amd"
      }
      if (kind === "xpu-info") {
        changed = !!root._state.xpuInfo[id]
        kind = "xpu"
      }
      if (failed || !changed)
        root._state.retryAfter[kind + ":" + id] = Date.now() + 30000
    })
    gpus = Model.publish(_snapshot.gpus, gpus,
      Date.now(), Math.max(5000, gpuInterval * 2))
    if (failed) _rediscover = true
    Qt.callLater(sampleBackend)
  }

  property Process statsProcess: Process {
    command: [
      "awk", "-v", "proc_root=" + (Quickshell.env("BTOP_PROC_ROOT") || "/proc"),
      "-f", root.sampler
    ]
    environment: ({ LC_ALL: "C" })
    stdout: StdioCollector { id: statsOutput; waitForEnd: true }
    onExited: function(code) {
      var sample = Model.stats(code === 0 ? statsOutput.text : "", root._previousCpu)
      root._previousCpu = sample.previous
      root.cpuUsage = sample.cpu
      root.memoryUsed = sample.used
      root.memoryTotal = sample.total
      root.memoryUsage = sample.total > 0 ? sample.used / sample.total * 100 : -1
    }
  }

  property Process discoveryProcess: Process {
    command: [
      "timeout", "--kill-after=0.5s", "3s",
      "bash", root.directory + "/helpers/discover-telemetry.sh"
    ]
    environment: ({ LC_ALL: "C" })
    stdout: StdioCollector { id: discoveryOutput; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) {
        root._rediscover = true
        root._discoverAfter = Date.now() + 30000
        return
      }
      var next = Model.discovery(discoveryOutput.text)
      if (next.raw !== root._inventory.raw) {
        root.backendErrors = {}
        root._state.metadata = {}
        root._state.retryAfter = {}
        root._state.fdPrevious = null
        root.gpus = next.gpus.map(function(g) { return Model.emptyGpu(g, {}) })
      }
      root._inventory = next
      root._state.amdIds = null
      root._state.xpuInfo = {}
      Qt.callLater(root.sampleSensors)
    }
  }

  property Process sensorProcess: Process {
    environment: ({ LC_ALL: "C" })
    stdout: StdioCollector { id: sensorOutput; waitForEnd: true }
    onExited: function(code) {
      if (root._discardSnapshot) {
        if (root._snapshot === null) {
          root._discardSnapshot = false
          Qt.callLater(root.discover)
        }
        return
      }
      var previousSnapshot = root._snapshot
      var nextSnapshot = Model.sensors(
        code === 0 ? sensorOutput.text : "", root._inventory, root._state.metadata)
      root._snapshot = nextSnapshot
      if (previousSnapshot) {
        nextSnapshot.gpus.forEach(function(gpu) {
          var old = previousSnapshot.gpus.find(function(g) { return g.id === gpu.id })
          if (old) gpu.failed = old.failed
        })
        nextSnapshot.gpus = Model.publish(nextSnapshot.gpus,
          previousSnapshot.gpus, Date.now(), Math.max(5000, root.gpuInterval * 2))
      } else root._state.attempted = {}
      // Rediscover paths when a previously readable kernel field disappears.
      root.gpus.forEach(function(old) {
        var next = root._snapshot.gpus.find(function(g) { return g.id === old.id })
        if (!next || next.status !== "active") return
        if (old.status === "sleeping") {
          root._state.fdPrevious = null
          root._state.amdIds = null
          root._state.xpuInfo = {}
          root._state.retryAfter = {}
          root._rediscover = true
        }
        Model.fields.forEach(function(field) {
          if (old.sources[field] === "kernel" && next[field] === null)
            root._rediscover = true
        })
      })
      if (code !== 0) root._rediscover = true
      root.gpus = Model.publish(nextSnapshot.gpus, root.gpus,
        Date.now(), Math.max(5000, root.gpuInterval * 2))
      root.cpuTemperature = nextSnapshot.temperature
      root.cpuTemperatureKind = nextSnapshot.temperatureKind
      root._lastGpuResult = Date.now()
      if (!previousSnapshot) root.sampleBackend()
    }
  }

  property Process worker: Process {
    environment: ({ LC_ALL: "C" })
    stdout: StdioCollector { id: workerOutput; waitForEnd: true }
    stderr: StdioCollector { id: workerError; waitForEnd: true }
    onStarted: {
      if (root._job.kind === "fastfetch") {
        write(JSON.stringify({ modules: [
          { type: "gpu", temp: true, driverSpecific: true }
        ] }) + "\n")
        stdinEnabled = false
      }
    }
    onExited: function(code) {
      root.finishBackend(code, workerOutput.text, workerError.text)
    }
  }

  property Timer statsTimer: Timer {
    interval: root.updateMs
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.sampleBase()
  }
  property Timer sensorTimer: Timer {
    interval: root.gpuInterval
    repeat: true
    running: true
    onTriggered: root.sampleSensors()
  }
  property Timer discoveryTimer: Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: {
      root._rediscover = true
      root.discover()
    }
  }
}
