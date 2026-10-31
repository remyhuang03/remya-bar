<img src="assets/icons/bar.svg" alt="" width="96" height="96">

# Remy'a Bar

A desktop bar project for **Hyprland on Linux**, using **Flutter**, **Material Design 3 Expressive**, and a **Rust workspace**. Development practices follow `../remya_settings`.

## Current milestone

The bar is a 40-logical-pixel capsule across the top of every connected output, with a settings icon that opens Remya Settings. It uses the top layer, reserves space for normal windows, has no title bar, and does not take keyboard focus. GDK display events create and destroy bars when outputs change, using monitor objects rather than persistent display indices. The application stays alive when no outputs are connected. Rust provides Hyprland request/reply IPC and a process-wide live event subscription. The installed bar follows Remya Settings' effective MD3E theme through D-Bus. Bar text and Flutter popups use the system Roboto Flex font; font files are not bundled, and the installer checks this runtime dependency. Other system modules are not implemented; Bar does not write settings itself.

Window behavior uses the existing [gtk-layer-shell](https://github.com/wmww/gtk-layer-shell) system library through the native GTK runner. Each output gets a separate GTK window and Flutter view. A Wayland compositor supporting layer-shell, such as Hyprland, is required; unsupported sessions exit with an error.

## Layout

```text
Cargo.toml                Root Rust workspace
lib/
  main.dart               Flutter startup and license registration
  app.dart                Application composition and theme
  features/               Hyprland adapter and Settings button/debug lookup
  src/rust/core/          Empty backend crate
  src/rust/hyprland/      Hyprland transport and generated Rust bridge
  src/rust/hyprland_bridge/ Generated Dart bridge
linux/                    GTK layer-shell runner and output enumeration
test/                     Widget and live Hyprland smoke tests
```

Flutter stays at the repository root. Rust crates live under `lib/src/rust/` and are registered in the root workspace. The Hyprland feature uses `flutter_rust_bridge` 2.13.0. Regenerate bindings with the matching generator and `flutter_rust_bridge.yaml`.

## Settings dependency and installation

Application ID: `top.remya.bar`; executable: `remya_bar`. Build Settings and Bar
independently with their pinned toolchains. Keep the Settings checkout adjacent
when building Bar: its public client package is a local source dependency.
Installed bundles need no source checkout.

Install Settings first, then from this repository run:

```bash
fvm flutter build linux --release
python tool/install.py
```

The installer follows XDG_DATA_HOME, registers the desktop entry and icon, and
creates `~/.local/bin/remya_bar`. Configuration policy, debug overrides, IPC behavior,
and dependency boundaries are documented in [backend integration](docs/backend.md).
See [Settings' complete CLI/D-Bus API](../remya_settings/docs/public-api.md) and
[the shared XDG layout](../remya_settings/docs/xdg-layout.md).

## Development

Install the **Roboto Flex system font** (Arch: `sudo pacman -S ttf-roboto-flex`), fontconfig, FVM, Rust via rustup, and Linux Flutter build prerequisites (Clang, CMake, Ninja, pkg-config, GTK 3 development libraries, and gtk-layer-shell). On Arch Linux, the layer-shell package is `gtk-layer-shell`; Debian/Ubuntu need `libgtk-layer-shell-dev` for building and `libgtk-layer-shell0` at runtime. Keep gtk-layer-shell installed when running the bundle: it is dynamically linked under LGPL-3.0-or-later. From the repository root:

```bash
fvm install
fvm flutter pub get
# Build the sibling Settings debug bundle once for the gear button.
# Run fvm flutter build linux --debug from ../remya_settings.
fvm flutter run -d linux --no-start-paused
```

FVM pins Flutter to `3.47.8`; `rust-toolchain.toml` selects stable Rust with rustfmt and Clippy. See [AGENTS.md](AGENTS.md) for architecture, coding, validation, and Git rules.

Use `--no-start-paused` so all per-output engines can render during development.

```bash
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze
fvm flutter test
fvm flutter build linux --debug
python test/bar_window_smoke.py  # Requires a running Hyprland session.
cmake --build build/linux/x64/debug --target bar_lifecycle_test
build/linux/x64/debug/bundle/bar_lifecycle_test
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
git diff --check
```

The native lifecycle test emits client-side GDK monitor events without reconfiguring the desktop. It checks duplicate notifications, teardown, engine release, recovery after all bar windows are removed, and repeated activation. The pinned Flutter SDK logs `The implicit view cannot be removed` on view teardown; treat successful lifecycle checks separately from this upstream diagnostic. Physical cable hotplug still needs hardware verification.

Licensed under [PolyForm Noncommercial License 1.0.0](LICENSE), matching `remya_settings`.
