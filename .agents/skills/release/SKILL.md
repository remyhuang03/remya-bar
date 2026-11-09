---
name: release
description: Prepare, validate, install, and publish a Remya Bar release for Linux through GitHub Releases and AUR.
---

# Remya Bar Release

Use a separate release branch and worktree based on the up-to-date `main`. Keep unrelated local work out of the candidate. For a paired release, put the two worktrees next to each other as `remya-settings` and `remya-bar`. Prepare, install, and publish Settings first. Bar builds against the sibling Settings client.

Use `0.1.0-dev.YYYYMMDD.N` for dev releases, with a `v` prefix for Git tags and `_` in place of `-` for AUR `pkgver`. Use the same version in both projects for a paired release. Run Flutter debug checks and release builds sequentially in each worktree.

## Phase 1 · Validate, build, and install the candidate

1. Run the preparation script from the release worktree with the pinned FVM toolchain, the Arch packaging tools, and an active Hyprland session.

   ```bash
   python3 .agents/skills/release/scripts/prepare_release.py --version 0.1.0-dev.20261109.0
   ```

   The script synchronizes the Flutter and Rust versions and lockfiles, regenerates Rust notices, and runs Dart format, Flutter analysis and tests, Rust format, Clippy, workspace tests, and `git diff --check`. Bar treats Clippy warnings as errors and runs the native lifecycle and Hyprland window smoke checks. Use `--skip-desktop-smoke` only if those checks already passed for the candidate.

   The script builds the Linux x86_64 release, stages a `.tar.zst`, `SHA256SUMS`, `PKGBUILD`, `.SRCINFO`, and `manifest.json` in `build/release/<version>/`, then unpacks the archive and runs its `tool/install.py`. It checks the installed bundle and the active user service. Exercise the installed app and verify its command and desktop entry.

   Omitting `--version` selects or resumes the local dev sequence for today. `--bump` increments it. `--skip-version-sync` resumes with matching version files. Use `--skip-checks` only when the same candidate has already passed the relevant checks.

2. Check the staged files and test the AUR package locally on Arch with the release archive beside the PKGBUILD. Use `makepkg --nodeps` for a packaging-only check if dependencies are unavailable. Build and dependency validation on a clean Arch host are separate checks.
3. Run the read-only publisher preflight. It checks the source, built and installed bundles, archive, and packaging metadata.

   ```bash
   python3 .agents/skills/release/scripts/publish_release.py --version 0.1.0-dev.20261109.0 --dry-run
   ```

Present the candidate, validation results, and artifact paths. Stop for explicit approval of the installed candidate. The first approval authorizes the README phase.

## Phase 2 · Update README with Gemini

1. After the candidate is approved, run [review_and_update_readme.py](scripts/review_and_update_readme.py). It calls `agy` with `gemini-3.8-flash-medium` in a temporary workspace and copies back only Gemini's README update. Use `--base-ref <ref>` to change the comparison base. Review the result against the approved application and project documentation. If Gemini fails, diagnose the failure before presenting the README for approval.

   ```bash
   python3 .agents/skills/release/scripts/review_and_update_readme.py
   python3 .agents/skills/release/scripts/prepare_release.py --version 0.1.0-dev.20261109.0 --refresh-readme
   ```

2. The refresh verifies the approved bundle and candidate inputs, then updates the archive, SHA-256, and AUR metadata with the README. Repeat the archive and package checks and the publisher dry-run. If candidate inputs or the installed bundle changed, return to Phase 1.

Open each updated `README.md` in MarkText on the workstation for the user's review. Run `marktext README.md` from the corresponding release worktree, or use the installed MarkText desktop launcher if the command is unavailable. Present the README diff and release notes for explicit approval to commit and publish. Stop before any commit, merge, tag, push, or publication.

## Phase 3 · Commit, merge, and publish after README approval

1. Commit the reviewed skill changes separately. Keep approved application changes and release version, lockfiles, notices, and README updates in focused commits. Stage only those paths. Fast-forward `main` and push it after approval. Keep the prepared worktree and its build output until publication is verified.
2. In the prepared worktree, with a clean tree and HEAD matching local and remote `main`, publish the reviewed archive.

   ```bash
   python3 .agents/skills/release/scripts/publish_release.py \
     --version 0.1.0-dev.20261109.0 --confirm-user-approved
   ```

   Add `--notes-file <path>` for reviewed release notes. The script creates or verifies the local annotated tag, pushes it, and publishes the GitHub prerelease with the archive and checksum. If a run stops after the tag push, confirm the tag and check for an existing GitHub release before retrying. Verify the remote tag commit and the downloadable assets.

3. Once the GitHub asset is downloadable and its checksum matches, publish the staged `PKGBUILD` and `.SRCINFO` to `ssh://aur@aur.archlinux.org/remya-bar-bin.git`. Check package ownership and existing contents first. Copy only the two metadata files, review the diff, commit, and push AUR `master`. Verify the AUR version and source URL. For a paired release, finish Settings before Bar.

Run workstation installation and Hyprland smoke checks locally. CI can run non-interactive checks and package artifacts. When adding CI publication, use an explicit dispatch or deployment approval and publish the README-refreshed archive of the approved bundle by checksum. Keep AUR credentials separate from GitHub release credentials.
