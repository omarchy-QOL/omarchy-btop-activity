#!/bin/bash

# Close the plugin's btop window when one is open, otherwise launch btop.
#
# The bar widget runs this with both arguments when settings.toml sets
# `left_click = "toggle"`. Bound bare, it makes one key open and close btop:
#
#   hl.unbind("SUPER + CTRL + T")
#   o.bind("SUPER + CTRL + T", "Activity", os.getenv("HOME")
#     .. "/.config/omarchy/plugins/ilyazar.btop/helpers/toggle-btop.sh")

set -euo pipefail

[[ $# -eq 0 || $# -eq 2 ]] || exit 2
mode="${1:-}"
config="${2-${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-btop-activity/btop.conf}"

if [[ $# -eq 0 ]]; then
  mode=$(jq -r '.. | objects | select(.id? == "ilyazar.btop") | .windowMode // empty' \
    "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json" 2>/dev/null | head -n 1 || true)
  mode=${mode:-Floating}
fi
case $mode in Floating | Tiled) ;; *) exit 2 ;; esac

# The same private identity survives changes between floating and tiled.
address=$(hyprctl clients -j | jq -r '
  first(.[] | select(.class == "org.omarchy.btop-activity") | .address) // empty')
if [[ -n $address ]]; then
  # btop saves settings only on a clean quit; closing the window kills it.
  pattern=$(sed 's/[][\.*^$+?(){}|]/\\&/g' <<<"$config")
  pkill -INT -u "$(id -u)" -f -- "^btop --config $pattern\$" || true
  for _ in {1..10}; do
    sleep 0.1
    hyprctl clients -j | jq -e --arg address "$address" \
      'any(.[]; .address == $address)' >/dev/null || exit 0
  done
  exec hyprctl dispatch "hl.dsp.window.close({ window = \"address:$address\" })"
fi

exec bash "$(dirname -- "${BASH_SOURCE[0]}")/open-btop.sh" "$mode" "$config"
