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
defaults and pages (`layout`, `osd`, `notifications`, `ai-ring`, `tasks`). The
`material-theme` and `account` pages link to Core’s shared theme and avatar
editors. An avatar saved in either the Bar Account page or Remya Settings
updates Bar’s sidebar profile. The Account page also uses Core's Google OAuth
service for identity-only sign-in. Bar links to the [Remya Apps privacy policy](https://apps.remya.top/privacy),
and allows users to disconnect the shared authorization. Core owns the tokens
and browser flow.
It is installed at `$XDG_DATA_HOME/remya/apps/remya-bar.json`. `BarPreferences`
accesses values only through `AppPreferences('remya-bar')`; editors use
revision-checked Replace.
Bar additionally validates pill uniqueness, center bounds, identifier UTF-8 byte
bounds and priority app uniqueness. Invalid values retain the last valid value
and revision. Conflicts are shown without retrying or silently repairing data.
Tray edits read a fresh value before Replace; sidebar edits use the displayed revision.
`position` (`top` or `bottom`) picks the layer-shell edge the bar anchors to;
cards, tooltips, menus, panels, toasts and the OSD follow that edge, and the
attached pill corners and card neck flip with it. Changes apply live.

`remya_bar --settings [page]` forwards to the resident GApplication. The primary
creates a normal GTK toplevel on the application engine with
`fl_view_new_for_engine`. `top.remya.bar/settings` carries `open({viewId, page})`,
`closed(viewId)` and Dart's `ready` handshake. Bar views request `open(page)`.
`close`, `startMove` and `pickAvatar` require the current settings view ID.
The avatar chooser is modal to that window and cancels if the view closes.
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
through the application-wide `top.remya.paths` channel. Invalid themes retain
the last valid theme. The installer checks system Inter (`inter-font` on Arch).

## Hyprland IPC and output lifetime

`remya_bar_hyprland` owns request/event IPC and typed snapshots, exposed through
FRB 2.13.0 and `lib/features/hyprland/hyprland_backend.dart`. Regenerate with the
matching generator and `flutter_rust_bridge.yaml`; CMake bundles the library.
The empty core crate has no feature responsibility.

Following the [Hyprland IPC protocol](https://wiki.hypr.land/IPC/):

- Request sockets open per request and close on completion, failure or a two-second
  timeout. Replies must be UTF-8 and at most 8 MiB; idle connections are never retained.
- One process-wide event worker serves the app, reconnecting after one
  second. Newline framing preserves raw event data. Invalid or over-64-KiB frames
  fail the connection. The 256-update queue emits `resync` for lagging consumers.
- Updates carry `kind`, `name`, `data`; the subscriber receives current connection
  status on startup. A one-second heartbeat releases closed subscriptions and is hidden by Dart.
- Paths require absolute XDG_RUNTIME_DIR and a single-component instance signature.
  There is no `/tmp/hypr` fallback. Transport uses Tokio; the GPL `hyprland` crate
  is incompatible with the dependency policy.

GTK maintains one bar per GDK monitor. Dart matches logical geometry against
Hyprland snapshots; ambiguous mirrored geometry is unavailable. Connector names
identify workspace ownership, never monitor indices. The app store coalesces
workspace, monitor, window and fullscreen events into one snapshot request
sequence, with one refresh in flight and an 80 ms event window. Its 30-second
reconciliation covers missed events. Results from an obsolete connection
generation are discarded. Each output projects its own active window, workspace
slots and fullscreen state. Fullscreen requires a mapped, visible client in
the active workspace or current special workspace with the fullscreen mode
bit set. Failed reads keep the last valid snapshot but hide the workspace pill
until recovery. Bar's shared workspace count drives the snapshot and actions.
Workspace actions target the owning
output; wheel uses monitor-relative `r±1`, Back toggles the special workspace,
and right click opens the overview. When at least one output subscribes, one
shared worker checks Super every 100 ms while connected. There are no Super
queries without a subscriber or a compositor connection.

Workspace and notification icon lookups share application-wide bounded LRUs
with a 15-second retry delay for misses. GTK icon theme changes invalidate
cached lookups. The notification icon byte cache is limited to 16 MiB. Absolute
notification image paths are rechecked every 30 seconds while referenced.

Fullscreen clients on the active or open special workspace hide only their
output's bar, close its popups and release its exclusive zone. Leaving fullscreen
restores the same Flutter view and 40-pixel reservation. Output removal releases
that view immediately. After the topology or scale settles, Bar re-execs with
one engine and fresh graphics contexts. With zero outputs it waits for a
display to return. Wake also re-execs. Each re-exec reloads Core preferences and
saved notification history.

## Popup transport

Use `BarTooltip` for hints: Flutter overlays cannot leave the bar's native
40-pixel surface. `BarPopup.show` sends `kind`, a view-local anchor, logical size,
component data and the Core theme; `BarPopupApp` renders content. GTK owns only
placement, focus policy, visibility and lifetime. Popup surfaces have zero
exclusive space and monitor-clamped bounds. gtk-layer-shell stays dynamically linked.

One application engine starts with a realized, unmapped implicit GTK view.
Native publishes complete revisioned view snapshots on `top.remya.bar/views`.
Dart requests `list` and receives `changed` with `{revision, views}`, where
`views` maps decimal Flutter view IDs to `bar`, `popup` or `settings`. The
`ViewCollection` mounts a view when both its descriptor and Flutter metrics are
available. IDs increase within the engine lifetime. Bar windows and popup owners
use `top.remya.bar/bar/<id>/window` and `top.remya.bar/bar/<id>/popup`. Popup views
use `top.remya.bar/popup/<id>`. Closing a view clears its route and cancels
pending popup actions. Native forwards actions to the owning bar view, which
supplies its theme. App services stay alive when the last output is removed.

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
The application applies Core's notification preferences to Rust in order.
All outputs observe the same applied Do Not Disturb setting. Rust checks schedules
every 30 seconds. Critical, priority-call and priority-app
notifications bypass suppression. Sound uses `canberra-gtk-play` unless disabled
or suppressed; replacements stay silent.

The bell toggles the left notification panel, mutually exclusive with the right
sidebar. Toasts use a separate non-focusable overlay. The focused output claims
the popup stack until empty, preventing duplicates across racing outputs; it hides
the stack while that output's notification panel is open.

The tray registers a StatusNotifierHost and supplies a watcher only if absent.
Visible tray widgets share one item poll and icon lookup. Identical snapshots
retain their icons and skip UI updates. Passive or disconnected items hide.
Icons validate ARGB or resolve through GTK. Menus load one level at a time with
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
The Clipboard tile opens the installed `remya_launcher --clipboard` and closes
the sidebar once the command starts. Launcher owns clipboard history and policy.

MPRIS signals coalesce for 25 ms; position refreshes each second while playing.
Player selection is shared across outputs; reconnects use bounded backoff and
unchanged snapshots are suppressed. Optimistic playback expires after two seconds
or rolls back on failure. Seek validates capabilities, unique owner and track ID.
Media artwork supplies the pill/card palette. Optional marquee runs at 20 Hz and
pauses while the keyboard is visible. Core owns output-device volume writes.

The application owns one AI usage poller and applies Core preference updates
from change and service-availability signals. Normal and forced reads share the
same single-flight logic. A failed fetch leaves the latest sample available
until its freshness window expires. Large response bodies decode off the UI
isolate.

## Weather

The Weather pill and forecast card use one controller per Flutter engine.
Layout controls whether the Weather pill is shown in the bar, and Weather
background updates run while the pill is placed in the bar. Open
**System → Weather** in Bar Settings to choose a location and set display or
update preferences. The location picker accepts a city, postal code or named
coordinates. Search can take a language and country filter. The
`weather-location` preference stores both the active location and saved
locations in a revision-checked Core transaction. An empty object or an object
with only `saved` has no active location. The `weather` preference stores the
other controls separately.

Open-Meteo supplies model conditions, up to 25 hourly entries and seven local
calendar days. The bridge supplies Unix seconds for hourly and current
validity, retrieval, sunrise and sunset. Daily buckets retain the provider's
local dates. The UI uses the forecast's IANA time zone for timestamps and
formats metric source values into the selected display units. A change of
display unit can update a cached forecast immediately. Precipitation probability
stays a percentage. Missing fields degrade independently and unknown weather
codes use the global theme.

All views share one Rust cache. It coalesces attempts for the same coordinates
within 30 seconds. The most recently retrieved forecast is saved atomically
under `$XDG_CACHE_HOME/remya/bar/weather.json` with absolute HOME fallback.
The cache-only bridge method reads it without a provider call. With background
fetching off, opening a forecast can refresh the cache and closing the last
forecast stops automatic requests. Refresh errors retain cached data for the
same coordinates for up to 24 hours. The controller applies retry backoff and
honors a provider Retry-After response. The UI distinguishes retrieval time
from model validity.

Weather icons are the nine static fill SVGs from
[Meteocons 3.0.0-next.10](https://registry.npmjs.org/@meteocons/svg-static/-/svg-static-3.0.0-next.10.tgz)
by Bas Milius. The app bundles the original assets and their MIT notice. The
icon-derived seed values recorded in the
[Weather design spec](https://www.figma.com/design/86FHxWxh0HF55G8pGU45cf/Remya-Bar?node-id=323-1746)
are reused at runtime, with the global scheme variant, brightness and contrast.

Search text and forecast coordinates are sent to Open-Meteo's non-commercial
API. Displayed values are rounded and localized by Remya. See
[Open-Meteo terms](https://open-meteo.com/en/terms),
[data license](https://open-meteo.com/en/licence),
[forecast API](https://open-meteo.com/en/docs) and
[GeoNames search attribution](https://open-meteo.com/en/docs/geocoding-api).

## Google Tasks

Settings → Tasks → Connection requests Google Tasks read/write consent through
[Core’s Google account service](../../remya-core/docs/google-account.md). The
Account page requests identity only. Both pages show the shared connection.
Disconnect can retain the account's local work or discard it by explicit choice.
The Tasks settings page also controls list visibility, quick-add destination,
view defaults, placement and remote update mode. Set `@default` to use the
Google default list. A missing explicit target requires a new choice.

One application-wide store serves all monitors, the right sidebar, the optional
Tasks section in Notifications, and Settings. Notifications clear independently
of tasks. The store follows Core account changes and associates saved drafts,
pending operations and confirmed responses with the opaque Google account ID.
The cache and edit journal live in the account's private directory under
`$XDG_STATE_HOME/remya/bar/tasks/`, with the absolute HOME fallback. The journal
includes task titles, notes, edit baselines and drafts. OAuth credentials and
the authenticated API transport belong to Core.

Sync paginates the list directory and reads each list in sequence through Core.
Automatic mode starts with two-minute polls and full refreshes every 30 minutes.
Accounts with many lists poll less frequently to reduce API use. Sync retains
prior data while refreshing, replays pending edits when the account is available, and
offers a field-level comparison for concurrent changes. A write re-reads the
item before patching, so a remote write can still race the patch. Creates with
an uncertain outcome require review in Google Tasks before explicitly retrying or discarding. Manual mode disables periodic fetches and keeps local submissions
enabled. The UI treats Scheduled date as a calendar date independent of
timezone. Google Tasks remains the entry point for advanced fields and source
applications own assignment changes.

## Local observations and keyboard

One wall-clock timer serves visible bar clocks. It aligns to the second while
any clock displays seconds, otherwise to the minute. Fullscreen and removed
views release their demand. The datetime card browses months independently of
live time and opens system settings through the public opener.
Battery and resource samples are shared across views. Only system batteries count.
Low charge takes precedence over energy-saver color. Battery policy comes from Core.

CPU, memory and network counters are sampled on the configured System card
refresh interval (`500` ms minimum, `1000` ms default) and binned over the
configured history time range (`30`–`600` seconds, `60` seconds default) via
`hardware_snapshot(refresh_interval_ms, time_range_seconds)`. Each sample also
requests CPU frequency, temperature and GPU readings from a separate blocking
worker. All views share the readings and retained history (up to 600 seconds),
including while the resource card is closed. The resource pill updates every
three seconds.
GPU history only records measured utilization and shows gaps for unsampled
intervals. CPU topology, GPU identity and sensor paths are cached with periodic
rediscovery. NVIDIA uses one shared NVML library. Missing sensors remain unknown
and network totals mark partial daily coverage. Core-backed quick status follows
Changed signals. Account has a one-minute fallback for edits made outside Core.

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
