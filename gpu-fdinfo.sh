#!/bin/bash
set -euo pipefail

interval_ms=${1:-250}
proc_root=${BTOP_GPU_PROC_ROOT:-/proc}
dri_root=${BTOP_GPU_DRI_ROOT:-/dev/dri}
declare -a fdinfo_files=()

[[ $interval_ms =~ ^[0-9]+$ ]] || exit 2
((interval_ms >= 50 && interval_ms <= 5000)) || exit 2

discover_files() {
  local device fd file process
  local -a devices=()
  local -a directories=()
  local -a expression=()

  fdinfo_files=()

  for device in "$dri_root"/card[0-9]* "$dri_root"/renderD[0-9]*; do
    [[ -e $device ]] && devices+=("$device")
  done
  ((${#devices[@]} > 0)) || return 0

  for process in "$proc_root"/[0-9]*; do
    [[ -O $process ]] || continue
    [[ -d $process/fd ]] && directories+=("$process/fd")
  done
  ((${#directories[@]} > 0)) || return 0

  for device in "${devices[@]}"; do
    ((${#expression[@]} > 0)) && expression+=(-o)
    expression+=(-samefile "$device")
  done

  while IFS= read -r -d '' fd; do
    file=${fd%/fd/*}/fdinfo/${fd##*/}
    [[ -r $file ]] && fdinfo_files+=("$file")
  done < <(
    printf '%s\0' "${directories[@]}" |
      find -L -files0-from - -mindepth 1 -maxdepth 1 \
        \( "${expression[@]}" \) -print0 2>/dev/null
  )
}

snapshot() {
  ((${#fdinfo_files[@]} > 0)) || return 0

  { printf '%s\0' "${fdinfo_files[@]}" |
      xargs -0 -r grep -H -E '^drm-(client-id|pdev|engine-)' \
        -- 2>/dev/null || true; } |
    awk '
      {
        separator = index($0, ":")
        file = substr($0, 1, separator - 1)
        line = substr($0, separator + 1)
        if (file != previous_file) {
          client = ""
          device = "unknown"
          previous_file = file
        }

        separator = match(line, /:[[:space:]]+/)
        label = substr(line, 1, separator - 1)
        value = substr(line, separator + RLENGTH)
        if (label == "drm-client-id") client = value
        else if (label == "drm-pdev") device = value
        else if (label ~ /^drm-engine-/ && client != "") {
          if (value !~ /^[0-9]+ ns$/) next
          sub(/^drm-engine-/, "", label)
          sub(/ ns$/, "", value)
          key = device "|" client "|" label
          if (!(key in maximum) || value + 0 > maximum[key])
            maximum[key] = value + 0
        }
      }
      END {
        for (key in maximum) printf "%s\t%.0f\n", key, maximum[key]
      }
    '
}

discover_files
declare -A before=() totals=()
first_started_ns=$(date +%s%N)
while IFS=$'\t' read -r key value; do
  before[$key]=$value
done < <(snapshot)
first_ended_ns=$(date +%s%N)

printf -v delay '%d.%03d' "$((interval_ms / 1000))" \
  "$((interval_ms % 1000))"
sleep "$delay"

second_started_ns=$(date +%s%N)
while IFS=$'\t' read -r key value; do
  [[ -v before[$key] ]] || continue
  ((value >= before[$key])) || continue
  device=${key%%|*}
  engine=${key##*|}
  total_key=$device'|'$engine
  totals[$total_key]=$((
    ${totals[$total_key]:-0} + value - before[$key]
  ))
done < <(snapshot)
second_ended_ns=$(date +%s%N)

((${#totals[@]} > 0)) || exit 3
interval_ns=$(((second_started_ns + second_ended_ns
  - first_started_ns - first_ended_ns) / 2))
maximum=0
for value in "${totals[@]}"; do
  ((value > maximum)) && maximum=$value
done
((maximum > interval_ns)) && maximum=$interval_ns
hundredths=$((maximum * 10000 / interval_ns))
printf 'usage\t%d.%02d\n' "$((hundredths / 100))" \
  "$((hundredths % 100))"
