<p align="center">
  <img src="assets/icons/app_icon-full.svg" width="128" alt="Remy'a Bar icon">
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

A modern, fluid desktop status bar for **Hyprland on Linux**, crafted with **Flutter** and **Material Design 3 Expressive**, backed by a high-performance **Rust** engine.

Remy'a Bar blends refined desktop aesthetics with deep Linux system integration. Drawing visual inspiration from [illogical-impulse's Bar](https://github.com/end-4/dots-hyprland/tree/main/dots/.config/quickshell/ii/modules/ii/bar), it delivers smooth animations, real-time compositor awareness, artwork-adaptive media controls, rich hover dashboards, and an Android/macOS-style Quick Settings control center—all while keeping system overhead minimal.

> [!CAUTION]
> **Early Development & Preview Only — Not Ready for Daily Use**
>
> This repository is currently intended strictly for design preview and development reference. Use at your own risk on real systems.

---

## Features

- **Workspaces and Displays**. Each output features a 40 px bar that auto-hides in fullscreen mode. On standard displays (≥ 700 logical px), the default layout arranges pills into four distinct groups: (1) notifications, active window, system resources, and media; (2) centered workspaces and clock; (3) application tray; and (4) battery and Quick Settings. Narrower displays fall back to a centered clock and Quick Settings toggle. Bar layout configuration, Material 3 theme tokens, and dynamic appearance policies are owned by the companion Remya Settings service.
- **Media and System Status**. The media player provides playback controls alongside gauges for default metrics (CPU, memory, and network), with an optional GPU display (via DRM or NVML for NVIDIA). Hovering reveals detailed metric graphs and hardware history.
- **Quick Settings**. A slide-out panel houses configurable quick settings toggles, hardware sliders, session actions, and an on-screen keyboard. Users can reorder tiles and hide unused options to customize the layout.
- **Tray and Notifications**. The system tray supports pinned or folded applications alongside an integrated notification center. Do Not Disturb filters popups and sounds while retaining persistent notification history.
- **AI Quota**. Colored provider rings show the remaining 5-hour and weekly quota of up to three AI subscriptions pinned in Remya Settings > AI, with a usage card on hover. Requires the optional `codexbar-cli` package with providers signed in.
- **On-Screen Display (OSD)**. A non-interactive top-centered MD3E capsule slider (`top.remya.bar/osd`) displays live feedback for volume (`0%` up to a configurable `100%–150%` maximum, with a `100%` threshold marker and harmonized `Boost` segment/tag), mute (preserving pre-mute slider position; `0%` and mute are the same state), hardware brightness (`0%–100%`), and `hyprsunset` software gamma dimming (`Gamma` tag), with step sizes, maximum volume, and minimum gamma configured in Remya Settings. The sidebar volume and brightness sliders use the same thresholds and colors.

---

## Getting Started

### Prerequisites

- **Desktop Environment**: Hyprland (or Wayland compositor supporting `wlr-layer-shell-unstable-v1`).
- **Dependencies**:
  - `gtk-layer-shell` (system package)
  - SQLite (`sqlite` on Arch) for notification history
  - Wayland client and XKB libraries (`wayland`, `libxkbcommon` on Arch), with `wayland-scanner` at build time
  - `inter-font` and `noto-fonts-cjk`
  - NetworkManager and BlueZ (for network & Bluetooth toggles)
  - NVIDIA Management Library (`libnvidia-ml.so.1`, provided by `nvidia-utils` on Arch) for optional NVIDIA GPU metrics. Without NVML, the resource monitor hides NVIDIA GPUs.
  - Remya Settings (`remya_settings`, provides theme, layout, & system D-Bus services)
  - Optional: `codexbar-cli` (provides the `codexbar` executable) for AI Quota

### Installation

For paired setups, install **Remya Settings** before installing **Remy'a Bar** so the D-Bus services, theme tokens, and configuration schemas are available.

#### From Release Archive (Linux x86_64)

For paired setups, install Remya Settings before Bar. To install using a Linux x86_64 release archive downloaded from [Releases](https://github.com/remyhuang03/remya-bar/releases) using its bundled `tool/install.py`:

```bash
# Verify checksum
sha256sum -c SHA256SUMS --ignore-missing

# Extract and install
tar --zstd -xf remya_bar-0.1.0-dev.20261111.0-linux-x86_64.tar.zst
cd remya_bar-0.1.0-dev.20261111.0-linux-x86_64
python tool/install.py
```

#### Building from Source

For paired setups, install Remya Settings before compiling and installing Bar. To compile and install from source:

```bash
fvm flutter build linux --release
python tool/install.py
```

The installer copies files into `~/.local/bin` and `XDG_DATA_HOME`, writes and enables the `top.remya.bar.service` systemd user unit, and configures the bar to start with the graphical session (`graphical-session.target`, requiring `WAYLAND_DISPLAY` and `HYPRLAND_INSTANCE_SIGNATURE` in the user manager environment, as provided by uwsm). Reinstalling stops the unit, replaces the bundle, and restarts the service. Remove other autostart entries to prevent duplicate instances; run `systemctl --user disable --now top.remya.bar.service` to turn autostart off.

### Hyprland Configuration

To bind an example shortcut (such as `Super + A`) to toggle the Quick Settings control center:

```ini
# Hyprland bind to toggle Quick Settings sidebar
bind = SUPER, A, exec, gdbus emit --session --object-path /top/remya/bar --signal top.remya.bar.Shortcuts.ToggleSidebar "$HYPRLAND_INSTANCE_SIGNATURE"

# Optional volume and brightness/gamma OSD shortcuts
bindel = , XF86AudioRaiseVolume, exec, gdbus emit --session --object-path /top/remya/bar --signal top.remya.bar.Shortcuts.VolumeUp "$HYPRLAND_INSTANCE_SIGNATURE"
bindel = , XF86AudioLowerVolume, exec, gdbus emit --session --object-path /top/remya/bar --signal top.remya.bar.Shortcuts.VolumeDown "$HYPRLAND_INSTANCE_SIGNATURE"
bindl  = , XF86AudioMute, exec, gdbus emit --session --object-path /top/remya/bar --signal top.remya.bar.Shortcuts.VolumeMute "$HYPRLAND_INSTANCE_SIGNATURE"
bindel = , XF86MonBrightnessUp, exec, gdbus emit --session --object-path /top/remya/bar --signal top.remya.bar.Shortcuts.BrightnessUp "$HYPRLAND_INSTANCE_SIGNATURE"
bindel = , XF86MonBrightnessDown, exec, gdbus emit --session --object-path /top/remya/bar --signal top.remya.bar.Shortcuts.BrightnessDown "$HYPRLAND_INSTANCE_SIGNATURE"
```

---

## Interactions & Shortcuts Cheat Sheet

| Component | Gesture / Action | Result |
| :--- | :--- | :--- |
| **Workspaces** | **Left Click** | Switch to workspace, or create if empty |
| | **Scroll Wheel** | Switch adjacent workspace (`r+1` / `r-1`) |
| | **Mouse Back Button** | Toggle special / scratchpad workspace |
| | **Hold Super** | Reveal workspace numbers and remote monitor tags |
| | **Right Click** | Open workspace overview popup |
| **Media Pill** | **Click** | Toggle play / pause or expand pill |
| | **Hover** | Open media card with track scrubber and volume |
| **Resources** | **Hover** | Open 60-second live performance graphs |
| **Clock** | **Click / Hover** | Open datetime dashboard and interactive calendar |
| **Notifications** | **Click / Hover** | Open the notification center and Do Not Disturb |
| | **Click a notification** | Run its default action, if it has one |
| **Quick Settings** | **Click the status pill** | Toggle the Quick Settings control center |
| | **`Super + A` (example)** | Toggle the Quick Settings control center from anywhere |
| | **Volume Slider Right-Click** | Open audio output device picker |
| | **Sliders Scroll Wheel** | Adjust volume or brightness by 5% per step |
| **System Tray** | **Left Click** | Activate tray application |
| | **Right Click** | Open application context menu & Pin/Fold options |
| | **Chevron Click** | Expand or collapse folded tray icons |
| **Any Popup** | **Escape / Click Outside** | Dismiss popup or detail card |

---

## Architecture Overview

Remy'a Bar utilizes a hybrid architecture engineered for responsiveness and reliability:

```
┌────────────────────────────────────────────────────────┐
│                   Flutter UI Layer                     │
│  - MD3 Expressive widgets & spring animations          │
│  - Per-monitor GTK Layer-Shell views                   │
│  - Floating Flutter popup host (BarPopup / Popups)     │
└───────────────────────────▲────────────────────────────┘
                            │ flutter_rust_bridge 2.13.0
┌───────────────────────────▼────────────────────────────┐
│                    Rust Workspace                      │
│  - remya_bar_hyprland: Tokio Unix socket IPC & events  │
│  - remya_bar_system: Cached /proc, sysfs, GPU & MPRIS  │
│  - System tray SNI host & DBusMenu client              │
└───────────────────────────▲────────────────────────────┘
                            │ D-Bus Signals & Calls
┌───────────────────────────▼────────────────────────────┐
│                Remya Settings Ecosystem                │
│  - Shared themes, colors, power profiles, and settings │
└────────────────────────────────────────────────────────┘
```

- **Low Resource Usage**: Rust handles all heavy lifting—sampling hardware sensors, parsing Hyprland socket streams, and hosting D-Bus interfaces—sharing a single cached state across all outputs.
- **Native Wayland Integration**: Built directly against `gtk-layer-shell` for true Wayland surface management, automatic exclusive zone handling, and zero-flicker monitor hotplugging.
- **Decoupled Architecture**: Configuration, themes, power profiles, and layout persistence are managed via the companion [Remya Settings](https://github.com/remyhuang03/remya-settings) service (`top.remya.settings`), which emits D-Bus signals that Bar follows to update state.

---

## License

Licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE), matching `remya_settings`.
