#!/usr/bin/env python3
"""Measure a deterministic notification burst against an isolated release Bar."""

import argparse
from contextlib import closing
import os
from pathlib import Path
import signal
import sqlite3
import subprocess
import tempfile
import time

import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

from desktop import (
    RUNS, bundle_hashes, hyprland, isolated_bar, run_id, topology, verify_bundle,
    wait_for, write_json,
)
from proc_sampler import PidScope, positive_float

NOTIFICATIONS = "org.freedesktop.Notifications"
NOTIFICATION_PATH = "/org/freedesktop/Notifications"
APP_NAME, APP_ID = "Remya Bar S09 fixture", "top.remya.bar.benchmark.notification"
TIMEOUT_MS = 750

def layer_outputs(pid, namespace):
    return sorted(name for name, output in hyprland("layers").items() if any(
        entry.get("pid") == pid and entry.get("namespace") == namespace
        for entries in output.get("levels", {}).values() for entry in entries
    ))

def burst(process, bus, database, outputs, hashes, options):
    pid = process.pid
    driver = dbus.Interface(bus.get_object("org.freedesktop.DBus", "/org/freedesktop/DBus"),
                            "org.freedesktop.DBus")
    wait_for(process, lambda: driver.NameHasOwner(NOTIFICATIONS)
             and layer_outputs(pid, "top.remya.bar") == [out["name"] for out in outputs], 0.1)
    owner = driver.GetNameOwner(NOTIFICATIONS)
    if driver.GetConnectionUnixProcessID(owner) != pid:
        raise RuntimeError("Notification owner is not the fixture")
    mapping = verify_bundle(pid, hashes)
    notification = dbus.Interface(bus.get_object(owner, NOTIFICATION_PATH), NOTIFICATIONS)
    events = []
    bus.add_signal_receiver(lambda note, reason: events.append([int(note), int(reason)]),
                            "NotificationClosed", NOTIFICATIONS, owner, NOTIFICATION_PATH)
    scope, checkpoints = PidScope(pid), {}
    context = GLib.MainContext.default()
    def checkpoint(stage):
        checkpoints[stage] = scope.read(memory_due=True)
        if checkpoints[stage]["errors"] or not checkpoints[stage]["identity_ok"]:
            raise RuntimeError(f"Process sampling failed at {stage}: {checkpoints[stage]['errors']}")
        checkpoints[stage]["toast_outputs"] = layer_outputs(pid, "top.remya.bar/notifications")
        while context.pending():
            context.iteration(False)

    checkpoint("before")
    received, persisted, timings = set(), {}, []
    start = time.monotonic()
    for number in range(1, options.count + 1):
        deadline = start + (number - 1) / options.rate
        time.sleep(max(0, deadline - time.monotonic()))
        sent = time.monotonic()
        replace = next(reversed(persisted)) if number == options.count or number % 40 == 0 else 0
        transient = number == 2
        title = f"S09 fixture {number:03d}"
        hints = dbus.Dictionary(
            {"suppress-sound": True, "desktop-entry": APP_ID, "transient": transient}, signature="sv")
        note = int(notification.Notify(APP_NAME, replace, "", title, "Benchmark notification",
                                       dbus.Array([], signature="s"), hints, TIMEOUT_MS, timeout=5))
        timings.append(((sent - deadline) * 1000, (time.monotonic() - sent) * 1000))
        if note == 0 or (note != replace if replace else note in received):
            raise RuntimeError(f"Unexpected ID {note} for fixture {number} replacing {replace}")
        received.add(note)
        if transient:
            transient_id = note
        else:
            persisted[note] = title
        if number == options.count // 2:
            checkpoint("during")
    duration, closed = time.monotonic() - start, next(iter(persisted))
    notification.CloseNotification(closed, timeout=5)
    del persisted[closed]
    checkpoint("burst_end")
    print(f"Sent {options.count}, observing for {options.observe:g}s", flush=True)
    time.sleep(options.observe / 2)
    print("Quiet observation halfway complete", flush=True)
    time.sleep(options.observe / 2)
    checkpoint("after")
    with closing(sqlite3.connect(database.as_uri() + "?mode=ro", uri=True)) as history:
        rows = dict(history.execute("SELECT id, json_extract(snapshot, '$.summary') FROM history"))
    if rows != persisted or sorted(events) != sorted([[transient_id, 1], [closed, 3]]):
        raise RuntimeError("Notification history or closure signals did not match the fixture")
    if driver.GetNameOwner(NOTIFICATIONS) != owner or topology() != outputs or verify_bundle(pid, hashes) != mapping:
        raise RuntimeError("Fixture, topology, or bundle mapping changed during the trial")
    return {
        "notify_replies": len(timings), "unique_ids": len(received), "replacements": len(timings) - len(received),
        "retained": len(rows), "closed": events, "burst_seconds": duration,
        "checkpoints": checkpoints, "call_columns": ["lateness_ms", "reply_ms"], "calls": timings,
    }

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", type=run_id, required=True)
    parser.add_argument("--bundle-dir", type=Path, required=True, help="Explicit release bundle directory")
    parser.add_argument("--count", type=int, default=200, help="Notify operations, including replacements")
    parser.add_argument("--rate", type=positive_float, default=20, help="Scheduled operations per second")
    parser.add_argument("--observe", type=positive_float, default=60, help="Seconds after the burst")
    options = parser.parse_args()
    output = RUNS / f"{options.run_id}.json"
    if output.exists() or not 4 <= options.count <= 200 or options.observe < 1:
        parser.error("Require a new run ID, count 4–200, and at least one second of observation")
    outputs, bundle = topology(), options.bundle_dir.resolve()
    if len(outputs) != 3:
        parser.error("Run with three displays enabled")
    hashes = bundle_hashes(bundle)
    with tempfile.TemporaryFile() as log, isolated_bar(bundle, log) as (bar, env):
        database = Path(env["XDG_STATE_HOME"]) / "remya/bar/notifications.sqlite3"
        with closing(dbus.bus.BusConnection(env["DBUS_SESSION_BUS_ADDRESS"], mainloop=DBusGMainLoop())) as bus:
            result = burst(bar, bus, database, outputs, hashes, options)
    RUNS.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir=RUNS) as temporary:
        staged = Path(temporary) / "result.json"
        write_json(staged, {"scenario": "S09-notification-burst", "outputs": outputs, "sha256": hashes,
                            "rate_per_second": options.rate, "observe_seconds": options.observe, "timeout_ms": TIMEOUT_MS,
                            "clock_ticks_hz": os.sysconf("SC_CLK_TCK"), **result})
        os.link(staged, output)
    print(output)

if __name__ == "__main__":
    signal.signal(signal.SIGTERM, signal.default_int_handler)
    try:
        main()
    except KeyboardInterrupt:
        raise SystemExit(130) from None
    except (OSError, RuntimeError, sqlite3.Error, subprocess.SubprocessError, dbus.DBusException) as error:
        raise SystemExit(str(error)) from None
