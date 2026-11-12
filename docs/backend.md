# Backend and Settings dependency

Remya Bar (`top.remya.bar`, executable `remya_bar`) is independently built and
installed. It depends on Remya Settings (`top.remya.settings`, executable
`remya_settings`) for configuration, shared Material theme policy, and future
settings operations. Install Settings first; the Bar installer checks its desktop
entry in XDG_DATA_HOME/XDG_DATA_DIRS.

## Public Settings boundary

Use `remya_settings_client`, owned by the Settings repository, for all Settings
interactions. The development source dependency is
`../remya-settings/packages/remya_settings_client`. Installed bundles contain
compiled code and do not require sibling source repositories.

The package contains the versioned contract, D-Bus client, settings opener,
MD3E theme, and observable theme controller. Release bars request the effective
theme through `top.remya.settings.Service1`, use `Changed` signals, and refresh
every two seconds to recover from service restarts. Settings starts in the
background on demand; the sidebar Settings action calls `Open("remya-bar")`. In debug,
the public opener launches the sibling repository's
`build/linux/x64/debug/bundle/remya_settings` directly, so an installed D-Bus
activation file is unnecessary. Build that Settings debug bundle first. Failed launches show
a popup error banner and remain retryable. The bar never writes settings files
or applies desktop appearance itself. Bar and popup typography use the system
Inter font, while preserving the shared CJK fallback list. Inter is a runtime
dependency (`inter-font` on Arch), checked by the installer; no font files are bundled.

Both apps use the same seed color, DynamicSchemeVariant mapping, typography
fallback, Material 3 mode, and expressive icon style. Invalid updates retain the
last valid theme. Debug builds first read `<bar-repo>/config/config.local.toml`,
then the sibling Settings repository's local config, then installed XDG config.
The native runner supplies the absolute repository root independently of cwd.
Release builds always use the Settings service.

See [the complete Settings API](../../remya-settings/docs/public-api.md) for both
CLI and D-Bus operations, schemas, availability, errors, and compatibility rules;
see [XDG installation and paths](../../remya-settings/docs/xdg-layout.md).
Future components must extend the owning Settings feature and its common
operation dispatcher, client contract, API documentation, and parity tests.
Do not import Settings UI/controllers/backends into Bar or add component-specific
private config parsing. No speculative plugins or future modules are included.

## Hyprland IPC

The `remya_bar_hyprland` Rust crate owns IPC. `flutter_rust_bridge` 2.13.0 exposes
`hyprlandRequest(command)`, `subscribeHyprland()`, the typed `hyprlandSnapshot()`
and validated workspace actions; the handwritten Dart adapter
is `lib/features/hyprland/hyprland_backend.dart`. The empty core crate is retained.
Regenerate bindings using the matching generator and `flutter_rust_bridge.yaml`.
Linux CMake builds and bundles the shared library for debug/profile/release.

Following the [official IPC protocol](https://wiki.hypr.land/IPC/):

- `.socket.sock` is request/reply: open immediately before a request and close on
  completion, failure, or a two-second timeout. Never retain an idle connection:
  Hyprland handles this socket synchronously. Replies are UTF-8, limited to 8 MiB.
- `.socket2.sock` is the live event subscription. One process-wide Rust worker
  serves all per-output Flutter engines and reconnects after failure with a
  one-second delay. Partial reads are framed by newline; event names and raw data
  (including commas and future event names) are preserved. Frames are limited to
  64 KiB. Invalid frames fail the connection instead of corrupting later events.
- Paths require absolute XDG_RUNTIME_DIR and a single-component instance signature.
  There is no obsolete `/tmp/hypr` fallback.

Updates have `kind`, `name`, and `data`: `connected` carries a version request
reply, `disconnected` carries the error, and `event` carries the raw compositor
event. Late output engines receive the current connection status. A bounded
256-update broadcast queue reports `resync` if a consumer falls behind; components
must re-request their state. A one-second `heartbeat` permits closed engine
subscriptions to be released; the Dart adapter hides heartbeats from components.
The worker remains process-scoped when all outputs disconnect, matching native
application lifetime. It does not change monitor configuration or request
keyboard focus.

The common `hyprland` crate was evaluated and excluded because its GPL license is
incompatible with this project's dependency policy. Transport uses Tokio's Unix
socket implementation and the documented protocol. Rust dependencies have bundled
notices under `assets/licenses/rust-dependencies.txt`; gtk-layer-shell remains a
dynamically linked system library.

## Notifications

The `remya_bar_system` crate owns `org.freedesktop.Notifications` for the whole
process (`lib/src/rust/system/src/notifications.rs`). The first
`subscribeNotifications()` call registers the server on the session bus with
`DoNotQueue`; while another daemon owns the name it retries every five seconds
and reports `error` instead of claiming to work. It never replaces another
owner. Capabilities are exactly `actions body body-markup body-hyperlinks
icon-static persistence`; `ActivationToken` is not sent.

IDs start at 1, skip 0 and live IDs, and `replaces_id` updates a notification
in place. The daemon records the receive time. `image-data` (honoring
rowstride, at most 128 px) becomes tray-style ARGB; `image-path` and file
`app_icon` values become the image; other icons resolve through the native
icon channel. Body markup keeps only `<b> <i> <u> <a href>` (http, https and
mailto links), turns `<br>` into a line break and falls back to the raw text
when malformed. The non-standard `value` hint is shown as progress.

`expire_timeout` -1 uses the Settings popup duration, 0 never expires, and
Critical never expires. Expiry hides the popup and keeps the notification in
history; `transient` notifications leave with their popup (reason 1).
`notificationsHover` pauses all popup timers. `CloseNotification` emits reason
3, user dismissal and Clear all reason 2. The `default` action is a click on
the notification; other actions are buttons and close the notification unless
it is `resident`. History keeps the newest 200.

The notification daemon stores history and the next notification ID in
`$XDG_STATE_HOME/remya/bar/notifications.sqlite3` (default
`$HOME/.local/state/remya/bar/notifications.sqlite3`). Relative XDG paths are
ignored. History updates, including replacements and dismissals, commit in a
single SQLite transaction. Transient notifications stay in memory. Restored
entries show their saved content in the center without replaying popups, sounds,
or action buttons tied to the previous daemon instance. Use an isolated
`XDG_STATE_HOME` when testing with a separate session bus.

Settings owns the preferences (`Get("notifications")`, see the Settings
[notifications API](../../remya-settings/docs/public-api.md#notifications)).
Every output engine reads them, follows `Changed` for the notification IDs and
passes them to `notificationsConfigure`; read errors keep the last valid
values. Each engine reports its output's Hyprland full screen state with
`notificationsFullscreen`. Rust computes Do Not Disturb from the manual switch,
the schedule (checked every 30 seconds) and full screen outputs, and reports
`quietReason` (`manual`, `schedule`, `fullscreen`). While it is in effect,
popups and sounds are suppressed except for Critical, priority-call
(`call`, `call.incoming`) and priority-app notifications; history keeps
everything. New notifications that pop up play their `sound-file` or
`sound-name`, or the theme's `message-new-instant`, through
`canberra-gtk-play` (libcanberra, a separate process) unless sounds are off or
the sender sets `suppress-sound`; replacements stay silent.

The `notifications` pill shows the bell and the history count, and opens the
`notifications` hover card. Popups use the separate `notification-toasts`
popup kind: native GTK places an OVERLAY layer surface (`top.remya.bar/notifications`)
anchored top-left, sliding in from the left edge, 8 px from the edges, with no keyboard focus or exclusive
zone. It is not hidden by hover cards, menus, the sidebar or fullscreen, and
closes only when no popup remains. The output focused when the first popup
arrives claims the stack through `notificationsClaimPopups`; Rust keeps that
single `popupHost` until no popup remains, so outputs racing on a focus change
cannot both show it. The host hides the stack while its own `notifications`
card is open, since the card lists the same notifications in that corner.

## Validation

Run the checks in AGENTS.md and `python ../remya-settings/test/interface_smoke.py`
after building both release bundles. The integration test uses temporary XDG
roots and an isolated session bus, verifies real bar theme changes on every
connected output, and stops its own bars and settings service. Keep debug and
release builds/tests sequential within a repository because Flutter shares its
native ephemeral engine files across build modes.

The Linux runner re-executes Bar with the same arguments after logind's
`PrepareForSleep(false)` signal or when GDK removes an output with a bar.
Re-exec happens before destroying the disconnected output's Flutter engine
because its destructor terminates the EGL display still shared by other bars
and popups. The new process reads the current outputs, restores notification
history and reloads preferences from Settings. Run `python test/bar_resume_smoke.py` with
`python-dbus` on Hyprland to exercise the wake path without suspending the host.

`fvm dart run test/hyprland_ipc_smoke.dart` verifies both real IPC endpoints
through the generated bridge: it requests monitors and waits up to 20 seconds
for an actual event. Open a window/layer during the check to trigger an event.
A canceled bridge stream can emit a final failed-post diagnostic during disposal;
this is separate from successful transport/readback.

## Flutter popup views

Use `BarTooltip` instead of Flutter `Tooltip` or `IconButton.tooltip` inside the
bar: a Flutter overlay cannot leave its 40-pixel native surface. Tooltip text,
background, border, wrapping, typography, and text scaling are rendered by Flutter.
The tooltip uses the owning Settings palette's `surfaceContainerHigh` and
`onSurface`, with an outline and rounded corners. GTK never draws its content.

`BarPopup.show` is the shared transport for floating components. Its request has
a component `kind`, view-local anchor rectangle, logical size, component `data`,
and the versioned Settings theme. `BarPopupApp` dispatches each kind to its Flutter
renderer. GTK owns placement, visibility, focus policy and lifetime only.

Detail cards share one per-output popup slot. AI Usage opens on hover or click. Its Flutter view uses an OVERLAY layer surface anchored top/left,
with exclusive zone 0, top margin 0 and ON_DEMAND keyboard focus (Escape hides
immediately). The window begins at the bar's exclusive edge. The left margin is
`clamp(anchor.x + (anchor.width - width) / 2, 0, monitor.width - width)`;
width/height remain monitor-clamped. Sidebar, tray/overview and tooltip surfaces
retain their separate placement and animation. A sidebar or tray menu blocks
card shows; opening either hides the current card.

Native copies the request and its data map, injecting integer
`data.pill: [anchor.x - left, anchor.width]` in popup-local coordinates. Flutter
joins that neck to the card body with clamped concave fillets. Its spring emergence
and 200 ms retraction change only the painted/clipped shape; `resize.height`
always measures full content including the 12 px neck and shadow insets. Missing
pill geometry falls back to a rounded card. The media pill sends its artwork
palette's primary as `cardSeed`; pill and card regenerate the same surface palette
using that seed, brightness and Settings style variant.

The popup announces `ready` before receiving `content`. Native sets `opening: true`
only when a card maps or switches kind; showing the same visible card replaces its
content with `opening: false`. Updates never replay emergence. After the 180 ms
leave delay, native sends `dismiss` and waits for Flutter's `hidden` acknowledgement
before hiding, with a 400 ms fallback. `enter` or another same-kind `show` cancels
the pending leave/dismiss and fallback, then sends `opening: false` to resume from
the current progress. Data updates during retraction are retained for that resume
without interrupting the close. Explicit `hide` remains immediate.

The owner receives `action` with
`{action: 'card.state', kind: <card kind>, open: true}` when shown and `open: false`
when really hidden. `BarPopup.openCard` follows this per-engine state and ignores
stale closes for another kind. Pills stay expanded and use the card's exact
surface color while attached; hover-card updates are sent only for changed
content (including the owning theme) while their kind is open. Reduced motion jumps to the animation endpoints.
The process starts one shared popup engine with a realized, unmapped implicit
GTK view. The popup entry path (`--remya-popup`) runs a Flutter `ViewCollection`
of the explicit popup views. Each open popup has its own view and method channel
named by its view ID. Native forwards actions to the owning bar view, which also
supplies the effective Settings theme. The popup engine runs no bar Rust event
subscription or Settings controller.

Each popup has zero exclusive space. The bar stays 40 pixels tall. Tooltip hover
waits 500 ms and closes on pointer exit or widget disposal. Closing a popup or
removing its output releases its GTK window, Flutter view, and channel. The engine
stays warm until the bar process exits. GTK 3 supplies each popup surface's integer
scale.

## Clock

`lib/features/clock/bar_clock.dart` displays the local system date and time in
its configured pill group on wide outputs, and centered on narrow outputs. It reads the real wall clock on every tick,
aligns updates to second boundaries, and cancels its timer when an output view
is removed. Only the clock widget rebuilds. It does not call Settings or spawn
processes for each tick; time and time zone writes remain owned by Settings.
The initial date/time format is deliberately fixed, with no formatting preference.
Very narrow transitional surfaces omit the clock so the sidebar button remains usable.


## Battery indicator

The main bar reads system batteries from Linux sysfs through the Rust bridge.
Peripheral batteries are excluded. The first system battery is shown when its
charge is available, and only the kernel status `Charging` shows a bolt. Charge at
or below 20% takes color precedence over energy saver. The saver color follows the
live `system.profile` from Settings' public `Get power` operation.

## Media control

The Bar subscribes to MPRIS property, seek and player-owner signals on a shared
session-bus connection and shares its Rust player selection across outputs.
Signals coalesce for 25 ms; position refreshes once per second only while playing.
Failed connections reconnect with bounded backoff; unchanged snapshots are suppressed.
Play/pause updates optimistically for up to two seconds and rolls back on failure.
The pill uses the selected player's position and duration. Both the pill and hover card derive their palette from the selected cover and fall
back to the Settings palette when artwork is unavailable.
The hover card sends transport and seek commands to that player. Rust checks
capabilities and validates the unique owner and track ID before seeking.
The output slider reads the default device via Settings' public Sound API
and writes the named device through `sound.output-volume`. Volume updates immediately
and coalesces pending writes to the latest value, with authoritative final readback.
The volume slider sends throttled updates while dragging; both sliders hold their
committed value until readback catches up or 1.5 seconds pass.

## Datetime card

Hover or click the clock to see local time with seconds, the UTC offset,
ISO week, day of year, UTC time, and a Monday-first calendar. The calendar
can browse months independently of live clock updates. Date markers have
a visual component only. The `datetime.settings` action opens the Date and
time page through the public Settings opener.

## Clock and battery

The clock capsule shows local time and the date. Bar reads
`remya-bar.clock-seconds` from the public Settings service and follows its
change notifications, with a default of showing seconds.

Bar reads the clock, layout, power, and Wi-Fi/Bluetooth quick status once at
startup and then only on Settings `Changed` signals; a signal that arrives
during a read reruns it. Only the account profile keeps a one-minute fallback,
because avatar or name edits made outside Settings emit no signal.

The battery card reads charge, estimated time, draw, health and cycle count
from the system battery when those fields are available. It reads and changes
the power profile and automatic Energy Saver through the public Settings Power
API. Settings owns the threshold and restores the last nonzero threshold when
automatic Energy Saver is enabled. Settings continues to validate and apply
power writes, and the card displays the returned state.

## Application tray

The Rust system backend registers as a StatusNotifierHost on the session bus.
It uses an existing `org.kde.StatusNotifierWatcher` or supplies the watcher if
none is present. Outputs share a short-lived snapshot with bounded, concurrent
item reads. Passive and disconnected items are hidden. Icons use validated ARGB
pixmaps, themed names, or app-provided icon paths rasterized by GTK. Normal and
secondary activation and wheel events are forwarded to the current D-Bus owner.

The 32px tray pill shows pinned items and reveals folded items inline with a
240ms transition. Right click opens a shared Flutter popup with the app's icon,
DBusMenu entries, and a local pin/fold action. The native layer positions it 6px
below the pill and clamps it to the owning output. Escape and outside clicks
dismiss the menu. An outside click while the overflow is open collapses it;
the native dismissal surface consumes that click. The menu loads one level at
a time with `AboutToShow` and `GetLayout` and revalidates enabled leaf actions
before sending `Event`. If an app has no usable DBusMenu, the local menu offers
its native `ContextMenu` action. Legacy XEmbed items are outside this implementation.

Items start pinned. Settings owns the folded IDs through
[`remya-bar.folded-apps`](../../remya-settings/docs/public-api.md#remya-bar-folded-applications).
Bar identifies apps by SNI ID with the executable name when available, since
different Chromium-based apps can export the same ID. All outputs read the
same Settings preference and reconcile on change. Appearance → Remya Bar
in Settings lists folded IDs and can pin them again, even while the app is closed.

## System Resources

The Rust system bridge samples CPU, memory, GPU and network once per second
using a cache shared by the output engines. The pill displays the latest
sample at three-second intervals. Its hover card receives live samples and
plots 60 seconds of CPU, GPU and network history. Missing sensors stay
unavailable. Network totals cover observations for the current local date,
with partial coverage marked in the card.

NVIDIA GPU metrics require the driver's NVML runtime (`libnvidia-ml.so.1`).
The Rust backend shares one initialized library and queries it on a blocking
worker. NVIDIA GPU entries are omitted when NVML cannot provide a sample.
Other GPU entries continue to come from DRM.

The System card uses a zero-exclusive-zone layer-shell surface on the pill's
output. The popup stays open as the pointer moves between the pill and card.
Its monitor button opens a supported desktop system monitor.

## Sidebar controls

The 420-logical-pixel panel opens 6 pixels from the output’s right edge and
8 pixels below the bar. The panel sizes to its content and scrolls when needed.

The sidebar reads live Settings state while visible. Display brightness targets
the owning output. Sound controls act on the displayed PipeWire input/output
device. Output volume spans 0–150%, with Boost above 100%. The brightness slider
uses hardware brightness down to 1%, then software dimming down to the configured
gamma floor. Raising it clears software dimming before raising hardware brightness.
Sliders apply live at 60 ms intervals and send the final value on release,
or adjust by five percentage points per wheel step. They hold the released value
until readback catches up or 1.5 seconds pass. The output slider opens the output
picker on secondary click.

Sidebar writes run in FIFO order; queued volume and brightness writes coalesce
per action and target to the latest value. Predictable controls update immediately
and reconcile with Settings results; refresh reads wait until the queue drains.
Layout editing, session actions, Wi-Fi connection/forget flows, Bluetooth
pairing/forget flows, and the airplane and keyboard toggles use the busy guard.

Wi-Fi scan, connection, disconnect, forget, and hidden-network activation use
Settings' NetworkManager API. BlueZ state, scan, connect, disconnect, forget,
and pairing prompts use the Bluetooth API. Night Light toggles the current
hyprsunset state and follows the schedule already configured in Settings.
Power Saver toggles between power-saver and balanced when both profiles exist,
and the Power detail lists every available profile. Keep awake shares the
Settings service's session-only hypridle inhibitor. On startup the bar asks
Settings to ensure hypridle is running. Settings reuses an existing daemon or
starts the packaged user service. Dark mode uses the Settings
Light/Dark preference and applies it through the same appearance backend.
Mic mute controls the current default PipeWire input through Settings Sound.
The compact and large Do Not Disturb controls use the same manual Settings
preference. Airplane mode reads live radio state via `readAirplane` and writes
via `setAirplaneEnabled`. Settings owns radio readback, partial-failure
handling, and migration of the former VPN tile in saved sidebar layouts.

The editor sends the old and new visible tile order to Settings for an atomic
update. Hidden IDs are inferred from the full tile list. The Power menu asks
logind to lock or terminate the current graphical session, reboot, or power off.
Log out, restart and shut down require a second click within three seconds.

The installed Bar can toggle its sidebar through a session D-Bus signal. To
bind Super+A manually in Hyprland Lua, use:

```lua
hl.bind("SUPER + A", hl.dsp.exec_cmd(
    'gdbus emit --session --object-path /top/remya/bar --signal top.remya.bar.Shortcuts.ToggleSidebar "$HYPRLAND_INSTANCE_SIGNATURE"'))
```

Replace any existing binding for that chord when adopting it. Bar listens only
to the signal for its own Hyprland instance and opens on the focused output.

## On-screen display (OSD)

`lib/features/osd/osd_slider.dart` and `lib/features/osd/osd_controller.dart`
implement the non-interactive `OSD / Capsule Slider` overlay (`260 × 48` px
capsule with a `28` px top reservation for the floating `Boost`, `Software brightness`, and `Dimming off`
range tags, total `260 × 76` px). Native GTK places `top.remya.bar/osd` on the
`OVERLAY` layer anchored top-center (`8` px below the bar, or `8` px from the
top edge while the bar is hidden in fullscreen) with zero exclusive space, no
keyboard focus, and an empty input region so pointer events pass through. Opening
or hiding the OSD does not close the sidebar, hover cards, or menus.

The OSD responds to Settings change signals for sound, hardware brightness and
gamma. Settings watches PulseAudio and kernel backlight events. Bar reads state
at startup, after a service restart, when an output changes, or when a shortcut
needs a missing baseline. Hardware brightness feedback appears on the affected
output; volume and gamma feedback appear on the focused output. Shortcut input
uses session D-Bus signals on `top.remya.bar.Shortcuts` at
`/top/remya/bar`: `VolumeUp`, `VolumeDown`, `VolumeMute`, `BrightnessUp`, and
`BrightnessDown`. Step sizes and minimum gamma are read from Settings via
`BarOsdClient` (`remya-bar.osd`: `remya-bar.volume-step`,
`remya-bar.brightness-step`, `remya-bar.gamma-min`) and updated on `Changed`
signals. Brightness shortcuts adjust hardware backlight/DDC brightness between
`1%` and `100%` and automatically transition into and out of `hyprsunset`
gamma dimming (`display-gamma`) down to `gamma-min` when hardware brightness
reaches its `1%` floor or is unavailable on the focused output. The popup shows
confirmed values, with a fixed right-side readout and a single coordinate for
the volume `100%` marker, handle, and boost split.
Shortcut repeats merge consecutive steps between writes while preserving both
sides of the hardware/software brightness boundary. Hyprland focus events keep
the target output current during the repeat burst.

## On-screen keyboard

The on-screen keyboard is a shared Flutter popup with a non-focusable Wayland
overlay surface. GTK opens it on the initiating output. Dropping the floating
keyboard on another output moves the entire panel there. Docking reserves space
on the current output. Media titles pause scrolling on all outputs while the
keyboard is visible. The floating position is written atomically to
`$XDG_STATE_HOME/remya/bar/keyboard.ini` (default `~/.local/state`).
Hyprland supplies the current layout group and physical Caps Lock state. The
runner compiles the XKB keymap and sends evdev key events with
`zwp_virtual_keyboard_v1`. Settings owns the touch key preview preference.

## Fullscreen output visibility

Each bar resolves its GDK output against Hyprland monitor coordinates. Mapped,
visible clients on the active or open special workspace hide that output's bar
when the compositor fullscreen bit is set. GTK closes the output's popups and
releases the bar's exclusive zone while hidden. Leaving fullscreen restores the
40-pixel reservation and the existing Flutter view. Hyprland events trigger a
refresh, with periodic reconciliation for missed events.

On outputs at least 700 logical pixels wide (after text scaling), pills follow
Settings' `remya-bar.layout` (read through `BarLayoutClient`, refreshed on
`Changed`, with the last valid layout kept on errors). Groups are spaced evenly
across the bar with 24-pixel side padding, and pills inside a group are 8 pixels
apart. The default layout has four groups: notifications, window, resources and
media in the first group, workspaces and clock in the centered group, the tray
in the third group, and battery and Quick Settings in the last group. Groups
keep their natural widths. When they fit, Settings can center one group, and the
groups before and after it are then spaced evenly within their own side, as long
as both sides fit. Otherwise groups sit 16 pixels apart and the bar scrolls
horizontally; the mouse wheel scrolls it unless a pill such as the workspaces
claims the wheel. The active window keeps a fixed 128-pixel slot while present,
so title changes never move other pills; empty workspaces omit the slot entirely.
Resources compact below 1600
logical pixels. The default metrics are CPU, memory and network. Layout options
select resource metrics, the active window app
name, and the workspace slot count, which Rust applies to every output engine.
The media title uses an ellipsis by default. The experimental media marquee
option scrolls long titles at 20 Hz and leaves the media controls available
in both modes.
Narrower outputs show the centered clock and the quick settings toggle.
The toggle shows live Wi-Fi, Bluetooth and volume state from Settings and
omits icons whose state is unknown.
Capsules with missing data are omitted before their width is assigned.

## Per-output workspace state

Rust parses the real monitor, workspace, client and active-window IPC responses.
GTK supplies the owning GDK monitor's logical geometry; Dart resolves it against
Rust monitor coordinates, independently of focus and enumeration order. GDK
geometry notifications (`top.remya.bar/window.outputChanged`) update this match.
Ambiguous mirrored coordinates are unavailable. Named workspaces are supported.
Rust builds eight slots from the active numeric group, with global occupancy,
connector ownership, urgency, and unique application classes ordered by window
area. Hyprland 0.57 exposes urgency through its Lua workspace API. Output
numbers follow the current layout, from left to right within each row and from
top to bottom across rows. Connector names still identify workspace ownership
when output numbers change.

The pill is 32 pixels high with widths of 214 on one display, 242 on several,
and up to 40 additional pixels for the active multi-app workspace. Own-output
workspaces use filled bands. Other outputs use outline bands and an MD3E ring
where visible. The Soft Triangle ring and tag use the Figma vectors because
the library triangle has a different profile. The ring overlays the standard
icon layout at its original 24-pixel size. A single shared Rust worker samples
Hyprland's Super key state every 100 ms and publishes changes to all views. Held
Super reveals numbers and
remote ownership marks. The special workspace name overlays dimmed, blurred slots
until the pointer enters the pill. Tooltips report the workspace, output and apps.

Relevant Hyprland events trigger coalesced state reads. A two-second
reconciliation recovers missed events and state changes. Failed reads retain the
last valid data and hide the pill until recovery. Left click focuses the owner of
an existing workspace or creates a missing numeric workspace on the owning bar
output. Wheel events use Hyprland's monitor-relative `r±1`. A mouse back button
toggles the open special workspace, or the default special workspace when none
is open. Right click opens a Flutter overview with keyboard navigation and
workspace selection. The bar surface retains its non-focusable policy.

Battery and resource data share one cached hardware sample across outputs. Media
discovery keeps its own refresh and retains its last successful player list if a
read fails. The resource card closes on Escape and dismisses the tray overflow
when it opens.


## AI Quota

The optional `codexbar-cli` dependency supplies the `codexbar` executable. A
worker in the warm popup engine coalesces requests from all outputs into one
sample every five minutes. Rust starts and supervises the CLI child, binds its
HTTP server to a reserved port on `127.0.0.1` and ties the child to the bar
process. The worker reads `Get("ai.bar")` from Settings (pins and threshold,
without a provider probe) and re-polls when Settings signals `Changed` for
`ai.providers` or `ai.bar`. Tracked providers are CodexBar's enabled set from
`codexbar config providers`, which Settings > AI writes. The pill shows
`pinned` in order (at most three, each only while it has data) or, without
pins, the first three tracked providers with data; the card shows every tracked
provider. `lowPercent` sets the low-quota threshold. While Settings is
unreachable the worker keeps its last Settings value; before the first one it
uses a 20% threshold. Usage is always probed for all providers and filtered locally.
It uses the authenticated dashboard shell for the fill preference and reads
usage and cost from the JSON routes.
CodexBar exposes its ordinary usage and cost routes to local loopback clients.
If a route is unavailable, the worker falls back to the corresponding CLI
command. The optional dependency is detected at runtime.

The pill and card show providers with at least one valid quota percentage.
Errors and samples older than ten minutes hide the affected provider until a
valid sample returns. Missing reset, pace, and spend fields stay unknown.
The card shows positive credit balances and banked resets reported by CodexBar.
Provider logos, brand colors and the Lobe Icons notice come from the Settings
client package (`loadAiIdentity()`, called at startup in the bar and popup
engines). Rings, meters and spend series use `aiProviderAccent`; low quotas use
the error colors. Logos are drawn without a color filter so color logos keep
their colors; monochrome ones follow `currentColor`. Providers without a known
logo use initials. Third-party marks remain the property of their owners. The
bar bundles no CodexBar-derived assets; it only runs the separately installed
`codexbar` executable. CodexBar 0.84 omits incident status from its HTTP usage response.
The card shows an incident when the payload supplies it. The manual refresh bypasses the usage cache. For cost it uses
`codexbar cost --refresh` because the HTTP cost endpoint in 0.84 does not force
a rescan. Freedesktop alerts are deduplicated by provider, window, reset time
and threshold for the lifetime of the bar process.
