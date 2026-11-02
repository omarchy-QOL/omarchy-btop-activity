#!/usr/bin/env python3

import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "helpers" / "gpu-fdinfo.py"
PCI = "0000:00:02.0"

SPEC = importlib.util.spec_from_file_location("gpu_fdinfo", HELPER)
GPU_FDINFO = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GPU_FDINFO)


class GpuFdinfoTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="gpu-fdinfo-")
        self.root = Path(self.temporary.name)
        self.proc = self.root / "proc"
        self.dri = self.root / "dri"
        self.proc.mkdir()
        self.dri.mkdir()
        (self.proc / "uptime").write_text("100.0 0.0\n")
        self.device = self.dri / "renderD128"
        self.device.touch()
        self.other = self.root / "other"
        self.other.touch()

    def tearDown(self):
        self.temporary.cleanup()

    def process(self, pid):
        process = self.proc / str(pid)
        (process / "fd").mkdir(parents=True)
        (process / "fdinfo").mkdir()
        return process

    def write_fdinfo(self, path, client, device=PCI):
        path.write_text(
            "drm-driver:\ti915\n"
            f"drm-client-id:\t{client}\n"
            f"drm-pdev:\t{device}\n"
            "drm-engine-render:\t100000000 ns\n"
            "drm-engine-copy:\t0 ns\n"
            "drm-cycles-render:\t5000\n"
            "drm-total-cycles-render:\t10000\n"
            "drm-engine-capacity-render:\t2\n"
            "drm-maxfreq-render:\t1000 MHz\n"
        )

    def run_helper(self, *wanted):
        environment = dict(
            os.environ,
            BTOP_GPU_PROC_ROOT=str(self.proc),
            BTOP_GPU_DRI_ROOT=str(self.dri),
        )
        return subprocess.run(
            ["python3", str(HELPER), *wanted],
            env=environment,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
        ).stdout

    def test_cli_emits_exact_counters(self):
        process = self.process(123)
        os.symlink(self.device, process / "fd" / "5")
        os.symlink(self.other, process / "fd" / "6")
        self.write_fdinfo(process / "fdinfo" / "5", 7)
        self.write_fdinfo(process / "fdinfo" / "6", 8)

        output = self.run_helper(PCI)

        self.assertEqual(output, (
            f"counter\t{PCI}\t7\tcopy\t0\t-\t-\t1\t-\n"
            f"counter\t{PCI}\t7\trender\t100000000\t5000\t10000"
            "\t2\t1000000000\n"
            "time\t100.000000\n"
        ))

    def test_hard_links_and_filters(self):
        process = self.process(124)
        os.link(self.device, process / "fd" / "3")
        self.write_fdinfo(process / "fdinfo" / "3", 9, PCI.upper())
        os.symlink(process / "fd", process / "fd" / "10")
        os.symlink("/", process / "fd" / "11")

        output = self.run_helper(PCI)

        self.assertIn(f"counter\t{PCI}\t9\trender", output)
        self.assertNotIn("\t10\t", output)
        self.assertNotIn("\t11\t", output)

    def test_missing_nodes_are_quiet(self):
        self.device.unlink()
        self.assertEqual(self.run_helper(PCI), "")

    def test_descriptor_disappearance_is_injected(self):
        process = self.process(125)
        for descriptor in ("4", "5"):
            os.symlink(self.device, process / "fd" / descriptor)
            self.write_fdinfo(process / "fdinfo" / descriptor, descriptor)
        nodes = GPU_FDINFO.device_nodes(str(self.dri))

        def stat_entry(entry, follow):
            if entry.path.endswith("/fd/4"):
                raise FileNotFoundError(entry.path)
            return entry.stat(follow_symlinks=follow)

        saw_process, files = GPU_FDINFO.matching_fdinfo(
            str(self.proc), nodes, stat_entry=stat_entry
        )

        self.assertTrue(saw_process)
        self.assertEqual(files, [str(process / "fdinfo" / "5")])

    def test_process_disappearance_is_injected(self):
        vanished = self.process(126)
        stable = self.process(127)
        os.symlink(self.device, stable / "fd" / "2")
        self.write_fdinfo(stable / "fdinfo" / "2", 2)
        nodes = GPU_FDINFO.device_nodes(str(self.dri))

        def scan_dir(path):
            if str(path) == str(vanished / "fd"):
                raise FileNotFoundError(path)
            return os.scandir(path)

        saw_process, files = GPU_FDINFO.matching_fdinfo(
            str(self.proc), nodes, scan_dir=scan_dir
        )

        self.assertTrue(saw_process)
        self.assertEqual(files, [str(stable / "fdinfo" / "2")])

    def test_open_failure_is_injected(self):
        def fail_open(*_args, **_kwargs):
            raise FileNotFoundError("vanished")

        self.assertEqual(
            GPU_FDINFO.parse_fdinfo("missing", {PCI}, open_file=fail_open), []
        )


if __name__ == "__main__":
    unittest.main()
