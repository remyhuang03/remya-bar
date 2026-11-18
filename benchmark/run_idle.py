#!/usr/bin/env python3
"""Measure the installed Bar on the live Hyprland session without changing it."""

import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import time

from desktop import (
    RUNS, bundle_hashes, command, hyprland, process_start, run_id, sha256,
    topology, verify_bundle, write_json,
)
from proc_sampler import positive_float

ROOT = RUNS.parent.parent


def service(unit):
    properties = dict(
        line.split("=", 1)
        for line in command("systemctl", "--user", "show", unit,
                            "-p", "ActiveState", "-p", "MainPID", "-p", "ControlGroup").splitlines()
    )
    pid = int(properties["MainPID"])
    group = properties["ControlGroup"]
    if properties["ActiveState"] != "active" or pid <= 0 or not group.startswith("/"):
        raise RuntimeError(f"Service {unit} has no active process and cgroup")
    cgroup = Path("/sys/fs/cgroup") / group.lstrip("/")
    return pid, cgroup, process_start(pid), cgroup.stat().st_ino


def desktop_identity():
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    candidates = [instance["pid"] for instance in hyprland("instances")
                  if signature and instance["instance"] == signature]
    if len(candidates) != 1:
        raise RuntimeError("Run inside the active Hyprland session")
    hyprland_pid = candidates[0]
    return {
        "bar": service("top.remya.bar.service"),
        "core": service("top.remya.core.service"),
        "hyprland": (hyprland_pid, None, process_start(hyprland_pid), None),
    }


def revision(directory):
    diff = command("git", "diff", "--binary", "HEAD", cwd=directory)
    return {
        "head": command("git", "rev-parse", "HEAD", cwd=directory),
        "dirty": bool(command("git", "status", "--porcelain", cwd=directory)),
        "tracked_diff_sha256": hashlib.sha256(diff.encode()).hexdigest() if diff else None,
    }


def hardware():
    cpu = Path('/proc/cpuinfo').read_text()
    model = re.search(r'^model name\s*:\s*(.+)$', cpu, re.M)
    return {
        'cpu': model[1] if model else None,
        'logical_cpus': os.cpu_count(),
        'architecture': platform.machine(),
        'display_devices': [
            block.strip() for block in re.split(r'\n(?=\S)', command('lspci', '-Dnnk'))
            if re.search(r'\[(0300|0302|0380)\]', block.splitlines()[0])
        ] if shutil.which('lspci') else None,
        'ac_online': {path.parent.name: path.read_text().strip()
                      for path in Path('/sys/class/power_supply').glob('*/online')},
    }


def preference_hashes():
    if not shutil.which("remya"):
        return None
    return {
        key: hashlib.sha256(command("remya", "get", key).encode()).hexdigest()
        for key in ("theme", "accent", "remya-bar.layout", "remya-bar.clock-seconds",
                    "remya-bar.position", "remya-bar.ai-ring")
    }


def collect(raw, identity, options):
    duration = options.preheat_seconds + options.measure_seconds
    args = [sys.executable, str(RUNS.parent / "proc_sampler.py"), "--output", str(raw),
            "--run-id", options.run_id, "--scenario", options.scenario, "--duration", str(duration)]
    for name, (pid, cgroup, _, _) in identity.items():
        args.extend(["--pid", f"{name}={pid}"])
        if cgroup:
            args.extend(["--cgroup", f"{name}={cgroup}"])
    started = time.monotonic()
    with subprocess.Popen(args) as child:
        try:
            while True:
                elapsed = time.monotonic() - started
                phase = "preheat" if elapsed < options.preheat_seconds else "measure"
                print(f"{phase} · {elapsed:.0f}/{duration:.0f} s", file=sys.stderr)
                try:
                    if child.wait(timeout=30) != 0:
                        raise RuntimeError("The collector did not finish")
                    break
                except subprocess.TimeoutExpired:
                    continue
        except KeyboardInterrupt:
            child.terminate()
            raise
    return duration


def verify_summary(summary, measure):
    if summary["run_status"] != "complete":
        raise RuntimeError("Run did not complete")
    bar = summary["pids"]["bar"]
    if not bar["cpu"]["sufficient_coverage"]:
        raise RuntimeError("Insufficient Bar CPU coverage")
    if bar["memory"]["pss_mib"]["sample_count"] < int(measure / 10):
        raise RuntimeError("Insufficient Bar PSS samples")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", type=run_id, required=True)
    parser.add_argument("--bundle-dir", type=Path, required=True)
    parser.add_argument("--preheat-seconds", type=positive_float, default=300)
    parser.add_argument("--measure-seconds", type=positive_float, default=600)
    parser.add_argument("--scenario", default="S03-live")
    parser.add_argument("--source-note", help="Release provenance or fixture label")
    options = parser.parse_args()

    expected = bundle_hashes(options.bundle_dir.resolve())
    identity = desktop_identity()
    mapping = verify_bundle(identity["bar"][0], expected)
    before = topology()
    if len(before) != 3 and options.scenario == "S03-live":
        parser.error("S03-live expects three displays; use a distinct scenario for other topologies")
    preferences = preference_hashes()
    metadata = {
        "started_local": datetime.now().astimezone().isoformat(),
        "scenario": options.scenario,
        "source_note": options.source_note,
        "checkout": revision(ROOT),
        "core_checkout": revision(ROOT.parent / "remya-core"),
        "locks": {name: sha256(ROOT / name) for name in ("pubspec.lock", "Cargo.lock")},
        "bundle_sha256": expected,
        "preheat_seconds": options.preheat_seconds,
        "measure_seconds": options.measure_seconds,
        "exploratory": (options.preheat_seconds, options.measure_seconds) != (300, 600),
        "outputs": before,
        "hardware": hardware(),
        "preference_sha256": preferences,
        "locale": os.environ.get("LANG"),
        "kernel": platform.release(),
        "hyprland": command("hyprctl", "version").splitlines()[0],
    }
    trial = RUNS / options.run_id
    trial.mkdir(parents=True)
    try:
        write_json(trial / "metadata.json", metadata)
        duration = collect(trial / "raw.jsonl", identity, options)
        if topology() != before or desktop_identity() != identity:
            raise RuntimeError("Topology or process identity changed during sampling")
        if preference_hashes() != preferences:
            raise RuntimeError("Theme or Bar preferences changed during sampling")
        if verify_bundle(identity["bar"][0], expected) != mapping:
            raise RuntimeError("Bar re-executed during sampling")
        summary_path = trial / "summary.json"
        command(sys.executable, str(RUNS.parent / "summarize.py"), str(trial / "raw.jsonl"),
                "--start", str(options.preheat_seconds), "--end", str(duration),
                "--output", str(summary_path))
        verify_summary(json.loads(summary_path.read_text()), options.measure_seconds)
    except BaseException:
        shutil.rmtree(trial)
        raise
    print(trial)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        raise SystemExit(130) from None
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error)) from None
