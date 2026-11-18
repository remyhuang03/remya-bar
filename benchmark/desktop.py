"""Shared read-only helpers for the Hyprland desktop benchmarks."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

from proc_sampler import NAME_PATTERN, parse_pid_stat

RUNS = Path(__file__).resolve().parent / "runs"


def run_id(value):
    if not NAME_PATTERN.fullmatch(value) or value in {".", ".."}:
        raise argparse.ArgumentTypeError("expected 1–64 letters, digits, dots, hyphens or underscores")
    return value


def command(*args, cwd=None):
    return subprocess.check_output(args, cwd=cwd, text=True, timeout=10).strip()


def hyprland(query):
    return json.loads(command("hyprctl", "-j", query))


def topology():
    fields = ("name", "width", "height", "refreshRate", "scale", "x", "y", "transform", "vrr")
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
    loaded = sorted(set(
        fields[5]
        for line in (proc / "maps").read_text().splitlines()
        if len(fields := line.split(maxsplit=5)) == 6
        and re.search(r"/libapp[.]so(?: \(deleted\))?$", fields[5])
    ))
    if (str(live_exe).endswith(" (deleted)")
            or loaded != [str(live_exe.parent / "lib/libapp.so")]
            or sha256(proc / "exe") != expected["remya_bar"]
            or bundle_hashes(live_exe.parent) != expected):
        raise RuntimeError("The running process does not match the expected release bundle")


def write_json(path, value):
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")
