#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TEST_DIR/.." && pwd)"
TEMP_ROOT="$(mktemp -d)"
readonly TEST_DIR PLUGIN_ROOT TEMP_ROOT
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

readonly CASE_ROOT="$TEMP_ROOT/case"
readonly STATE_ROOT="$CASE_ROOT/missing/state"
readonly STATE_DIR="$STATE_ROOT/omarchy-btop-activity"
readonly CONFIG_PATH="$STATE_DIR/btop.conf"

extract_command() {
  local property="$1"

  sed -n "/readonly property string ${property}: \[/,/  \].join(\"\\\\n\")/p" \
    "$PLUGIN_ROOT/Service.qml" |
    sed -n 's/^[[:space:]]*\(".*"\),\{0,1\}$/\1/p' |
    jq -Rr fromjson
}

prepare_command="$(extract_command prepareStateCommand)"
readonly prepare_command

[[ -n $prepare_command ]]
bash -n <<<"$prepare_command"

reset_case() {
  rm -rf -- "$CASE_ROOT"
  mkdir -p "$CASE_ROOT"
}

run_prepare() {
  bash -c "$prepare_command" btop-state-prepare "$@"
}

# A missing root is created, as ~/.local/state is not guaranteed.
reset_case
run_prepare "$STATE_ROOT" "$STATE_DIR" "$CONFIG_PATH"
[[ $(stat -c '%a' "$STATE_DIR") == 700 ]]
[[ ! -e $CONFIG_PATH ]]

# An existing directory and config are reused.
printf 'existing plugin settings\n' >"$CONFIG_PATH"
chmod 0755 "$STATE_DIR"
run_prepare "$STATE_ROOT" "$STATE_DIR" "$CONFIG_PATH"
[[ $(stat -c '%a' "$STATE_DIR") == 700 ]]
[[ $(<"$CONFIG_PATH") == "existing plugin settings" ]]

# Dotfile setups may symlink the root.
reset_case
mkdir "$CASE_ROOT/real"
ln -s real "$CASE_ROOT/link"
run_prepare "$CASE_ROOT/link" "$CASE_ROOT/link/omarchy-btop-activity" \
  "$CASE_ROOT/link/omarchy-btop-activity/btop.conf"
[[ -d $CASE_ROOT/real/omarchy-btop-activity ]]

# The plugin directory itself must not point elsewhere.
reset_case
mkdir -p "$STATE_ROOT" "$CASE_ROOT/elsewhere"
ln -s "$CASE_ROOT/elsewhere" "$STATE_DIR"
if run_prepare "$STATE_ROOT" "$STATE_DIR" "$CONFIG_PATH"; then
  exit 1
else
  [[ $? -eq 23 ]]
fi

# Relative and mismatched paths never touch the filesystem.
reset_case
cd "$CASE_ROOT"
if run_prepare state state/omarchy-btop-activity \
  state/omarchy-btop-activity/btop.conf; then
  exit 1
else
  [[ $? -eq 20 ]]
fi
[[ ! -e state ]]
if run_prepare "$STATE_ROOT" "$CASE_ROOT/other" "$CASE_ROOT/other/btop.conf"; then
  exit 1
else
  [[ $? -eq 22 ]]
fi
[[ ! -e $STATE_ROOT ]]

printf 'ok - state directory preparation\n'
