#!/bin/bash
set -euo pipefail

TEST_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(CDPATH= cd -- "$TEST_DIR/.." && pwd)"
# /usr/bin/qmltestrunner may still be Qt 5.
QMLTESTRUNNER=${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner}
readonly TEST_DIR PLUGIN_ROOT QMLTESTRUNNER

[[ -x $QMLTESTRUNNER ]] || {
  printf 'Qt 6 qmltestrunner is required: %s\n' "$QMLTESTRUNNER" >&2
  exit 1
}

cd "$PLUGIN_ROOT"

tests/test_runtime_config_preparation.sh
node --test tests/test_telemetry.mjs
"$QMLTESTRUNNER" -input "$TEST_DIR" -import "$PLUGIN_ROOT" \
  -platform offscreen -o -,txt
