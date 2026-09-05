#!/bin/bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
target_dir=${XDG_DATA_HOME:-"$HOME/.local/share"}/ilyazar-btop
target=$target_dir/gpu-telemetry

mkdir -p "$target_dir"
cc -O2 -std=c11 -Wall -Wextra -Werror \
  "$script_dir/gpu-telemetry.c" -ldl -o "$target"

printf 'installed %s\n' "$target"
