.pragma library

var minimum = 100
var maximum = 86400000
var presets = [250, 500, 1000, 2000, 5000]

// Replace the ladder with the values from settings.toml, dropping any that
// are out of range or repeated. An empty result keeps the defaults above.
function usePresets(values) {
  var accepted = []
  for (var i = 0; i < (values || []).length; i++) {
    var value = parse(values[i])
    if (value !== null && accepted.indexOf(value) < 0) accepted.push(value)
  }
  if (accepted.length)
    presets = accepted.sort(function (a, b) { return a - b })
}

function parse(value) {
  var text = String(value === null || value === undefined ? "" : value).trim()
  if (!/^[0-9]+$/.test(text)) return null

  var number = Number(text)
  if (!isFinite(number) || Math.floor(number) !== number) return null
  if (number < minimum || number > maximum) return null
  return number
}

function nudge(value, direction) {
  var number = parse(value)
  if (number === null) return null
  var delta = direction < 0 ? -1 : direction > 0 ? 1 : 0
  return Math.max(minimum, Math.min(maximum, number + delta))
}

function ladder(value, direction) {
  var number = parse(value)
  if (number === null) return null

  if (direction > 0) {
    for (var up = 0; up < presets.length; up++)
      if (presets[up] > number) return presets[up]
    return presets[0]
  }

  for (var down = presets.length - 1; down >= 0; down--)
    if (presets[down] < number) return presets[down]
  return presets[presets.length - 1]
}
