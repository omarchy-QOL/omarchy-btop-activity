#!/bin/bash
set -euo pipefail

PLUGIN_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEMP_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEMP_ROOT"' EXIT
MOCK_BIN="$TEMP_ROOT/bin"
LOG="$TEMP_ROOT/calls.log"
RULE_LOG="$TEMP_ROOT/rules.log"
CLIENTS="$TEMP_ROOT/clients.json"
RUNTIME_CONFIG="$TEMP_ROOT/runtime/omarchy-btop-activity/btop.conf"

mkdir -p "$MOCK_BIN" "$(dirname "$RUNTIME_CONFIG")" "$TEMP_ROOT/config/omarchy"
: >"$RUNTIME_CONFIG"
cat >"$MOCK_BIN/hyprctl" <<MOCK
#!/bin/bash
if [[ \$1 == clients ]]; then
  if [[ \${QUERY_EXIT:-0} != 0 ]]; then
    printf 'client query failed\n' >&2
    exit "\$QUERY_EXIT"
  fi
  exec cat "$CLIENTS"
elif [[ \$1 == eval ]]; then
  printf '%s\n' "\$2" >>"$RULE_LOG"
  exit "\${RULE_EXIT:-0}"
fi
shift
printf 'dispatch %s\n' "\$*" >>"$LOG"
if [[ \$* == hl.dsp.window.close* && \${CLOSE_EXIT:-0} != 0 ]]; then
  printf 'window close failed\n' >&2
  exit "\$CLOSE_EXIT"
fi
MOCK
cat >"$MOCK_BIN/omarchy-launch-tui" <<MOCK
#!/bin/bash
printf 'launch %s\n' "\$*" >>"$LOG"
MOCK
cat >"$MOCK_BIN/omarchy-notification-send" <<MOCK
#!/bin/bash
printf '%s\n' "\$*" >"$TEMP_ROOT/notice"
MOCK
chmod 0755 "$MOCK_BIN/hyprctl" "$MOCK_BIN/omarchy-launch-tui" \
  "$MOCK_BIN/omarchy-notification-send"

run_helper() {
  local helper=$1
  shift
  : >"$LOG"
  : >"$RULE_LOG"
  env PATH="$MOCK_BIN:$PATH" HOME="$TEMP_ROOT" \
    XDG_CONFIG_HOME="$TEMP_ROOT/config" XDG_RUNTIME_DIR="$TEMP_ROOT/runtime" \
    bash "$PLUGIN_ROOT/helpers/$helper" "$@"
}

# Neither floating/tiled changes nor ordinary btop windows change ownership.
printf '[{"class":"org.omarchy.btop","address":"0x111"},
  {"class":"org.omarchy.btop_tiled","address":"0x222"},
  {"class":"org.omarchy.btop-activity","address":"0xabc"}]' >"$CLIENTS"
for mode in Floating Tiled; do
  run_helper toggle-btop.sh "$mode" "$RUNTIME_CONFIG"
  [[ $(wc -l <"$LOG") -eq 1 ]]
  grep -Fxq 'dispatch hl.dsp.window.close({ window = "address:0xabc" })' "$LOG"
  [[ ! -s $RULE_LOG ]]
done

# Open/focus and Help use that same private window, never the ordinary one.
run_helper open-btop.sh Tiled "$RUNTIME_CONFIG"
grep -Fxq 'dispatch hl.dsp.focus({ window = "address:0xabc" })' "$LOG"
[[ $(wc -l <"$LOG") -eq 1 && ! -s $RULE_LOG ]]
run_helper open-btop-help.sh Floating "$RUNTIME_CONFIG"
grep -Fxq 'dispatch hl.dsp.focus({ window = "address:0xabc" })' "$LOG"
grep -Fxq 'dispatch hl.dsp.send_key_state({ mods = "SHIFT", key = "slash", state = "down", window = "address:0xabc" })' "$LOG"
grep -Fxq 'dispatch hl.dsp.send_key_state({ mods = "SHIFT", key = "slash", state = "up", window = "address:0xabc" })' "$LOG"
[[ $(wc -l <"$LOG") -eq 3 ]]

# Even if duplicate private windows exist, one click closes only one.
printf '[{"class":"org.omarchy.btop-activity","address":"0xabc"},
  {"class":"org.omarchy.btop-activity","address":"0xdef"}]' >"$CLIENTS"
run_helper toggle-btop.sh Floating "$RUNTIME_CONFIG"
[[ $(wc -l <"$LOG") -eq 1 ]]
grep -Fxq 'dispatch hl.dsp.window.close({ window = "address:0xabc" })' "$LOG"

# An ordinary btop window alone must not prevent a new private launch.
printf '[{"class":"org.omarchy.btop","address":"0x111"}]' >"$CLIENTS"
for mode in Floating Tiled; do
  run_helper toggle-btop.sh "$mode" "$RUNTIME_CONFIG"
  grep -Fxq "launch --app-id=org.omarchy.btop-activity btop --config $RUNTIME_CONFIG" "$LOG"
  [[ $(wc -l <"$LOG") -eq 1 ]]
  grep -Fq "class = '^org[.]omarchy[.]btop-activity$'" "$RULE_LOG"
  if [[ $mode == Floating ]]; then
    grep -Fq "tag = '+floating-window'" "$RULE_LOG"
  else
    grep -Fq 'tile = true' "$RULE_LOG"
  fi
done

# Bare keybindings reuse the current private config and the selected mode.
printf '[]' >"$CLIENTS"
printf '{"bar":{"layout":{"right":[{"id":"ilyazar.btop","windowMode":"Tiled"}]}}}' \
  >"$TEMP_ROOT/config/omarchy/shell.json"
run_helper toggle-btop.sh
grep -Fxq "launch --app-id=org.omarchy.btop-activity btop --config $RUNTIME_CONFIG" "$LOG"
grep -Fq 'tile = true' "$RULE_LOG"

rm "$RUNTIME_CONFIG"
if run_helper toggle-btop.sh 2>"$TEMP_ROOT/error"; then
  printf 'launched btop without its private config\n' >&2
  exit 1
fi
[[ ! -s $LOG && ! -s $RULE_LOG ]]
grep -Fq 'Open btop from the plugin first.' "$TEMP_ROOT/error"
grep -Fq 'Open btop from the plugin first.' "$TEMP_ROOT/notice"

# Closing an existing private window does not need its config file.
printf '[{"class":"org.omarchy.btop-activity","address":"0xabc"}]' >"$CLIENTS"
run_helper toggle-btop.sh
grep -Fxq 'dispatch hl.dsp.window.close({ window = "address:0xabc" })' "$LOG"
: >"$RUNTIME_CONFIG"

if QUERY_EXIT=42 run_helper toggle-btop.sh Floating "$RUNTIME_CONFIG" 2>"$TEMP_ROOT/error"; then
  exit 1
else
  [[ $? -eq 42 ]]
fi
[[ ! -s $LOG ]]
grep -Fxq 'client query failed' "$TEMP_ROOT/error"

printf 'invalid json' >"$CLIENTS"
if run_helper toggle-btop.sh Floating "$RUNTIME_CONFIG" 2>"$TEMP_ROOT/error"; then
  exit 1
fi
[[ ! -s $LOG && -s $TEMP_ROOT/error ]]

printf '[{"class":"org.omarchy.btop-activity","address":"0xabc"}]' >"$CLIENTS"
if CLOSE_EXIT=43 run_helper toggle-btop.sh Floating "$RUNTIME_CONFIG" 2>"$TEMP_ROOT/error"; then
  exit 1
else
  [[ $? -eq 43 ]]
fi
[[ $(wc -l <"$LOG") -eq 1 ]]
grep -Fxq 'dispatch hl.dsp.window.close({ window = "address:0xabc" })' "$LOG"
grep -Fxq 'window close failed' "$TEMP_ROOT/error"

printf '[]' >"$CLIENTS"
if RULE_EXIT=44 run_helper toggle-btop.sh Floating "$RUNTIME_CONFIG"; then
  exit 1
else
  [[ $? -eq 44 ]]
fi
[[ ! -s $LOG ]]

printf 'ok - private btop window launch, help and toggle\n'
