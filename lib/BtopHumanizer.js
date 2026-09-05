.pragma library

// Match aristocratos/btop Tools::floating_humanizer for GPU-box bytes:
// shorten=true, start=0, bit=false, base_10_sizes=false.
var mebiUnits = [
  "Byte", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB", "ZiB", "YiB"
]

function floatingHumanizer(bytes) {
  if (!isFinite(bytes) || bytes < 0) return ""

  var value = Math.floor(Number(bytes)) * 100
  var start = 0
  while (value >= 102400) {
    value = Math.floor(value / 1024)
    start++
  }

  var out = String(value)
  if (out.length === 4 && start > 0) {
    out = out.slice(0, 3)
    out = out.slice(0, 2) + "." + out.slice(2)
  } else if (out.length === 3 && start > 0) {
    out = out.charAt(0) + "." + out.slice(1)
  } else if (out.length >= 2) {
    out = out.slice(0, out.length - 2)
  }
  if (out === "") out = "0"

  var hasSep = out.indexOf(".") !== -1
  if (hasSep) out = Number(out).toFixed(1)
  if (out.length > 3) {
    if (hasSep) out = String(Math.round(Number(out)))
    else {
      out = out.charAt(0) + ".0"
      start++
    }
  }
  if (start >= mebiUnits.length) return ""
  return out + mebiUnits[start].charAt(0)
}

function vramText(used, total) {
  if (!(used >= 0 && total > 0)) return "unavail. (vRAM)"
  var usedText = floatingHumanizer(used)
  var totalText = floatingHumanizer(total)
  if (usedText === "" || totalText === "") return "unavail. (vRAM)"
  return usedText + "/" + totalText + " (vRAM)"
}
