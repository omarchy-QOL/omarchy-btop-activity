#!/bin/bash
set -euo pipefail

[[ $# -eq 2 ]] || exit 2

app_id=$1
config_path=$2

case $app_id in
  org.omarchy.btop | org.omarchy.btop_tiled) ;;
  *) exit 2 ;;
esac

send_help_key() {
  local state=$1
  local event
  event="hl.dsp.send_key_state({ mods = \"SHIFT\", key = \"slash\", "
  event+="state = \"$state\", window = \"class:$app_id\" })"
  hyprctl dispatch "$event" >/dev/null
}

omarchy-launch-or-focus-tui \
  --app-id="$app_id" btop --config "$config_path" >/dev/null 2>&1 &

for _ in {1..30}; do
  if hyprctl clients -j | jq -e --arg app_id "$app_id" \
    '.[] | select(.class == $app_id)' >/dev/null; then
    sleep 0.6
    send_help_key down
    sleep 0.05
    send_help_key up
    exit
  fi
  sleep 0.1
done
