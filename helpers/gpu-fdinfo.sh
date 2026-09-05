#!/bin/bash
set -euo pipefail

proc_root=${BTOP_GPU_PROC_ROOT:-/proc}
dri_root=${BTOP_GPU_DRI_ROOT:-/dev/dri}
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
declare -a devices=() directories=() expression=() files=()

for device in "$dri_root"/card[0-9]* "$dri_root"/renderD[0-9]*; do
  [[ -e $device ]] && devices+=("$device")
done
for process in "$proc_root"/[0-9]*; do
  [[ -O $process && -d $process/fd ]] && directories+=("$process/fd")
done
((${#devices[@]} && ${#directories[@]})) || exit 0
for device in "${devices[@]}"; do
  ((${#expression[@]})) && expression+=(-o)
  expression+=(-samefile "$device")
done
while IFS= read -r -d '' descriptor; do
  file=${descriptor%/fd/*}/fdinfo/${descriptor##*/}
  [[ -r $file ]] && files+=("$file")
done < <(
  # GNU find reads every search root from stdin.
  # shellcheck disable=SC2185
  printf '%s\0' "${directories[@]}" |
    find -L -files0-from - -mindepth 1 -maxdepth 1 \
      \( "${expression[@]}" \) -print0 2>/dev/null
)

# Keep counters between refreshes in QML instead of sleeping in the collector.
{
  read -r uptime _ <"$proc_root/uptime"
  printf 'begin\t%s\n' "$uptime"
  if ((${#files[@]})); then
    printf '%s\0' "${files[@]}" |
      xargs -0 -r grep -H -E '^drm-(client-id|pdev|engine-|cycles-|total-cycles-|maxfreq-)' \
        -- 2>/dev/null || true
  fi
  read -r uptime _ <"$proc_root/uptime"
  printf 'end\t%s\n' "$uptime"
} | awk -v wanted="$*" -f "$script_dir/gpu-fdinfo.awk"
