#!/usr/bin/env python3
"""Phase 1 release preparation for Remya Bar (top.remya.bar).

Synchronizes the dev/release version across pubspec.yaml and Cargo.toml,
regenerates third-party Rust notices, runs the validation suite, builds the
release bundle, installs it on the workstation via tool/install.py, and stages
the GitHub Release archive + AUR PKGBUILD/.SRCINFO under build/release/<version>/.

After candidate approval, --refresh-readme repackages the same bundle.
Does NOT commit, tag, push, or publish.
"""
from __future__ import annotations

import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
from release_checks import VERSION, bundle_sha256, git, installed_bundle, sha256_file, source_sha256

APP_ID = "remya_bar"
PACKAGE = "top.remya.bar"
UNIT = f"{PACKAGE}.service"
DEV_VERSION_RE = re.compile(r"^(\d+\.\d+\.\d+)-dev\.(\d{8})\.(\d+)$")


def repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


def skill_root() -> Path:
    return Path(__file__).resolve().parents[1]


def run(cmd: list[str], *, cwd: Path, check: bool = True, capture: bool = False) -> subprocess.CompletedProcess[str]:
    print(f"==> $ {' '.join(cmd)}", flush=True)
    return subprocess.run(cmd, cwd=cwd, check=check, text=True, capture_output=capture)


def read_current_versions(root: Path) -> tuple[str, str]:
    pubspec = (root / "pubspec.yaml").read_text()
    cargo = (root / "Cargo.toml").read_text()
    pub_match = re.search(r"^version:\s*(\S+)\s*$", pubspec, re.MULTILINE)
    cargo_match = re.search(r'^version\s*=\s*"([^"]+)"\s*$', cargo, re.MULTILINE)
    if not pub_match or not cargo_match:
        raise RuntimeError("Unable to parse version from pubspec.yaml or Cargo.toml")
    return pub_match.group(1), cargo_match.group(1)


def existing_tag_sequences(root: Path, base: str, date_str: str) -> list[int]:
    prefix = f"v{base}-dev.{date_str}."
    result = subprocess.run(
        ["git", "tag", "--list", f"{prefix}*"],
        cwd=root,
        check=True,
        text=True,
        capture_output=True,
    )
    sequences: list[int] = []
    for line in result.stdout.splitlines():
        tag = line.strip()
        if tag.startswith(prefix):
            tail = tag[len(prefix):]
            if tail.isdecimal():
                sequences.append(int(tail))
    return sorted(sequences)


def resolve_target_version(root: Path, requested: str | None, *, bump: bool, allow_stable: bool) -> str:
    pub_ver, cargo_ver = read_current_versions(root)
    if requested:
        if VERSION.fullmatch(requested) and ("-dev." in requested or allow_stable):
            return requested
        raise ValueError(
            f"Invalid version {requested!r}: expected <major>.<minor>.<patch>-dev.<YYYYMMDD>.<seq> "
            "(e.g. 0.1.0-dev.20261109.0)"
        )

    base_match = re.match(r"^(\d+\.\d+\.\d+)", cargo_ver) or re.match(r"^(\d+\.\d+\.\d+)", pub_ver)
    base = base_match.group(1) if base_match else "0.1.0"
    today = datetime.now().strftime("%Y%m%d")
    tag_seqs = existing_tag_sequences(root, base, today)

    current_match = DEV_VERSION_RE.match(pub_ver)
    if current_match and current_match.group(1) == base and current_match.group(2) == today:
        current_seq = int(current_match.group(3))
        if not bump and current_seq not in tag_seqs:
            return f"{base}-dev.{today}.{current_seq}"
        next_seq = max([current_seq, *tag_seqs]) + 1
        return f"{base}-dev.{today}.{next_seq}"

    next_seq = (max(tag_seqs) + 1) if tag_seqs else 0
    return f"{base}-dev.{today}.{next_seq}"


def sync_version_files(root: Path, version: str) -> None:
    pubspec_path = root / "pubspec.yaml"
    pubspec_text = pubspec_path.read_text()
    new_pubspec, pub_count = re.subn(
        r"^version:[^\S\n]*\S+[^\S\n]*$",
        f"version: {version}",
        pubspec_text,
        count=1,
        flags=re.MULTILINE,
    )
    if pub_count != 1:
        raise RuntimeError("Failed to update version in pubspec.yaml")
    pubspec_path.write_text(new_pubspec)

    cargo_path = root / "Cargo.toml"
    cargo_text = cargo_path.read_text()
    new_cargo, cargo_count = re.subn(
        r'^version[ \t]*=[ \t]*"[^"]+"[ \t]*$',
        f'version = "{version}"',
        cargo_text,
        count=1,
        flags=re.MULTILINE,
    )
    if cargo_count != 1:
        raise RuntimeError("Failed to update version in Cargo.toml")
    cargo_path.write_text(new_cargo)

    run(["fvm", "flutter", "pub", "get"], cwd=root)
    run(["cargo", "metadata", "--offline", "--format-version", "1"], cwd=root, capture=True)
    run([sys.executable, "tool/generate_rust_notices.py"], cwd=root)


def run_validation(root: Path, *, skip_desktop_smoke: bool) -> None:
    run(["fvm", "dart", "format", "--output=none", "--set-exit-if-changed", "lib", "test"], cwd=root)
    run(["fvm", "flutter", "analyze"], cwd=root)
    run(["fvm", "flutter", "test"], cwd=root)
    run(["cargo", "fmt", "--all", "--", "--check"], cwd=root)
    run(["cargo", "clippy", "--workspace", "--all-targets", "--", "-D", "warnings"], cwd=root)
    run(["cargo", "test", "--workspace"], cwd=root)
    run(["git", "diff", "--check"], cwd=root)

    if not skip_desktop_smoke:
        run(["fvm", "flutter", "build", "linux", "--debug"], cwd=root)
        run(["cmake", "--build", "build/linux/x64/debug", "--target", "bar_lifecycle_test"], cwd=root)
        run(["build/linux/x64/debug/bundle/bar_lifecycle_test"], cwd=root)
        if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
            run([sys.executable, "test/bar_window_smoke.py"], cwd=root)
        else:
            print("==> Skipping test/bar_window_smoke.py (no active HYPRLAND_INSTANCE_SIGNATURE)")


def build_release(root: Path) -> str:
    run(["fvm", "flutter", "build", "linux", "--release"], cwd=root)
    return bundle_sha256(root / "build/linux/x64/release/bundle", APP_ID)


def install_staged_release(root: Path, release_dir: Path, version: str, built_hash: str) -> None:
    stem = f"{APP_ID}-{version}-linux-x86_64"
    with tempfile.TemporaryDirectory(prefix=f"{APP_ID}-release-") as temporary:
        extracted = Path(temporary) / stem
        run(["tar", "--zstd", "-xf", str(release_dir / f"{stem}.tar.zst"), "-C", temporary], cwd=root)
        run([sys.executable, "tool/install.py"], cwd=extracted)

    if bundle_sha256(installed_bundle(APP_ID), APP_ID) != built_hash:
        raise RuntimeError("Installed workstation bundle differs from the built bundle")
    run(["systemctl", "--user", "is-active", "--quiet", UNIT], cwd=root)


def render_pkgbuild(version: str, archive_hash: str) -> str:
    template = (skill_root() / "resources/PKGBUILD.bin.in").read_text()
    return (
        template.replace("@UPSTREAM_VER@", version)
        .replace("@PKGVER@", version.replace("-", "_"))
        .replace("@SHA256@", archive_hash)
    )


def stage_release_artifacts(root: Path, version: str, manifest: dict) -> Path:
    release_dir = root / "build/release" / version
    release_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=release_dir.parent) as temporary:
        staging = Path(temporary)
        write_release_artifacts(root, version, manifest, staging)
        for artifact in staging.iterdir():
            if artifact.name != "manifest.json":
                artifact.replace(release_dir / artifact.name)
        (staging / "manifest.json").replace(release_dir / "manifest.json")
    return release_dir


def write_release_artifacts(root: Path, version: str, manifest: dict, release_dir: Path) -> None:
    stem = f"{APP_ID}-{version}-linux-x86_64"
    staging_root = release_dir / stem
    bundle_dst = staging_root / "build/linux/x64/release/bundle"
    bundle_dst.parent.mkdir(parents=True)
    shutil.copytree(root / "build/linux/x64/release/bundle", bundle_dst, symlinks=True)

    (staging_root / "tool").mkdir(parents=True)
    shutil.copy2(root / "tool/install.py", staging_root / "tool/install.py")

    (staging_root / "linux/packaging").mkdir(parents=True)
    shutil.copy2(
        root / "linux/packaging/top.remya.bar.desktop",
        staging_root / "linux/packaging/top.remya.bar.desktop",
    )

    (staging_root / "assets/icons").mkdir(parents=True)
    shutil.copy2(root / "assets/icons/bar.svg", staging_root / "assets/icons/bar.svg")

    (staging_root / "assets/licenses").mkdir(parents=True)
    shutil.copy2(
        root / "assets/licenses/rust-dependencies.txt",
        staging_root / "assets/licenses/rust-dependencies.txt",
    )
    shutil.copy2(root / "LICENSE", staging_root / "LICENSE")
    shutil.copy2(root / "README.md", staging_root / "README.md")

    archive_name = f"{stem}.tar.zst"
    archive_path = release_dir / archive_name
    # Checkouts on filesystems with synthetic modes can appear world-writable.
    run(
        ["tar", "--zstd", "--mode=go-w", "--owner=0", "--group=0", "-cf", str(archive_path), stem],
        cwd=release_dir,
    )
    shutil.rmtree(staging_root)

    archive_hash = sha256_file(archive_path)
    (release_dir / "SHA256SUMS").write_text(f"{archive_hash}  {archive_name}\n")

    (release_dir / "PKGBUILD").write_text(render_pkgbuild(version, archive_hash))
    srcinfo = run(["makepkg", "--printsrcinfo"], cwd=release_dir, capture=True).stdout
    (release_dir / ".SRCINFO").write_text(srcinfo)
    manifest = {**manifest, "archive_name": archive_name, "archive_sha256": archive_hash}
    (release_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


def candidate_source_sha256(root: Path) -> str:
    return source_sha256(root, ":(exclude,top)README.md")


def refresh_readme(root: Path, version: str) -> Path:
    release_dir = root / "build/release" / version
    manifest = json.loads((release_dir / "manifest.json").read_text())
    if (manifest["app_id"], manifest["version"]) != (APP_ID, version):
        raise RuntimeError("Candidate manifest does not match this project and version")
    if manifest.get("candidate_source_sha256") != candidate_source_sha256(root):
        raise RuntimeError("Candidate sources changed beyond README.md. Prepare and review a new candidate.")
    client_hash = source_sha256(root.parent / "remya-settings", "packages/remya_settings_client")
    if client_hash != manifest["settings_client_sha256"]:
        raise RuntimeError("The sibling Settings client changed. Prepare and review a new candidate.")
    for bundle in (root / "build/linux/x64/release/bundle", installed_bundle(APP_ID)):
        if bundle_sha256(bundle, APP_ID) != manifest["bundle_sha256"]:
            raise RuntimeError(f"Bundle changed after candidate preparation: {bundle}")
    archive = release_dir / f"{APP_ID}-{version}-linux-x86_64.tar.zst"
    if sha256_file(archive) != manifest["archive_sha256"]:
        raise RuntimeError("Candidate archive changed after preparation")
    manifest.update(source_sha256=source_sha256(root), readme_refreshed=True)
    return stage_release_artifacts(root, version, manifest)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", help="Explicit release version (e.g. 0.1.0-dev.20261109.0)")
    parser.add_argument("--bump", action="store_true", help="Increment today's dev sequence number")
    parser.add_argument("--allow-stable", action="store_true", help="Allow stable X.Y.Z version format")
    parser.add_argument("--skip-version-sync", action="store_true", help="Keep current version files unchanged")
    parser.add_argument(
        "--refresh-readme",
        action="store_true",
        help="Restage the approved bundle with the updated README, without building or installing",
    )
    parser.add_argument("--skip-checks", action="store_true", help="Skip format/analyze/test validation suite")
    parser.add_argument("--skip-desktop-smoke", action="store_true", help="Skip debug native/window smoke tests")
    args = parser.parse_args()

    root = repo_root()
    if not shutil.which("makepkg"):
        raise RuntimeError("makepkg is required to stage AUR metadata")
    if args.refresh_readme and not args.version:
        parser.error("--refresh-readme requires --version")

    if args.skip_version_sync or args.refresh_readme:
        pub_ver, cargo_ver = read_current_versions(root)
        if pub_ver != cargo_ver:
            raise RuntimeError(f"Version mismatch: pubspec.yaml ({pub_ver}) != Cargo.toml ({cargo_ver})")
        version = pub_ver
    else:
        version = resolve_target_version(root, args.version, bump=args.bump, allow_stable=args.allow_stable)
    if not VERSION.fullmatch(version):
        raise ValueError(f"Invalid release version: {version!r}")
    if args.version and args.version != version:
        raise ValueError(f"Requested version {args.version} differs from {version}")
    if git(root, "tag", "--list", f"v{version}") or git(
        root, "ls-remote", "origin", f"refs/tags/v{version}"
    ):
        raise RuntimeError(f"Release tag v{version} already exists")
    if args.refresh_readme:
        release_dir = refresh_readme(root, version)
        print(f"README refreshed in {release_dir}. Present the README diff for release approval.")
        return 0
    if not args.skip_version_sync:
        sync_version_files(root, version)

    if not args.skip_checks:
        run_validation(root, skip_desktop_smoke=args.skip_desktop_smoke)

    source_hash = source_sha256(root)
    bundle_hash = build_release(root)
    if source_sha256(root) != source_hash:
        raise RuntimeError("Source files changed during the release build")
    manifest = {
        "app_id": APP_ID,
        "package": PACKAGE,
        "version": version,
        "tag": f"v{version}",
        "pkgver": version.replace("-", "_"),
        "prerelease": "-" in version,
        "bundle_sha256": bundle_hash,
        "source_sha256": source_hash,
        "candidate_source_sha256": candidate_source_sha256(root),
        "base_commit": git(root, "rev-parse", "HEAD"),
        "prepared_at": datetime.now().astimezone().isoformat(),
        "readme_refreshed": False,
        "settings_client_sha256": source_sha256(root.parent / "remya-settings", "packages/remya_settings_client"),
    }
    release_dir = stage_release_artifacts(root, version, manifest)
    install_staged_release(root, release_dir, version, bundle_hash)

    print("\n============================================================")
    print(f"Prepared {PACKAGE} release v{version}")
    print(f"Workstation installed & verified: {installed_bundle(APP_ID)}")
    print(f"Staged artifacts directory:       {release_dir}")
    print(f"  - {release_dir / f'{APP_ID}-{version}-linux-x86_64.tar.zst'}")
    print(f"  - {release_dir / 'SHA256SUMS'}")
    print(f"  - {release_dir / 'PKGBUILD'}")
    print(f"  - {release_dir / '.SRCINFO'}")
    print("============================================================")
    print("STOP HERE: Get candidate approval before asking Gemini to update README.md.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
