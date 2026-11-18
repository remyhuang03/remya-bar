"""Shared read-only helpers for the Hyprland desktop benchmarks."""

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

from proc_sampler import NAME_PATTERN, parse_pid_stat

RUNS = Path(__file__).resolve().parent / "runs"

BUS_CONFIG = """<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <policy context="default">
    <allow own="*"/>
    <allow send_destination="*"/>
    <allow receive_sender="*"/>
  </policy>
</busconfig>
"""


def run_id(value):
    if not NAME_PATTERN.fullmatch(value) or value in {".", ".."}:
        raise argparse.ArgumentTypeError("expected 1–64 letters, digits, dots, hyphens or underscores")
    return value


def command(*args, cwd=None):
    return subprocess.check_output(args, cwd=cwd, text=True, timeout=10).strip()


def hyprland(query):
    return json.loads(command("hyprctl", "-j", query))


def topology():
    fields = ("name", "width", "height", "refreshRate", "scale", "x", "y",
              "transform", "vrr", "dpmsStatus")
    return sorted(
        ({key: monitor.get(key) for key in fields} for monitor in hyprland("monitors")),
        key=lambda monitor: monitor["name"],
    )


def sha256(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def bundle_hashes(bundle):
    return {
        name: sha256(bundle / name)
        for name in ("remya_bar", "lib/libapp.so", "lib/libflutter_linux_gtk.so",
                     "lib/libremya_bar_hyprland.so", "lib/libremya_bar_system.so")
    }


def process_start(pid):
    stat = parse_pid_stat((Path("/proc") / str(pid) / "stat").read_text())
    if stat["state"] in {"Z", "X", "x"}:
        raise RuntimeError(f"PID {pid} exited")
    return stat["starttime_ticks"]


def verify_bundle(pid, expected):
    proc = Path("/proc") / str(pid)
    live_exe = (proc / "exe").readlink()
    mapped = [
        (fields[0], fields[5])
        for line in (proc / "maps").read_text().splitlines()
        if len(fields := line.split(maxsplit=5)) == 6
        and re.search(r"/libapp[.]so(?: \(deleted\))?$", fields[5])
    ]
    loaded = {path for _, path in mapped}
    if (str(live_exe).endswith(" (deleted)")
            or loaded != {str(live_exe.parent / "lib/libapp.so")}
            or sha256(proc / "exe") != expected["remya_bar"]
            or bundle_hashes(live_exe.parent) != expected):
        raise RuntimeError("The running process does not match the expected release bundle")
    return tuple(region for region, _ in mapped)


def write_json(path, value):
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")


def stop(process):
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()


@contextmanager
def isolated_bar(bundle, log, *, trace=False):
    with tempfile.TemporaryDirectory(prefix="remya-bar-benchmark-") as directory:
        scratch = Path(directory)
        config = scratch / "bus.conf"
        config.write_text(BUS_CONFIG, encoding="utf-8")
        with subprocess.Popen(
            ["dbus-daemon", f"--config-file={config}", "--nofork", "--print-address=1"],
            stdout=subprocess.PIPE, text=True,
        ) as bus:
            try:
                address = bus.stdout.readline().strip()
                if not address:
                    raise RuntimeError("Private session bus did not start")
                env = {**os.environ, "DBUS_SESSION_BUS_ADDRESS": address,
                       "XDG_STATE_HOME": str(scratch / "state"),
                       "REMYA_BAR_BENCHMARK": "1" if trace else "0"}
                with subprocess.Popen([bundle / "remya_bar"], env=env, stdout=log, stderr=log) as process:
                    try:
                        yield process, env
                    finally:
                        stop(process)
            finally:
                stop(bus)


def wait_for(process, check, interval):
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"Bar exited with code {process.returncode}")
        result = check()
        if result:
            return result
        time.sleep(interval)
    raise RuntimeError("Timed out waiting for the test window")
