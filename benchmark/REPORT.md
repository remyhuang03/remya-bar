# Three-display performance report

Measured on 2026-11-18 (Asia/Taipei) with the three active displays in
[AGENTS.md](AGENTS.md). The workstation ran Arch Linux (kernel
7.3.4-arch1-2), Hyprland 0.57.2, and an Intel Core Ultra 7 255H with Intel
Arc and NVIDIA RTX 5060 graphics. Bar used Flutter 3.47.9. AC was connected.

The baseline is the previously installed release, identified by executable and
AOT hashes. The final release was built from application commit `305c342`
against Core checkout `c85db17`. The settings probe also tested the initial
single-engine build at `1e1e931` to check the effect of the follow-up changes.

## S03 · Live process resources

Each release had one 15-minute trial. The first five minutes were excluded.
Both ten-minute intervals had 100% CPU coverage and 60 PSS samples. The
three outputs kept the modes in AGENTS.md. This was the workstation's live
session with its existing settings and background workload. The before and
after runs were sequential, with one trial per release and no frozen fixture
for the other desktop applications.

| Metric | Previous release | Final release |
| --- | ---: | ---: |
| Bar PSS median (MiB) | 583.7 | 378.3 |
| Bar PSS p95 (MiB) | 615.4 | 381.9 |
| Bar PSS sampled max (MiB) | 630.1 | 386.5 |
| Bar RSS p95 (MiB) | 859.0 | 598.6 |
| Bar mean CPU (% of one core) | 25.70% | 12.22% |
| Bar 10-second CPU p95 | 30.90% | 14.30% |
| Bar service cgroup mean CPU | 31.16% | 14.98% |
| Bar service cgroup memory.current p95 (MiB) | 1,020.4 | 779.1 |
| Core mean CPU | 3.73% | 2.70% |
| Hyprland mean CPU | 9.84% | 6.74% |
| Sampling process mean CPU | 0.51% | 0.47% |

Bar PSS p95 fell 37.9% and mean CPU fell 52.4% in this comparison. The
candidate still exceeds the guide's provisional 340 MiB ceiling and 1.1%
mean CPU target for three displays. Cgroup CPU includes the Bar PID and any
helpers assigned to that service. Core and Hyprland figures reflect the shared
desktop workload. [Baseline summary](runs/baseline-triple-01/summary.json) ·
[Final summary](runs/candidate-triple-01/summary.json)

A separate ten-second user-space profile collected 93 samples during warm-up.
Dart AOT, NVIDIA EGL, the Bar Rust system library, and Flutter GTK each
accounted for at least 10% of those samples. This trace has library-level
resolution and was excluded from the steady-state interval.

## S06 · Settings window lifecycle

The first open was measured immediately after the fixture's three bar surfaces
registered. Each build then completed 100 warm cycles, using two seconds
open and two seconds closed. Each instance had a private bus and state root.
The probe timed command invocation to observed Hyprland mapping, including
process startup, IPC, and 25 ms polling. First-open values are single
observations.

| Metric | Previous release | Initial single engine | Final release |
| --- | ---: | ---: | ---: |
| First mapping (ms) | 1,061 | 526 | 506 |
| Warm mapping median (ms) | 185 | 218 | 185 |
| Warm mapping p95 (ms) | 227 | 242 | 223 |
| Warm close p95 (ms) | 50 | 47 | 45 |
| PSS after cycle 100 (MiB) | 339.9 | 179.6 | 190.8 |
| Open FDs after cycle 100 | 89 | 52 | 51 |

The final release recovered the warm mapping time observed in the previous
release. Its small p95 difference is below the observation interval. Native
events recorded one engine, 101 Settings views created, and 101 removed
during the final probe. The three bar views remained after the last close.
[First comparison](runs/settings-triple-01.json) ·
[Final repeat](runs/settings-triple-final-01.json)

## S09 · Notification burst

The final release completed 200 Notify calls in 9.95 s on an isolated D-Bus
session. Five replacements kept their IDs. The transient expiry and explicit
close emitted reasons 1 and 3, and the history retained the expected 193
entries. The toast was observed on eDP-1 at the burst checkpoints and had
closed by the 60-second follow-up. PSS at the four checkpoints was 109.1,
154.8, 168.8 and 157.1 MiB. These checkpoints describe the burst and recovery
window. [Raw S09 result](runs/candidate-notify-01.json)

## Correctness coverage

Flutter passed 150 tests and Rust passed 46. Clippy, Dart analysis, debug
and release builds, and native lifecycle tests passed. Hyprland checks
covered all three live surfaces, exclusive-space restoration, fullscreen
scoping, and a synthetic logind resume with notification-history recovery.
The installed bundle, command and desktop entry matched the tested release.
Settings requests forwarded to the installed service and closing the window
left that service running.

Remaining release checks include physical hotplug and resume, IME and avatar
dialog interaction, hardware input-to-photon latency, renderer and thread
policy comparisons, five matched idle pairs, and an eight-hour soak.
Unprivileged RAPL counters were unavailable and this session used AC. GPU
power and whole-system energy remain unmeasured.
