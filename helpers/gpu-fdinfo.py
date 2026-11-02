#!/usr/bin/env python3

import os
import re
import sys


DEVICE_NAME = re.compile(r"^(?:card|renderD)[0-9]+$")
NUMBER = re.compile(r"^[0-9]+$")


def device_nodes(dri_root, list_dir=None, stat_path=None):
    list_dir = list_dir or os.listdir
    stat_path = stat_path or os.stat
    nodes = set()
    try:
        names = list_dir(dri_root)
    except OSError:
        return nodes
    for name in names:
        if not DEVICE_NAME.fullmatch(name):
            continue
        try:
            stat = stat_path(os.path.join(dri_root, name), follow_symlinks=True)
        except OSError:
            continue
        nodes.add((stat.st_dev, stat.st_ino))
    return nodes


def matching_fdinfo(proc_root, nodes, uid=None, scan_dir=None,
                    stat_entry=None, access_path=None):
    uid = os.getuid() if uid is None else uid
    scan_dir = scan_dir or os.scandir
    stat_entry = stat_entry or (
        lambda entry, follow: entry.stat(follow_symlinks=follow)
    )
    access_path = access_path or os.access
    files = []
    saw_process = False
    try:
        processes = scan_dir(proc_root)
    except OSError:
        return saw_process, files
    with processes:
        for process in processes:
            if not process.name.isdigit():
                continue
            try:
                if stat_entry(process, False).st_uid != uid:
                    continue
                fd_dir = os.path.join(process.path, "fd")
                if not os.path.isdir(fd_dir):
                    continue
                saw_process = True
                with scan_dir(fd_dir) as descriptors:
                    for descriptor in descriptors:
                        if not descriptor.name.isdigit():
                            continue
                        try:
                            stat = stat_entry(descriptor, True)
                        except OSError:
                            continue
                        if (stat.st_dev, stat.st_ino) not in nodes:
                            continue
                        path = os.path.join(
                            process.path, "fdinfo", descriptor.name
                        )
                        if access_path(path, os.R_OK):
                            files.append(path)
            except OSError:
                continue
    files.sort()
    return saw_process, files


def parse_fdinfo(path, wanted, open_file=None):
    open_file = open_file or open
    client = device = ""
    engines = {}
    try:
        with open_file(path, encoding="ascii", errors="replace") as stream:
            for raw_line in stream:
                label, separator, raw_value = raw_line.partition(":")
                if not separator:
                    continue
                values = raw_value.split()
                if not values:
                    continue
                value = values[0]
                unit = values[1] if len(values) > 1 else ""
                if label == "drm-client-id":
                    client = value
                    continue
                if label == "drm-pdev":
                    device = value.lower()
                    continue
                if not NUMBER.fullmatch(value):
                    continue
                engine = field = ""
                if label.startswith("drm-engine-capacity-"):
                    engine = label.removeprefix("drm-engine-capacity-")
                    field = "capacity"
                elif label.startswith("drm-engine-") and unit == "ns":
                    engine = label.removeprefix("drm-engine-")
                    field = "ns"
                elif label.startswith("drm-total-cycles-"):
                    engine = label.removeprefix("drm-total-cycles-")
                    field = "total"
                elif label.startswith("drm-cycles-"):
                    engine = label.removeprefix("drm-cycles-")
                    field = "cycles"
                elif label.startswith("drm-maxfreq-"):
                    engine = label.removeprefix("drm-maxfreq-")
                    field = "frequency"
                    if unit == "MHz":
                        value = str(int(value) * 1_000_000)
                    elif unit == "KHz":
                        value = str(int(value) * 1_000)
                if engine:
                    engines.setdefault(engine, {})[field] = value
    except OSError:
        return []
    if device not in wanted or not client:
        return []
    rows = []
    for engine in sorted(engines):
        values = engines[engine]
        rows.append((
            "counter", device, client, engine,
            values.get("ns", "-"), values.get("cycles", "-"),
            values.get("total", "-"), values.get("capacity", "1"),
            values.get("frequency", "-"),
        ))
    return rows


def uptime(proc_root, open_file=None):
    open_file = open_file or open
    with open_file(
        os.path.join(proc_root, "uptime"), encoding="ascii"
    ) as stream:
        return float(stream.read().split()[0])


def collect(proc_root, dri_root, wanted):
    nodes = device_nodes(dri_root)
    if not nodes:
        return []
    saw_process, files = matching_fdinfo(proc_root, nodes)
    if not saw_process:
        return []
    started = uptime(proc_root)
    rows = []
    for path in files:
        rows.extend(parse_fdinfo(path, wanted))
    ended = uptime(proc_root)
    if started > 0 and ended >= started:
        rows.append(("time", f"{(started + ended) / 2:.6f}"))
    return rows


def main(arguments=None):
    arguments = sys.argv[1:] if arguments is None else arguments
    proc_root = os.environ.get("BTOP_GPU_PROC_ROOT", "/proc")
    dri_root = os.environ.get("BTOP_GPU_DRI_ROOT", "/dev/dri")
    wanted = {value.lower() for value in arguments}
    rows = collect(proc_root, dri_root, wanted)
    if rows:
        sys.stdout.write("\n".join("\t".join(row) for row in rows) + "\n")


if __name__ == "__main__":
    main()
