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
background on demand; the release gear button calls `Open("home")`. In debug,
the public opener launches the sibling repository's
`build/linux/x64/debug/bundle/remya_settings` directly, so an installed D-Bus
activation file is unnecessary. Build that Settings debug bundle first. Failed launches show
an error tooltip/icon and remain retryable. The bar never writes settings files
or applies desktop appearance itself.

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
`hyprlandRequest(command)` and `subscribeHyprland()`; the handwritten Dart adapter
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

`lib/features/clock/bar_clock.dart` displays the local system date and time at the
geometric center of each output. It reads the real wall clock on every tick,
aligns updates to second boundaries, and cancels its timer when an output view
is removed. Only the clock widget rebuilds. It does not call Settings or spawn
processes for each tick; time and time zone writes remain owned by Settings.
The initial date/time format is deliberately fixed, with no formatting preference.
Very narrow transitional surfaces omit the clock so the Settings launcher remains usable.
