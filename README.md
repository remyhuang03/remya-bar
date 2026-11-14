<p align="center">
  <img src="assets/icons/app_icon-full.svg" width="128" alt="Remy'a Bar icon">
</p>

<h1 align="center">Remy'a Bar</h1>

<h3 align="center">A feature-rich status bar for Arch Linux Hyprland</h3>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Arch%20Linux%20%7C%20Hyprland-1793D1?logo=archlinux" alt="Platform">
  <img src="https://img.shields.io/badge/Flutter-3.47.9-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Rust-2024-dea584?logo=rust" alt="Rust">
  <img src="https://img.shields.io/badge/License-PolyForm%20Noncommercial-blue" alt="License">
</p>

<p align="center">
  <strong>English</strong> ·
  <a href="docs/README.zh-CN.md">简体中文</a> ·
  <a href="docs/README.zh-TW.md">繁體中文</a> ·
  <a href="docs/README.ru.md">Русский</a> ·
  <a href="docs/README.de.md">Deutsch</a> ·
  <a href="docs/README.es.md">Español</a> ·
  <a href="docs/README.ja.md">日本語</a>
</p>

A modern, fluid desktop status bar for **Linux Hyprland**, built with **Flutter** and **Material Design 3 Expressive**, powered by a high-performance **Rust** engine. Visually inspired by [illogical-impulse's Bar](https://github.com/end-4/dots-hyprland/tree/main/dots/.config/quickshell/ii/modules/ii/bar), it provides a rich set of status widgets.

> [!WARNING]
> This software is currently in **Beta** and may contain bugs or instability. Features and behavior are still being refined, and performance optimization is ongoing.

<p align="center">
  <video src="docs/images/hero-demo.mp4" controls autoplay loop muted playsinline width="100%"></video>
</p>

## 🚀 Installation

`remya-bar` depends on the `top.remya.Core1` D-Bus service provided by **Remya Core** (`remya-core` / `remyad`) to manage shared theme tokens and configuration persistence. Please install and enable **Remya Core** before installing **Remy'a Bar** (`top.remya.bar.service` is automatically ordered to start after `top.remya.core.service`; **Remya Settings** is an optional system settings frontend).

### 1a. Install via AUR (Recommended)

Install `remya-bar` using your preferred AUR helper:

```bash
paru -S remya-bar || yay -S remya-bar
```

### 1b. Install from Release Archive (Linux x86_64)

After downloading the Linux x86_64 release archive from [Releases](https://github.com/remyhuang03/remya-bar/releases), you can install it using the bundled `tool/install.py`:

```bash
# Verify file checksum
sha256sum -c SHA256SUMS --ignore-missing

# Extract and install
tar --zstd -xf remya_bar-<version>-linux-x86_64.tar.zst
cd remya_bar-<version>-linux-x86_64
python tool/install.py
```

The installer copies files into `~/.local/bin` and `XDG_DATA_HOME`, writes and enables the `top.remya.bar.service` systemd user unit, and configures the bar to start with `graphical-session.target` (requiring `WAYLAND_DISPLAY` and `HYPRLAND_INSTANCE_SIGNATURE` in the user manager environment, e.g., provided by `uwsm`). Reinstalling automatically stops the unit, replaces the bundle, and restarts the service. Run `systemctl --user disable --now top.remya.bar.service` to disable autostart.

### 2. Hyprland Configuration

Add the following keybindings to your Hyprland Lua configuration (e.g., `~/.config/hypr/hyprland.lua`) (if you already have existing bindings, you can remove them first with `hl.unbind(...)`):

```lua
local barShortcutSignal = 'gdbus emit --session --object-path /top/remya/bar --signal top.remya.bar.Shortcuts.'

-- Toggle Quick Settings sidebar
hl.bind(
    "SUPER + A",
    hl.dsp.exec_cmd(barShortcutSignal .. 'ToggleSidebar "$HYPRLAND_INSTANCE_SIGNATURE"')
)

-- Volume and brightness keybindings
hl.bind(
    "XF86AudioRaiseVolume",
    hl.dsp.exec_cmd(barShortcutSignal .. 'VolumeUp "$HYPRLAND_INSTANCE_SIGNATURE"'),
    { locked = true, repeating = true }
)
hl.bind(
    "XF86AudioLowerVolume",
    hl.dsp.exec_cmd(barShortcutSignal .. 'VolumeDown "$HYPRLAND_INSTANCE_SIGNATURE"'),
    { locked = true, repeating = true }
)
hl.bind(
    "XF86AudioMute",
    hl.dsp.exec_cmd(barShortcutSignal .. 'VolumeMute "$HYPRLAND_INSTANCE_SIGNATURE"'),
    { locked = true }
)
hl.bind(
    "XF86MonBrightnessUp",
    hl.dsp.exec_cmd(barShortcutSignal .. 'BrightnessUp "$HYPRLAND_INSTANCE_SIGNATURE"'),
    { locked = true, repeating = true }
)
hl.bind(
    "XF86MonBrightnessDown",
    hl.dsp.exec_cmd(barShortcutSignal .. 'BrightnessDown "$HYPRLAND_INSTANCE_SIGNATURE"'),
    { locked = true, repeating = true }
)
```

## ✨ Features

### Status Bar Pills

<table>
  <tr>
    <th>Pill</th>
    <th>Description</th>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/pill-sidebar.svg" alt="Quick Settings toggle pill" height="34"></td>
    <td><strong>Quick Controls Entry</strong>: Integrates network, Bluetooth, volume, and other statuses; click to expand the control center.</td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/pill-media.svg" alt="Media control pill" height="34"></td>
    <td><strong>Media Playback</strong>: Displays the currently playing track with one-click play/pause and track switching.</td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/pill-clock.svg" alt="Clock pill" height="34"></td>
    <td><strong>Clock &amp; Date</strong>: Accurately displays the current time and date; click or hover to expand the calendar.</td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/pill-workspaces.svg" alt="Workspaces pill" height="34"></td>
    <td><strong>Workspace Switcher</strong>: Displays app icons, focused windows, and urgency indicators across workspaces.</td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/pill-resources.svg" alt="System resources pill" height="34"></td>
    <td><strong>System Resources</strong>: Displays real-time CPU, memory, and other system resource metrics.</td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/pill-ai-quota.svg" alt="AI quota pill" height="34"></td>
    <td><strong>AI Usage</strong>: Clearly visualizes remaining quota and reset times across AI subscriptions.</td>
  </tr>
</table>

### Hover Panels & Control Center

<table>
  <tr>
    <td width="50%" align="center" valign="top">
      <img src="docs/images/demo-card-resources.svg" alt="System resource monitor panel" width="100%">
    </td>
    <td width="50%" align="center" valign="top">
      <img src="docs/images/demo-card-datetime.svg" alt="Date and time panel" width="100%">
    </td>
  </tr>
  <tr>
    <td align="center"><sub><b>System Monitor</b>: CPU, GPU, memory allocation, and 60-second network traffic graphs</sub></td>
    <td align="center"><sub><b>Date &amp; Time</b>: Large clock, world time, week of year, and interactive monthly calendar</sub></td>
  </tr>
  <tr>
    <td width="50%" align="center" valign="top">
      <img src="docs/images/demo-card-media.svg" alt="Media control panel" width="100%">
    </td>
    <td width="50%" align="center" valign="top">
      <img src="docs/images/demo-card-battery.svg" alt="Battery and power mode panel" width="100%">
    </td>
  </tr>
  <tr>
    <td align="center"><sub><b>Media Controls</b>: Adaptive colors from album art, track scrubber, and volume slider</sub></td>
    <td align="center"><sub><b>Battery &amp; Power</b>: Charge level, power draw, health, cycle count, and performance mode switching</sub></td>
  </tr>
  <tr>
    <td width="50%" align="center" valign="top">
      <img src="docs/images/demo-card-ai-quota.svg" alt="AI usage statistics panel" width="100%">
    </td>
    <td width="50%" align="center" valign="top">
      <img src="docs/images/demo-sidebar.svg" alt="Quick Settings control center" width="97%">
    </td>
  </tr>
  <tr>
    <td align="center"><sub><b>AI Usage</b>: Multi-platform session/weekly quotas, reset countdowns, and daily consumption stats</sub></td>
    <td align="center"><sub><b>Quick Settings</b>: System quick toggles and handy utility shortcuts</sub></td>
  </tr>
</table>

### On-Screen Display (OSD)

<table>
  <tr>
    <td width="45%" align="center">
      <img src="docs/images/demo-osd.svg" alt="On-Screen Display OSD" width="280">
    </td>
    <td>
      <ul>
        <li><strong>Volume &amp; Boost</strong>: Pops up a live progress capsule centered at the top when adjusting volume or enabling overdrive boost.</li>
        <li><strong>Brightness &amp; Software Dimming</strong>: Supports hardware backlight and software brightness adjustment indicators, clearly distinguishing the active mode.</li>
        <li><strong>Notifications &amp; Do Not Disturb</strong>: Centrally logs missed desktop notifications with one-click clear and a Do Not Disturb toggle.</li>
      </ul>
    </td>
  </tr>
</table>

## ⌨️ Development

### Tech Stack & Architecture

- **Flutter**: Pinned to `3.47.9` via FVM, paired with Material Design 3 Expressive (`material_ui`).
- **Rust**: `2024` edition, managed as a Cargo workspace using the root `rust-toolchain.toml`.
- **FFI**: Bridges `remya_bar_hyprland` and `remya_bar_system` to Flutter via `flutter_rust_bridge`.
- **Wayland**: Native GTK runtime dynamically linked against `gtk-layer-shell` for per-monitor status bar windows, `BarPopup` floating hosts, and the standalone `--settings` window.
- **Core Integration**: Connects to `remya-core` over session D-Bus (`top.remya.Core1`) via the `remya_client` and `remya_ui` packages to manage shared themes and atomic preference persistence. See [docs/backend.md](docs/backend.md) for contract details.

```
┌────────────────────────────────────────────────────────┐
│                   Flutter UI Layer                     │
│  - MD3 Expressive widgets & spring animations          │
│  - Per-monitor GTK Layer-Shell views                   │
│  - Floating popup host (BarPopup) & --settings window  │
└───────────────────────────▲────────────────────────────┘
                            │ flutter_rust_bridge
┌───────────────────────────▼────────────────────────────┐
│                    Rust Workspace                      │
│  - remya_bar_hyprland: Tokio Unix socket IPC & events  │
│  - remya_bar_system: Cached /proc, sysfs, GPU & MPRIS  │
│  - System tray SNI host & DBusMenu client              │
└───────────────────────────▲────────────────────────────┘
                            │ D-Bus (top.remya.Core1)
┌───────────────────────────▼────────────────────────────┐
│                   Remya Core (remyad)                  │
│  - Shared theme tokens, system settings & preferences  │
└────────────────────────────────────────────────────────┘
```

- **Directory Structure**:
  - `lib/main.dart` and `lib/app.dart`: Application startup and root widget composition.
  - `lib/features/`: Feature-based Flutter UI, state, and controllers.
  - `lib/src/rust/`: Modular Rust crates (`hyprland`, `system`, `core`, and generated bridge crates).
  - `linux/`: Native GTK runtime, `gtk-layer-shell` configuration, and desktop packaging scripts.
  - `assets/icons/`: Application icon and feature icons.
  - `tool/install.py`: XDG installation and systemd user service helper script.

### Prerequisites & Setup

- FVM with Flutter SDK `3.47.9`
- Rust toolchain (`2024` edition) managed via `rustup`
- A sibling `../remya-core` checkout during development to provide `packages/remya_client` and `packages/remya_ui` (compiled release bundles do not require a sibling source checkout)
- **Remya Core** installed and enabled at runtime (providing `dbus-1/services/top.remya.Core1.service` and `top.remya.core.service`)
- Arch Linux runtime and native build dependencies:

| Dependency | Purpose |
| :--- | :--- |
| `gtk-layer-shell`, `wayland`, `libxkbcommon`, `wayland-protocols` | Wayland layer-shell surfaces, input handling, and `wayland-scanner` |
| `sqlite` | Persistent notification history |
| `inter-font`, `noto-fonts-cjk` | System typography and CJK fallback |
| `networkmanager`, `bluez` | Network and Bluetooth Quick Settings toggles |
| `nvidia-utils` *(optional)* | Provides `libnvidia-ml.so.1` for NVIDIA GPU metrics |
| `codexbar-cli` *(optional)* | Provides `codexbar` executable for AI quota |

```bash
fvm install
fvm flutter pub get
```

After modifying Rust bridge APIs, regenerate bindings using `flutter_rust_bridge_codegen` and `flutter_rust_bridge.yaml`.

### Validation & Local Installation

```bash
# Dart formatting, static analysis, and tests
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze
fvm flutter test

# Rust formatting, lints, and tests
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace

# Linux debug build and native lifecycle / smoke tests
fvm flutter build linux --debug
cmake --build build/linux/x64/debug --target bar_lifecycle_test
build/linux/x64/debug/bundle/bar_lifecycle_test
python test/bar_window_smoke.py  # Requires a running Hyprland session

# Release build and install to local XDG directories
fvm flutter build linux --release
python tool/install.py
```

## 📜 License

This project is released under the [PolyForm Noncommercial License 1.0.0](LICENSE).