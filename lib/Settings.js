.pragma library

// Minimal reader for the shipped settings.toml: top-level `key = value` pairs
// whose value is a quoted string or an array of integers. Anything missing or
// unparsable keeps the default below.

var defaults = { leftClick: "open" }

function stripComment(line) {
  var quoted = false
  for (var i = 0; i < line.length; i++) {
    if (line[i] === "\"") quoted = !quoted
    else if (line[i] === "#" && !quoted) return line.substring(0, i)
  }
  return line
}

function intList(value) {
  var body = /^\[(.*)\]$/.exec(value)
  if (!body) return null
  var items = body[1].split(",").map(function (item) { return item.trim() })
  if (items.length && items[items.length - 1] === "") items.pop()
  var numbers = []
  for (var i = 0; i < items.length; i++) {
    if (!/^[0-9]+$/.test(items[i])) return null
    numbers.push(Number(items[i]))
  }
  return numbers.length ? numbers : null
}

function parse(text) {
  var settings = { pollIntervals: null, leftClick: defaults.leftClick }
  var lines = String(text === null || text === undefined ? "" : text).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var pair = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$/.exec(
      stripComment(lines[i]))
    if (!pair) continue
    if (pair[1] === "poll_intervals") settings.pollIntervals = intList(pair[2])
    else if (pair[1] === "left_click") {
      var word = /^"([a-z]*)"$/.exec(pair[2])
      if (word && (word[1] === "open" || word[1] === "toggle"))
        settings.leftClick = word[1]
    }
  }
  return settings
}
