#!/bin/bash

# Toggle the plugin's btop window: close it when it is open, launch it
# otherwise. Used by the bar widget when "Left click" is set to Toggle, and
# directly usable from a Hyprland keybinding so the same key opens and
# closes btop:
#
#   hl.unbind("SUPER + CTRL + T")
#   o.bind("SUPER + CTRL + T", "Activity",
#     os.getenv("HOME") .. "/.config/omarchy/plugins/ilyazar.btop/toggle-btop.sh")
#
# The widget passes --app-id and --config explicitly. Invoked bare (from a
# keybinding), the script derives the window mode from shell.json and uses
# the plugin's runtime config when it exists — falling back to a plain
# launch, matching Omarchy's stock btop binding, when it does not.

set -euo pipefail

APP_ID=""
CONFIG=""

usage() {
  echo "Usage: toggle-btop.sh [--app-id ID] [--config PATH]"
  echo "Close the plugin's btop window if open, otherwise launch it."
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --app-id)
      APP_ID=$2
      shift 2
      ;;
    --config)
      CONFIG=$2
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z $APP_ID ]]; then
  mode=$(jq -r '
    .. | objects | select(.id? == "ilyazar.btop") | .windowMode // empty
  ' "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json" 2>/dev/null |
    head -n 1 || true)
  if [[ ${mode:-} == Tiled ]]; then
    APP_ID="org.omarchy.btop_tiled"
  else
    APP_ID="org.omarchy.btop"
  fi
fi

if [[ -z $CONFIG ]]; then
  candidate="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ilyazar-btop.conf"
  [[ -f $candidate ]] && CONFIG=$candidate
fi

close_one() {
  local address=$1 pid=$2
  if [[ -n $address ]]; then
    # Omarchy's Hyprland speaks Lua dispatchers; plain closewindow is the
    # fallback for a stock compositor.
    if hyprctl dispatch \
      "hl.dsp.window.close({ window = \"address:${address}\" })" \
      >/dev/null 2>&1; then
      return 0
    fi
    if hyprctl dispatch closewindow "address:${address}" >/dev/null 2>&1; then
      return 0
    fi
  fi
  if [[ -n $pid && $pid != 0 ]]; then
    kill "$pid" >/dev/null 2>&1 && return 0
  fi
  return 1
}

clients_json=$(hyprctl clients -j 2>/dev/null || true)
[[ -n $clients_json ]] || clients_json='[]'

# Close every window the plugin may have opened, in either window mode —
# switching Floating/Tiled while a window is open must not strand the old one.
mapfile -t rows < <(
  jq -r '
    .[]
    | select(.class == "org.omarchy.btop" or .class == "org.omarchy.btop_tiled")
    | [(.address // ""), ((.pid // 0) | tostring)]
    | @tsv
  ' <<<"$clients_json"
)

if ((${#rows[@]} > 0)); then
  closed=0
  for row in "${rows[@]}"; do
    address=${row%%$'\t'*}
    pid=${row#*$'\t'}
    if close_one "$address" "$pid"; then
      closed=1
    fi
  done
  ((closed))
  exit 0
fi

command=(omarchy-launch-or-focus-tui "--app-id=$APP_ID" btop)
[[ -n $CONFIG ]] && command+=(--config "$CONFIG")
exec "${command[@]}"
