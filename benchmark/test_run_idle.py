import argparse
import unittest

from desktop import run_id
from run_idle import verify_summary


class RunIdleTest(unittest.TestCase):
    def test_output_directory_name_stays_in_runs(self):
        self.assertEqual(run_id("candidate-triple-01"), "candidate-triple-01")
        for value in (".", "..", "../outside", "contains spaces"):
            with self.subTest(value=value), self.assertRaises(argparse.ArgumentTypeError):
                run_id(value)

    def test_unusable_measurement_does_not_count_as_completed(self):
        summary = {
            "run_status": "complete",
            "pids": {"bar": {
                "cpu": {"sufficient_coverage": True},
                "memory": {"pss_mib": {"sample_count": 59}},
            }},
        }
        with self.assertRaisesRegex(RuntimeError, "PSS"):
            verify_summary(summary, 600)
        summary["pids"]["bar"]["memory"]["pss_mib"]["sample_count"] = 60
        verify_summary(summary, 600)
