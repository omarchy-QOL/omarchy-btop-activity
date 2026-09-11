#!/bin/bash
set -euo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLUGIN_ROOT=$(cd "$TEST_DIR/.." && pwd)
TEMP_ROOT=$(mktemp -d)
readonly TEST_DIR PLUGIN_ROOT TEMP_ROOT
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

PROC_ROOT=$TEMP_ROOT/proc
DRI_ROOT=$TEMP_ROOT/dri
MOCK_BIN=$TEMP_ROOT/bin
FIND_LOG=$TEMP_ROOT/find.log
HELPER=$PLUGIN_ROOT/helpers/gpu-fdinfo.sh
PCI=0000:00:02.0

mkdir -p "$PROC_ROOT" "$DRI_ROOT" "$MOCK_BIN"
printf '100.0 0.0\n' >"$PROC_ROOT/uptime"

cat >"$MOCK_BIN/find" <<'MOCK'
#!/bin/bash
printf 'find %s\n' "$*" >>"${FIND_LOG:-/dev/null}"
exit 99
MOCK
chmod 0755 "$MOCK_BIN/find"

write_fdinfo() {
  local path=$1 client=$2 render_ns=$3
  mkdir -p -- "$(dirname -- "$path")"
  printf '%s\n' \
    $'drm-driver:\ti915' \
    $'drm-client-id:\t'"$client" \
    $'drm-pdev:\t'"$PCI" \
    $'drm-engine-render:\t'"$render_ns"' ns' \
    $'drm-engine-copy:\t0 ns' >"$path"
}

run_helper() {
  : >"$FIND_LOG"
  env PATH="$MOCK_BIN:$PATH" FIND_LOG="$FIND_LOG" \
    BTOP_GPU_PROC_ROOT="$PROC_ROOT" BTOP_GPU_DRI_ROOT="$DRI_ROOT" \
    bash "$HELPER" "$@"
}

assert_no_find() {
  [[ ! -s $FIND_LOG ]]
}

device=$DRI_ROOT/renderD128
: >"$device"
process=$PROC_ROOT/123
mkdir -p "$process/fd" "$process/fdinfo"
ln -s "$device" "$process/fd/5"
ln -s "$TEMP_ROOT/other" "$process/fd/6"
: >"$TEMP_ROOT/other"
write_fdinfo "$process/fdinfo/5" 7 100000000
write_fdinfo "$process/fdinfo/6" 8 999

output=$(run_helper "$PCI")
assert_no_find
grep -Fq $'counter\t'"$PCI"$'\t7\trender\t100000000' <<<"$output"
grep -Fq $'counter\t'"$PCI"$'\t7\tcopy\t0' <<<"$output"
! grep -Fq $'\t8\t' <<<"$output"
grep -Eq $'^time\t' <<<"$output"

# Same inode via a hard link still matches, like find -samefile.
mkdir -p "$PROC_ROOT/124/fd" "$PROC_ROOT/124/fdinfo"
ln -- "$device" "$PROC_ROOT/124/fd/3"
write_fdinfo "$PROC_ROOT/124/fdinfo/3" 9 50
output=$(run_helper "$PCI")
assert_no_find
grep -Fq $'counter\t'"$PCI"$'\t9\trender\t50' <<<"$output"

# A followed fd that is a directory (the FTS_LOGICAL crash shape) is ignored.
ln -s "$process/fd" "$process/fd/10"
ln -s / "$process/fd/11"
output=$(run_helper "$PCI")
assert_no_find
grep -Fq $'counter\t'"$PCI"$'\t7\trender\t100000000' <<<"$output"

# Vanished descriptors and processes must not abort the helper.
mkdir -p "$PROC_ROOT/125/fd" "$PROC_ROOT/125/fdinfo"
ln -s "$device" "$PROC_ROOT/125/fd/4"
write_fdinfo "$PROC_ROOT/125/fdinfo/4" 10 1
ln -s "$TEMP_ROOT/missing-target" "$process/fd/12"
rm -rf "$PROC_ROOT/125"
output=$(run_helper "$PCI")
assert_no_find
grep -Fq $'counter\t'"$PCI"$'\t7\trender\t100000000' <<<"$output"

# Unreadable fdinfo is skipped; a large dummy fd table stays within argv limits.
mkdir -p "$PROC_ROOT/126/fd" "$PROC_ROOT/126/fdinfo"
ln -s "$device" "$PROC_ROOT/126/fd/1"
write_fdinfo "$PROC_ROOT/126/fdinfo/1" 11 3
chmod 000 "$PROC_ROOT/126/fdinfo/1"
for n in {20..120}; do
  ln -s "$TEMP_ROOT/other" "$PROC_ROOT/126/fd/$n"
done
output=$(run_helper "$PCI")
assert_no_find
! grep -Fq $'\t11\t' <<<"$output"
grep -Fq $'counter\t'"$PCI"$'\t7\trender\t100000000' <<<"$output"
chmod 644 "$PROC_ROOT/126/fdinfo/1"

# No DRM nodes: quiet success, no find.
rm -f "$DRI_ROOT"/card[0-9]* "$DRI_ROOT"/renderD[0-9]*
output=$(run_helper "$PCI")
assert_no_find
[[ -z $output ]]

printf 'ok - gpu fdinfo sampling\n'
