#!/bin/bash
set -euo pipefail

proc_root=${BTOP_GPU_PROC_ROOT:-/proc}
dri_root=${BTOP_GPU_DRI_ROOT:-/dev/dri}
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
declare -a files=()

shopt -s nullglob
command -v python3 >/dev/null 2>&1 || exit 0

devices=("$dri_root"/card[0-9]* "$dri_root"/renderD[0-9]*)
((${#devices[@]})) || exit 0
saw_process=0
for process in "$proc_root"/[0-9]*; do
  [[ -O $process && -d $process/fd ]] && { saw_process=1; break; }
done
((saw_process)) || exit 0

# GNU find -L on /proc/<pid>/fd aborts in gnulib FTS leave_dir (FTS_LOGICAL
# cycle hash) when a descriptor directory vanishes or a followed fd is a
# directory. Walk the fd table in Python and match DRM nodes by device+inode,
# which is the same test as find -samefile without FTS.
while IFS= read -r -d '' file; do
  files+=("$file")
done < <(python3 - "$proc_root" "$dri_root" <<'PY'
import os, re, sys

proc_root, dri_root = sys.argv[1], sys.argv[2]
uid = os.getuid()
device_name = re.compile(r"^(?:card|renderD)[0-9]+$")
drm = set()

try:
    names = os.listdir(dri_root)
except OSError:
    sys.exit(0)

for name in names:
    if not device_name.fullmatch(name):
        continue
    try:
        st = os.stat(os.path.join(dri_root, name), follow_symlinks=True)
    except OSError:
        continue
    drm.add((st.st_dev, st.st_ino))

if not drm:
    sys.exit(0)

try:
    processes = os.scandir(proc_root)
except OSError:
    sys.exit(0)

with processes:
    for process in processes:
        if not process.name.isdigit():
            continue
        try:
            if process.stat(follow_symlinks=False).st_uid != uid:
                continue
            fdinfo_dir = os.path.join(process.path, "fdinfo")
            with os.scandir(os.path.join(process.path, "fd")) as fds:
                for fd in fds:
                    if not fd.name.isdigit():
                        continue
                    try:
                        st = fd.stat(follow_symlinks=True)
                    except OSError:
                        continue
                    if (st.st_dev, st.st_ino) not in drm:
                        continue
                    info = os.path.join(fdinfo_dir, fd.name)
                    if os.access(info, os.R_OK):
                        sys.stdout.buffer.write(os.fsencode(info) + b"\0")
        except OSError:
            continue
PY
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
