# Remy'a Bar benchmarks

[AGENTS.md](AGENTS.md) records the workstation's three-display topology.
Use the release bundle and keep the same features, display modes, power
profile and workload across repeats. Record changes in the trial notes.
Keep raw readings and summaries together in the ignored `runs/` directory.
The [workstation report](REPORT.md) records the completed release comparisons.

## S03 · Live three-display resource use

From the repository root, start one trial against the already installed,
running build.

```sh
python benchmark/run_idle.py --run-id candidate-triple-01 \
    --bundle-dir build/linux/x64/release/bundle
```

The runner verifies the installed executable and AOT bundle by SHA-256,
records the Bar, Core and Hyprland process identities, and rejects trials
with changed output topology, theme, Bar preferences or insufficient Bar
coverage. Preference values are hashed through the Core CLI. By default
it warms up for five minutes and measures the next ten minutes. It writes
`raw.jsonl`, `summary.json` and `metadata.json` in
`benchmark/runs/<run-id>/`. Use `--preheat-seconds` and
`--measure-seconds` for exploratory samples. Repeat five times per
variant for a release comparison.

CPU is the percentage of one logical core. PSS is in MiB and comes from
real `smaps_rollup` readings every ten seconds. PID CPU and cgroup CPU
overlap. Use cgroup CPU to include any helpers running in the service.
Keep profiler and recorder runs outside the idle comparison. The runner
does not change desktop configuration or services.

Recompute a ten-minute summary from an existing recording with
`python benchmark/summarize.py RAW_JSONL --start 300 --end 900`.
The standalone collector, `proc_sampler.py --help`, can also follow an
explicit test process or cgroup on another topology.

## S06 · Settings view open and close

```sh
python benchmark/settings_cycles.py --run-id settings-triple-01 \
    --baseline /path/to/baseline/bundle \
    --candidate build/linux/x64/release/bundle
```

Each variant starts a temporary Bar with a private session bus and state
directory. This uses the live compositor, temporarily reserves another bar
row, and opens Settings windows. There is no live Core or tray fixture in
the private session. The running installed Bar is left in place.

The probe records the first Settings open separately and then runs 100
warm cycles with two seconds open and two seconds closed. Use
`--warm-cycles` and `--hold` for short functional runs. Omit `--baseline`
to repeat a candidate trial. The probe measures
command invocation to the first observed Hyprland mapping, plus close
command to observed removal. Polling, command startup and compositor
scheduling are included. Native view lifecycle events, when available,
carry monotonic timestamps and cumulative live view counts. These are
separate from compositor presentation and hardware input latency.

## S09 · Notification burst

With Python D-Bus and PyGObject installed, run the fixture against an explicit
release bundle.

```sh
python benchmark/notification_burst.py --run-id candidate-notify-01 \
    --bundle-dir build/linux/x64/release/bundle
```

The private bus receives 200 calls at 20 per second, including replacements,
one transient expiry and one explicit close. The probe checks returned IDs,
closure reasons and the retained history after 60 seconds. It samples resource
use and observes toast surfaces at checkpoints. It uses temporary history and
sends no notifications to the installed session bus.

## Verification

```sh
python -m unittest discover -s benchmark -p 'test_*.py'
```

Report real output/scale changes, hardware resume, power and long-running
soak observations separately. `proc_sampler.py` excludes suspend time
from its monotonic sampling window. It does not read GPU allocation or
power counters.
