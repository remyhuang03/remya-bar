# Agent Instructions & Development Guidelines

## Project Scope
- `remya_bar` is a desktop bar project for Hyprland on Linux, using Flutter and Rust.
- The current milestone includes a 40-pixel capsule bar, a Settings launcher, shared MD3E theme integration, and Rust Hyprland request/event IPC. Other system modules are not implemented.
- Use the system `gtk-layer-shell` library in the native GTK runner for bar window behavior: top layer, top/left/right anchors, a 40-logical-pixel height, automatic exclusive space, no decorations, and no keyboard focus. Keep one bar window and bar Flutter view per GDK monitor; use GDK display signals for hotplug and keep the application alive with no connected outputs. Do not use display indices as persistent identities.
- Reuse development practices from `../remya-settings`, not its settings UI, catalog renderer, assets, or window geometry. The Bar application ID is `top.remya.bar`; Settings uses `top.remya.settings`. Executables remain `remya_bar` and `remya_settings`.
- Add real bar behavior and platform integrations only when required by a concrete task.

## Architecture: Monorepo + Feature-first + Rust Workspace
- Keep Flutter at the repository root and manage Rust crates through the root `Cargo.toml` workspace.
- Organize Flutter code under `lib/features/<feature>/`, keeping each feature's UI, state, and data access together. Add internal layers only when needed.
- Keep application composition in `lib/app.dart` and startup in `lib/main.dart`.
- Put Rust crates under `lib/src/rust/<crate>/`. Group backend functionality by feature; create crates only for concrete responsibility or dependency boundaries.
- `lib/src/rust/core/` is the initial empty backend crate. Do not turn it into a catch-all for unrelated features.
- Extract shared code only when multiple features need it; avoid speculative layers and empty feature scaffolding.
- Implement backend logic and complex or performance-critical computation in Rust. The Hyprland feature uses `flutter_rust_bridge` 2.13.0; use the matching generator and `flutter_rust_bridge.yaml`. Keep the core crate empty.
- Keep generated bridge code separate from handwritten code and regenerate it instead of editing it manually.

## Core Integration and XDG
- Remya Bar depends on separately installed Remya Core (`remyad`, CLI `remya`, session D-Bus `top.remya.Core1` at `/top/remya/Core1`, interface `top.remya.Core1`). Use the pure Dart `remya_client` and Flutter `remya_ui` packages from `../remya-core/packages/` during development. Never import Settings GUI or backend code.
- Bar uses the same sibling path dependencies for development and candidate builds. CI checks out and verifies the full `CORE_REVISION` in `.github/workflows/linux.yml`, then records it in candidate build metadata.
- Core owns system settings, shared theme, validation and atomic persistence. Bar owns its preference schemas/defaults in `linux/packaging/remya-bar.json` and uses `BarPreferences` over `AppPreferences('remya-bar')` exclusively. Never read or write app preference files directly. Recheck cross-field constraints in Dart and keep the last valid state on errors.
- Install the registration at `$XDG_DATA_HOME/remya/apps/remya-bar.json`. Core persists its values at `$XDG_CONFIG_HOME/remya/bar/settings.toml`; system settings live in `remya/system/`, shared theme in `remya/shared/theme.toml`.
- Use revision-checked `Replace` for tray read-modify-write and sidebar editors; surface Core conflicts without retrying or overwriting another view.
- Debug theme priority is Bar `config/config.local.toml`, sibling Core `config/shared/theme.toml`, then installed `remya/shared/theme.toml`. The native runner supplies the absolute repository root independently of launch cwd. Release uses the service theme controller from `remya_ui`.
- Use the public `openRemyaSettings` opener for system pages. Bar preference entry points use Bar's own `--settings [page]` window, forwarded through GApplication to the resident instance. Its desktop file provides `[Desktop Action settings]`. Bar, popup, and settings views share the application engine. Settings views are ordinary GTK toplevels, and closing one destroys only its view.
- Read `docs/backend.md` and Core's linked public API, XDG and app-preferences documents before changing contracts; update documentation with contract changes. Do not add compatibility aliases, removed-interface fallbacks or automatic migration.
- Preserve the last valid theme on invalid configuration/service errors. Keep the bar surface transparent outside its capsule shape without changing its exclusive zone or focus policy.
- Render tooltips and floating content with Flutter through `BarPopup`/`BarPopupApp`. GTK owns surface placement, visibility, focus policy and lifetime only. Use `BarTooltip` for concise hints with the owning Remya theme.

## Toolchains & Dependencies
- The system `gtk-layer-shell` library is required at build time and runtime. Keep this LGPL library dynamically linked.

## Coding & UI
- Apply setting changes immediately when the setting supports immediate application and doing so is appropriate; do not add an unnecessary Apply button.
- For settings that require a system restart, show a global "Reboot to apply" status bar with Restart now and Later actions, and a local explanation beside the setting. State application restart or sign-in requirements accurately when a full reboot is unnecessary.
- In settings, use `remya_ui` controls instead of their Material counterparts: `SettingsSegmentedButton` (solid connected segments, optional `SettingsSegment.icon`) or `SettingChoice` for single choices, never Material `SegmentedButton`.
- Keep tooltips and other user-facing hints concise. Prefer a short name or status over an action sentence; use `Settings`, not `Open Remya Settings`. Put detailed diagnostics in logs or an appropriate detail view.
- Let the native runner own initial window setup and respect Wayland compositor policy.

## Validation
- Run bar-specific checks as relevant before presenting changes for review:
  ```bash
  python test/bar_window_smoke.py  # Requires a running Hyprland session.
  cmake --build build/linux/x64/debug --target bar_lifecycle_test
  build/linux/x64/debug/bundle/bar_lifecycle_test
  ```
- Use `fvm flutter run -d linux --no-start-paused` for interactive verification. Run release builds when release behavior changes.
- After development and verification, stop all bar instances started for the task and confirm their layer surfaces and reserved space are released. Do not leave development bars running or stop unrelated desktop bars.
- `tool/install.py` installs and enables the `top.remya.bar.service` systemd user unit (graphical-session.target) and restarts it on the new bundle. On this workstation the installed bar stays autostarting and running: do not disable or stop that unit during cleanup; stop only the extra development or verification instances you started.

<!-- BEGIN:remya-shared profiles=base,source-length,rust,flutter-app,workstation-install,release-skill -->
<!-- Generated from remya-apps-skills/rules/. Do not edit manually; run remya-apps-skills/rules/sync.py. -->

## Shared Remya Guidelines

- Write rule documents, including `AGENTS.md`, in English.
- Respect XDG base directories (`XDG_CONFIG_HOME`, `XDG_DATA_HOME`); ignore relative XDG values and use absolute `$HOME` fallbacks; do not create unused cache/state directories. Never automatically modify user Hyprland or desktop configuration.
- License & dependencies: PolyForm Noncommercial License 1.0.0 (`LICENSE`). Check dependency license compatibility before adding code or libraries and preserve third-party notices. Prefer permissive licenses (`MIT`, `BSD`, `Apache-2.0`, `ISC`, `Zlib`, `Unlicense`). Keep `LGPL` libraries dynamically linked or in separate processes; never introduce `GPL`, `AGPL`, `SSPL`, or incompatible strong-copyleft code. Reuse existing helpers/packages.
- Validation hygiene: Keep durable tests for non-trivial logic and regressions; remove obsolete, duplicate, or temporary UI-inspection tests before committing. Validate configuration input, preserve the last valid state on errors, and use atomic persistence.
- Git workflow: Develop and validate on a separate branch `<type>/<short-description>` (lowercase words and hyphens). Use small, focused stacked commits when appropriate. Follow Conventional Commits: `<type>(<scope>): <description>` (lowercase imperative description without a final period; mark breaking changes with `!` or `BREAKING CHANGE:`). Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`. Inspect diffs, stage only intended paths, and preserve unrelated changes. Commit approval is mandatory: show completed changes and validation results before requesting explicit user approval to run `git commit`. Approval to commit also authorizes merging ready branches into `main`, deleting fully merged local branches (and clean worktrees), pushing `main` to `origin`, and verifying remote refs.

### Source Length Check

- Run `python tool/check_source_length.py` as part of local validation (warns for Rust and Dart files over 800 physical lines, including comments and blank lines). Review every reported file against the single-responsibility principle and refactor files that mix responsibilities.
- When a reviewed file should stay together, run `python tool/check_source_length.py add <path> --reason "<why it should stay together>"` and include the updated `tool/source_length_exceptions.json` (keyed by SHA-256; modified files still over 800 lines require another review).

### Rust Toolchain & Validation

- Use the root `rust-toolchain.toml` (do not change toolchain channels without explicit instruction) and inherit common crate metadata from the workspace where applicable. Commit `Cargo.lock`; ignore build output.
- Run before presenting changes: `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo test --workspace`.

### Flutter Linux App Guidelines

- Always invoke Flutter and Dart via `fvm flutter ...` and `fvm dart ...`, never global SDK commands.
- Target Linux only.
- All UI must follow Material Design 3 Expressive (MD3E): import `package:material_ui/material_ui.dart` instead of `package:flutter/material.dart`; enable Material 3 and Expressive color schemes; follow the design system for spacing, shape, typography, and motion.
- Use dot shorthand wherever supported and the expected type is unambiguous. Split complex widgets by responsibility and keep small single-use widgets private.
- Run `fvm flutter pub get` after dependency changes. Run `fvm dart format --output=none --set-exit-if-changed lib test`, `fvm flutter analyze`, `fvm flutter test`, and `fvm flutter build linux --debug` as relevant. Keep debug and release builds sequential because Flutter shares ephemeral native engine files between modes.
- A successful build does not verify desktop behavior; verify affected window behavior and interactions on the real desktop and report untested boundaries.

### Workstation Release Install

- After application or daemon code changes, finish validation, rebuild the release bundle/binaries, and run `python tool/install.py` on this workstation as the final implementation step so the user can manually review the installed application. Source changes and successful builds alone do not complete the task.
- Verify that the installed bundle, command, desktop entry, and any service unit use the updated build, and exercise the installed application. Preserve user configuration and unrelated installations. Install `remya-core` before dependent apps (and Settings before Bar when both change). Stop verification instances you started without disabling persistent user units.

### Releases

- Use the user-level `remya-release` skill from [remya-apps-skills](https://github.com/remyhuang03/remya-apps-skills) for Linux release work (install via `npx skills add remyhuang03/remya-apps-skills --skill remya-release --agent codex --global`, then invoke `$remya-release`). Release `remya-core` first at every stage.
<!-- END:remya-shared -->
