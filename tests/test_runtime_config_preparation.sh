#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TEST_DIR/.." && pwd)"
TEMP_ROOT="$(mktemp -d)"
readonly TEST_DIR PLUGIN_ROOT TEMP_ROOT
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

readonly CASE_ROOT="$TEMP_ROOT/case"
readonly RUNTIME_ROOT="$CASE_ROOT/runtime"
readonly RUNTIME_DIR="$RUNTIME_ROOT/omarchy-btop-activity"
readonly CONFIG_PATH="$RUNTIME_DIR/btop.conf"

extract_command() {
  local property="$1"

  sed -n "/readonly property string ${property}: \[/,/  \].join(\"\\\\n\")/p" \
    "$PLUGIN_ROOT/Service.qml" |
    sed -n 's/^[[:space:]]*\(".*"\),\{0,1\}$/\1/p' |
    jq -Rr fromjson
}

prepare_command="$(extract_command prepareRuntimeCommand)"
readonly prepare_command

[[ -n $prepare_command ]]
bash -n <<<"$prepare_command"

reset_case() {
  rm -rf -- "$CASE_ROOT"
  mkdir -p "$RUNTIME_ROOT"
  chmod 0700 "$RUNTIME_ROOT"
}

run_prepare() {
  bash -c "$prepare_command" btop-runtime-prepare \
    "$RUNTIME_ROOT" "$RUNTIME_DIR" "$CONFIG_PATH"
}

assert_fresh_runtime_prepared() {
  reset_case
  run_prepare

  [[ -d $RUNTIME_DIR ]]
  [[ $(stat -c '%a' "$RUNTIME_DIR") == 700 ]]
  [[ ! -e $CONFIG_PATH ]]
}

assert_existing_runtime_reused() {
  reset_case
  mkdir -p "$RUNTIME_DIR"
  printf 'existing plugin settings\n' >"$CONFIG_PATH"

  run_prepare

  [[ $(<"$CONFIG_PATH") == "existing plugin settings" ]]
}

assert_invalid_runtime_root_rejected() {
  reset_case

  if bash -c "$prepare_command" btop-runtime-prepare "" "" ""; then
    return 1
  fi

  [[ ! -e /omarchy-btop-activity ]]
}

assert_fresh_runtime_prepared
assert_existing_runtime_reused
assert_invalid_runtime_root_rejected

printf 'ok - runtime config preparation\n'
