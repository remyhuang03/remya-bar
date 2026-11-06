"""Verify per-output fullscreen visibility using only a temporary GTK window.

Requires Hyprland, GTK 3/PyGObject, and no existing visible fullscreen windows.
Pass an installed bar executable as the optional first argument for release QA.
"""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

import gi

gi.require_version('Gtk', '3.0')
from gi.repository import GLib, Gtk


def hyprctl(command):
    return json.loads(subprocess.check_output(
        ['hyprctl', command, '-j'], timeout=3,
    ))


def fullscreen_outputs(monitors, clients):
    return {
        monitor['name']
        for monitor in monitors
        for client in clients
        if client.get('monitor') == monitor['id']
        and client.get('mapped') and not client.get('hidden')
        and client.get('fullscreen', 0) & 2
        and client.get('workspace', {}).get('id') in {
            monitor.get('activeWorkspace', {}).get('id'),
            monitor.get('specialWorkspace', {}).get('id'),
        }
    }


def pump():
    context = GLib.MainContext.default()
    while context.pending():
        context.iteration(False)


def wait_for(check, process=None, log=None):
    deadline = time.monotonic() + 15
    while True:
        pump()
        if process is not None and process.poll() is not None:
            log.seek(0)
            raise AssertionError(f'Bar exited: {log.read()}')
        try:
            return check()
        except AssertionError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.1)


def own_window(title):
    clients = [client for client in hyprctl('clients')
               if client.get('pid') == os.getpid() and client.get('title') == title]
    assert len(clients) == 1, ('Temporary GTK window not mapped', clients)
    return clients[0]


def own_bars(layers, pid, output):
    return [(level, layer)
            for level, entries in layers[output]['levels'].items()
            for layer in entries if layer['pid'] == pid]


def check_bars(process, baseline, hidden=None):
    monitors = hyprctl('monitors')
    layers = hyprctl('layers')
    assert {monitor['name'] for monitor in monitors} == set(baseline), 'Outputs changed during test'
    for monitor in monitors:
        name = monitor['name']
        bars = own_bars(layers, process.pid, name)
        expected = list(baseline[name])
        if name == hidden:
            assert not bars, ('Fullscreen output bar remains mapped', name, bars)
        else:
            assert len(bars) == 1, (name, bars)
            level, bar = bars[0]
            assert level == '2' and bar['h'] == 40, bar
            assert bar['namespace'] == 'top.remya.bar', bar
            expected[1] += 40
        assert monitor['reserved'] == expected, (name, monitor['reserved'], expected)
    assert hyprctl('activewindow').get('pid') != process.pid, 'Bar took keyboard focus'
    assert all(client.get('pid') != process.pid for client in hyprctl('clients'))


def check_baseline(baseline, pid):
    monitors = hyprctl('monitors')
    layers = hyprctl('layers')
    assert {monitor['name'] for monitor in monitors} == set(baseline), 'Outputs changed during test'
    assert all(monitor['reserved'] == baseline[monitor['name']] for monitor in monitors)
    assert all(not own_bars(layers, pid, monitor['name']) for monitor in monitors)


def stop(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def self_check():
    monitors = [{'id': 1, 'name': 'DP-1', 'activeWorkspace': {'id': 3}}]
    client = {'monitor': 1, 'workspace': {'id': 3}, 'mapped': True,
              'hidden': False, 'fullscreen': 2}
    assert fullscreen_outputs(monitors, [client]) == {'DP-1'}
    assert not fullscreen_outputs(monitors, [{**client, 'fullscreen': 1}])
    assert not fullscreen_outputs(monitors, [{**client, 'workspace': {'id': 4}}])
    assert not fullscreen_outputs(monitors, [{**client, 'hidden': True}])


def main():
    self_check()
    root = Path(__file__).resolve().parents[1]
    binary = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / 'build/linux/x64/debug/bundle/remya_bar'
    assert binary.is_file(), f'Bar executable missing: {binary}'
    monitors = hyprctl('monitors')
    baseline = {monitor['name']: monitor['reserved'] for monitor in monitors}
    assert baseline, 'No connected outputs'
    assert not fullscreen_outputs(monitors, hyprctl('clients')), 'Run this check without existing visible fullscreen windows'
    GLib.set_prgname('top.remya.bar.fullscreen-smoke')
    title = f'Remya fullscreen smoke {os.getpid()}'
    window = Gtk.Window(title=title)
    window.set_default_size(480, 320)
    process = None
    last_pid = None
    with tempfile.TemporaryFile(mode='w+') as log:
        try:
            process = subprocess.Popen([str(binary)], stdout=log, stderr=log)
            last_pid = process.pid
            wait_for(lambda: check_bars(process, baseline), process, log)
            window.show_all()
            client = wait_for(lambda: own_window(title), process, log)
            output = next(monitor['name'] for monitor in hyprctl('monitors')
                          if monitor['id'] == client['monitor'])
            address = client['address']

            for startup in [False, True]:
                if startup:
                    stop(process)
                    wait_for(lambda: check_baseline(baseline, process.pid))
                window.fullscreen()

                def full():
                    assert own_window(title).get('fullscreen', 0) & 2, 'Temporary window is not fullscreen'

                wait_for(full)
                if startup:
                    process = subprocess.Popen([str(binary)], stdout=log, stderr=log)
                    last_pid = process.pid
                wait_for(lambda: check_bars(process, baseline, output), process, log)
                window.unfullscreen()

                def restored():
                    assert not own_window(title).get('fullscreen', 0) & 2
                    check_bars(process, baseline)
                    assert hyprctl('activewindow').get('address') == address, 'Focus changed while restoring the bar'

                wait_for(restored, process, log)
            print(f'PASS: fullscreen hides only {output}, releases 40px, restores the bar without focus theft; '
                  'startup fullscreen state also verified.')
        finally:
            window.destroy()
            pump()
            if process is not None:
                stop(process)
            if last_pid is not None:
                wait_for(lambda: check_baseline(baseline, last_pid))


if __name__ == '__main__':
    main()
