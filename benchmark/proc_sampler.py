#!/usr/bin/env python3
"""Read-only Linux process/cgroup sampler. Python standard library only.

This measures specified processes, optional cgroups, and the collector itself.
It does not measure GPU allocations, display presentation, or input-to-photon.
No target settings are changed; nothing is installed; no environment is dumped.
Warm-up is recorded normally and excluded later with summarize.py --start.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import os
from pathlib import Path
import re
import sys
import time
from typing import Any

VERSION = 1
NAME_PATTERN = re.compile(r"^[A-Za-z0-9_.-]{1,64}$")


def parse_pid_stat(text: str) -> dict[str, Any]:
    """Parse /proc/PID/stat without splitting comm (which can contain ')')."""
    left = text.find("(")
    right = text.rfind(")")
    if left < 1 or right <= left:
        raise ValueError("malformed stat comm")
    pid = int(text[:left].strip())
    fields = text[right + 1 :].split()
    if len(fields) < 20:
        raise ValueError("stat has too few fields")
    # fields[0] is the documented field 3 (state).
    user_ticks = int(fields[11])
    system_ticks = int(fields[12])
    return {
        "pid": pid,
        "state": fields[0],
        "cpu_user_ticks": user_ticks,
        "cpu_system_ticks": system_ticks,
        "cpu_ticks": user_ticks + system_ticks,
        "threads": int(fields[17]),
        "starttime_ticks": int(fields[19]),
    }


def parse_smaps_rollup(text: str) -> dict[str, int | None]:
    keys = {
        "Pss": "pss_kib",
        "Rss": "rss_kib",
        "Private_Clean": "private_clean_kib",
        "Private_Dirty": "private_dirty_kib",
        "SwapPss": "swap_pss_kib",
        "Pss_Anon": "pss_anon_kib",
        "Pss_File": "pss_file_kib",
        "Pss_Shmem": "pss_shmem_kib",
    }
    output: dict[str, int | None] = {value: None for value in keys.values()}
    for line in text.splitlines():
        key, separator, rest = line.partition(":")
        if separator and key in keys:
            fields = rest.split()
            if len(fields) != 2 or fields[1] != "kB":
                raise ValueError("unexpected smaps unit or format")
            output[keys[key]] = int(fields[0])
    clean = output["private_clean_kib"]
    dirty = output["private_dirty_kib"]
    output["private_kib"] = (
        clean + dirty if clean is not None and dirty is not None else None
    )
    return output


def error_tag(operation: str, error: Exception) -> str:
    """Stable error metadata; do not dump arbitrary file contents."""
    errno = getattr(error, "errno", None)
    suffix = f":errno={errno}" if errno is not None else ""
    return f"{operation}:{type(error).__name__}{suffix}"


def timed_read(path: Path) -> tuple[str, int, int]:
    before = time.monotonic_ns()
    text = path.read_text(encoding="utf-8", errors="strict")
    after = time.monotonic_ns()
    return text, (before + after) // 2, after - before


class PidScope:
    def __init__(self, pid: int):
        self.pid = pid
        self.expected_start: int | None = None

    def read(self, memory_due: bool) -> dict[str, Any]:
        result: dict[str, Any] = {
            "pid": self.pid,
            "starttime_ticks": self.expected_start,
            "identity_ok": False,
            "cpu_observed_ns": None,
            "cpu_ticks": None,
            "memory_observed_ns": None,
            "pss_kib": None,
            "rss_kib": None,
            "private_kib": None,
            "swap_pss_kib": None,
            "threads": None,
            "fd_count": None,
            "memory_attempted": memory_due,
            "errors": [],
        }
        base = Path("/proc") / str(self.pid)
        try:
            raw, observed_ns, _ = timed_read(base / "stat")
            stat = parse_pid_stat(raw)
            if stat["pid"] != self.pid:
                raise ValueError("stat pid mismatch")
        except (OSError, ValueError, UnicodeError) as error:
            result["errors"].append(error_tag("stat", error))
            return result

        if self.expected_start is None:
            self.expected_start = stat["starttime_ticks"]
        if stat["starttime_ticks"] != self.expected_start:
            result["errors"].append("pid_identity_changed")
            result["observed_starttime_ticks"] = stat["starttime_ticks"]
            return result
        if stat["state"] in {"Z", "X", "x"}:
            result["errors"].append("target_exited_or_zombie")
            return result

        result.update(stat)
        result["identity_ok"] = True
        result["cpu_observed_ns"] = observed_ns
        if memory_due:
            try:
                raw, memory_ns, duration_ns = timed_read(base / "smaps_rollup")
                result.update(parse_smaps_rollup(raw))
                result["memory_observed_ns"] = memory_ns
                result["smaps_read_wall_ns"] = duration_ns
                if result["pss_kib"] is None:
                    result["errors"].append("smaps_missing_pss")
            except (OSError, ValueError, UnicodeError) as error:
                result["errors"].append(error_tag("smaps_rollup", error))
            try:
                result["fd_count"] = sum(1 for _ in (base / "fd").iterdir())
            except OSError as error:
                result["errors"].append(error_tag("fd", error))

            # smaps/FD reads can race with exit/reuse. Discard the whole sample
            # if it no longer belongs to the original process.
            try:
                after = parse_pid_stat((base / "stat").read_text())
                if (
                    after["starttime_ticks"] != self.expected_start
                    or after["state"] in {"Z", "X", "x"}
                ):
                    raise ValueError("identity changed during collection")
            except (OSError, ValueError, UnicodeError) as error:
                result = {
                    "pid": self.pid,
                    "starttime_ticks": self.expected_start,
                    "identity_ok": False,
                    "cpu_observed_ns": None,
                    "cpu_ticks": None,
                    "memory_observed_ns": None,
                    "pss_kib": None,
                    "rss_kib": None,
                    "private_kib": None,
                    "swap_pss_kib": None,
                    "threads": None,
                    "fd_count": None,
                    "memory_attempted": memory_due,
                    "errors": [error_tag("identity_check", error)],
                }
        return result


class CgroupScope:
    def __init__(self, path: Path):
        self.path = path
        self.expected_identity: tuple[int, int] | None = None

    def read(self) -> dict[str, Any]:
        result: dict[str, Any] = {
            "identity_ok": False,
            "cgroup_identity": None,
            "cpu_observed_ns": None,
            "cpu_usage_usec": None,
            "cpu_user_usec": None,
            "cpu_system_usec": None,
            "memory_observed_ns": None,
            "memory_current_bytes": None,
            "errors": [],
        }
        try:
            stat = self.path.stat()
            identity = (stat.st_dev, stat.st_ino)
            if self.expected_identity is None:
                self.expected_identity = identity
            if identity != self.expected_identity:
                result["errors"].append("cgroup_identity_changed")
                return result
            result["cgroup_identity"] = list(identity)
            result["identity_ok"] = True
        except OSError as error:
            result["errors"].append(error_tag("cgroup_stat", error))
            return result
        try:
            raw, observed_ns, _ = timed_read(self.path / "cpu.stat")
            fields = dict(line.split() for line in raw.splitlines() if line.strip())
            result["cpu_usage_usec"] = int(fields["usage_usec"])
            result["cpu_user_usec"] = int(fields["user_usec"]) if "user_usec" in fields else None
            result["cpu_system_usec"] = int(fields["system_usec"]) if "system_usec" in fields else None
            result["cpu_observed_ns"] = observed_ns
        except (OSError, ValueError, KeyError, UnicodeError) as error:
            result["errors"].append(error_tag("cpu.stat", error))
        try:
            raw, observed_ns, _ = timed_read(self.path / "memory.current")
            result["memory_current_bytes"] = int(raw.strip())
            result["memory_observed_ns"] = observed_ns
        except (OSError, ValueError, UnicodeError) as error:
            result["errors"].append(error_tag("memory.current", error))
        try:
            after = self.path.stat()
            if (after.st_dev, after.st_ino) != identity:
                raise ValueError("cgroup identity changed during collection")
        except (OSError, ValueError) as error:
            for key in (
                "cpu_observed_ns", "cpu_usage_usec", "cpu_user_usec", "cpu_system_usec",
                "memory_observed_ns", "memory_current_bytes",
            ):
                result[key] = None
            result["identity_ok"] = False
            result["errors"].append(error_tag("cgroup_identity_check", error))
        return result


def parse_named(value: str) -> tuple[str, str]:
    name, separator, target = value.partition("=")
    if not separator or not NAME_PATTERN.fullmatch(name) or not target:
        raise argparse.ArgumentTypeError("expected NAME=VALUE; NAME uses A-Z a-z 0-9 _ . -")
    return name, target


def positive_float(value: str) -> float:
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError("must be finite and greater than zero")
    return number


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", action="append", type=parse_named, default=[], metavar="NAME=PID")
    parser.add_argument("--cgroup", action="append", type=parse_named, default=[], metavar="NAME=PATH")
    parser.add_argument("--duration", type=positive_float, default=600.0, help="seconds, including any warm-up")
    parser.add_argument("--interval", type=positive_float, default=1.0, help="CPU/cgroup sampling period, seconds")
    parser.add_argument("--memory-interval", type=positive_float, default=10.0, help="PID smaps/FD sampling period, seconds")
    parser.add_argument("--run-id", default="unspecified")
    parser.add_argument("--scenario", default="unspecified")
    parser.add_argument("--output", type=Path, required=True, help="new JSONL file; existing files are not overwritten")
    args = parser.parse_args()
    if not args.pid and not args.cgroup:
        parser.error("specify at least one --pid or --cgroup")
    if args.interval < 0.05 or args.memory_interval < args.interval:
        parser.error("--interval must be >= 0.05; --memory-interval must be >= --interval")

    pids: dict[str, PidScope] = {}
    for name, raw in args.pid:
        if name in pids or not raw.isdecimal() or int(raw) <= 0:
            parser.error("duplicate PID scope name or invalid PID")
        pids[name] = PidScope(int(raw))
    cgroups: dict[str, CgroupScope] = {}
    for name, raw in args.cgroup:
        path = Path(raw)
        if name in cgroups or not path.is_absolute():
            parser.error("duplicate cgroup scope name or cgroup path is not absolute")
        cgroups[name] = CgroupScope(path)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    try:
        output = args.output.open("x", encoding="utf-8")
    except OSError as error:
        parser.error(f"cannot create output: {error}")
    start_ns = time.monotonic_ns()
    own_cpu_start_ns = time.process_time_ns()
    period_ns = int(args.interval * 1e9)
    memory_period_ns = int(args.memory_interval * 1e9)
    deadline_ns = start_ns
    end_ns = start_ns + int(args.duration * 1e9)
    next_memory_ns = start_ns
    sample_count = 0
    status = "complete"

    def emit(value: dict[str, Any]) -> None:
        output.write(json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False) + "\n")
        output.flush()

    with output:
        emit({
            "kind": "metadata",
            "schema_version": VERSION,
            "run_id": args.run_id,
            "scenario": args.scenario,
            "started_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
            "monotonic_start_ns": start_ns,
            "clock": "CLOCK_MONOTONIC; Linux suspend time is excluded",
            "clock_ticks_per_second": os.sysconf("SC_CLK_TCK"),
            "requested_duration_s": args.duration,
            "interval_s": args.interval,
            "memory_interval_s": args.memory_interval,
            "cpu_percent_basis": "100 percent = one logical CPU",
            "pids": {name: scope.pid for name, scope in pids.items()},
            "cgroups": {name: str(scope.path) for name, scope in cgroups.items()},
            "collector_pid": os.getpid(),
            "collector_cpu_baseline_ns": own_cpu_start_ns,
            "limitations": [
                "No GPU or presentation measurement",
                "PSS sampling can miss short memory peaks and short-lived children",
                "Cgroup accounting and PID accounting overlap; do not sum them",
                "Collector CPU does not include all induced system/compositor overhead",
                "No view/engine counts: application instrumentation is required",
            ],
        })
        try:
            while True:
                remaining = deadline_ns - time.monotonic_ns()
                while remaining > 0:
                    # Short waits allow signals; never perform a long blocking sleep.
                    time.sleep(min(remaining / 1e9, 1.0))
                    remaining = deadline_ns - time.monotonic_ns()
                read_start_ns = time.monotonic_ns()
                memory_due = read_start_ns >= next_memory_ns
                if memory_due:
                    next_memory_ns = (
                        start_ns + ((read_start_ns - start_ns) // memory_period_ns + 1) * memory_period_ns
                    )
                pid_values = {name: scope.read(memory_due) for name, scope in pids.items()}
                cgroup_values = {name: scope.read() for name, scope in cgroups.items()}
                read_end_ns = time.monotonic_ns()
                emit({
                    "kind": "sample",
                    "index": sample_count,
                    "monotonic_ns": read_start_ns,
                    "elapsed_s": (read_start_ns - start_ns) / 1e9,
                    "schedule_lag_ns": max(0, read_start_ns - deadline_ns),
                    "collection_wall_ns": read_end_ns - read_start_ns,
                    "collector_cpu_total_ns": time.process_time_ns() - own_cpu_start_ns,
                    "collector_observed_ns": read_end_ns,
                    "pids": pid_values,
                    "cgroups": cgroup_values,
                })
                sample_count += 1
                if read_end_ns >= end_ns:
                    break
                now_ns = time.monotonic_ns()
                next_regular = start_ns + ((now_ns - start_ns) // period_ns + 1) * period_ns
                deadline_ns = min(next_regular, end_ns)
        except KeyboardInterrupt:
            status = "interrupted"
        finally:
            emit({
                "kind": "end",
                "status": status,
                "sample_count": sample_count,
                "monotonic_ns": time.monotonic_ns(),
                "collector_cpu_total_ns": time.process_time_ns() - own_cpu_start_ns,
            })
    print(f"Wrote {sample_count} samples to {args.output} ({status}).", file=sys.stderr)
    return 130 if status == "interrupted" else 0


if __name__ == "__main__":
    raise SystemExit(main())
