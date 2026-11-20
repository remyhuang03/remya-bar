"""Warn about Rust and Dart files that need a single-responsibility review."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[1]
EXCEPTIONS = ROOT / "tool" / "source_length_exceptions.json"
LIMIT = 800


def source_paths():
    output = subprocess.check_output(
        [
            "git", "ls-files", "-z", "--cached", "--others", "--exclude-standard",
            "--", "*.rs", "*.dart",
        ],
        cwd=ROOT,
    )
    return sorted({os.fsdecode(path) for path in output.split(b"\0") if path})


def long_sources(paths):
    for name in paths:
        path = ROOT / name
        if not path.is_file() or path.resolve() != path:
            continue
        content = path.read_bytes()
        lines = content.count(b"\n") + int(bool(content) and not content.endswith(b"\n"))
        if lines > LIMIT:
            yield name, lines, hashlib.sha256(content).hexdigest()


def warn(name, lines):
    message = (
        f"{name} has {lines} lines (limit {LIMIT}). "
        "Review it for single responsibility and refactor if needed."
    )
    if os.environ.get("GITHUB_ACTIONS") == "true":
        message = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        print(f"::warning title=Refactoring review::{message}")
    else:
        print(f"Warning: {message}")


def save_exception(name, digest, reason):
    lock_path = EXCEPTIONS.with_suffix(".json.lock")
    lock = lock_path.open("x", encoding="utf-8")
    try:
        with lock:
            exceptions = json.loads(EXCEPTIONS.read_text(encoding="utf-8"))
            exceptions[name] = {"sha256": digest, "reason": reason}
            json.dump(exceptions, lock, indent=2, sort_keys=True)
            lock.write("\n")
        lock_path.replace(EXCEPTIONS)
    except BaseException:
        lock_path.unlink()
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command")
    add = commands.add_parser("add", help="Record a reviewed file's current SHA-256")
    add.add_argument("path", help="Repository-relative source path")
    add.add_argument("--reason", required=True, help="Why the file should stay together")
    args = parser.parse_args()

    paths = source_paths()
    if args.command == "add":
        name = Path(args.path).as_posix()
        reason = args.reason.strip()
        if not reason:
            add.error("--reason must be non-empty")
        if name not in paths:
            add.error("path must name a Rust or Dart source in this repository")
        for _, _, digest in long_sources([name]):
            save_exception(name, digest, reason)
            print(f"Recorded source length exception for {name}")
            return
        add.error(f"path must name a regular source file longer than {LIMIT} lines")

    exceptions = json.loads(EXCEPTIONS.read_text(encoding="utf-8"))
    for name, lines, digest in long_sources(paths):
        if exceptions.get(name, {}).get("sha256") != digest:
            warn(name, lines)


if __name__ == "__main__":
    main()
