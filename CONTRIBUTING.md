# Contributing to Remy'a Bar

Bug reports, documentation fixes, tests, and code contributions are welcome.
Please follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Report a problem or suggest a change

Search [existing issues](https://github.com/remyhuang03/remya-bar/issues?q=is%3Aissue)
first, then [choose an issue template](https://github.com/remyhuang03/remya-bar/issues/new/choose).
Open an issue first for a substantial change so we can agree on scope.
Follow the [security policy](SECURITY.md) for vulnerabilities.

## Set up and make a change

1. Start a topic branch from `main`, for example `fix/startup` or `docs/installation`.
2. Follow the [setup in the README](README.md). Use the Rust toolchain specified in `rust-toolchain.toml`. Install the Flutter SDK pinned in `.fvmrc` with FVM. Check out Remy'a Core as a sibling directory. Use the Core revision pinned in the Linux workflow to reproduce CI.
3. Follow the [project guidelines](AGENTS.md) and add a regression test for a non-trivial fix.
4. Use Conventional Commits, for example `fix(linux): handle startup errors`.
5. Open a pull request against `main` and record the changes and validation results.

## Verify your change

Run the checks relevant to your change. The [Linux workflow](.github/workflows/linux.yml) lists the full CI checks.

```bash
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze
fvm flutter test
fvm flutter build linux --debug
cargo fmt --all -- --check
cargo clippy --locked --workspace --all-targets -- -D warnings
cargo test --locked --workspace
git diff --check
```

Test changes that depend on the compositor, hardware or session services in a
real Hyprland session when possible. State what you verified and share only
sanitized logs and attachments.

Maintainers can run **Linux CI** from the Actions tab on `main` to build a
Linux x86_64 candidate. The workflow uploads the archive, build information, and
SHA-256 checksum as an Actions artifact.

See [LICENSE](LICENSE) for the PolyForm Noncommercial License 1.0.0. Verify
dependency and asset compatibility and preserve required notices.
