#!/bin/bash
set -euo pipefail

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PLUGIN_ROOT=$(cd -- "$TEST_DIR/.." && pwd)
TEMP_ROOT=$(mktemp -d)
readonly TEST_DIR PLUGIN_ROOT TEMP_ROOT
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

PROC_ROOT=$TEMP_ROOT/proc
SENSOR_ROOT=$TEMP_ROOT/sensors
BASH_SAMPLER=$PLUGIN_ROOT/helpers/sample-telemetry.sh
mkdir -p "$PROC_ROOT" "$SENSOR_ROOT"

assert_equal() {
  local expected=$1 actual=$2 label=$3
  if [[ $actual != "$expected" ]]; then
    printf 'not ok - %s\nexpected:\n%s\nactual:\n%s\n' \
      "$label" "$expected" "$actual" >&2
    exit 1
  fi
}

printf '%s\n' \
  'cpu 100 20 30 400 10 5 6 7 8 9' \
  'cpu0 50 10 15 200 5 2 3 4 4 5' >"$PROC_ROOT/stat"
printf '%s\n' \
  'MemTotal:       1000 kB' \
  'MemFree:         200 kB' \
  'MemAvailable:    400 kB' >"$PROC_ROOT/meminfo"

expected_stats=$'cpu\t161\t578\nmemory\t614400\t1024000'
actual=$(bash "$BASH_SAMPLER" stats "$PROC_ROOT")
assert_equal "$expected_stats" "$actual" 'CPU and memory sample'

printf '42500.5\n' >"$SENSOR_ROOT/package_input"
printf '0\n' >"$SENSOR_ROOT/package_fault"
printf '%s\n' '-500' >"$SENSOR_ROOT/negative_input"
printf '99000\n' >"$SENSOR_ROOT/fault_input"
printf '1\n' >"$SENSOR_ROOT/fault_fault"

active=$SENSOR_ROOT/gpu-active
sleeping=$SENSOR_ROOT/gpu-sleeping
unsupported=$SENSOR_ROOT/gpu-unsupported
mkdir -p "$active/power" "$sleeping/power" "$unsupported/power"
printf 'active\n' >"$active/power/runtime_status"
printf 'suspended\n' >"$sleeping/power/runtime_status"
printf 'unsupported\n' >"$unsupported/power/runtime_status"
printf '0035\n' >"$active/usage"
printf '50000\n' >"$active/temperature_input"
printf '1024\n' >"$active/used"
printf '4096\n' >"$active/total"
printf '12\n' >"$unsupported/usage"

inventory=$(printf '%s\n' \
  $'cpu\tpackage\t'"$SENSOR_ROOT/package_input" \
  $'cpu\tnegative\t'"$SENSOR_ROOT/negative_input" \
  $'cpu\tfault\t'"$SENSOR_ROOT/fault_input" \
  $'gpu\t0000:01:00.0\t0x1002\tamdgpu\tcard0\t'"$active"$'\t'"$active/temperature_input"$'\t'"$active/usage"$'\t'"$active/used"$'\t'"$active/total" \
  $'gpu\t0000:02:00.0\t0x8086\ti915\tcard1\t'"$sleeping"$'\t\t\t\t' \
  $'gpu\t0000:03:00.0\t0x8086\ti915\tcard2\t'"$unsupported"$'\t\t'"$unsupported/usage"$'\t\t')

expected_sensors=$(printf '%s\n' \
  $'temperature\tpackage\t42.5005' \
  $'temperature\tnegative\t-0.5' \
  $'temperature\tfault\t-' \
  $'gpu\t0000:01:00.0\tactive\t35\t50\t1024\t4096' \
  $'gpu\t0000:02:00.0\tsleeping\t-\t-\t-\t-' \
  $'gpu\t0000:03:00.0\tactive\t12\t-\t-\t-')
actual=$(bash "$BASH_SAMPLER" sensors "$inventory")
assert_equal "$expected_sensors" "$actual" 'sensor sample'

printf 'MemTotal: 1000 kB\n' >"$PROC_ROOT/meminfo"
actual=$(bash "$BASH_SAMPLER" stats "$PROC_ROOT")
assert_equal $'cpu\t161\t578' "$actual" 'missing available memory'

rm -f "$PROC_ROOT/stat" "$PROC_ROOT/meminfo"
actual=$(bash "$BASH_SAMPLER" stats "$PROC_ROOT")
assert_equal '' "$actual" 'missing proc files'

if bash "$BASH_SAMPLER" invalid 2>/dev/null; then
  printf 'not ok - invalid sampler mode succeeded\n' >&2
  exit 1
fi

printf 'ok - Bash telemetry sampling\n'
