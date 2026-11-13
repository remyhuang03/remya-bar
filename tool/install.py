#!/usr/bin/env python3
"""Install a built release bundle in XDG_DATA_HOME without changing configuration."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

APP_ID = "remya_bar"
PACKAGE = "top.remya.bar"
UNIT = f"{PACKAGE}.service"


def data_home(environment):
    value = environment.get("XDG_DATA_HOME", "")
    if value.startswith("/"):
        return Path(value)
    home = environment.get("HOME", "")
    if not home.startswith("/"):
        raise ValueError("An absolute HOME or XDG_DATA_HOME is required")
    return Path(home) / ".local/share"


def desktop_quote(path):
    # Desktop Entry Exec quoting, followed by string-value escaping.
    value = str(path).replace("%", "%%")
    for character in ('\\', '"', '`', '$'):
        value = value.replace(character, "\\" + character)
    return '"' + value.replace("\\", "\\\\") + '"'


def unit_quote(path):
    # systemd.syntax: double-quoted word; % and $ are specifier/variable prefixes.
    value = str(path).replace("\\", "\\\\").replace('"', '\\"')
    return '"' + value.replace("%", "%%").replace("$", "$$") + '"'


def user_unit(executable):
    # The session manager imports WAYLAND_DISPLAY and HYPRLAND_INSTANCE_SIGNATURE.
    return (
        "[Unit]\nDescription=Remy'a Bar\n"
        "PartOf=graphical-session.target\nAfter=graphical-session.target\n"
        "Wants=top.remya.core.service\nAfter=top.remya.core.service\n\n"
        f"[Service]\nExecStart={unit_quote(executable)}\n"
        "Restart=on-failure\nRestartSec=2\n\n"
        "[Install]\nWantedBy=graphical-session.target\n")


def systemctl(*arguments, check=True):
    return subprocess.run(["systemctl", "--user", *arguments], check=check, capture_output=not check)


def require_inter_font():
    try:
        result = subprocess.run(['fc-match', '--format=%{family}', 'Inter'], capture_output=True, text=True, check=True)
    except (OSError, subprocess.CalledProcessError) as error:
        raise RuntimeError("Install fontconfig and the Inter system font first (Arch: sudo pacman -S inter-font)") from error
    if 'Inter' not in result.stdout.strip().split(','):
        raise RuntimeError("Install the Inter system font first (Arch: sudo pacman -S inter-font)")


def install(root, environment):
    require_inter_font()
    data = data_home(environment).resolve()
    source = root / "build/linux/x64/release/bundle"
    if not (source / APP_ID).is_file():
        raise RuntimeError("Run fvm flutter build linux --release first")
    destination = data / "remya" / APP_ID
    roots = [data] + [Path(value) for value in (environment.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":") if value.startswith("/")]
    if not any((directory / "dbus-1/services/top.remya.Core1.service").is_file() for directory in roots):
        raise RuntimeError("Install Remya Core first; Remya Bar requires top.remya.Core1 D-Bus activation")
    # The autostart unit is restarted with the new bundle; other instances block the update.
    has_systemd = shutil.which("systemctl") is not None
    was_active = has_systemd and systemctl("is-active", "--quiet", UNIT, check=False).returncode == 0
    if was_active:
        systemctl("stop", UNIT)
    for process in Path("/proc").iterdir():
        if not process.name.isdecimal():
            continue
        try:
            executable = (process / "exe").resolve()
        except (OSError, RuntimeError):
            continue
        if executable.is_relative_to(destination):
            raise RuntimeError(f"Stop {APP_ID} before updating its installed bundle")
    home = environment.get("HOME", "")
    if not home.startswith("/"):
        raise ValueError("An absolute HOME is required for ~/.local/bin")
    command = Path(home) / ".local/bin" / APP_ID
    if command.exists() or command.is_symlink():
        if not command.is_symlink() or command.resolve() != destination / APP_ID:
            raise RuntimeError(f"Refusing to replace unrelated command: {command}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f".{APP_ID}-", dir=destination.parent) as temporary:
        staging = Path(temporary) / "bundle"
        shutil.copytree(source, staging, symlinks=True)
        backup = Path(temporary) / "previous"
        if destination.exists():
            destination.rename(backup)
        try:
            staging.rename(destination)
        except OSError:
            if backup.exists():
                backup.rename(destination)
            raise
    applications = data / "applications"
    applications.mkdir(parents=True, exist_ok=True)
    entry = (root / f"linux/packaging/{PACKAGE}.desktop").read_text()
    # env lets Gio validate the launcher before expanding literal %% in path arguments.
    entry = entry.replace(f"Exec={APP_ID}", f"Exec=/usr/bin/env {desktop_quote(destination / APP_ID)}")
    (applications / f"{PACKAGE}.desktop").write_text(entry)
    registrations = data / "remya/apps"
    registrations.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(root / "linux/packaging/remya-bar.json", registrations / "remya-bar.json")
    icons = data / "icons/hicolor/scalable/apps"
    icons.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(root / "assets/icons/app_icon.svg", icons / f"{PACKAGE}.svg")
    if shutil.which("gtk-update-icon-cache"):
        subprocess.run(["gtk-update-icon-cache", "-f", "-t", str(data / "icons/hicolor")], check=True)
    command.parent.mkdir(parents=True, exist_ok=True)
    if not command.is_symlink():
        command.symlink_to(destination / APP_ID)
    if shutil.which("update-desktop-database"):
        subprocess.run(["update-desktop-database", str(applications)], check=True)
    units = data / "systemd/user"
    units.mkdir(parents=True, exist_ok=True)
    (units / UNIT).write_text(user_unit(destination / APP_ID))
    if has_systemd:
        systemctl("daemon-reload")
        systemctl("enable", UNIT)
        # Start with the graphical session; restart a running unit on the new bundle.
        if was_active or systemctl("is-active", "--quiet", "graphical-session.target", check=False).returncode == 0:
            systemctl("restart", UNIT)
    print(f"Installed {PACKAGE} in {destination}")
    print(f"Command: {command} (add ~/.local/bin to PATH if needed)")
    print(f"Autostart: {UNIT} starts with the graphical session")


if __name__ == "__main__":
    install(Path(__file__).resolve().parents[1], os.environ)
