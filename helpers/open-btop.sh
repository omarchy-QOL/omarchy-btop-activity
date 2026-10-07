#!/bin/bash
set -euo pipefail

[[ $# -eq 2 ]] || exit 2
mode=$1
config=$2
app_id=org.omarchy.btop-activity

case $mode in
  # Omarchy's floating-window tag carries float, center and size, so the
  # user's own rules for that tag apply here too.
  Floating) rules="tag = '+floating-window'" ;;
  Tiled) rules='tile = true' ;;
  *) exit 2 ;;
esac

address=$(hyprctl clients -j | jq -r --arg app_id "$app_id" \
  'first(.[] | select(.class == $app_id) | .address) // empty')
if [[ -n $address ]]; then
  exec hyprctl dispatch "hl.dsp.focus({ window = \"address:$address\" })"
fi

[[ -n $config && -f $config && -r $config ]] || {
  message='The btop plugin configuration is not ready. Open btop from the plugin first.'
  printf '%s\n' "$message" >&2
  omarchy-notification-send "btop Activity" "$message"
  exit 1
}

# The plugin's private identity is not covered by Omarchy's stock btop rule.
hyprctl eval "
  if ilyazar_btop_activity_rule then ilyazar_btop_activity_rule:set_enabled(false) end
  ilyazar_btop_activity_rule = hl.window_rule({
    match = { class = '^org[.]omarchy[.]btop-activity$' }, $rules
  })"
exec omarchy-launch-tui --app-id="$app_id" btop --config "$config"
