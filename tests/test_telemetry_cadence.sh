#!/bin/bash
set -euo pipefail

PLUGIN_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEMP_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEMP_ROOT"' EXIT
mkdir "$TEMP_ROOT/lib" "$TEMP_ROOT/tests"
cp "$PLUGIN_ROOT/Telemetry.qml" "$TEMP_ROOT/Telemetry.qml"
cp "$PLUGIN_ROOT/lib/Telemetry.js" "$TEMP_ROOT/lib/Telemetry.js"
# Keep parent imports inside Quickshell's config root and valid for lint.
printf '%s\n' 'import "tests" as Tests' 'Tests.Probe {}' >"$TEMP_ROOT/shell.qml"
for fixture in telemetry-cadence telemetry-demand; do
  cp "$PLUGIN_ROOT/tests/$fixture.qml" "$TEMP_ROOT/tests/Probe.qml"
  QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout 8s quickshell --no-color -p "$TEMP_ROOT/shell.qml" >"$TEMP_ROOT/log" 2>&1 || {
      cat "$TEMP_ROOT/log"
      exit 1
    }
  grep -F 'ok - ' "$TEMP_ROOT/log"
done
