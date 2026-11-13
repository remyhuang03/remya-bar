# Backend and Remya Core contract

Remya Bar (`top.remya.bar`, executable `remya_bar`) depends on Remya Core,
not the Settings GUI. The installer requires the XDG activation file
`dbus-1/services/top.remya.Core1.service` and orders `top.remya.bar.service`
after `top.remya.core.service`. The session D-Bus name, object path and interface
are `top.remya.Core1`, `/top/remya/Core1`, and `top.remya.Core1`; Core provides
`remyad` and CLI `remya`.

## Public integration boundary

Development uses path dependencies `../remya-core/packages/remya_client` (pure
Dart system/shared APIs, `AppPreferences`, opener) and
`../remya-core/packages/remya_ui` (theme, theme controller, AI identity icons).
Compiled bundles do not require sibling repositories. System sound, networking,
Bluetooth, power, night light, brightness/gamma, account and AI provider usage
remain Core operations. Brightness/gamma currently have no typed Dart helpers;
Bar uses the documented Get/Set operations via `SettingsClient.call`.
System pages open through `openRemyaSettings`; debug may launch the sibling
Settings debug bundle using that public opener.

Bar owns `linux/packaging/remya-bar.json`, installed as
`$XDG_DATA_HOME/remya/apps/remya-bar.json`. It declares the `remya-bar`
registration, `top.remya.bar` desktop id, `bar` config namespace, pages `layout`,
`osd`, `notifications`, `ai-ring`, complete schemas and defaults. Storage keys are
`layout`, `clock-seconds`, `keyboard-preview`, `folded-apps`, `sidebar-layout`,
`osd`, `notifications`, `quiet-schedule`, `priority-notifications`, and `ai-ring`.
Object field names in storage use kebab case. Bar's internal popup transport
retains its existing field names.

`BarPreferences` uses only `AppPreferences('remya-bar')` Get/Set/Replace.
Core stores these values at `$XDG_CONFIG_HOME/remya/bar/settings.toml` and emits
`Changed` with the full registered setting id, e.g. `remya-bar.osd`.
Bar additionally checks pill uniqueness across groups, center bounds, UTF-8
byte bounds for identifiers, and priority app id uniqueness. Errors retain the
last valid value/revision; invalid values are never silently repaired. Tray
edits read the current value and Replace with its revision. Sidebar edits use
the revision of the displayed value and retain Core's conflict message:
`Changed in another view. Reopen the editor.` No old interface or migration is used.

System settings live in `remya/system/`; shared appearance lives in
`remya/shared/theme.toml`. Only absolute XDG roots are accepted, with absolute
HOME fallbacks. Release uses `SettingsThemeController.service` from `remya_ui`.
Debug theme resolution is `<bar>/config/config.local.toml`, then
`<core>/config/shared/theme.toml`, then installed shared theme. The runner
supplies an absolute repository root independently of cwd. Invalid themes retain
the last valid theme. Bar and popup typography use system Inter with shared CJK
fallbacks; the installer checks Inter (`inter-font` on Arch).

## Settings window entry

`remya_bar --settings [page]` forwards to the resident GApplication. The primary
creates a normal GTK toplevel titled `Remya Bar Settings` with app id
`top.remya.bar`, using `fl_view_new_for_engine` on the existing warm popup engine.
`top.remya.bar/settings` carries `open({viewId, page})`, `closed(viewId)` and the
Dart `ready` handshake; bar engines request `open(page)`. Repeated opens reuse
the window and deliver the new page. Closing destroys the view, keeping the
engine available. The desktop action Exec is the installed command plus
`--settings`, so Core `OpenApp('remya-bar', page)` reaches this entry.

`BarSettingsEntry` shows the registered pages (`layout`, `osd`,
`notifications`, `ai-ring`) in a navigation rail. Each `open` delivers a request
serial, so reopening any page navigates even while the window stays open; an
empty or unknown page keeps the current one. The window runs its own
`BarSettingsController` and Remya theme controller on the popup engine (debug
reads the repository root through `top.remya.paths`, also registered there).
The controller subscribes to Core `Changed` and service owner changes before
reading, rereads a key on its `Changed`, and reads tracked providers from
`ai.providers`. Every edit is a `Replace` with the revision of the displayed
value. Read errors (for example `Unavailable`) and write errors are shown with
text, an icon and a Reload action while the last valid values stay visible; a
conflict stays shown until the user reloads that preference or saves it again.
Controls of a preference being saved are disabled; schedule times and repeat are
hidden while the quiet schedule is off, and options of hidden pills are omitted.
The sidebar and keyboard Settings buttons open this window. Buttons that open
Remya Settings pages are hidden unless `applications/top.remya.settings.desktop`
exists in an absolute XDG data root (rechecked at most every five seconds).

See Core's [public API](../../remya-core/docs/public-api.md),
[XDG layout](../../remya-core/docs/xdg-layout.md), and
[app preferences](../../remya-core/docs/app-preferences.md).

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

`expire_timeout` -1 uses the Bar popup duration, 0 never expires, and
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

Bar owns notification preferences in `remya-bar.notifications`,
`remya-bar.quiet-schedule` and `remya-bar.priority-notifications`.
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

The `notifications` pill shows the bell and the history count, and toggles the
left-anchored `notifications` panel (`top.remya.bar/notifications-panel`),
matching the Quick Settings sidebar interaction model: click-to-toggle,
slide-in from the left, click-outside/Escape dismissal, pinned Do Not Disturb
toggle, and mutually exclusive visibility with the right sidebar. Popups use the separate `notification-toasts`
popup kind: native GTK places an OVERLAY layer surface (`top.remya.bar/notifications`)
anchored top-left, sliding in from the left edge, 8 px from the edges, with no keyboard focus or exclusive
zone. It is not hidden by hover cards, menus, the sidebar or fullscreen, and
closes only when no popup remains. The output focused when the first popup
arrives claims the stack through `notificationsClaimPopups`; Rust keeps that
single `popupHost` until no popup remains, so outputs racing on a focus change
cannot both show it. The host hides the stack while its own `notifications`
panel is open, since the panel lists the same notifications in that corner.

## Validation

Run the checks in AGENTS.md. Validate registration schemas/defaults with
`uv run --no-cache --with jsonschema python test/bar_registration_test.py`
and temporary-XDG installation with `python test/install_test.py`. Native
lifecycle and window smoke checks should use an isolated session bus and
temporary XDG state/data roots to preserve the installed desktop. Keep debug and
release builds/tests sequential within a repository because Flutter shares its
native ephemeral engine files across build modes.

The Linux runner re-executes Bar with the same arguments after logind's
`PrepareForSleep(false)` signal or when GDK removes an output with a bar.
Output additions and changes to the GTK monitor scale also re-execute Bar,
after a short debounce so the Wayland output announcements can settle. This
recreates the surfaces and raster contexts with the new output scales.
Re-exec happens before destroying the disconnected output's Flutter engine
because its destructor terminates the EGL display still shared by other bars
and popups. The new process reads the current outputs, restores notification
history and reloads preferences from Core. Run `python test/bar_resume_smoke.py` with
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
The tooltip uses the owning Core palette's `surfaceContainerHigh` and
`onSurface`, with an outline and rounded corners. GTK never draws its content.

`BarPopup.show` is the shared transport for floating components. Its request has
a component `kind`, view-local anchor rectangle, logical size, component `data`,
and the versioned Core theme. `BarPopupApp` dispatches each kind to its Flutter
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
using that seed, brightness and Core style variant.

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
content (including the owning theme) while their kind is open. Open cards also follow the visible pill bounds on
rendered frames, including during horizontal scrolling and pill animation.
Reduced motion jumps to the animation endpoints.
The process starts one shared popup engine with a realized, unmapped implicit
GTK view. The popup entry path (`--remya-popup`) runs a Flutter `ViewCollection`
of the explicit popup views. Each open popup has its own view and method channel
named by its view ID. Native forwards actions to the owning bar view, which also
supplies the effective Core theme. The popup engine runs no bar Rust event
subscription or Core controller.

Each popup has zero exclusive space. The bar stays 40 pixels tall. Tooltip hover
waits 500 ms and closes on pointer exit or widget disposal. Closing a popup or
removing its output releases its GTK window, Flutter view, and channel. The engine
stays warm until the bar process exits. GTK 3 supplies each popup surface's integer
scale.

## Clock

`lib/features/clock/bar_clock.dart` displays the local system date and time in
its configured pill group on wide outputs, and centered on narrow outputs. It reads the real wall clock on every tick,
aligns updates to second boundaries, and cancels its timer when an output view
is removed. Only the clock widget rebuilds. It does not call Core or spawn
processes for each tick; time and time zone writes remain owned by Core.
The initial date/time format is deliberately fixed, with no formatting preference.
Very narrow transitional surfaces omit the clock so the sidebar button remains usable.


## Battery indicator

The main bar reads system batteries from Linux sysfs through the Rust bridge.
Peripheral batteries are excluded. The first system battery is shown when its
charge is available, and only the kernel status `Charging` shows a bolt. Charge at
or below 20% takes color precedence over energy saver. The saver color follows the
live `system.profile` from Core's public `Get power` operation.

## Media control

The Bar subscribes to MPRIS property, seek and player-owner signals on a shared
session-bus connection and shares its Rust player selection across outputs.
Signals coalesce for 25 ms; position refreshes once per second only while playing.
Failed connections reconnect with bounded backoff; unchanged snapshots are suppressed.
Play/pause updates optimistically for up to two seconds and rolls back on failure.
The pill uses the selected player's position and duration. Both the pill and hover card derive their palette from the selected cover and fall
back to the Core palette when artwork is unavailable.
The hover card sends transport and seek commands to that player. Rust checks
capabilities and validates the unique owner and track ID before seeking.
The output slider reads the default device via Core's public Sound API
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
`remya-bar.clock-seconds` from the public Core service and follows its
change notifications, with a default of showing seconds.

Bar reads the clock, layout, power, and Wi-Fi/Bluetooth quick status once at
startup and then only on Core `Changed` signals; a signal that arrives
during a read reruns it. Only the account profile keeps a one-minute fallback,
because avatar or name edits made outside Core emit no signal.

The battery card reads charge, estimated time, draw, health and cycle count
from the system battery when those fields are available. It reads and changes
the power profile and automatic Energy Saver through the public Core Power
API. Core owns the threshold and restores the last nonzero threshold when
automatic Energy Saver is enabled. Core continues to validate and apply
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

Items start pinned. Bar owns folded IDs through `remya-bar.folded-apps`.
Bar identifies apps by SNI ID with the executable name when available, since
different Chromium-based apps can export the same ID. All outputs read the
same Bar preference through Core and reconcile on change.

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

The sidebar reads live Core state while visible. Display brightness targets
the owning output. Sound controls act on the displayed PipeWire input/output
device. Output volume spans 0% to the Bar `remya-bar.osd` `volume-max` ceiling
(100–150%, default 150%; a higher level set elsewhere extends the track), with
Boost above 100%. The sliders share the OSD visual rules: a dot marks the 100%
volume threshold or the hardware brightness floor while it lies on the inactive
track, Boost is a separate orange segment past a 4-pixel cut, software dimming
uses the gamma fill, and a muted device keeps its level with a gray fill.
Zero volume and mute are one state everywhere: 0% is shown as Muted, dragging
to 0% also mutes, any audible level unmutes, and unmuting a silent device
restores one volume step. The brightness slider
uses hardware brightness down to 1%, then software dimming down to the configured
gamma floor. Raising it clears software dimming before raising hardware brightness.
Sliders apply live at 60 ms intervals and send the final value on release,
or adjust by five percentage points per wheel step. They hold the released value
until readback catches up or 1.5 seconds pass. The output slider opens the output
picker on secondary click.

Sidebar writes run in FIFO order; queued volume and brightness writes coalesce
per action and target to the latest value. Predictable controls update immediately
and reconcile with Core results; refresh reads wait until the queue drains.
Layout editing, session actions, Wi-Fi connection/forget flows, Bluetooth
pairing/forget flows, and the airplane and keyboard toggles use the busy guard.

Wi-Fi scan, connection, disconnect, forget, and hidden-network activation use
Core's NetworkManager API. BlueZ state, scan, connect, disconnect, forget,
and pairing prompts use the Bluetooth API. Night Light toggles the current
hyprsunset state and follows the schedule already configured in Core.
Power Saver toggles between power-saver and balanced when both profiles exist,
and the Power detail lists every available profile. Keep awake shares the
Core service's session-only hypridle inhibitor. On startup the bar asks
Core to ensure hypridle is running. Core reuses an existing daemon or
starts the packaged user service. Dark mode uses the Core
Light/Dark preference and applies it through the same appearance backend.
Mic mute controls the current default PipeWire input through Core Sound.
The compact and large Do Not Disturb controls use the same manual Bar
preference. Airplane mode reads live radio state via `readAirplane` and writes
via `setAirplaneEnabled`. Core owns radio readback and partial-failure handling.
Bar validates sidebar tile IDs without retired-tile or VPN migration.

The editor uses the visible tile order and Core revision for an atomic Replace. Hidden IDs are inferred from the full tile list. The Power menu asks
logind to lock, suspend, or terminate the current graphical session, reboot, or
power off. Suspend, log out, restart and shut down require a second click within
three seconds. Screenshot, screen record, and color picker tiles launch
`remya_screen_capture` (no arguments, `--record`, and `--color-picker`) from the
sibling debug bundle in debug mode or the XDG-installed bundle/command.

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

The OSD responds to Core change signals for sound, hardware brightness and
gamma. Core watches PulseAudio and kernel backlight events. Bar reads state
at startup, after a service restart, when an output changes, or when a shortcut
needs a missing baseline. Hardware brightness feedback appears on the affected
output; volume and gamma feedback appear on the focused output. Shortcut input
uses session D-Bus signals on `top.remya.bar.Shortcuts` at
`/top/remya/bar`: `VolumeUp`, `VolumeDown`, `VolumeMute`, `BrightnessUp`, and
`BrightnessDown`. Step sizes, maximum volume, and minimum gamma are read from
BarPreferences (`remya-bar.osd`: `volume-step`, `volume-max`,
`brightness-step`, `gamma-min`) and
updated on `Changed` signals. `VolumeUp` stops at `volume-max` but never lowers
a higher level set elsewhere. `VolumeDown` reaching 0% also mutes; `VolumeMute`
or `VolumeUp` from 0% unmutes at one volume step. Brightness shortcuts adjust hardware backlight/DDC brightness between
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
`zwp_virtual_keyboard_v1`. Bar owns the touch key preview preference through Core app preferences.

## Fullscreen output visibility

Each bar resolves its GDK output against Hyprland monitor coordinates. Mapped,
visible clients on the active or open special workspace hide that output's bar
when the compositor fullscreen bit is set. GTK closes the output's popups and
releases the bar's exclusive zone while hidden. Leaving fullscreen restores the
40-pixel reservation and the existing Flutter view. Hyprland events trigger a
refresh, with periodic reconciliation for missed events.

On outputs at least 700 logical pixels wide (after text scaling), pills follow
Bar's `remya-bar.layout` (read through `BarPreferences`, refreshed on
`Changed`, with the last valid layout kept on errors). Groups are spaced evenly
across the bar with 24-pixel side padding, and pills inside a group are 8 pixels
apart. The default layout has four groups: notifications, window and resources
in the first group, workspaces and clock in the centered group, the tray
in the third group, and AI usage, battery and Quick Settings in the last group. Groups
keep their natural widths. When they fit, the layout can center one group, and the
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
The toggle shows live Wi-Fi, Bluetooth and volume state from Core and
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
process. Reads `remya-bar.ai-ring` via BarPreferences (`pinned`, `low-percent`,
`show-used`, `ring-order` without a provider probe) and re-polls when Core signals
`Changed` for `ai.providers` or `remya-bar.ai-ring`. Tracked providers are CodexBar's enabled set from
`codexbar config providers`, which Settings > AI writes through Core. The pill shows
`pinned` in order (at most three, each only while it has data) or, without
pins, the first three tracked providers with data; the card shows every tracked
provider. `lowPercent` sets the low-quota threshold. While Core is
unreachable the worker keeps its last Core value; before the first one it
uses a 20% threshold. Usage is always probed for all providers and filtered locally.
Bar views apply presentation preferences independently of the quota probe. A
single quota window uses the outer ring. With two windows, the selected ring
order also sets the expanded pill's readout order. Rings start at 12 o'clock
and run clockwise. Card meters run from left to right. Both place used quota
first and remaining quota second. The pace marker stays on the used-quota
scale. The quota preference selects the highlighted segment and the
percentage readout. The worker
reads the provider catalog from the authenticated dashboard shell when needed
and reads usage and cost from the JSON routes.
CodexBar exposes its ordinary usage and cost routes to local loopback clients.
If a route is unavailable, the worker falls back to the corresponding CLI
command. The optional dependency is detected at runtime.

The pill and card show providers with at least one valid quota percentage.
Errors and samples older than ten minutes hide the affected provider until a
valid sample returns. Missing reset, pace, and spend fields stay unknown.
The card shows positive credit balances and banked resets reported by CodexBar.
Provider logos, brand colors and the Lobe Icons notice come from the Core
UI package (`loadAiIdentity()`, called at startup in the bar and popup
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
