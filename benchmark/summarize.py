#!/usr/bin/env python3
"""Summarize proc_sampler JSONL without filling missing memory readings.

CPU is 100% per logical CPU. Invalid identities, counter reversals, missing
samples, and long sampling gaps break CPU segments. Valid short segments are
split at analysis/bucket boundaries using their interval-average rate. This is
explicit interpolation inside a measured short interval, never across a gap.
No performance pass/fail budget is inferred by this script.
"""

from __future__ import annotations

import argparse
from collections import Counter
import json
import math
from pathlib import Path
import statistics
import sys
from typing import Any


def quantile_nearest_rank(values: list[float], probability: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    return ordered[max(0, math.ceil(probability * len(ordered)) - 1)]


def describe(values: list[float]) -> dict[str, Any]:
    return {
        "sample_count": len(values),
        "min": min(values) if values else None,
        "median": statistics.median(values) if values else None,
        "p95": quantile_nearest_rank(values, 0.95),
        "p99": quantile_nearest_rank(values, 0.99),
        "max_sampled": max(values) if values else None,
    }


def describe_memory(points: list[tuple[float, float]]) -> dict[str, Any]:
    output = describe([value for _, value in points])
    output["first"] = points[0][1] if points else None
    output["last"] = points[-1][1] if points else None
    output["descriptive_ols_change_per_hour"] = None
    if len(points) >= 2:
        mean_t = statistics.fmean(t for t, _ in points)
        mean_y = statistics.fmean(y for _, y in points)
        denominator = sum((t - mean_t) ** 2 for t, _ in points)
        if denominator > 0:
            slope = sum((t - mean_t) * (y - mean_y) for t, y in points) / denominator
            output["descriptive_ols_change_per_hour"] = slope * 3600
    return output


def cpu_summary(
    points: list[tuple[float, float, Any] | None],
    start: float,
    end: float,
    max_gap: float,
    bucket_seconds: float,
    minimum_coverage: float,
) -> dict[str, Any]:
    """Points hold relative monotonic seconds, cumulative CPU seconds, identity."""
    rejected: Counter[str] = Counter()
    segments: list[tuple[float, float, float]] = []
    previous: tuple[float, float, Any] | None = None
    expected_identity: Any = None
    for point in points:
        if point is None:
            previous = None
            rejected["missing_or_invalid_sample_entire_recording"] += 1
            continue
        if expected_identity is None:
            expected_identity = point[2]
        if point[2] != expected_identity:
            if start <= point[0] <= end:
                rejected["identity_changed"] += 1
            previous = None
            continue
        if previous is not None:
            t0, c0, identity0 = previous
            t1, c1, identity1 = point
            dt = t1 - t0
            dc = c1 - c0
            reason = None
            if identity0 != identity1:
                reason = "identity_changed"
            elif dt <= 0:
                reason = "nonpositive_time_delta"
            elif dt > max_gap:
                reason = "sampling_gap"
            elif dc < 0:
                reason = "counter_reversed"
            if reason:
                if t1 >= start and t0 <= end:
                    rejected[reason] += 1
            else:
                a, b = max(start, t0), min(end, t1)
                if b > a:
                    segments.append((a, b, dc * (b - a) / dt))
        previous = point

    covered = sum(b - a for a, b, _ in segments)
    consumed = sum(cpu for _, _, cpu in segments)
    width = end - start
    bucket_count = int(math.floor(width / bucket_seconds + 1e-9))
    buckets = [{"start_s": start + i * bucket_seconds,
                "end_s": start + (i + 1) * bucket_seconds,
                "covered_s": 0.0, "cpu_time_s": 0.0}
               for i in range(bucket_count)]
    for a, b, cpu in segments:
        if not buckets:
            break
        first = max(0, int(math.floor((a - start) / bucket_seconds)))
        last = min(bucket_count - 1, int(math.floor((b - start) / bucket_seconds)))
        for index in range(first, last + 1):
            bucket = buckets[index]
            overlap = max(0.0, min(b, bucket["end_s"]) - max(a, bucket["start_s"]))
            if overlap:
                bucket["covered_s"] += overlap
                bucket["cpu_time_s"] += cpu * overlap / (b - a)
    eligible_values = []
    for bucket in buckets:
        coverage = min(1.0, bucket["covered_s"] / bucket_seconds)
        eligible = coverage >= minimum_coverage
        bucket["coverage_fraction"] = coverage
        bucket["eligible"] = eligible
        bucket["cpu_percent_one_core"] = (
            100 * bucket["cpu_time_s"] / bucket["covered_s"]
            if eligible and bucket["covered_s"] > 0 else None
        )
        if eligible:
            eligible_values.append(bucket["cpu_percent_one_core"])
    coverage = min(1.0, covered / width)
    return {
        "cpu_percent_one_core_mean": 100 * consumed / covered if covered > 0 else None,
        "cpu_time_s_observed": consumed,
        "valid_covered_s": covered,
        "requested_window_s": width,
        "coverage_fraction": coverage,
        "sufficient_coverage": coverage >= minimum_coverage,
        "max_accepted_interval_s": max_gap,
        "rejected_counts": dict(rejected),
        "nonoverlapping_window_s": bucket_seconds,
        "full_window_count": bucket_count,
        "eligible_window_count": len(eligible_values),
        "window_cpu_percent_p95": quantile_nearest_rank(eligible_values, 0.95),
        "window_cpu_percent_max": max(eligible_values) if eligible_values else None,
        "windows": buckets,
    }


def summarize(
    records: list[dict[str, Any]],
    start: float = 0,
    end: float | None = None,
    bucket_seconds: float = 10,
    max_gap: float | None = None,
    minimum_coverage: float = 0.99,
) -> dict[str, Any]:
    metadata_rows = [record for record in records if record.get("kind") == "metadata"]
    if len(metadata_rows) != 1:
        raise ValueError("expected exactly one metadata record")
    metadata = metadata_rows[0]
    if metadata.get("schema_version") != 1:
        raise ValueError("unsupported sampler schema version")
    samples = [record for record in records if record.get("kind") == "sample"]
    if not samples:
        raise ValueError("no samples")
    origin = int(metadata["monotonic_start_ns"])
    ticks_per_second = int(metadata["clock_ticks_per_second"])
    if ticks_per_second <= 0:
        raise ValueError("invalid clock tick rate")
    actual_end = max((int(sample["monotonic_ns"]) - origin) / 1e9 for sample in samples)
    if end is None:
        end = min(float(metadata["requested_duration_s"]), actual_end)
    if not all(math.isfinite(value) for value in (start, end, bucket_seconds, minimum_coverage)):
        raise ValueError("nonfinite analysis option")
    if start < 0 or end <= start or bucket_seconds <= 0 or not 0 < minimum_coverage <= 1:
        raise ValueError("invalid analysis window or coverage setting")
    if max_gap is None:
        max_gap = 1.75 * float(metadata["interval_s"])
    if not math.isfinite(max_gap) or max_gap <= 0:
        raise ValueError("invalid max gap")
    last_timestamp = None
    for sample in samples:
        timestamp = int(sample["monotonic_ns"])
        if last_timestamp is not None and timestamp <= last_timestamp:
            raise ValueError("samples are not in strictly increasing monotonic order")
        last_timestamp = timestamp

    result: dict[str, Any] = {
        "schema_version": 1,
        "run_id": metadata.get("run_id"),
        "scenario": metadata.get("scenario"),
        "analysis_window_start_s": start,
        "analysis_window_end_s": end,
        "available_samples_end_s": actual_end,
        "cpu_percent_basis": "100 percent = one logical CPU",
        "quantile_method": "nearest rank; median uses arithmetic midpoint for even n",
        "boundary_method": "proportional split of valid short CPU intervals; no interpolation across invalid samples/gaps",
        "memory_method": "only actual successful reads; no forward fill; max is sampled, not a guaranteed peak",
        "minimum_coverage": minimum_coverage,
        "run_status": "missing_end_record",
        "pids": {},
        "cgroups": {},
        "warnings": [
            "No GPU allocations, wakeups, per-view frames, or end-to-end presentation are measured",
            "PID and cgroup CPU/memory scopes may overlap; do not add their totals",
            "Low sample counts do not support precise tail claims; all quantiles include counts",
            "OLS memory trend is descriptive and does not establish or exclude a leak",
            "Collector self CPU omits overhead induced in the kernel or target",
            "Averages with insufficient coverage must not be used to pass performance gates",
        ],
    }
    endings = [record for record in records if record.get("kind") == "end"]
    if endings:
        result["run_status"] = endings[-1].get("status", "unknown")

    for group in ("pids", "cgroups"):
        names = set(metadata.get(group, {}))
        for sample in samples:
            names.update(sample.get(group, {}))
        for name in sorted(names):
            points: list[tuple[float, float, Any] | None] = []
            errors: Counter[str] = Counter()
            memory: dict[str, list[tuple[float, float]]] = {}
            counts: dict[str, list[float]] = {"threads": [], "fd_count": []}
            fields = ({"pss_kib": ("pss_mib", 1024),
                       "rss_kib": ("rss_mib", 1024),
                       "private_kib": ("private_mib", 1024),
                       "swap_pss_kib": ("swap_pss_mib", 1024),
                       "pss_anon_kib": ("pss_anon_mib", 1024),
                       "pss_file_kib": ("pss_file_mib", 1024),
                       "pss_shmem_kib": ("pss_shmem_mib", 1024)}
                      if group == "pids" else
                      {"memory_current_bytes": ("memory_current_mib", 1048576)})
            memory = {label: [] for label, _ in fields.values()}
            for sample in samples:
                value = sample.get(group, {}).get(name)
                sample_time = (int(sample["monotonic_ns"]) - origin) / 1e9
                if not value:
                    points.append(None)
                    if start <= sample_time <= end:
                        errors["scope_missing"] += 1
                    continue
                if start <= sample_time <= end:
                    errors.update(value.get("errors", []))
                counter_key = "cpu_ticks" if group == "pids" else "cpu_usage_usec"
                counter = value.get(counter_key)
                observed = value.get("cpu_observed_ns")
                identity = ((value.get("pid"), value.get("starttime_ticks")) if group == "pids"
                            else tuple(value.get("cgroup_identity") or []))
                if value.get("identity_ok") and counter is not None and observed is not None:
                    divisor = ticks_per_second if group == "pids" else 1e6
                    points.append(((int(observed) - origin) / 1e9, counter / divisor, identity))
                else:
                    points.append(None)
                memory_observed = value.get("memory_observed_ns")
                if value.get("identity_ok") and memory_observed is not None:
                    memory_time = (int(memory_observed) - origin) / 1e9
                    if start <= memory_time <= end:
                        for key, (label, divisor) in fields.items():
                            number = value.get(key)
                            if number is not None:
                                memory[label].append((memory_time, number / divisor))
                if value.get("identity_ok") and start <= sample_time <= end:
                    for key in counts:
                        if value.get(key) is not None:
                            counts[key].append(float(value[key]))
            result[group][name] = {
                "target": metadata.get(group, {}).get(name),
                "cpu": cpu_summary(points, start, end, max_gap, bucket_seconds, minimum_coverage),
                "memory": {label: describe_memory(values) for label, values in memory.items()},
                "counts": {label: describe(values) for label, values in counts.items() if values},
                "errors_in_window": dict(errors),
            }

    own_points = []
    wall_values = []
    lag_values = []
    for sample in samples:
        own_ns = sample.get("collector_cpu_total_ns")
        observed_ns = sample.get("collector_observed_ns")
        if own_ns is not None and observed_ns is not None:
            own_points.append(((int(observed_ns) - origin) / 1e9, own_ns / 1e9, "collector"))
        else:
            own_points.append(None)
        sample_time = (int(sample["monotonic_ns"]) - origin) / 1e9
        if start <= sample_time <= end:
            if sample.get("collection_wall_ns") is not None:
                wall_values.append(sample["collection_wall_ns"] / 1e6)
            if sample.get("schedule_lag_ns") is not None:
                lag_values.append(sample["schedule_lag_ns"] / 1e6)
    result["collector"] = {
        "cpu": cpu_summary(own_points, start, end, max_gap, bucket_seconds, minimum_coverage),
        "collection_wall_ms": describe(wall_values),
        "schedule_lag_ms": describe(lag_values),
    }
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--start", type=float, default=0.0, help="exclude earlier warm-up, seconds after collection start")
    parser.add_argument("--end", type=float, help="stop analysis at this elapsed second")
    parser.add_argument("--bucket-seconds", type=float, default=10.0)
    parser.add_argument("--max-gap", type=float, help="longer CPU intervals are discarded; default 1.75 x sampling interval")
    parser.add_argument("--minimum-coverage", type=float, default=0.99)
    parser.add_argument("--output", type=Path, help="new summary JSON; default stdout")
    args = parser.parse_args()
    try:
        with args.input.open(encoding="utf-8") as stream:
            records = [json.loads(line) for line in stream if line.strip()]
        result = summarize(records, args.start, args.end, args.bucket_seconds,
                           args.max_gap, args.minimum_coverage)
        text = json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            with args.output.open("x", encoding="utf-8") as output:
                output.write(text)
            print(f"Wrote {args.output}.", file=sys.stderr)
        else:
            sys.stdout.write(text)
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
