#!/bin/bash
set -euo pipefail

test_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugin_root=$(cd "$test_dir/.." && pwd)
temp_root=$(mktemp -d)
readonly plugin_root temp_root
trap 'rm -rf -- "$temp_root"' EXIT

proc_root=$temp_root/proc
dri_root=$temp_root/dri
process_root=$proc_root/123
device=$dri_root/renderD128
mkdir -p "$process_root/fd" "$process_root/fdinfo" "$dri_root"
: >"$device"

write_fdinfo() {
  local path=$1
  local client=$2
  local render_ns=$3
  local temporary=$path.tmp

  printf '%s\n' \
    $'drm-driver:\ti915' \
    $'drm-client-id:\t'"$client" \
    $'drm-pdev:\t0000:00:02.0' \
    $'drm-engine-render:\t'"$render_ns"' ns' \
    $'drm-engine-copy:\t0 ns' >"$temporary"
  mv -T -- "$temporary" "$path"
}

for descriptor in 5 6 7; do
  ln -s "$device" "$process_root/fd/$descriptor"
done
write_fdinfo "$process_root/fdinfo/5" 7 100000000
write_fdinfo "$process_root/fdinfo/6" 7 100000000
write_fdinfo "$process_root/fdinfo/7" 8 20000000

(
  sleep 0.10
  write_fdinfo "$process_root/fdinfo/5" 7 200000000
  write_fdinfo "$process_root/fdinfo/6" 7 200000000
  write_fdinfo "$process_root/fdinfo/7" 8 30000000
) &
updater=$!

output=$(BTOP_GPU_PROC_ROOT=$proc_root BTOP_GPU_DRI_ROOT=$dri_root \
  bash "$plugin_root/gpu-fdinfo.sh" 200)
wait "$updater"

[[ $output == usage$'\t'* ]]
usage=${output#*$'\t'}
awk -v usage="$usage" 'BEGIN { exit !(usage >= 25 && usage <= 65) }'

if BTOP_GPU_PROC_ROOT=$temp_root/empty \
    BTOP_GPU_DRI_ROOT=$dri_root \
    bash "$plugin_root/gpu-fdinfo.sh" 50; then
  exit 1
else
  [[ $? -eq 3 ]]
fi

if bash "$plugin_root/gpu-fdinfo.sh" invalid; then
  exit 1
else
  [[ $? -eq 2 ]]
fi

printf 'ok - gpu fdinfo sampling\n'
