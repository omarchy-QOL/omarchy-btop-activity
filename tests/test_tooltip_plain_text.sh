#!/bin/bash
#
# The bar renders tooltips with `textFormat: Text.PlainText` (Omarchy's
# Ui/Button.qml and plugins/bar/Bar.qml), so any HTML the widget puts in
# `tooltipText` is shown to the user as literal tag text. Guard the tooltip
# construction against markup and HTML entities creeping back in.

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TEST_DIR/.." && pwd)"
readonly TEST_DIR PLUGIN_ROOT

readonly WIDGET="$PLUGIN_ROOT/BarWidget.qml"

fail() {
  echo "not ok - $1" >&2
  exit 1
}

# The tooltip property and the helper it calls, i.e. everything that ends up in
# tooltipText. Stops at the next top-level property to keep unrelated QML out.
tooltip_source() {
  sed -n '/readonly property string tooltip:/,/^  readonly property var sortingChoices/p' "$WIDGET"
  sed -n '/^  function alignedTooltip(/,/^  }/p' "$WIDGET"
  sed -n '/^  readonly property string gpuTemperatureText:/,/^  readonly property string tooltip:/p' "$WIDGET"
}

source_text="$(tooltip_source)"
[[ -n $source_text ]] || fail "could not extract the tooltip construction from BarWidget.qml"

# A real tag has a letter or slash straight after the opening bracket.
if grep -Eq '<(/|[A-Za-z]+[ >])' <<<"$source_text"; then
  fail "tooltip construction emits HTML tags (the bar renders PlainText)"
fi

if grep -q '&amp;\|&lt;\|&gt;' <<<"$source_text"; then
  fail "tooltip construction escapes HTML entities (the bar renders PlainText)"
fi

# The rich-text helper this replaced must not come back.
if grep -q 'styledTooltip' "$WIDGET"; then
  fail "styledTooltip is back in BarWidget.qml"
fi

# tooltipText must be fed the plain aligned text directly.
if ! grep -q 'readonly property string tooltip: alignedTooltip(' "$WIDGET"; then
  fail "tooltip is no longer built straight from alignedTooltip"
fi

if ! grep -q 'tooltipText: root.tooltip' "$WIDGET"; then
  fail "the bar button no longer takes its tooltip from root.tooltip"
fi

echo "ok - tooltip stays plain text"
