# Agent Instructions & Development Guidelines

## Project Scope
- `remya_bar` is a desktop bar project for Hyprland on Linux, using Flutter and Rust.
- The current milestone includes a 40-pixel capsule bar, a Settings launcher, shared MD3E theme integration, and Rust Hyprland request/event IPC. Other system modules are not implemented.
- Use the system `gtk-layer-shell` library in the native GTK runner for bar window behavior: top layer, top/left/right anchors, a 40-logical-pixel height, automatic exclusive space, no decorations, and no keyboard focus. Keep one bar window and bar Flutter view per GDK monitor; use GDK display signals for hotplug and keep the application alive with no connected outputs. Do not use display indices as persistent identities.
- Reuse development practices from `../remya_settings`, not its settings UI, catalog renderer, assets, or window geometry. The Bar application ID is `top.remya.bar`; Settings uses `top.remya.settings`. Executables remain `remya_bar` and `remya_settings`.
- Add real bar behavior and platform integrations only when required by a concrete task. Do not automatically modify Hyprland configuration or other desktop settings.
- Never present sample values as detected system state or claim an integration works merely because its UI renders.
- Write rule documents, including `AGENTS.md`, in English.

## Architecture: Monorepo + Feature-first + Rust Workspace
- Keep Flutter at the repository root and manage Rust crates through the root `Cargo.toml` workspace.
- Organize Flutter code under `lib/features/<feature>/`, keeping each feature's UI, state, and data access together. Add internal layers only when needed.
- Keep application composition in `lib/app.dart` and startup in `lib/main.dart`.
- Put Rust crates under `lib/src/rust/<crate>/`. Group backend functionality by feature; create crates only for concrete responsibility or dependency boundaries.
- `lib/src/rust/core/` is the initial empty backend crate. Do not turn it into a catch-all for unrelated features.
- Extract shared code only when multiple features need it; avoid speculative layers and empty feature scaffolding.
- Implement backend logic and complex or performance-critical computation in Rust. The Hyprland feature uses `flutter_rust_bridge` 2.13.0; use the matching generator and `flutter_rust_bridge.yaml`. Keep the core crate empty.
- Keep generated bridge code separate from handwritten code and regenerate it instead of editing it manually.

## Settings Integration and XDG
- Remya Bar depends on the separately installed Remya Settings application. Use its public `remya_settings_client` package and versioned session D-Bus interface; never import Settings UI, controllers, or system-writing backends.
- Settings owns schemas, defaults, validation, persistence, and system writes. New available operations must work through both its CLI and D-Bus dispatcher and have API documentation and parity tests.
- Keep bar components feature-first. Access Settings through the client contract instead of adding private file parsing or component-specific launch mechanisms.
- Keep installed preferences under XDG_CONFIG_HOME/remya/settings and installation metadata/bundles under XDG_DATA_HOME; ignore relative XDG paths and use specified HOME fallbacks. Do not create unused cache/state directories.
- Debug config priority is Bar repository config/config.local.toml, sibling Settings repository config/config.local.toml, then XDG config. Native runner paths must make repository lookup independent of launch cwd. Release clients use the Settings service. Debug Settings launch uses the sibling debug bundle through the public client opener and must not require installed activation files.
- Preserve the last valid theme on invalid configuration/service errors. Keep the bar surface transparent outside its capsule shape without changing its exclusive zone or focus policy.
- Read `docs/backend.md` and the linked Settings API/XDG documents before changing integration behavior. Update those documents with contract changes.

- Render tooltips and other floating component content with Flutter through the shared `BarPopup`/`BarPopupApp` host. Native GTK owns only surface placement, visibility, focus policy, and lifetime; never draw popup text or UI with GTK. Use `BarTooltip` for hover hints and pass the owning Settings theme.

## Toolchains & Dependencies
- Always invoke Flutter and Dart as `fvm flutter ...` and `fvm dart ...`, never through global SDK commands.
- `.fvmrc` pins Flutter to `3.47.8`. Do not change versions without explicit instruction. Run `fvm install` for fresh setup.
- Use the root `rust-toolchain.toml` and inherit common crate metadata from the workspace.
- Commit `.fvmrc`, `pubspec.lock`, and `Cargo.lock`; ignore SDK caches, build output, and local configuration.
- Reuse existing helpers and dependencies. Add packages only for concrete requirements.
- Prefer existing packages and platform libraries over implementing equivalent behavior. Check available packages before writing custom integrations.
- The system `gtk-layer-shell` library is required at build time and runtime. Keep this LGPL library dynamically linked.
- This project uses the PolyForm Noncommercial License 1.0.0 (`LICENSE`), matching `remya_settings`.
- Check dependency license compatibility before adding code or libraries and preserve third-party notices. Prefer permissive licenses (MIT, BSD, Apache-2.0, ISC, Zlib, Unlicense). LGPL libraries must remain dynamically linked or separate processes; do not introduce GPL, AGPL, SSPL, or other incompatible strong-copyleft code.

## Coding & UI
- Use dot shorthand wherever supported and the expected type is unambiguous. Keep explicit types when shorthand cannot resolve correctly.
- Split complex components into smaller objects with clear responsibilities. Keep small, non-reusable components private in the same file and composition shallow.
- All UI must follow Material Design 3 Expressive (MD3E).
- Import `package:material_ui/material_ui.dart` instead of `package:flutter/material.dart`.
- Enable Material 3 and Expressive color schemes; follow the design system for spacing, shape, typography, and motion.
- Preserve keyboard navigation, visible focus, readable contrast, and scrolling at supported window sizes.
- Keep tooltips and other user-facing hints concise. Prefer a short name or status over an action sentence; use `Settings`, not `Open Remya Settings`. Put detailed diagnostics in logs or an appropriate detail view.
- Target Linux only; do not generate other platforms without explicit instruction.
- Let the native runner own initial window setup and respect Wayland compositor policy. Never automatically modify user desktop configuration.

## Validation
- Run relevant checks before presenting changes for review:
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
- Run `fvm flutter pub get` after dependency changes. Use `fvm flutter run -d linux --no-start-paused` for interactive verification so all per-output engines render. Run release builds when release behavior changes.
- After development and verification, stop all bar instances started for the task and confirm their layer surfaces and reserved space are released. Do not leave development bars running or stop unrelated desktop bars.
- Keep durable tests for non-trivial logic and regressions; remove temporary UI inspection tests after verification and avoid duplicate coverage.
- Keep debug and release builds/tests sequential within this repository because Flutter shares ephemeral native engine files between modes.
- A successful build does not verify desktop behavior. Check affected window behavior and interactions on the real desktop; report untested boundaries.
- Validate configuration input, preserve the last valid state on errors, and use atomic persistence when writing configuration is introduced. Never commit secrets or machine-specific configuration.

## Git Workflow
- Develop and validate on a separate branch using `<type>/<short-description>` with lowercase words and hyphens, such as `feat/appearance` or `chore/initialize-project`.
- Use stacked commits when appropriate to split multi-step, dependent changes into small, focused, reviewable commits.
- Follow Conventional Commits: `<type>(<scope>): <description>`. Use a lowercase imperative description without a final period; mark breaking changes with `!` or a `BREAKING CHANGE:` footer.
- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, and `revert`.
- Inspect diffs, stage only intended paths, and preserve unrelated changes.
- Commit approval is mandatory: show completed changes and validation results before requesting explicit user review approval to run `git commit`.
- Do not push or merge without user authorization. Verify remote refs after authorized delivery.
