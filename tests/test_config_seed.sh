#!/bin/bash
set -euo pipefail

PLUGIN_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEMP_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEMP_ROOT"' EXIT
SHELL_ROOT="$TEMP_ROOT/shell"
MOCK_BIN="$TEMP_ROOT/bin"
USER_CONFIG="$TEMP_ROOT/config/btop/btop.conf"
PACKAGED_CONFIG="$TEMP_ROOT/packaged.conf"
STATE_CONFIG="$TEMP_ROOT/state/omarchy-btop-activity/btop.conf"

mkdir -p "$SHELL_ROOT/lib" "$SHELL_ROOT/tests" "$MOCK_BIN"
cp "$PLUGIN_ROOT"/{Service,Telemetry}.qml "$SHELL_ROOT/"
cp "$PLUGIN_ROOT"/lib/*.js "$SHELL_ROOT/lib/"
cp "$PLUGIN_ROOT/tests/config-seed.qml" "$SHELL_ROOT/tests/Probe.qml"
printf '%s\n' 'import "tests" as Tests' 'Tests.Probe {}' >"$SHELL_ROOT/shell.qml"

# Never signal a real btop from the test.
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >"%s/pkill.log"\n' "$TEMP_ROOT" >"$MOCK_BIN/pkill"
printf '#!/bin/bash\nprintf "source = default\\ncolor_theme = \\"Default\\"\\n"\n' \
  >"$MOCK_BIN/btop"
chmod 0755 "$MOCK_BIN/pkill" "$MOCK_BIN/btop"

reset_case() {
  rm -rf -- "$TEMP_ROOT/config" "$TEMP_ROOT/state" "$PACKAGED_CONFIG"
  mkdir -p "$(dirname "$USER_CONFIG")"
}

run_service() {
  env PATH="$MOCK_BIN:$PATH" HOME="$TEMP_ROOT" \
    SEED_DELETIONS="${SEED_DELETIONS:-0}" XDG_CONFIG_HOME="$TEMP_ROOT/config" XDG_STATE_HOME="$TEMP_ROOT/state" \
    SEED_OMARCHY_CONFIG="$PACKAGED_CONFIG" \
    QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout 8s quickshell --no-color -p "$SHELL_ROOT/shell.qml" \
    >"$TEMP_ROOT/log" 2>&1 || {
      cat "$TEMP_ROOT/log"
      exit 1
    }
}

has() { grep -Fxq "$1" "$STATE_CONFIG"; }

assert_managed_keys() {
  has 'update_ms = 1234'
  has 'proc_sorting = "memory"'
  has 'proc_tree = true'
  has 'theme_background = false'
}

# The user config seeds the file, stays untouched and cannot disable saving.
reset_case
printf 'source = user\ndisks_filter = "/home"\nsave_config_on_exit = false\n' \
  >"$USER_CONFIG"
printf 'source = packaged\n' >"$PACKAGED_CONFIG"
cp "$USER_CONFIG" "$TEMP_ROOT/user.orig"
run_service
has 'source = user'
has 'disks_filter = "/home"'
has 'save_config_on_exit = true'
assert_managed_keys
cmp "$USER_CONFIG" "$TEMP_ROOT/user.orig"
grep -Fq -- "-f -- ^btop --config ${STATE_CONFIG//./\\.}\$" "$TEMP_ROOT/pkill.log"

# Blank and missing user configs fall through to the packaged one.
reset_case
printf '\n' >"$USER_CONFIG"
printf 'source = packaged\n' >"$PACKAGED_CONFIG"
run_service
has 'source = packaged'
rm -r "$TEMP_ROOT/state" "$USER_CONFIG"
run_service
has 'source = packaged'

# Without either file, btop's defaults still follow the Omarchy theme.
reset_case
run_service
has 'source = default'
has 'color_theme = "current"'

# An existing file is never reseeded and only managed keys change.
reset_case
printf 'source = user\n' >"$USER_CONFIG"
mkdir -p "$(dirname "$STATE_CONFIG")"
printf 'source = state\ndisks_filter = "/data"\nsave_config_on_exit = false\n' \
  >"$STATE_CONFIG"
run_service
has 'source = state'
has 'disks_filter = "/data"'
has 'save_config_on_exit = false'
assert_managed_keys

# A config deleted while the shell runs is seeded again, repeatedly.
reset_case
printf 'source = user\n' >"$USER_CONFIG"
SEED_DELETIONS=2 run_service
has 'source = user'

printf 'ok - private btop config seeding\n'
