#!/bin/bash
set -euo pipefail

sys_root=${BTOP_SYS_ROOT:-/sys}

value() {
  REPLY=
  [[ -r $1 ]] && read -r REPLY <"$1" || true
}

temperature_path() {
  local directory=$1 preferred=$2 file label fallback=
  REPLY=
  for file in "$directory"/temp*_input; do
    [[ -r $file ]] || continue
    value "${file%_input}_label"
    label=$REPLY
    if [[ ${3:-} == gpu ]]; then
      case "${label,,}" in mem*|vram*) continue;; esac
    fi
    [[ -n $fallback ]] || fallback=$file
    if [[ $label == "$preferred" ]]; then
      REPLY=$file
      return
    fi
  done
  REPLY=$fallback
}

cpu_found=false
for directory in "$sys_root"/class/hwmon/hwmon*; do
  value "$directory/name"
  name=$REPLY
  case "$name" in
    coretemp)
      package_found=false
      for label in "$directory"/temp*_label; do
        value "$label"
        if [[ $REPLY == "Package id "* && -r ${label%_label}_input ]]; then
          printf 'cpu\tpackage\t%s\n' "${label%_label}_input"
          package_found=true
          cpu_found=true
        fi
      done
      if ! "$package_found"; then
        for file in "$directory"/temp*_input; do
          [[ -r $file ]] || continue
          printf 'cpu\tcore\t%s\n' "$file"
          cpu_found=true
        done
      fi
      ;;
    k10temp|zenpower)
      temperature_path "$directory" Tdie
      file=$REPLY
      [[ -n $file ]] || continue
      value "${file%_input}_label"
      if [[ $REPLY != Tdie ]]; then
        temperature_path "$directory" Tctl
        file=$REPLY
        value "${file%_input}_label"
      fi
      kind=package
      [[ $REPLY == Tctl ]] && kind=control
      [[ $REPLY == Tdie ]] && kind=die
      printf 'cpu\t%s\t%s\n' "$kind" "$file"
      cpu_found=true
      ;;
    k8temp)
      for file in "$directory"/temp*_input; do
        [[ -r $file ]] || continue
        printf 'cpu\tcore\t%s\n' "$file"
        cpu_found=true
      done
      ;;
    cpu_thermal|cpu-thermal|soc_thermal|soc-thermal)
      temperature_path "$directory" CPU
      [[ -n $REPLY ]] || continue
      printf 'cpu\tpackage\t%s\n' "$REPLY"
      cpu_found=true
      ;;
  esac
done

if ! "$cpu_found"; then
  for directory in "$sys_root"/class/thermal/thermal_zone*; do
    value "$directory/type"
    case "${REPLY,,}" in
      x86_pkg_temp|cpu-thermal|cpu_thermal|cpu[0-9]*-thermal|soc_thermal|soc-thermal)
        [[ -r $directory/temp ]] || continue
        printf 'cpu\tpackage\t%s\n' "$directory/temp"
        ;;
    esac
  done
fi

declare -A seen=()
emit_gpu() {
  local directory=$1 id=$2 vendor driver card="" temperature="" file
  [[ -v seen[$id] ]] && return
  # Intel's sys: selector requires the canonical device path.
  directory=$(readlink -f -- "$directory" 2>/dev/null) || return 0
  seen[$id]=1
  value "$directory/vendor"
  vendor=$REPLY
  driver=$(readlink "$directory/driver" 2>/dev/null || true)
  driver=${driver##*/}
  for file in "$directory"/drm/card*; do
    [[ ${file##*/} =~ ^card[0-9]+$ ]] || continue
    card=${file##*/}
    break
  done
  for file in "$directory"/hwmon/hwmon*; do
    temperature_path "$file" edge gpu
    if [[ $driver == xe && -r $file/temp2_input ]]; then
      REPLY=$file/temp2_input
    fi
    [[ -n $REPLY ]] || continue
    temperature=$REPLY
    break
  done
  printf 'gpu\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$id" "$vendor" "$driver" "$card" "$directory" "$temperature" \
    "$directory/gpu_busy_percent" "$directory/mem_info_vram_used" \
    "$directory/mem_info_vram_total"
}

for directory in "$sys_root"/bus/pci/devices/*; do
  value "$directory/class"
  [[ $REPLY == 0x03* ]] || continue
  emit_gpu "$directory" "${directory##*/}"
done

# Platform GPUs do not necessarily have a PCI address.
for card_path in "$sys_root"/class/drm/card*; do
  [[ ${card_path##*/} =~ ^card[0-9]+$ && -d $card_path/device ]] || continue
  directory=$(readlink -f "$card_path/device" 2>/dev/null) || continue
  id=${directory##*/}
  [[ $id =~ ^[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]$ ]] \
    || id="platform:$directory"
  emit_gpu "$directory" "$id"
done

for tool in fastfetch nvidia-smi amd-smi rocm-smi intel_gpu_top xpu-smi; do
  path=$(command -v "$tool" || true)
  if [[ -z $path && ( $tool == amd-smi || $tool == rocm-smi ) \
      && -x /opt/rocm/bin/$tool ]]; then
    path=/opt/rocm/bin/$tool
  fi
  [[ -n $path ]] && printf 'tool\t%s\t%s\n' "$tool" "$path"
done
exit 0
