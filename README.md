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

A modern, fluid desktop status bar for **Hyprland on Linux**, crafted with **Flutter** and **Material Design 3 Expressive**, backed by a high-performance **Rust** engine.

Remy'a Bar blends refined desktop aesthetics with deep Linux system integration. Drawing visual inspiration from [illogical-impulse's Bar](https://github.com/end-4/dots-hyprland/tree/main/dots/.config/quickshell/ii/modules/ii/bar), it delivers smooth animations, real-time compositor awareness, artwork-adaptive media controls, rich hover dashboards, and an Android/macOS-style Quick Settings control center—all while keeping system overhead minimal.

> [!CAUTION]
> **Early Development & Preview Only — Not Ready for Daily Use**
>
> This repository is currently intended strictly for design preview and development reference. Use at your own risk on real systems.

---

## Features

### 🪟 Smart Workspaces & Window Tracking
- **Application-Aware Slots**: Displays live icons for the active windows on each workspace, automatically featuring the primary application and stacked previews for multi-window workspaces.
- **Multi-Monitor Presence**: Distinguishes between workspaces on the current display and other connected monitors with distinct visual styling and monitor identity tags.
- **Super Key Inspection**: Hold the `Super` key at any moment to reveal underlying workspace numbers and remote monitor indicators.
- **Urgency Alerts**: Highlights windows requesting user attention with distinct urgency badges.
- **Special Workspace Support**: Smoothly previews scratchpad/special workspaces with background dimming.
- **Effortless Navigation**: Click to switch or create workspaces, scroll with the mouse wheel (`r±1`), use the mouse back button to toggle special workspaces, or right-click to open a keyboard-navigable workspace overview.
- **Active Window Info**: Shows the focused app ID above its window title, compacting with ellipsis when space is tight. The app ID line can be turned off in Settings.

### 🎵 Dynamic Media Player
- **Artwork-Adaptive Theming**: Both the bar's media pill and its expanded control card dynamically sample colors from the currently playing album art, creating a harmonious look for every track.
- **At-a-Glance Progress**: Real-time progress bar with marquee title scrolling for longer track names.
- **Rich Media Card**: Hover or click to access full playback controls (play/pause, previous/next, track seeking) and master audio output volume.

### 📊 Hardware & Resource Monitor
- **Compact Gauges**: Circular sector indicators provide instant visual readouts for CPU, RAM, Swap, Network upload/download, and GPU utilization (DRM sysfs & NVIDIA).
- **Live 60-Second History**: Hover over the monitor capsule to reveal detailed metric cards with real-time rolling graphs and network totals for the day.
- **Task Manager Shortcut**: Quick-launch button to jump straight into your preferred desktop system monitor.
- **Efficient Caching**: Shared background sampling engine ensures smooth metrics without redundant disk or driver polling.

### 🎛️ Quick Settings Control Center
- **Slide-Out Panel**: An Android-style quick settings drawer accessible by clicking the Wi-Fi, Bluetooth and volume status toggle, clicking the clock, or pressing `Super + A`.
- **Hardware Sliders**: Smooth adjustments for Display Brightness (targeting your active monitor), Sound Output Volume (with right-click output device selector), and Microphone Input Volume.
- **Connected Quick Toggles**:
  - **Wi-Fi**: Scan nearby networks, connect, disconnect, forget, and join hidden networks.
  - **Bluetooth**: Scan, pair, connect, and manage wireless peripherals.
  - **Night Light**: Toggle screen temperature (hyprsunset) following your configured schedule.
  - **Power Profiles**: Switch between Performance, Balanced, and Power Saver modes.
  - **Keep Awake**: Inhibit screen idle and sleep (hypridle) on demand with automatic startup checks.
  - **Dark Mode**: Instantly switch between light and dark Material Design themes.
  - **Mic Mute**: One-click mute for your active PipeWire input device.
- **Customizable Tile Layout**: Reorder quick tiles and hide unused toggles with settings saved automatically.
- **Session Actions**: Quick shortcuts for Lock, Log Out, Restart, and Shut Down, protected with confirmation timers against accidental clicks.

### 📥 Intelligent System Tray
- **StatusNotifierItem (SNI) & DBusMenu**: Full support for modern Linux tray applications (Steam, Discord, OBS, Telegram, etc.).
- **Pinned & Folded Apps**: Keep your most important icons visible while folding secondary apps into an expandable tray with smooth reveal animations.
- **Context Menus**: Right-click any tray icon to open native application menus alongside pin/fold management.

### 🔔 Notifications
- **Built-in Notification Service**: Remy'a Bar is the `org.freedesktop.Notifications` server, with actions, body markup and links, images, and progress (`value` hint). Stop dunst, mako, swaync or another shell's notification service first; while another one owns the name, the bell is crossed out and the card says so.
- **Popups**: New notifications slide in at the top left of the output focused when they arrive, with an optional sound. Hovering pauses their timers; Critical notifications stay until closed.
- **Notification Center**: Hover or click the bell to see history grouped by app, run actions, dismiss or clear all.
- **Do Not Disturb**: Toggle it in the card, the Quick Settings tile or Remy'a Settings → Notifications, or turn it on automatically on a schedule or while an app is full screen. It silences popups and sounds except Critical notifications, incoming calls and priority apps; history still collects everything. Popup duration and sounds are also set there.

### AI Quota
- Install the optional `codexbar-cli` system package and make its `codexbar`
  executable available on the bar service's `PATH`. Authenticate your providers
  in [CodexBar](https://github.com/steipete/CodexBar).
- Use **AI** in Remya Settings to choose the tracked providers, pin up
  to three to the pill and set the low-quota threshold (20% by default). Without
  pins the pill shows the first three providers with data; the card shows every
  tracked provider. Hover over or click the pill for details. Right-click or use
  **Refresh** to update immediately.
- The default layout places AI Usage immediately before Battery in the same
  group. Use the pill layout editor to move or hide it.

### 🔋 Battery & Power Management
- **Battery Capsule**: Clear visual readout with percentage, dynamic charging bolt, and remaining runtime estimates.
- **Detailed Power Card**: Hover to inspect battery health, charge cycle counts, current power draw, and Energy Saver thresholds.

### 📅 Time, Date & Interactive Calendar
- **Live Clock**: Clean date and time display with configurable seconds synchronization.
- **Datetime Dashboard**: Hover or click to view local time with seconds, UTC offset, ISO week number, day of year, and UTC reference time.
- **Interactive Calendar**: Monday-first calendar with month navigation and quick access to Remya Settings Date & Time configuration.

### 🖥️ Multi-Monitor & Smart Fullscreen
- **Per-Monitor Layer Shell**: Automatic 40px capsule bar across every connected output with zero keyboard focus stealing and exclusive space reservation.
- **Smart Fullscreen Auto-Hide**: The bar automatically conceals itself and releases reserved space when a fullscreen application is active on that output, smoothly returning when leaving fullscreen.
- **Responsive Layout**: Adapts gracefully across display widths:
  - $\ge$ 700 px: Pills in evenly spaced groups that you can reorder, regroup, or hide in Remy'a Settings (notifications, window, resources and media; workspaces and clock; tray; battery and Quick Settings by default; one group can be centered).
  - Content that does not fit scrolls horizontally instead of being clipped.
  - < 700 px: Compact mode showing centered clock and essential control center launcher.

### 🎨 Material Design 3 Expressive
- **Unified Design System**: Built with MD3 Expressive styling, smooth spring curves, high-contrast surface roles, and Inter typography with comprehensive CJK fallbacks.
- **System Theme Sync**: Live color scheme, accent seed, and dark/light mode synchronization driven by Remya Settings over D-Bus.

---

## Getting Started

### Prerequisites

- **Desktop Environment**: Hyprland (or Wayland compositor supporting `wlr-layer-shell-unstable-v1`).
- **Dependencies**:
  - `gtk-layer-shell` (system package)
  - Wayland client and XKB libraries (`wayland`, `libxkbcommon` on Arch), with `wayland-scanner` at build time
  - `inter-font` and `noto-fonts-cjk`
  - NetworkManager and BlueZ (for network & Bluetooth toggles)
  - NVIDIA Management Library (`libnvidia-ml.so.1`, provided by `nvidia-utils` on Arch) for NVIDIA GPU metrics. Without NVML, the resource monitor hides NVIDIA GPUs.
  - Remya Settings (`remya_settings`, provides theme & system D-Bus services)

### Installation

Install Remy'a Bar using the automated installer into `~/.local/bin` and `XDG_DATA_HOME`:

```bash
fvm flutter build linux --release
python tool/install.py
```

The installer also writes and enables the `top.remya.bar.service` systemd user
unit, so the bar starts with the graphical session (`graphical-session.target`,
which needs `WAYLAND_DISPLAY` and `HYPRLAND_INSTANCE_SIGNATURE` in the user
manager environment, as uwsm provides). Reinstalling stops the unit, replaces
the bundle and starts it again. Remove any other autostart entry for the bar so
it does not start twice; `systemctl --user disable --now top.remya.bar.service`
turns autostart off.

The installer verifies runtime libraries, registers the desktop entry, installs icons, and places the executable `remya_bar` in your user PATH.

### Hyprland Configuration

Add the bar to your Hyprland startup configuration:

```ini
# ~/.config/hypr/hyprland.conf

# Autostart Remy'a Bar
exec-once = remya_bar
```

To bind a shortcut (e.g. `Super + A`) to toggle the Quick Settings control center:

```ini
# Hyprland bind to toggle Quick Settings sidebar
bind = SUPER, A, exec, gdbus emit --session --object-path /top/remya/bar --signal top.remya.bar.Shortcuts.ToggleSidebar "$HYPRLAND_INSTANCE_SIGNATURE"
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
| **Notifications** | **Click / Hover** | Open the notification center and Do not disturb |
| | **Click a notification** | Run its default action, if it has one |
| **Quick Settings** | **Click Icon / Clock** | Toggle the Quick Settings control center |
| | **`Super + A`** | Toggle the Quick Settings control center from anywhere |
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
                            │ D-Bus
┌───────────────────────────▼────────────────────────────┐
│                Remya Settings Ecosystem                │
│  - Shared themes, colors, power profiles, and settings │
└────────────────────────────────────────────────────────┘
```

- **Low Resource Usage**: Rust handles all heavy lifting—sampling hardware sensors, parsing Hyprland socket streams, and hosting D-Bus interfaces—sharing a single cached state across all outputs.
- **Native Wayland Integration**: Built directly against `gtk-layer-shell` for true Wayland surface management, automatic exclusive zone handling, and zero-flicker monitor hotplugging.
- **Decoupled Architecture**: Configuration, themes, and persistence are cleanly managed via the companion [Remya Settings](https://github.com/remyhuang03/remya-settings) service.

---

## License

Licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE), matching `remya_settings`.
