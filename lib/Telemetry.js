.pragma library

var fields = ["usage", "temperature", "memoryUsed", "memoryTotal"]
var MiB = 1048576
var sources = {
  nvidia: "nvidia-smi", fastfetch: "fastfetch", amd: "amd-smi",
  rocm: "rocm-smi", intel: "intel_gpu_top", xpu: "xpu-smi", fdinfo: "fdinfo"
}

function number(value, minimum, maximum) {
  if (value && typeof value === "object") value = value.value
  if (typeof value !== "number" && typeof value !== "string") return null
  if (String(value).trim() === "") return null
  var result = Number(value)
  return isFinite(result) && result >= minimum && result <= maximum
    ? result : null
}

function pci(value) {
  var match = /^([0-9a-f]{4,8}):([0-9a-f]{2}):([0-9a-f]{2})\.([0-7])$/i
    .exec(String(value || "").trim())
  if (!match) return ""
  var domain = parseInt(match[1], 16).toString(16)
  while (domain.length < 4) domain = "0" + domain
  return domain + ":" + match[2].toLowerCase() + ":"
    + match[3].toLowerCase() + "." + match[4]
}

function discovery(raw) {
  var result = { raw: raw, gpus: [], tools: {} }
  String(raw).split("\n").forEach(function(line) {
    var f = line.split("\t")
    if (f[0] === "tool" && f[2]) result.tools[f[1]] = f[2]
    if (f[0] !== "gpu" || f.length !== 10) return
    result.gpus.push({
      id: pci(f[1]) || f[1], vendor: f[2], driver: f[3],
      card: f[4], path: f[5]
    })
  })
  // btop initializes NVIDIA, AMD, then Intel backends.
  var order = { "0x10de": 0, "0x1002": 1, "0x8086": 2 }
  result.gpus.sort(function(a, b) {
    var left = order[a.vendor] === undefined ? 3 : order[a.vendor]
    var right = order[b.vendor] === undefined ? 3 : order[b.vendor]
    return left - right || a.id.localeCompare(b.id)
  })
  return result
}

function stats(raw, previous) {
  var result = { cpu: -1, used: -1, total: -1, previous: null }
  String(raw).split("\n").forEach(function(line) {
    var f = line.split("\t")
    var a = number(f[1], 0, Infinity), b = number(f[2], 0, Infinity)
    if (a === null || b === null || b <= 0 || a > b) return
    if (f[0] === "cpu") {
      result.previous = { busy: a, total: b }
      if (previous && a >= previous.busy && b > previous.total)
        result.cpu = Math.min(100,
          100 * (a - previous.busy) / (b - previous.total))
    }
    if (f[0] === "memory") {
      result.used = a
      result.total = b
    }
  })
  return result
}

function emptyGpu(device, metadata) {
  var info = metadata[device.id] || {}
  return {
    id: device.id, vendor: device.vendor, driver: device.driver,
    card: device.card, path: device.path, name: info.name || "",
    memoryKind: info.memoryKind || "unknown", status: "unavailable",
    usage: null, temperature: null, temperatureKind: "",
    memoryUsed: null, memoryTotal: null,
    scope: "", sources: {}, updated: {}, failed: {}
  }
}

function merge(gpus, id, values, source, scope) {
  var gpu = gpus.find(function(g) { return g.id === id })
  if (!gpu || gpu.status !== "active") return 0
  var changed = 0
  fields.forEach(function(field) {
    var value = number(values[field], field === "temperature" ? -273.15 : 0,
      field === "usage" ? 100 : field === "temperature" ? 200 : Infinity)
    if (value === null || (field === "memoryTotal" && value === 0)) return
    if (gpu[field] !== null && gpu.sources[field] !== source &&
        !(field === "usage" && gpu.scope === "clients" && scope === "device"))
      return
    gpu[field] = value
    gpu.sources[field] = source
    gpu.updated[field] = Date.now()
    if (field === "usage") gpu.scope = scope || "device"
    if (field === "temperature") gpu.temperatureKind = values.temperatureKind || ""
    changed++
  })
  return changed
}

function publish(current, previous, now, lifetime) {
  return current.map(function(gpu) {
    var result = Object.assign({}, gpu)
    result.sources = Object.assign({}, gpu.sources)
    result.updated = Object.assign({}, gpu.updated)
    var old = previous.find(function(g) { return g.id === gpu.id && g.driver === gpu.driver })
    fields.forEach(function(field) {
      if (gpu.memoryKind === "none" && field.indexOf("memory") === 0) {
        result[field] = null
        return
      }
      if (gpu.status !== "active" || now - (gpu.updated[field] || 0) > lifetime)
        result[field] = null
      if (result[field] !== null || !old || gpu.status !== "active") return
      var source = old.sources[field]
      if (!source || source === "kernel" || gpu.failed[field] === source ||
          now - (old.updated[field] || 0) > lifetime) return
      result[field] = old[field]
      result.sources[field] = source
      result.updated[field] = old.updated[field]
      if (field === "usage") result.scope = old.scope
      if (field === "temperature") result.temperatureKind = old.temperatureKind
    })
    if (result.usage === null) result.scope = ""
    return result
  })
}

function sensors(raw, inventory, metadata) {
  var result = {
    temperature: null, temperatureKind: "",
    gpus: inventory.gpus.map(function(g) { return emptyGpu(g, metadata) })
  }
  String(raw).split("\n").forEach(function(line) {
    var f = line.split("\t")
    if (f[0] === "temperature") {
      var value = number(f[2], -273.15, 200)
      if (value !== null &&
          (result.temperature === null || value > result.temperature)) {
        result.temperature = value
        result.temperatureKind = f[1]
      }
    }
    if (f[0] !== "gpu" || f.length !== 7) return
    var gpu = result.gpus.find(function(g) { return g.id === f[1] })
    if (!gpu) return
    gpu.status = f[2]
    merge(result.gpus, gpu.id, {
      usage: f[3], temperature: f[4], memoryUsed: f[5], memoryTotal: f[6]
    }, "kernel")
  })
  return result
}

function missing(gpu, usageOnly) {
  if (gpu.status !== "active") return false
  if (gpu.usage === null || gpu.scope === "clients") return true
  return !usageOnly && (gpu.temperature === null ||
    (gpu.memoryKind !== "none" &&
      (gpu.memoryUsed === null || gpu.memoryTotal === null)))
}

function safeToQuery(gpus, vendor) {
  return !gpus.some(function(g) {
    return (!vendor || g.vendor === vendor) && g.status !== "active"
  })
}

function nextJob(gpus, tools, state, directory, now) {
  function eligible(kind, predicate) {
    return gpus.filter(function(g) {
      return predicate(g) && !state.attempted[kind + ":" + g.id] &&
        !(state.retryAfter[kind + ":" + g.id] > now)
    })
  }
  function job(kind, devices, args, command) {
    if (!devices.length || !command) return null
    devices.forEach(function(g) { state.attempted[kind + ":" + g.id] = true })
    return { kind: kind, ids: devices.map(function(g) { return g.id }),
      command: [command].concat(args) }
  }
  var devices = eligible("nvidia", function(g) {
    return g.vendor === "0x10de" && g.driver !== "nouveau" && missing(g)
  })
  if (devices.length && tools["nvidia-smi"] && safeToQuery(gpus, "0x10de"))
    return job("nvidia", devices, [
      "--query-gpu=pci.bus_id,utilization.gpu,temperature.gpu,memory.used,memory.total",
      "--format=csv,noheader,nounits",
      "--id=" + devices.map(function(g) { return g.id }).join(",")
    ], tools["nvidia-smi"])

  devices = eligible("intel", function(g) {
    return g.driver === "i915" && missing(g, true)
  })
  if (devices.length && tools.intel_gpu_top && safeToQuery(gpus, "0x8086"))
    return job("intel", [devices[0]], [
      "-J", "-n", "2", "-s", "100", "-o", "-", "-d", "sys:" + devices[0].path
    ], tools.intel_gpu_top)

  devices = eligible("fastfetch", function(g) {
    return g.status === "active" && (!state.metadata[g.id] || missing(g))
  })
  if (devices.length && tools.fastfetch && safeToQuery(gpus))
    return job("fastfetch", devices,
      ["--config", "-", "--format", "json"], tools.fastfetch)

  devices = eligible("amd", function(g) {
    return g.vendor === "0x1002" && g.driver === "amdgpu" && missing(g)
  })
  if (devices.length && tools["amd-smi"] && safeToQuery(gpus, "0x1002")) {
    if (state.amdIds === null && !state.attempted.amdList) {
      state.attempted.amdList = true
      return job("amd-list", devices, ["list", "--json"], tools["amd-smi"])
    }
    var mapped = devices.filter(function(g) {
      return Object.keys(state.amdIds || {}).some(function(key) {
        return state.amdIds[key] === g.id
      })
    })
    if (mapped.length)
      return job("amd", mapped,
        ["metric", "--json", "-u", "-t", "-m", "-g"]
          .concat(mapped.map(function(g) { return g.id })),
        tools["amd-smi"])
  }

  devices = eligible("rocm", function(g) {
    return g.vendor === "0x1002" && g.driver === "amdgpu" && missing(g)
  })
  if (devices.length && tools["rocm-smi"] && safeToQuery(gpus, "0x1002"))
    return job("rocm", devices, [
      "--showbus", "--showuse", "--showtemp", "--showmeminfo", "vram", "--json"
    ], tools["rocm-smi"])

  devices = eligible("xpu", function(g) {
    return g.vendor === "0x8086" && missing(g)
  })
  if (devices.length && tools["xpu-smi"] && safeToQuery(gpus, "0x8086")) {
    var target = devices[0]
    if (!state.xpuInfo[target.id] && !state.attempted["xpu-info:" + target.id])
      return job("xpu-info", [target],
        ["discovery", "-d", target.id, "-j"], tools["xpu-smi"])
    return job("xpu", [target], ["stats", "-d", target.id, "-j"], tools["xpu-smi"])
  }

  devices = eligible("fdinfo", function(g) {
    return !!pci(g.id) && missing(g, true)
  })
  return job("fdinfo", devices,
    [directory + "/helpers/gpu-fdinfo.sh"]
      .concat(devices.map(function(g) { return g.id })), "bash")
}

function gpuArray(data) {
  if (Array.isArray(data)) return data
  if (data && Array.isArray(data.gpu_data)) return data.gpu_data
  return data && typeof data === "object" ? [data] : []
}

function fastfetch(data, gpus, metadata) {
  var module = Array.isArray(data) &&
    data.find(function(item) { return item.type === "GPU" })
  if (!module || !Array.isArray(module.result)) return
  module.result.forEach(function(row) {
    var card = /^DRM \((card[0-9]+)\)$/.exec(row.platformApi || "")
    var id = ""
    var packed = number(row.deviceId, 0, Math.pow(2, 48) - 1)
    if (packed !== null) {
      function hex(value, width) {
        var text = value.toString(16)
        while (text.length < width) text = "0" + text
        return text
      }
      id = hex(Math.floor(packed / 65536), 4) + ":"
        + hex(Math.floor(packed / 256) % 256, 2) + ":"
        + hex(Math.floor(packed / 8) % 32, 2) + "." + (packed % 8)
    }
    var gpu = gpus.find(function(g) { return g.id === id })
    if (gpu && card && gpu.card && gpu.card !== card[1]) return
    if (!gpu && card) gpu = gpus.find(function(g) {
      return g.card === card[1] && (packed === null || !pci(g.id))
    })
    if (!gpu || gpu.status !== "active") return
    var memory = row.memory && row.memory.dedicated || {}
    var total = number(memory.total, 0, Infinity)
    var kind = row.type === "Integrated"
      ? (total === 0 && !(gpu.memoryTotal > 0) ? "none" : "shared")
      : row.type === "Discrete" ? "dedicated" : "unknown"
    metadata[gpu.id] = { name: row.name || "", memoryKind: kind }
    gpu.name = row.name || ""
    gpu.memoryKind = kind
    if (kind === "none") gpu.memoryUsed = gpu.memoryTotal = null
    merge(gpus, gpu.id, {
      usage: row.coreUsage, temperature: row.temperature,
      memoryUsed: kind === "none" ? null : memory.used,
      memoryTotal: total
    }, "fastfetch")
  })
}

function fdinfo(raw, previous, gpus) {
  var current = { time: 0, counters: {} }, engines = {}
  String(raw).split("\n").forEach(function(line) {
    var f = line.split("\t")
    if (f[0] === "time") current.time = number(f[1], 0, Infinity) || 0
    if (f[0] !== "counter" || f.length !== 9) return
    var key = f.slice(1, 4).join("|")
    var row = f.slice(4).map(function(v) { return number(v, 0, Infinity) })
    var duplicate = current.counters[key]
    if (duplicate) row = row.map(function(v, i) {
      return v === null ? duplicate[i]
        : duplicate[i] === null ? v : Math.max(v, duplicate[i])
    })
    current.counters[key] = row
  })
  var elapsed = previous && current.time - previous.time
  if (!(elapsed > 0)) return current
  Object.keys(current.counters).forEach(function(key) {
    var next = current.counters[key], before = previous.counters[key]
    if (!before || !(next[3] > 0)) return
    var busy = null, capacity = next[3]
    if (next[0] !== null && before[0] !== null) {
      next[0] = Math.max(next[0], before[0])
      busy = (next[0] - before[0]) / (elapsed * 1e9 * capacity)
    } else if (next[1] !== null && before[1] !== null) {
      var denominator = next[2] !== null && before[2] !== null
        ? next[2] - before[2] : elapsed * next[4]
      if (!(denominator > 0) || next[1] < before[1]) return
      busy = (next[1] - before[1]) / (denominator * capacity)
    }
    if (busy === null) return
    var parts = key.split("|"), engine = parts[0] + "|" + parts[2]
    engines[engine] = (engines[engine] || 0) + busy * 100
  })
  var usage = {}
  Object.keys(engines).forEach(function(key) {
    var id = key.split("|")[0]
    usage[id] = Math.max(usage[id] || 0, Math.min(100, engines[key]))
  })
  Object.keys(usage).forEach(function(id) {
    merge(gpus, id, { usage: usage[id] }, "fdinfo", "clients")
  })
  return current
}

function applyBackend(job, raw, gpus, state) {
  if (job.kind === "fdinfo") {
    state.fdPrevious = fdinfo(raw, state.fdPrevious, gpus)
    return
  }
  if (job.kind === "nvidia") {
    String(raw).split("\n").forEach(function(line) {
      var f = line.split(",").map(function(v) { return v.trim() })
      if (f.length !== 5 || job.ids.indexOf(pci(f[0])) < 0) return
      merge(gpus, pci(f[0]), {
        usage: f[1], temperature: f[2],
        memoryUsed: scaled(f[3], MiB), memoryTotal: scaled(f[4], MiB)
      }, "nvidia-smi")
      var gpu = gpus.find(function(g) { return g.id === pci(f[0]) })
      if (gpu) gpu.memoryKind = "dedicated"
    })
    return
  }
  var data = JSON.parse(raw)
  if (!data || data.error) return
  if (job.kind === "fastfetch") fastfetch(data, gpus, state.metadata)
  if (job.kind === "amd-list") {
    state.amdIds = {}
    var rows = gpuArray(data)
    rows.forEach(function(row) {
      var id = pci(row.bdf)
      // Partition indices must not be mistaken for whole physical devices.
      if (id && rows.filter(function(r) { return pci(r.bdf) === id }).length === 1)
        state.amdIds[String(row.gpu)] = id
    })
  }
  if (job.kind === "amd") gpuArray(data).forEach(function(row) {
    var id = state.amdIds[String(row.gpu)]
    if (job.ids.indexOf(id) < 0) return
    var usage = row.usage || {}, temp = row.temperature || {}
    var memory = row.mem_usage || {}
    var edge = number(temp.edge, -273.15, 200)
    merge(gpus, id, {
      usage: usage.gfx_activity,
      temperature: edge === null ? temp.hotspot : edge,
      temperatureKind: edge === null ? "hotspot" : "",
      // AMD SMI labels MiB values as MB in its JSON output.
      memoryUsed: scaled(memory.used_vram, MiB),
      memoryTotal: scaled(memory.total_vram, MiB)
    }, "amd-smi")
  })
  if (job.kind === "rocm") Object.keys(data).forEach(function(key) {
    var row = data[key], id = pci(row["PCI Bus"])
    if (job.ids.indexOf(id) < 0) return
    var edge = number(row["Temperature (Sensor edge) (C)"], -273.15, 200)
    merge(gpus, id, {
      usage: row["GPU use (%)"],
      temperature: edge === null ? row["Temperature (Sensor junction) (C)"] : edge,
      temperatureKind: edge === null ? "hotspot" : "",
      memoryUsed: row["VRAM Total Used Memory (B)"],
      memoryTotal: row["VRAM Total Memory (B)"]
    }, "rocm-smi")
  })
  if (job.kind === "intel" && Array.isArray(data) && data.length >= 2) {
    var engines = data[data.length - 1].engines || {}
    var busy = Object.keys(engines).map(function(key) {
      return number(engines[key].busy, 0, 100)
    }).filter(function(v) { return v !== null })
    if (busy.length)
      merge(gpus, job.ids[0], { usage: Math.max.apply(null, busy) }, "intel_gpu_top")
  }
  if (job.kind === "xpu-info" && pci(data.pci_bdf_address) === job.ids[0])
    state.xpuInfo[job.ids[0]] = data
  if (job.kind === "xpu") {
    var info = state.xpuInfo[job.ids[0]]
    if (!info || String(info.device_id) !== String(data.device_id)) return
    var values = { memoryTotal: info.memory_physical_size_byte }
    var mapping = {
      XPUM_STATS_GPU_UTILIZATION: "usage",
      XPUM_STATS_GPU_CORE_TEMPERATURE: "temperature",
      XPUM_STATS_MEMORY_USED: "memoryUsed"
    }
    Object.keys(mapping).forEach(function(type) {
      function metricValue(metrics) {
        var metric = (metrics || []).find(function(m) { return m.metrics_type === type })
        return metric ? number(metric.value, 0, Infinity) : null
      }
      var value = metricValue(data.device_level)
      var field = mapping[type]
      if (value === null && data.tile_level && data.tile_level.length) {
        var tiles = data.tile_level.map(function(tile) { return metricValue(tile.data_list) })
        if (tiles.every(function(v) { return v !== null })) {
          value = field === "temperature" ? Math.max.apply(null, tiles)
            : tiles.reduce(function(sum, v) { return sum + v }, 0)
          if (field === "usage") value /= tiles.length
        }
      }
      values[field] = field === "memoryUsed" ? scaled(value, MiB) : value
    })
    merge(gpus, job.ids[0], values, "xpu-smi")
  }
}

function scaled(value, factor) {
  var result = number(value, 0, Infinity)
  return result === null ? null : result * factor
}
