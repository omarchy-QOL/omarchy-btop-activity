#!/bin/bash
set -euo pipefail

interval_ms=${1:-250}
proc_root=${BTOP_GPU_PROC_ROOT:-/proc}
dri_root=${BTOP_GPU_DRI_ROOT:-/dev/dri}

[[ $interval_ms =~ ^[0-9]+$ ]] || exit 2
((interval_ms >= 50 && interval_ms <= 5000)) || exit 2

snapshot() {
  local device fd file process
  local -a devices=()
  local -a files=()

  for device in "$dri_root"/card[0-9]* "$dri_root"/renderD[0-9]*; do
    [[ -e $device ]] && devices+=("$device")
  done
  ((${#devices[@]} > 0)) || return 0

  for process in "$proc_root"/[0-9]*; do
    [[ -O $process ]] || continue
    for fd in "$process"/fd/[0-9]*; do
      for device in "${devices[@]}"; do
        [[ $fd -ef $device ]] || continue
        file=$process/fdinfo/${fd##*/}
        [[ -r $file ]] && files+=("$file")
        break
      done
    done
  done
  ((${#files[@]} > 0)) || return 0

  { grep -H -E '^drm-(client-id|pdev|engine-)' \
      "${files[@]}" 2>/dev/null || true; } |
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
          if (value + 0 > maximum[key]) maximum[key] = value + 0
        }
      }
      END {
        for (key in maximum) printf "%s\t%.0f\n", key, maximum[key]
      }
    '
}

declare -A before=() totals=()
started_ns=$(date +%s%N)
while IFS=$'\t' read -r key value; do
  before[$key]=$value
done < <(snapshot)

printf -v delay '%d.%03d' "$((interval_ms / 1000))" \
  "$((interval_ms % 1000))"
sleep "$delay"

ended_ns=$(date +%s%N)
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

((${#totals[@]} > 0)) || exit 3
interval_ns=$((ended_ns - started_ns))
maximum=0
for value in "${totals[@]}"; do
  ((value > maximum)) && maximum=$value
done
((maximum > interval_ns)) && maximum=$interval_ns
hundredths=$((maximum * 10000 / interval_ns))
printf 'usage\t%d.%02d\n' "$((hundredths / 100))" \
  "$((hundredths % 100))"
