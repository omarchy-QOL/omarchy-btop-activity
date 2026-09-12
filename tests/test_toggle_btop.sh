#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TEST_DIR/.." && pwd)"
TEMP_ROOT="$(mktemp -d)"
readonly TEST_DIR PLUGIN_ROOT TEMP_ROOT
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

readonly MOCK_BIN="$TEMP_ROOT/bin"
readonly LOG="$TEMP_ROOT/calls.log"
readonly CLIENTS="$TEMP_ROOT/clients.json"
readonly RUNTIME_CONFIG="$TEMP_ROOT/runtime/ilyazar-btop.conf"

mkdir -p "$MOCK_BIN" "$TEMP_ROOT/runtime" "$TEMP_ROOT/config/omarchy"

cat >"$MOCK_BIN/hyprctl" <<MOCK
#!/bin/bash
[[ \$1 == clients ]] && exec cat "$CLIENTS"
shift
printf 'close %s\n' "\$*" >>"$LOG"
MOCK

cat >"$MOCK_BIN/omarchy-launch-or-focus-tui" <<MOCK
#!/bin/bash
printf 'launch %s\n' "\$*" >>"$LOG"
MOCK

chmod 0755 "$MOCK_BIN/hyprctl" "$MOCK_BIN/omarchy-launch-or-focus-tui"

run_toggle() {
  : >"$LOG"
  env PATH="$MOCK_BIN:$PATH" HOME="$TEMP_ROOT" \
    XDG_CONFIG_HOME="$TEMP_ROOT/config" XDG_RUNTIME_DIR="$TEMP_ROOT/runtime" \
    bash "$PLUGIN_ROOT/helpers/toggle-btop.sh" "$@"
}

# An open window is closed and nothing new is launched. Windows from either
# window mode count, so switching modes cannot strand one.
for class in org.omarchy.btop org.omarchy.btop_tiled; do
  printf '[{"class": "%s", "address": "0xabc"}]' "$class" >"$CLIENTS"
  run_toggle org.omarchy.btop "$RUNTIME_CONFIG"
  grep -Fq 'close hl.dsp.window.close({ window = "address:0xabc" })' "$LOG"
  ! grep -q '^launch' "$LOG"
done

# No window: launch with the arguments the widget passes.
printf '[]' >"$CLIENTS"
run_toggle org.omarchy.btop "$RUNTIME_CONFIG"
grep -Fq "launch --app-id=org.omarchy.btop btop --config $RUNTIME_CONFIG" "$LOG"

# Bare invocation (a keybinding): window mode comes from shell.json and the
# runtime config is used when it exists.
printf '{"bar":{"layout":{"right":[{"id":"ilyazar.btop","windowMode":"Tiled"}]}}}' \
  >"$TEMP_ROOT/config/omarchy/shell.json"
: >"$RUNTIME_CONFIG"
run_toggle
grep -Fq "launch --app-id=org.omarchy.btop_tiled btop --config $RUNTIME_CONFIG" "$LOG"

# Bare invocation without either falls back to a plain floating launch.
rm "$RUNTIME_CONFIG" "$TEMP_ROOT/config/omarchy/shell.json"
run_toggle
grep -Fqx 'launch --app-id=org.omarchy.btop btop' "$LOG"

printf 'ok - toggle btop\n'
