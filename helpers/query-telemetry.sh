#!/bin/bash
set -euo pipefail

# Discovery can become stale while earlier queries are running.
sleeping=false
while [[ $1 != -- ]]; do
  if [[ ! -d $1 ]]; then
    printf 'unavailable\t%s\n' "$1"
    sleeping=true
    shift
    continue
  fi
  state=
  if [[ -r $1/power/runtime_status ]]; then
    read -r state <"$1/power/runtime_status" || true
  fi
  case "$state" in
    ""|active|unsupported) ;;
    *)
      printf 'sleeping\t%s\n' "$1"
      sleeping=true
      ;;
  esac
  shift
done
shift
"$sleeping" && exit 75
exec "$@"
