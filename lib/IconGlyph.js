.pragma library

// Font glyph for an icon style, or "" when the style draws something else.
function forStyle(style) {
  if (style === "CPU") return "\u{f035b}"
  if (style === "Pulse") return ""
  return ""
}
