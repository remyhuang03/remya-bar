<p align="center">
  <img src="assets/icons/bar.svg" width="128" alt="Remy'a Bar icon">
</p>

<h1 align="center">Remy'a Bar</h1>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Arch%20Linux%20%7C%20Hyprland-1793D1?logo=archlinux" alt="Platform">
  <img src="https://img.shields.io/badge/Flutter-3.47.8-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Rust-2024-dea584?logo=rust" alt="Rust">
  <a href="https://github.com/wmww/gtk-layer-shell"><img src="https://img.shields.io/badge/Wayland-gtk--layer--shell-blue" alt="Wayland"></a>
  <a href="docs/backend.md"><img src="https://img.shields.io/badge/D--Bus-top.remya.settings-5865F2" alt="D-Bus"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-PolyForm%20Noncommercial-blue" alt="License"></a>
</p>

A desktop status bar for **Hyprland on Linux**, built with **Flutter**, **Material Design 3 Expressive**, and a modular **Rust workspace**. Visual hierarchy and layout take proportions from [illogical-impulse's Bar](https://github.com/end-4/dots-hyprland/tree/main/dots/.config/quickshell/ii/modules/ii/bar), featuring an active window title, dedicated Resources and Media capsules, centered workspaces, clock, battery, system tray, and an Android-style Quick settings sidebar. Remya Bar deeply integrates with the Linux system via Rust and follows the shared Remya Settings ecosystem.

> [!CAUTION]
> **Early Development & Preview Only — Not Ready for Daily Use**
>
> - **Under Active Development**: Remya Bar is in an early, experimental development stage and has not reached a stable release.
> - **WIP Subsystems & Preview Boundaries**: While core modules (workspaces, active window, system metrics, media player, battery, clock, system tray, and Flutter popup host) are implemented and functional, Quick settings sidebar controls and notification integrations are UI placeholders awaiting backend connections.
> - **Subject to Breaking Changes**: Internal protocols, bridge bindings, and layout parameters may change rapidly. Hardware edge cases (e.g., dynamic physical multi-monitor hotplugging across complex GPU configurations) require ongoing real-session verification.
> - **For Preview & Evaluation Only**: This repository is intended strictly for development preview and reference. Use at your own risk on real desktop sessions.

## Implemented Features (Experimental)

Remya Bar combines modern desktop bar ergonomics with low-overhead native Linux and Hyprland backend integrations, synchronized with the system via Rust:

- **Multi-Monitor Layer Shell**: 40-logical-pixel top capsule bar per connected output using native `gtk-layer-shell`. Exclusive space reservation, zero window decorations, no keyboard focus stealing, and dynamic GDK display hotplug/unplug keeping the app alive across zero connected outputs. Fullscreen windows automatically hide the bar and release reserved space on the active output.
- **Hyprland IPC & Workspaces**: Low-overhead native Hyprland integration via Tokio Unix sockets (`.socket.sock` for request/reply, `.socket2.sock` for live events). Features an 8-slot workspace strip with occupancy indicators, largest-window application icons cached via GDK/GIO, animated 22px active indicator, mouse wheel navigation (`r±1`), mouse back-button special workspace toggle, and active window title tracking.
- **Hardware Resources Monitor**: Compact capsule displaying CPU, RAM, Swap, Network upload/download totals, and GPU utilization (DRM sysfs & NVIDIA). Icon-backed circular sector indicators rendered with MD3 inverse surface roles for contrast across light/dark themes. 500 ms hover card with detailed system metrics.
- **MPRIS Media Player**: Integrated media pill with real-time playback progress bar, continuous marquee scrolling for long titles, and hover expansion. Accompanied by a rich Flutter media card featuring dynamic artwork-seeded Expressive color scheme, playback transport controls, position seeking, and default output volume slider.
- **System Tray (StatusNotifierItem)**: Native SNI host on the session bus with `DBusMenu` support. 32px tray pill supporting pinned items, inline reveal animations for folded items, right-click interactive Flutter popup menu, and preference synchronization with Remya Settings (`remya-bar.folded-apps`).
- **Power & Battery**: 48 × 24 px battery capsule showing sysfs percentage, dynamic charging bolt, health, and estimated remaining time. Integrates with Remya Settings power saver profiles (`system.profile`). Hover card provides battery stats and energy saver toggles.
- **Clock & Calendar**: Centered local time display with English weekday formatting. Configurable seconds toggle synchronized with Settings (`remya-bar.clock-seconds`). Hover card exposes a full calendar view and timezone information.
- **Connectivity Indicators**: Live NetworkManager (Wi-Fi signal strength, ethernet state) and BlueZ Bluetooth device readouts via D-Bus without manual polling.
- **Quick Settings Sidebar**: 460px Android-style slide-out panel featuring account avatar & username synchronized with Settings, system actions (Settings opener, lock, logout, power, quit), volume/brightness/microphone sliders, quick controls grid, and notification area. Includes outside-click dismissal and on-demand keyboard focus.
- **Native Flutter Popups**: Shared `BarPopup`/`BarPopupApp` architecture ensuring all tooltips, hover detail cards, menus, and the sidebar render natively in Flutter with proper MD3E styling, avoiding GTK drawing limitations.
- **Remya Settings Integration**: Real-time MD3E theme, seed color, and dark mode synchronization via `remya_settings_client` over D-Bus (`top.remya.settings`).

## Architecture & Native Runner

Bar uses a multi-engine GTK layer-shell runner paired with unified Rust backend workers:

- **Per-Output Engines**: Each physical monitor has its own GTK window and independent Flutter view/engine, managed dynamically on GDK display signals without using brittle display indices.
- **Flutter Popup Host**: Floating components (tooltips, hover detail cards, tray context menus, and the Quick settings sidebar) render through a dedicated native popup host (`BarPopup` / `BarPopupApp`). GTK manages only placement, visibility, focus policy, and lifetime; all UI, typography, and animations are driven by Flutter.
- **Unified Rust Backends**: Rust crates under `lib/src/rust/` bridge directly to Dart via `flutter_rust_bridge` 2.13.0:
  - `remya_bar_hyprland`: Native Wayland compositor IPC handling request/reply and persistent live event streaming.
  - `remya_bar_system`: Unified periodic snapshot worker for system metrics (CPU, RAM, GPU, network, battery), MPRIS media player discovery, SNI tray host, BlueZ, and NetworkManager.
- **Shared Worker Caching**: All per-output Flutter engines share a single Rust baseline cache, avoiding duplicate `/proc` reads, redundant D-Bus queries, or excessive GPU driver polling.
- **Settings Ecosystem**: Remya Bar is a client to Remya Settings. It reads themes, preferences, and account metadata over D-Bus, delegating all system writes and configuration persistence to Remya Settings.

## Repository Layout

```text
Cargo.toml                Root Rust workspace
lib/
  main.dart, app.dart     Flutter startup, composition, and theme
  features/<feature>/     Feature-first Flutter UI, state, and controllers
  src/rust/<crate>/       Modular Rust backends (hyprland, system) and FRB bridges
  widgets/                Reusable bar widgets (tooltips, groups, sector indicators)
linux/                    GTK layer-shell runner, popup placement, and icon lookup
docs/                     Architecture, IPC specs, and backend documentation
test/                     Unit, widget, lifecycle, and desktop smoke tests
tool/                     Build and installation scripts
```

## Development

Prerequisites:
- **Fonts**: Inter system font (`inter-font` on Arch) and Noto Sans CJK (`noto-fonts-cjk` on Arch).
- **Libraries & Tools**: `gtk-layer-shell` (dynamically linked LGPL system library), fontconfig, FVM, Rust via rustup, Clang, CMake, Ninja, pkg-config, and GTK 3 development headers.
- **Runtime Environment**: Hyprland (or Wayland compositor supporting wlr-layer-shell-unstable-v1), NetworkManager, and BlueZ.

```bash
fvm install
fvm flutter pub get
# (Optional) Build sibling Settings debug bundle for the Quick settings launcher:
# (cd ../remya_settings && fvm flutter build linux --debug)
fvm flutter run -d linux --no-start-paused
```

FVM pins Flutter to `3.47.8`; `rust-toolchain.toml` selects stable Rust with rustfmt and Clippy. See [AGENTS.md](AGENTS.md) for architecture, coding, validation, and Git rules. Use `--no-start-paused` so all per-output engines render during development.

### Code Quality & Verification

Run the relevant validation checks before presenting changes:

```bash
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze
fvm flutter test
fvm flutter build linux --debug
python test/bar_window_smoke.py         # Requires a running Hyprland session.
python test/fullscreen_window_smoke.py # Uses its own temporary GTK window.
python test/popup_window_smoke.py      # Requires ydotoold for real pointer interaction.
cargo run -p remya_bar_system --example system_probe
dbus-run-session -- cargo run -p remya_bar_system --example mpris_smoke
cmake --build build/linux/x64/debug --target bar_lifecycle_test
build/linux/x64/debug/bundle/bar_lifecycle_test
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
git diff --check
```

## Installation

The application ID is `top.remya.bar`; its executable is `remya_bar`.
Build and install into `XDG_DATA_HOME` with a user command in `~/.local/bin`:

```bash
fvm flutter build linux --release
python tool/install.py
```

- Launch **Remy'a Bar** directly by running `remya_bar`, or add `exec-once = remya_bar` to your Hyprland configuration.
- The installer verifies runtime dependencies (gtk-layer-shell, Inter font, and Remya Settings desktop entry), registers the desktop entry and icon, and installs the release binary.
- Configuration policy, IPC behavior, and Settings dependency boundaries are documented in [backend integration](docs/backend.md).
- See [Settings' complete CLI/D-Bus API](../remya_settings/docs/public-api.md) and [the shared XDG layout](../remya_settings/docs/xdg-layout.md).

## Usage & Interactions

- **Workspace Navigation**: Scroll the mouse wheel over the workspace strip to switch workspaces (`r±1`); click the mouse back button to toggle the default special workspace.
- **Hover Detail Cards**: Hover over Resources, Media, Battery, or Clock for 500 ms to view detailed Flutter cards; move the pointer away to dismiss with an interactive grace timer.
- **Media Controls**: Click the media pill to expand or play/pause; scrub track position or adjust master output volume directly inside the media card.
- **System Tray**: Left-click tray items for primary activation, right-click for the DBusMenu popup, and click the reveal chevron to expand folded icons.
- **Quick Settings Sidebar**: Click the Quick settings launcher icon or Clock to toggle the 460px sidebar. Click outside or press `Escape` to dismiss.

## License

Licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE), matching `remya_settings`.
