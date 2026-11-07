# Backend and Settings dependency

Remya Bar (`top.remya.bar`, executable `remya_bar`) is independently built and
installed. It depends on Remya Settings (`top.remya.settings`, executable
`remya_settings`) for configuration, shared Material theme policy, and future
settings operations. Install Settings first; the Bar installer checks its desktop
entry in XDG_DATA_HOME/XDG_DATA_DIRS.

## Public Settings boundary

Use `remya_settings_client`, owned by the Settings repository, for all Settings
interactions. The development source dependency is
`../remya_settings/packages/remya_settings_client`. Installed bundles contain
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

See [the complete Settings API](../../remya_settings/docs/public-api.md) for both
CLI and D-Bus operations, schemas, availability, errors, and compatibility rules;
see [XDG installation and paths](../../remya_settings/docs/xdg-layout.md).
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

## Validation

Run the checks in AGENTS.md and `python ../remya_settings/test/interface_smoke.py`
after building both release bundles. The integration test uses temporary XDG
roots and an isolated session bus, verifies real bar theme changes on every
connected output, and stops its own bars and settings service. Keep debug and
release builds/tests sequential within a repository because Flutter shares its
native ephemeral engine files across build modes.

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
and the versioned Settings theme. `BarPopupApp` dispatches the kind to its Flutter
renderer; currently only `tooltip` is implemented. New floating components add
their renderer and payload validation here and reuse the same native host.

The GTK runner owns positioning, visibility, transient ownership, and teardown of
a non-focusable popup surface through gtk-layer-shell's supported popup path.
It lazily creates one additional Flutter view per output and reuses it across
shows and content/theme updates. The popup entry path (`--remya-popup`) does not
initialize the bar's Rust event subscription or Settings controller. The owner
passes its effective theme; the popup announces readiness before receiving data.

The popup has no exclusive zone and is not a normal application window. The bar
remains 40 pixels tall. Tooltip hover waits 500 ms and closes on pointer exit or
widget disposal. Popup resources are destroyed with their owning output view.
GTK 3 still supplies the platform surface's integer scale; this change unifies
text rendering with Flutter and does not change desktop scale or font settings.

## Clock

`lib/features/clock/bar_clock.dart` displays the local system date and time to
the right of the workspaces on wide outputs, and centered on narrow outputs. It reads the real wall clock on every tick,
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

The Bar polls MPRIS on the session bus and shares its Rust player selection
across outputs. The pill uses the selected player's position and duration. Both
the pill and hover card derive their palette from the selected cover and fall
back to the Settings palette when artwork is unavailable.
The hover card sends transport and seek commands to that player. Rust checks
capabilities and validates the unique owner and track ID before seeking.
The output slider reads the default device via Settings' public Sound API
and writes the named device through `sound.output-volume`.

## Datetime card

Hover or click the clock to see local time with seconds, the UTC offset,
ISO week, day of year, UTC time, and a Monday-first calendar. The calendar
can browse months independently of live clock updates. Date markers have
a visual component only. The `datetime.settings` action opens the Date and
time page through the public Settings opener.

## Clock and battery

The clock capsule shows local time and the date. Bar reads
`remya-bar.clock-seconds` from the public Settings service and follows its
change notifications, with periodic reconciliation and a default of showing
seconds.

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
[`remya-bar.folded-apps`](../../remya_settings/docs/public-api.md#remya-bar-folded-applications).
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

The System card uses a zero-exclusive-zone layer-shell surface on the pill's
output. The popup stays open as the pointer moves between the pill and card.
Its monitor button opens a supported desktop system monitor.

## Sidebar controls

The 420-logical-pixel panel opens 6 pixels from the output’s right edge and
8 pixels below the bar. The panel sizes to its content and scrolls when needed.

The sidebar reads live Settings state while visible. Display brightness targets
the owning output. Sound controls act on the displayed PipeWire input/output
device. Sliders send their value on release or adjust by five percentage points
per wheel step. The output slider opens the output picker on secondary click.

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
Do Not Disturb and the other unimplemented toggles are displayed as unavailable.

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

## Fullscreen output visibility

Each bar resolves its GDK output against Hyprland monitor coordinates. Mapped,
visible clients on the active or open special workspace hide that output's bar
when the compositor fullscreen bit is set. GTK closes the output's popups and
releases the bar's exclusive zone while hidden. Leaving fullscreen restores the
40-pixel reservation and the existing Flutter view. Hyprland events trigger a
refresh, with periodic reconciliation for missed events.

On outputs at least 700 logical pixels wide (after text scaling), the workspaces
are centered. Resources and media sit left of them, with the active window title
at the far left; the clock and battery sit to their right. The tray and sidebar
button are right-aligned. Resource spacing compacts and window/media titles yield
space before a component is omitted. Media needs 1100 logical pixels. Narrower
outputs show the centered clock and the sidebar button; the tray is hidden.
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
