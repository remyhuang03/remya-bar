# Benchmark Guidelines

Use the workstation's three-display Hyprland session for future Remy'a Bar
benchmarks. Verify the topology before each run and record the observed modes,
refresh rates, scales, and logical positions with the result.

| Connector | Mode | Refresh (Hz) | Scale | Logical origin |
| --- | --- | --- | --- | --- |
| eDP-1 | 2560 × 1600 | 120.000 | 1.6 | (1, 1296) |
| DP-3 | 3840 × 2160 | 120.006 | 1.6666666 | (0, 0) |
| DP-1 | 1920 × 1080 | 60.000 | 1.3333334 | (1601, 1296) |

All three displays were unrotated with VRR disabled when recorded on
2026-11-18 (Asia/Taipei). Label any different topology explicitly.

Discard interrupted runs. Retain failed or erroneous attempts only when the
evidence can be reused, such as a reproducible regression, and describe why
it was retained. Keep successful raw samples and corresponding summaries
together under the ignored `runs/` directory.
