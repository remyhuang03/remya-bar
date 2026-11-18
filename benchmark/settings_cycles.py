#!/usr/bin/env python3
"""Compare Settings window mapping and closing using isolated release instances."""

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

from desktop import RUNS, bundle_hashes, command, hyprland, process_start, run_id, topology, verify_bundle, write_json
from proc_sampler import PidScope, positive_float
from summarize import describe

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


def own_settings(clients, pid):
    return next((client for client in clients if client.get("pid") == pid
                 and client.get("class") == "top.remya.bar"
                 and client.get("title") == "Remy'a Bar Settings"
                 and client.get("mapped", True)), None)


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


def measure(bundle, expected, outputs, options):
    binary = str(bundle / "remya_bar")
    with tempfile.TemporaryDirectory(prefix="remya-bar-benchmark-") as directory:
        scratch = Path(directory)
        config = scratch / "bus.conf"
        config.write_text(BUS_CONFIG)
        with subprocess.Popen(["dbus-daemon", f"--config-file={config}", "--nofork", "--print-address=1"],
                              stdout=subprocess.PIPE, text=True) as bus, tempfile.TemporaryFile(mode="w+t") as log:
            try:
                address = bus.stdout.readline().strip()
                if not address:
                    raise RuntimeError("Private session bus did not start")
                env = {**os.environ, "DBUS_SESSION_BUS_ADDRESS": address,
                       "XDG_STATE_HOME": str(scratch / "state"), "REMYA_BAR_BENCHMARK": "1"}
                with subprocess.Popen([binary], env=env, stdout=log, stderr=log) as process:
                    try:
                        samples, checkpoints = run_cycles(process, binary, env, expected, outputs, options)
                    finally:
                        process.terminate()
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            process.kill()
            finally:
                bus.terminate()
            log.seek(0)
            trace = [line.split("remya-bar-benchmark ", 1)[1].strip()
                     for line in log if "remya-bar-benchmark " in line]
    return {"sha256": expected, "first": samples[0], "warm": samples[1:],
            "warm_mapping_ms": describe([sample["mapping_ms"] for sample in samples[1:]]),
            "warm_close_ms": describe([sample["close_ms"] for sample in samples[1:]]),
            "memory": checkpoints, "native_trace": trace}


def run_cycles(process, binary, env, expected, outputs, options):
    pid = process.pid
    identity = process_start(pid)
    scope = PidScope(pid)

    def each_output_has_bar():
        layers = hyprland("layers")
        return all(
            any(entry.get("pid") == pid and entry.get("namespace") == "top.remya.bar"
                for entry in layers.get(output["name"], {}).get("levels", {}).get("2", []))
            for output in outputs
        )

    wait_for(process, each_output_has_bar, options.interval)
    verify_bundle(pid, expected)
    samples = []
    checkpoints = {}
    for index in range(options.warm_cycles + 1):
        if index % 10 == 0:
            print(f"{Path(binary).parent} · cycle {index}/{options.warm_cycles}", file=sys.stderr)
        start = time.monotonic()
        subprocess.run([binary, "--settings", "layout"], env=env, timeout=10, check=True)
        client = wait_for(process, lambda: own_settings(hyprland("clients"), pid), options.interval)
        mapping_ms = (time.monotonic() - start) * 1000
        address = client["address"]
        if not re.fullmatch(r"0x[0-9a-fA-F]+", address) or process_start(pid) != identity:
            raise RuntimeError("Test window identity changed")
        time.sleep(options.hold)
        start = time.monotonic()
        if not any(client.get("pid") == pid and client.get("address") == address
                   for client in hyprland("clients")):
            raise RuntimeError("Test window closed before the requested action")
        if command("hyprctl", "dispatch", f'hl.dsp.window.close({{window = "address:{address}"}})') != "ok":
            raise RuntimeError("Hyprland did not accept test window close")
        wait_for(process, lambda: own_settings(hyprland("clients"), pid) is None, options.interval)
        samples.append({"cycle": index, "mapping_ms": mapping_ms,
                        "close_ms": (time.monotonic() - start) * 1000})
        time.sleep(options.hold)
        if index in {1, 10, 50, options.warm_cycles}:
            readings = scope.read(memory_due=True)
            checkpoints[str(index)] = {key: readings[key] for key in
                                       ("pss_kib", "fd_count", "threads", "errors")}
    if topology() != outputs or process_start(pid) != identity:
        raise RuntimeError("Topology or test process changed during the trial")
    return samples, checkpoints


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", type=run_id, required=True)
    parser.add_argument("--baseline", type=Path, required=True, help="Baseline release bundle directory")
    parser.add_argument("--candidate", type=Path, required=True, help="Candidate release bundle directory")
    parser.add_argument("--warm-cycles", type=int, default=100)
    parser.add_argument("--hold", type=positive_float, default=2, help="Seconds open and seconds closed")
    parser.add_argument("--interval", type=positive_float, default=0.025, help="Hyprland observation interval in seconds")
    options = parser.parse_args()
    if options.warm_cycles < 1:
        parser.error("--warm-cycles must be positive")
    output = RUNS / f"{options.run_id}.json"
    if output.exists():
        parser.error("Result already exists")
    outputs = topology()
    if len(outputs) != 3:
        parser.error("Run on the benchmark workstation with all three displays enabled")
    variants = [options.baseline.resolve(), options.candidate.resolve()]
    hashes = [bundle_hashes(path) for path in variants]
    if hashes[0] == hashes[1]:
        parser.error("Baseline and candidate bundles are identical")
    data = {
        "scenario": "S06-settings",
        "outputs": outputs,
        "timing": "Command invocation to observed Hyprland mapping; includes IPC, polling and scheduling",
        "environment": "Private session bus and application state; no real Core or tray fixtures",
        "interval_s": options.interval,
        "hold_s": options.hold,
        "warm_cycles": options.warm_cycles,
    }
    for label, path, expected in zip(("baseline", "candidate"), variants, hashes):
        data[label] = measure(path, expected, outputs, options)
    RUNS.mkdir(exist_ok=True)
    write_json(output, data)
    print(output)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        raise SystemExit(130) from None
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error)) from None
