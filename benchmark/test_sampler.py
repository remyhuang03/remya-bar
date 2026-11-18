#!/usr/bin/env python3
"""Targeted correctness checks, synthetic data plus a short collector smoke run.

These are tool tests, not measurements of remya-bar.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import proc_sampler
import summarize


def fake_stat(pid: int = 123, start: int = 456, comm: str = "test ) with (") -> str:
    fields = ["S"] + ["0"] * 49
    fields[11] = "120"       # utime
    fields[12] = "30"        # stime
    fields[13] = "9000"      # cutime must not be added
    fields[14] = "8000"      # cstime must not be added
    fields[17] = "4"         # num_threads
    fields[19] = str(start)  # starttime
    return f"{pid} ({comm}) " + " ".join(fields)


def synthetic_records() -> list[dict]:
    records = [{"kind": "metadata", "schema_version": 1,
                "monotonic_start_ns": 0, "clock_ticks_per_second": 100,
                "requested_duration_s": 20, "interval_s": 1,
                "pids": {"bar": 123}, "cgroups": {"bar": "/synthetic"}}]
    for second in range(21):
        memory_due = second % 10 == 0
        records.append({
            "kind": "sample", "monotonic_ns": second * 10**9,
            "collector_observed_ns": second * 10**9,
            "collector_cpu_total_ns": second * 10**6,
            "pids": {"bar": {"pid": 123, "starttime_ticks": 456,
                "identity_ok": True, "cpu_observed_ns": second * 10**9,
                "cpu_ticks": second * 100,
                "memory_observed_ns": second * 10**9 if memory_due else None,
                "pss_kib": (1024 + second) if memory_due else None,
                "errors": []}},
            "cgroups": {"bar": {"identity_ok": True, "cgroup_identity": [1, 2],
                "cpu_observed_ns": second * 10**9,
                "cpu_usage_usec": second * 10000,
                "memory_observed_ns": second * 10**9,
                "memory_current_bytes": 1048576,
                "errors": []}},
        })
    records.append({"kind": "end", "status": "complete"})
    return records


class SamplerTests(unittest.TestCase):
    def test_stat_handles_spaces_parentheses_and_excludes_children(self):
        parsed = proc_sampler.parse_pid_stat(fake_stat())
        self.assertEqual(parsed["pid"], 123)
        self.assertEqual(parsed["cpu_ticks"], 150)
        self.assertEqual(parsed["threads"], 4)
        self.assertEqual(parsed["starttime_ticks"], 456)

    def test_pid_reuse_is_not_silently_accepted(self):
        scope = proc_sampler.PidScope(123)
        with patch("proc_sampler.timed_read", side_effect=[
            (fake_stat(start=456), 1000, 1),
            (fake_stat(start=789), 2000, 1),
            (fake_stat(start=789), 3000, 1),
        ]):
            self.assertTrue(scope.read(False)["identity_ok"])
            for _ in range(2):
                reused = scope.read(False)
                self.assertFalse(reused["identity_ok"])
                self.assertIsNone(reused["cpu_ticks"])
                self.assertIn("pid_identity_changed", reused["errors"])

    def test_missing_memory_stays_null(self):
        parsed = proc_sampler.parse_smaps_rollup("Rss: 123 kB\n")
        self.assertEqual(parsed["rss_kib"], 123)
        self.assertIsNone(parsed["pss_kib"])
        self.assertIsNone(parsed["private_kib"])

    def test_pid_and_cgroup_one_core_cpu_units(self):
        result = summarize.summarize(synthetic_records())
        self.assertAlmostEqual(result["pids"]["bar"]["cpu"]["cpu_percent_one_core_mean"], 100)
        self.assertAlmostEqual(result["cgroups"]["bar"]["cpu"]["cpu_percent_one_core_mean"], 1)
        self.assertEqual(result["pids"]["bar"]["cpu"]["eligible_window_count"], 2)
        self.assertEqual(result["pids"]["bar"]["memory"]["pss_mib"]["sample_count"], 3)
        self.assertAlmostEqual(result["collector"]["cpu"]["cpu_percent_one_core_mean"], 0.1)

    def test_warmup_exclusion_and_no_memory_forward_fill(self):
        result = summarize.summarize(synthetic_records(), start=5, end=15)
        self.assertEqual(result["pids"]["bar"]["memory"]["pss_mib"]["sample_count"], 1)
        self.assertAlmostEqual(result["pids"]["bar"]["cpu"]["valid_covered_s"], 10)

    def test_missing_samples_and_gaps_are_not_bridged(self):
        points = [(0., 0., "id"), (1., 1., "id"), None,
                  (3., 3., "id"), (4., 4., "id")]
        result = summarize.cpu_summary(points, 0, 4, 1.75, 4, .99)
        self.assertAlmostEqual(result["valid_covered_s"], 2)
        self.assertAlmostEqual(result["cpu_percent_one_core_mean"], 100)
        self.assertFalse(result["sufficient_coverage"])
        self.assertIsNone(result["window_cpu_percent_p95"])
        result2 = summarize.cpu_summary([(0, 0, "id"), (3, 3, "id")], 0, 3, 1.75, 3, .99)
        self.assertEqual(result2["valid_covered_s"], 0)
        self.assertIsNone(result2["cpu_percent_one_core_mean"])

    def test_identity_change_invalidates_new_process_points(self):
        result = summarize.cpu_summary(
            [(0, 0, "old"), (1, 1, "old"), (2, 0, "new"), (3, 1, "new")],
            0, 3, 1.75, 3, .99)
        self.assertAlmostEqual(result["valid_covered_s"], 1)
        self.assertEqual(result["rejected_counts"]["identity_changed"], 2)

    def test_time_weighted_average_and_boundary_splitting(self):
        result = summarize.cpu_summary([(0, 0, "id"), (2, 1, "id"), (5, 4, "id")],
                                       0, 5, 4, 5, .99)
        self.assertAlmostEqual(result["cpu_percent_one_core_mean"], 80)
        clipped = summarize.cpu_summary([(0, 0, "id"), (2, 1, "id"), (5, 4, "id")],
                                        1, 4, 4, 3, .99)
        self.assertAlmostEqual(clipped["cpu_time_s_observed"], 2.5)
        self.assertAlmostEqual(clipped["valid_covered_s"], 3)

    def test_nonoverlapping_buckets(self):
        points = [(float(t), min(t, 10) * .1 + max(0, t - 10) * .2, "id")
                  for t in range(21)]
        result = summarize.cpu_summary(points, 0, 20, 1.75, 10, .99)
        self.assertAlmostEqual(result["cpu_percent_one_core_mean"], 15)
        self.assertAlmostEqual(result["windows"][0]["cpu_percent_one_core"], 10)
        self.assertAlmostEqual(result["windows"][1]["cpu_percent_one_core"], 20)
        self.assertAlmostEqual(result["window_cpu_percent_p95"], 20)

    def test_short_real_collector_smoke(self):
        # Target this test process, not remya-bar. Keep the run below one second.
        directory = Path(__file__).resolve().parent
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "smoke.jsonl"
            completed = subprocess.run([
                sys.executable, str(directory / "proc_sampler.py"),
                "--pid", f"test={os.getpid()}", "--duration", "0.6",
                "--interval", "0.2", "--memory-interval", "0.4",
                "--output", str(path),
            ], text=True, capture_output=True, timeout=10)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            records = [json.loads(line) for line in path.read_text().splitlines()]
            result = summarize.summarize(records, bucket_seconds=.2)
            self.assertEqual(result["run_status"], "complete")
            self.assertGreaterEqual(result["pids"]["test"]["memory"]["pss_mib"]["sample_count"], 1)
            self.assertIsNotNone(result["pids"]["test"]["cpu"]["cpu_percent_one_core_mean"])


if __name__ == "__main__":
    unittest.main()
