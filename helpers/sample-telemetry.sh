#!/bin/bash
set -euo pipefail

mode=${1:-}

normalize_number() {
  local value=$1 sign= whole fraction=
  if [[ ! $value =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    REPLY=-
    return
  fi
  if [[ $value == -* ]]; then
    sign=-
    value=${value#-}
  fi
  whole=${value%%.*}
  [[ $value == *.* ]] && fraction=${value#*.}
  while [[ ${#whole} -gt 1 && $whole == 0* ]]; do whole=${whole#0}; done
  while [[ $fraction == *0 ]]; do fraction=${fraction%0}; done
  [[ $whole == 0 && -z $fraction ]] && sign=
  REPLY=$sign$whole${fraction:+.$fraction}
}

read_number() {
  local path=$1 value=
  if [[ -n $path && -r $path ]]; then
    IFS= read -r value <"$path" || true
  fi
  normalize_number "$value"
}

divide_milli() {
  local value=$1 sign= whole fraction= digits scale split
  if [[ $value == -* ]]; then
    sign=-
    value=${value#-}
  fi
  whole=${value%%.*}
  [[ $value == *.* ]] && fraction=${value#*.}
  digits=$whole$fraction
  while [[ ${#digits} -gt 1 && $digits == 0* ]]; do digits=${digits#0}; done
  scale=$((${#fraction} + 3))
  while ((${#digits} <= scale)); do digits=0$digits; done
  split=$((${#digits} - scale))
  whole=${digits:0:split}
  fraction=${digits:split}
  while [[ $fraction == *0 ]]; do fraction=${fraction%0}; done
  [[ $whole == 0 && -z $fraction ]] && sign=
  REPLY=$sign$whole${fraction:+.$fraction}
}

temperature() {
  local path=$1 fault value
  fault=$path
  if [[ $fault == *_input ]]; then
    fault=${fault%_input}_fault
    read_number "$fault"
    if [[ $REPLY == 1 ]]; then
      REPLY=-
      return
    fi
  fi
  read_number "$path"
  [[ $REPLY == - ]] && return
  value=$REPLY
  divide_milli "$value"
}

split_tsv() {
  local record=$1
  fields=()
  while [[ $record == *$'\t'* ]]; do
    fields+=("${record%%$'\t'*}")
    record=${record#*$'\t'}
  done
  fields+=("$record")
}

cpu_number() {
  if [[ $1 =~ ^[0-9]+$ ]]; then
    REPLY=$((10#$1))
  else
    REPLY=0
  fi
}

sample_stats() {
  local proc_root=${1:-/proc} line= key value
  local -a cpu=() values=()
  local total=0 busy memory_total=0 memory_available=0 have_available=false

  if [[ -r $proc_root/stat ]]; then
    IFS= read -r line <"$proc_root/stat" || true
    read -r -a cpu <<<"$line"
  fi
  if [[ ${cpu[0]:-} == cpu ]]; then
    for ((index = 1; index <= 8; index++)); do
      cpu_number "${cpu[index]:-}"
      values+=("$REPLY")
      ((total += REPLY))
    done
    busy=$((values[0] + values[1] + values[2] + values[5] + values[6]))
    printf 'cpu\t%d\t%d\n' "$busy" "$total"
  fi

  if [[ -r $proc_root/meminfo ]]; then
    while read -r key value _; do
      if [[ $key == MemTotal: && $value =~ ^[0-9]+$ ]]; then
        memory_total=$((10#$value))
      elif [[ $key == MemAvailable: && $value =~ ^[0-9]+$ ]]; then
        memory_available=$((10#$value))
        have_available=true
      fi
    done <"$proc_root/meminfo"
  fi
  if ((memory_total > 0 && memory_available <= memory_total)) &&
      "$have_available"; then
    printf 'memory\t%d\t%d\n' \
      "$(((memory_total - memory_available) * 1024))" \
      "$((memory_total * 1024))"
  fi
}

sample_sensors() {
  local inventory=${1:-} record state state_path usage heat used total
  local -a fields=()

  while IFS= read -r record || [[ -n $record ]]; do
    split_tsv "$record"
    [[ ${#fields[@]} -ge 3 ]] || continue
    if [[ ${fields[0]} == cpu ]]; then
      temperature "${fields[2]}"
      printf 'temperature\t%s\t%s\n' "${fields[1]}" "$REPLY"
      continue
    fi
    [[ ${fields[0]} == gpu && ${#fields[@]} -eq 10 ]] || continue
    state=
    state_path=${fields[5]}/power/runtime_status
    if [[ -r $state_path ]]; then
      IFS= read -r state <"$state_path" || true
    fi
    if [[ -n $state && $state != active && $state != unsupported ]]; then
      printf 'gpu\t%s\tsleeping\t-\t-\t-\t-\n' "${fields[1]}"
      continue
    fi
    read_number "${fields[7]}"; usage=$REPLY
    temperature "${fields[6]}"; heat=$REPLY
    read_number "${fields[8]}"; used=$REPLY
    read_number "${fields[9]}"; total=$REPLY
    printf 'gpu\t%s\tactive\t%s\t%s\t%s\t%s\n' \
      "${fields[1]}" "$usage" "$heat" "$used" "$total"
  done <<<"$inventory"
}

case $mode in
  stats) sample_stats "${2:-/proc}" ;;
  sensors) sample_sensors "${2:-}" ;;
  *)
    printf 'Usage: %s <stats PROC_ROOT | sensors INVENTORY>\n' "$0" >&2
    exit 2
    ;;
esac
