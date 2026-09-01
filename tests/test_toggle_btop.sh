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

mkdir -p "$MOCK_BIN"

cat >"$MOCK_BIN/hyprctl" <<MOCK
#!/bin/bash
if [[ \$1 == clients ]]; then cat "$CLIENTS"; exit 0; fi
if [[ \$1 == dispatch ]]; then shift; printf 'dispatch %s\n' "\$*" >>"$LOG"; exit 0; fi
exit 1
MOCK

cat >"$MOCK_BIN/omarchy-launch-or-focus-tui" <<MOCK
#!/bin/bash
printf 'launch %s\n' "\$*" >>"$LOG"
MOCK

chmod +x "$MOCK_BIN/hyprctl" "$MOCK_BIN/omarchy-launch-or-focus-tui"

run_toggle() {
  : >"$LOG"
  env PATH="$MOCK_BIN:$PATH" \
    HOME="$TEMP_ROOT" \
    XDG_CONFIG_HOME="$TEMP_ROOT/config" \
    XDG_RUNTIME_DIR="$TEMP_ROOT/runtime" \
    bash "$PLUGIN_ROOT/toggle-btop.sh" "$@"
}

mkdir -p "$TEMP_ROOT/runtime" "$TEMP_ROOT/config/omarchy"

# An open floating window is closed and nothing new is launched.
printf '[{"class": "org.omarchy.btop", "address": "0xabc", "pid": 4242}]' >"$CLIENTS"
run_toggle --app-id org.omarchy.btop --config "$TEMP_ROOT/runtime/ilyazar-btop.conf"
grep -q 'dispatch hl.dsp.window.close({ window = "address:0xabc" })' "$LOG"
! grep -q '^launch' "$LOG"

# Windows from either mode are closed, so switching modes cannot strand one.
printf '[{"class": "org.omarchy.btop_tiled", "address": "0xdef", "pid": 4243}]' >"$CLIENTS"
run_toggle --app-id org.omarchy.btop
grep -q 'address:0xdef' "$LOG"
! grep -q '^launch' "$LOG"

# No window: launches with the given app id and config.
printf '[]' >"$CLIENTS"
: >"$TEMP_ROOT/runtime/ilyazar-btop.conf"
run_toggle --app-id org.omarchy.btop --config "$TEMP_ROOT/runtime/ilyazar-btop.conf"
grep -q "launch --app-id=org.omarchy.btop btop --config $TEMP_ROOT/runtime/ilyazar-btop.conf" "$LOG"

# Bare invocation (a keybinding): window mode comes from shell.json and the
# runtime config is picked up when present.
printf '{"bar":{"layout":{"right":[{"id":"ilyazar.btop","windowMode":"Tiled"}]}}}' \
  >"$TEMP_ROOT/config/omarchy/shell.json"
run_toggle
grep -q "launch --app-id=org.omarchy.btop_tiled btop --config $TEMP_ROOT/runtime/ilyazar-btop.conf" "$LOG"

# Bare invocation without a runtime config launches plain, like the stock binding.
rm "$TEMP_ROOT/runtime/ilyazar-btop.conf" "$TEMP_ROOT/config/omarchy/shell.json"
run_toggle
grep -q 'launch --app-id=org.omarchy.btop btop$' "$LOG"

echo "toggle-btop tests passed"
