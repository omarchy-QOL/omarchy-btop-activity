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

assert_large_fd_set() {
  local long_name large_root large_proc large_dri large_device sample pid output
  local -a directories=()

  printf -v long_name 'x%.0s' {1..180}
  large_root=$temp_root/fd/$long_name
  large_proc=$large_root/proc
  large_dri=$large_root/dri
  large_device=$large_dri/renderD128
  sample=$large_root/sample-fdinfo

  directories+=("$large_dri")
  for pid in {100..155}; do
    directories+=("$large_proc/$pid/fd" "$large_proc/$pid/fdinfo")
  done
  printf '%s\0' "${directories[@]}" | xargs -0 -r mkdir -p
  : >"$large_device"
  write_fdinfo "$sample" 7 0

  for pid in {100..155}; do
    ln -s "$large_device" "$large_proc/$pid/fd/5"
    ln -s "$sample" "$large_proc/$pid/fdinfo/5"
  done

  if env -i PATH="$PATH" bash -c '
      ulimit -s 512
      printf -v PAD "%*s" 120000 ""
      export PAD
      /bin/true "$@" 2>/dev/null
    ' _ "${directories[@]}"; then
    return 1
  else
    [[ $? -eq 126 ]]
  fi

  output=$(
    env -i PATH="$PATH" bash -c '
      ulimit -s 512
      printf -v PAD "%*s" 120000 ""
      export PAD
      BTOP_GPU_PROC_ROOT=$1 BTOP_GPU_DRI_ROOT=$2 bash "$3" 50
    ' _ "$large_proc" "$large_dri" "$plugin_root/gpu-fdinfo.sh"
  )
  [[ $output == $'usage\t0.00' ]]
}

for descriptor in 5 6 7; do
  ln -s "$device" "$process_root/fd/$descriptor"
done
write_fdinfo "$process_root/fdinfo/5" 7 0
write_fdinfo "$process_root/fdinfo/6" 7 0
write_fdinfo "$process_root/fdinfo/7" 8 0

(
  sleep 0.10
  write_fdinfo "$process_root/fdinfo/5" 7 100000000
  write_fdinfo "$process_root/fdinfo/6" 7 100000000
  write_fdinfo "$process_root/fdinfo/7" 8 10000000
) &
updater=$!

output=$(BTOP_GPU_PROC_ROOT=$proc_root BTOP_GPU_DRI_ROOT=$dri_root \
  bash "$plugin_root/gpu-fdinfo.sh" 200)
wait "$updater"

[[ $output == usage$'\t'* ]]
usage=${output#*$'\t'}
awk -v usage="$usage" 'BEGIN { exit !(usage >= 25 && usage <= 65) }'

write_fdinfo "$process_root/fdinfo/5" 7 0
write_fdinfo "$process_root/fdinfo/6" 7 0
write_fdinfo "$process_root/fdinfo/7" 8 0
output=$(BTOP_GPU_PROC_ROOT=$proc_root BTOP_GPU_DRI_ROOT=$dri_root \
  bash "$plugin_root/gpu-fdinfo.sh" 50)
[[ $output == $'usage\t0.00' ]]

assert_large_fd_set

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
