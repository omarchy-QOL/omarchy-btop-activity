#!/bin/bash

set -euo pipefail

bindings_file="${1:-$HOME/.config/hypr/bindings.lua}"
target_line=1
shortcut_pattern='super[[:space:]]*\+[[:space:]]*ctrl[[:space:]]*\+[[:space:]]*t'

if [[ -r $bindings_file ]]; then
  line_number=0
  matched=false
  while IFS= read -r line || [[ -n $line ]]; do
    ((line_number += 1))
    lower=${line,,}
    if [[ $lower == *btop* || $lower == *'"activity"'* ||
          $lower =~ $shortcut_pattern ]]; then
      target_line=$line_number
      matched=true
      break
    fi
  done <"$bindings_file"
  "$matched" || target_line=$((line_number + 1))
fi

if command -v nvim >/dev/null 2>&1; then
  exec omarchy-launch-tui --app-id=org.omarchy.btop-keybindings \
    nvim "+$target_line" "$bindings_file"
fi

exec omarchy-launch-config-editor "$bindings_file"
