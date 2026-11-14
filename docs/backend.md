# Bar backend and Core integration

Remya Bar (`top.remya.bar`, executable `remya_bar`) owns its surfaces, preferences,
Hyprland IPC, notifications, tray, media controls, resources and keyboard. System
settings and shared appearance belong to the separately installed Remya Core.
The installer requires `dbus-1/services/top.remya.Core1.service` and orders
`top.remya.bar.service` after `top.remya.core.service`.

Core is the canonical reference for the [public API](../../remya-core/docs/public-api.md),
[XDG layout](../../remya-core/docs/xdg-layout.md),
[app preferences](../../remya-core/docs/app-preferences.md) and
[shared theme](../../remya-core/docs/app-preferences.md#shared-theme-toml).
Bar uses `remya_client` and `remya_ui`, never Settings implementation code.
Compiled bundles do not require sibling checkouts.

## Bar preferences and settings window

[linux/packaging/remya-bar.json](../linux/packaging/remya-bar.json) owns schemas,
defaults and pages (`layout`, `osd`, `notifications`, `ai-ring`). It is installed
at `$XDG_DATA_HOME/remya/apps/remya-bar.json`. `BarPreferences` accesses values
only through `AppPreferences('remya-bar')`; editors use revision-checked Replace.
Bar additionally validates pill uniqueness, center bounds, identifier UTF-8 byte
bounds and priority app uniqueness. Invalid values retain the last valid value
and revision. Conflicts are shown without retrying or silently repairing data.
Tray edits read a fresh value before Replace; sidebar edits use the displayed revision.

`remya_bar --settings [page]` forwards to the resident GApplication. The primary
creates a normal GTK toplevel on the warm popup engine with
`fl_view_new_for_engine`. `top.remya.bar/settings` carries `open({viewId, page})`,
`closed(viewId)` and Dart's `ready` handshake; bar engines request `open(page)`.
Repeated opens reuse the window and deliver a new request serial; an unknown or
empty page keeps the current page. Closing destroys only its view. The desktop
settings action uses `--settings`, accepting Core's OpenApp handoff.

The settings controller subscribes to Core changes and owner changes before
reading. Failed reads/writes retain valid values and expose Reload; a conflict
remains until that preference is reloaded or saved. Controls being saved are
disabled; dependent options hide when their parent is off.
System-page actions use `openRemyaSettings` and appear only when Settings' desktop
entry exists in an absolute XDG data root, rechecked at most every five seconds.

Release uses `SettingsThemeController.service`. Debug theme priority is Bar's
`config/config.local.toml`, Core's `config/shared/theme.toml`, then installed shared
theme. The runner supplies an absolute repository root independently of cwd,
including on the popup engine through `top.remya.paths`. Invalid themes retain
the last valid theme. The installer checks system Inter (`inter-font` on Arch).

## Hyprland IPC and output lifetime

`remya_bar_hyprland` owns request/event IPC and typed snapshots, exposed through
FRB 2.13.0 and `lib/features/hyprland/hyprland_backend.dart`. Regenerate with the
matching generator and `flutter_rust_bridge.yaml`; CMake bundles the library.
The empty core crate has no feature responsibility.

Following the [Hyprland IPC protocol](https://wiki.hypr.land/IPC/):

- Request sockets open per request and close on completion, failure or a two-second
  timeout. Replies must be UTF-8 and at most 8 MiB; idle connections are never retained.
- One process-wide event worker serves all output engines, reconnecting after one
  second. Newline framing preserves raw event data. Invalid or over-64-KiB frames
  fail the connection. The 256-update queue emits `resync` for lagging consumers.
- Updates carry `kind`, `name`, `data`; late engines receive current connection
  status. A one-second heartbeat releases closed subscriptions and is hidden by Dart.
- Paths require absolute XDG_RUNTIME_DIR and a single-component instance signature.
  There is no `/tmp/hypr` fallback. Transport uses Tokio; the GPL `hyprland` crate
  is incompatible with the dependency policy.

GTK maintains one bar per GDK monitor. Dart matches logical geometry against
Hyprland snapshots; ambiguous mirrored geometry is unavailable. Connector names
identify workspace ownership, never monitor indices. Coalesced event reads and
a two-second reconciliation recover missed workspace updates. Failed reads keep
valid state but hide the pill until recovery. Workspace actions target the owning
output; wheel uses monitor-relative `r±1`, Back toggles the special workspace,
and right click opens the overview. One shared worker observes Super every 100 ms.

Fullscreen clients on the active or open special workspace hide only their
output's bar, close its popups and release its exclusive zone. Leaving fullscreen
restores the same Flutter view and 40-pixel reservation. No connected outputs is
a supported state. Wake, output additions/removals and monitor-scale changes
trigger a debounced re-exec before destroying a disconnected engine: its EGL
display is shared with other views. Re-exec reloads Core preferences and saved
notification history.

## Popup transport

Use `BarTooltip` for hints: Flutter overlays cannot leave the bar's native
40-pixel surface. `BarPopup.show` sends `kind`, a view-local anchor, logical size,
component data and the Core theme; `BarPopupApp` renders content. GTK owns only
placement, focus policy, visibility and lifetime. Popup surfaces have zero
exclusive space and monitor-clamped bounds. gtk-layer-shell stays dynamically linked.

One shared popup engine starts with a realized, unmapped implicit GTK view.
`--remya-popup` runs a `ViewCollection` of explicit views, each with a channel
named by view ID. Native forwards actions to the owning bar view, which supplies
its theme. The engine stays warm after views close and runs no bar Rust event
subscription or Core controller; the settings window owns its own controllers.

Detail cards share one per-output slot. Native injects `data.pill: [x, width]`
in popup coordinates. Flutter draws the neck and animated shape while resize
measures full content, including neck and shadows. Media `cardSeed` makes pill
and card use the same artwork palette. Sidebar/tray openings hide and block cards.
Cards use an OVERLAY surface with ON_DEMAND focus; Escape hides immediately.

A view sends `ready` before native sends `content`. `opening: true` is used only
on mapping or kind changes; same-kind updates never replay emergence. After the
180 ms leave delay, native sends `dismiss`, waiting for `hidden` or a 400 ms
fallback. `enter` or another same-kind show cancels dismissal and resumes the
current progress; updates during retraction do not interrupt closing. Explicit
hide is immediate. `card.state` actions report kind/open; stale closes for other
kinds are ignored. Open pills track changed data, theme and anchor bounds,
including scrolling. Reduced motion jumps to animation endpoints.
Tooltips wait 500 ms and close on exit/disposal. Removing an output releases its
windows, views and channels without cooling the shared engine.

## Notifications and tray

`remya_bar_system` owns `org.freedesktop.Notifications` process-wide. Subscription
uses `DoNotQueue`, retries every five seconds when occupied, reports an error and
never replaces another daemon. Capabilities are `actions body body-markup
body-hyperlinks icon-static persistence`; ActivationToken is not sent.

IDs skip zero and live IDs; replacement updates in place. Images validate
rowstride and are capped at 128 px. Body markup allows only bold, italic,
underline and http/https/mailto links; malformed markup falls back to raw text.
The nonstandard `value` hint supplies progress. Timeout -1 uses Bar's configured
duration; zero and Critical never expire. Hover pauses timers. Expiry retains
history except for transient entries (reason 1); explicit close uses reason 3,
user dismissal reason 2. Actions close unless resident. History retains 200 items.

History and the next ID commit transactionally to
`$XDG_STATE_HOME/remya/bar/notifications.sqlite3` with absolute HOME fallback.
Transient entries stay in memory. Restored entries never replay popups, sounds
or actions belonging to the old daemon. Tests use isolated state roots and buses.
Bar notification preferences configure manual/scheduled/fullscreen Do Not Disturb;
Rust checks schedules every 30 seconds. Critical, priority-call and priority-app
notifications bypass suppression. Sound uses `canberra-gtk-play` unless disabled
or suppressed; replacements stay silent.

The bell toggles the left notification panel, mutually exclusive with the right
sidebar. Toasts use a separate non-focusable overlay. The focused output claims
the popup stack until empty, preventing duplicates across racing outputs; it hides
the stack while that output's notification panel is open.

The tray registers a StatusNotifierHost and supplies a watcher only if absent.
Outputs share bounded concurrent item reads. Passive/disconnected items hide;
icons validate ARGB or resolve through GTK. Menus load one level at a time with
AboutToShow/GetLayout and revalidate enabled leaf actions before Event. Activation,
secondary activation and scrolling target the current D-Bus owner. Without a
usable DBusMenu, ContextMenu remains available. XEmbed is unsupported.
Folded identities use SNI ID plus executable when available; all outputs follow
the same Bar preference. Outside clicks dismiss menus and consume the click.

## System controls, OSD and media

Sidebar sound, brightness, network, Bluetooth, power, night light, appearance and
account controls use Core's owning APIs. Core's feature documents define system
policy and permissions. Bar requests `power.idle-daemon start` on startup.
Do Not Disturb and sidebar layout remain Bar preferences.

Writes run FIFO; queued volume/brightness values coalesce per action and target.
Predictions reconcile with confirmed results, and refresh reads wait for the
queue to drain. Volume respects the Bar ceiling (100–150%); zero also mutes,
audible levels unmute, and unmuting silence restores one step. Brightness crosses
from hardware's 1% floor into software gamma, clearing gamma before increasing
hardware. Sliders throttle to 60 ms, send release values and hold them until
readback catches up or 1.5 seconds pass. Errors retain observed state.

OSD follows Core change signals, reloads its baseline on reconnect/output changes,
and shows confirmed values only. Hardware brightness feedback targets that output;
volume/gamma target the focused output. Its overlay has no focus or input region.
Shortcuts at `/top/remya/bar`, interface `top.remya.bar.Shortcuts`, are VolumeUp,
VolumeDown, VolumeMute, BrightnessUp, BrightnessDown and ToggleSidebar. Repeats
coalesce without skipping the hardware/gamma boundary. Signals are scoped to the
current Hyprland instance. To bind the sidebar manually:

```lua
hl.bind("SUPER + A", hl.dsp.exec_cmd(
    'gdbus emit --session --object-path /top/remya/bar --signal top.remya.bar.Shortcuts.ToggleSidebar "$HYPRLAND_INSTANCE_SIGNATURE"'))
```

Session actions use logind. Suspend, log out, reboot and shutdown require a second
click within three seconds. Capture tiles launch `remya_screen_capture` with no
arguments, `--record` or `--color-picker`, using debug or installed resolution.

MPRIS signals coalesce for 25 ms; position refreshes each second while playing.
Player selection is shared across outputs; reconnects use bounded backoff and
unchanged snapshots are suppressed. Optimistic playback expires after two seconds
or rolls back on failure. Seek validates capabilities, unique owner and track ID.
Media artwork supplies the pill/card palette. Optional marquee runs at 20 Hz and
pauses while the keyboard is visible. Core owns output-device volume writes.

## Local observations and keyboard

The clock reads wall time on aligned second boundaries and releases its timer
with its output view. The datetime card browses months independently of live time;
its Settings action uses the public opener. Seconds visibility is a Bar preference.
Battery/resource samples are shared across engines; only system batteries count.
Low charge takes precedence over energy-saver color. Battery policy comes from Core.

Resources sample CPU, memory, GPU and network each second; the pill updates every
three seconds and the card retains 60 seconds of history. Missing sensors remain
unknown. Network totals mark partial daily coverage. NVIDIA uses one shared NVML
library on a blocking worker and omits unavailable samples. Core-backed quick
status follows Changed signals; account alone has a one-minute fallback for edits
made outside Core.

The keyboard uses a non-focusable virtual-keyboard overlay, following Hyprland's
layout group and Caps Lock. Native compiles XKB and sends evdev events through
`zwp_virtual_keyboard_v1`. Moving across outputs moves the whole panel; docking
reserves space. Floating position is atomically stored in
`$XDG_STATE_HOME/remya/bar/keyboard.ini`; touch-key preview is a Bar preference.

## Validation

Use AGENTS.md for required checks. `python test/bar_registration_test.py` validates
schema/default boundaries with python-jsonschema; `python test/install_test.py`
uses temporary XDG roots. Keep debug/release builds sequential. Native lifecycle
checks and window smoke scripts exercise different surface and engine regressions
on an isolated bus; preserve installed desktop state.
`python test/bar_resume_smoke.py` needs python-dbus and Hyprland and exercises wake
without suspending. `fvm dart run test/hyprland_ipc_smoke.dart` needs real request
and event endpoints; create a window/layer to produce an event within 20 seconds.
A canceled bridge stream may emit a final failed-post diagnostic during disposal.
