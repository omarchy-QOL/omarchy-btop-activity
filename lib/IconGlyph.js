.pragma library

// Shown for a custom icon that fails to load; heavy so it holds up at bar size.
var invalid = "\u{f1238}"

// Font glyph for an icon style, or "" when the style draws something else.
function forStyle(style) {
  if (style === "CPU") return "\u{f035b}"
  if (style === "Pulse") return "\uf21e"
  return ""
}
