#!/bin/bash
set -euo pipefail

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PLUGIN_ROOT=$(cd -- "$TEST_DIR/.." && pwd)
TEMP_ROOT=$(mktemp -d)
readonly TEST_DIR PLUGIN_ROOT TEMP_ROOT
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

MOCK_BIN=$TEMP_ROOT/bin
LOG=$TEMP_ROOT/editor.log
BINDINGS=$TEMP_ROOT/bindings.lua
mkdir -p "$MOCK_BIN"

cat >"$MOCK_BIN/nvim" <<'MOCK'
#!/bin/bash
exit 0
MOCK
cat >"$MOCK_BIN/omarchy-launch-tui" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >"$EDITOR_LOG"
MOCK
cat >"$MOCK_BIN/omarchy-launch-config-editor" <<'MOCK'
#!/bin/bash
printf 'config %s\n' "$*" >"$EDITOR_LOG"
MOCK
chmod 0755 "$MOCK_BIN"/*

run_case() {
  local content=$1 expected_line=$2 label=$3
  printf '%b' "$content" >"$BINDINGS"
  EDITOR_LOG=$LOG PATH="$MOCK_BIN:/usr/bin" \
    bash "$PLUGIN_ROOT/helpers/open-keybindings.sh" "$BINDINGS"
  expected="--app-id=org.omarchy.btop-keybindings nvim +$expected_line $BINDINGS"
  actual=$(<"$LOG")
  if [[ $actual != "$expected" ]]; then
    printf 'not ok - %s\nexpected: %s\nactual: %s\n' \
      "$label" "$expected" "$actual" >&2
    exit 1
  fi
}

run_case $'first\nsecond\nopen btop here\nfourth\n' 3 'btop match'
run_case $'first\ncommand = "AcTiViTy"\nthird\n' 2 'Activity match'
run_case $'first\nSUPER  + CTRL +  T\nthird\n' 2 'shortcut match'
run_case $'first\nsecond without newline' 3 'append after final line'
run_case '' 1 'empty file'

rm -f "$BINDINGS"
EDITOR_LOG=$LOG PATH="$MOCK_BIN:/usr/bin" \
  bash "$PLUGIN_ROOT/helpers/open-keybindings.sh" "$BINDINGS"
expected="--app-id=org.omarchy.btop-keybindings nvim +1 $BINDINGS"
[[ $(<"$LOG") == "$expected" ]]

rm -f "$MOCK_BIN/nvim"
EDITOR_LOG=$LOG PATH="$MOCK_BIN" /bin/bash \
  "$PLUGIN_ROOT/helpers/open-keybindings.sh" "$BINDINGS"
[[ $(<"$LOG") == "config $BINDINGS" ]]

printf 'ok - keybindings editor position\n'
