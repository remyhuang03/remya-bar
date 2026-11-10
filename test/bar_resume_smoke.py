"""Exercise the real runner on Hyprland with a private logind bus (python-dbus)."""

import os
from pathlib import Path
import subprocess
import tempfile
import time

import dbus

from bar_window_smoke import check_bars, hyprctl


def wait_for_bar(process, log, driver, before, previous_name=None):
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline and process.poll() is None:
        for name in driver.ListNames():
            if not name.startswith(':') or name == previous_name:
                continue
            if driver.GetConnectionUnixProcessID(name) == process.pid:
                try:
                    check_bars(process, before)
                except AssertionError:
                    break
                return name
        time.sleep(0.1)
    log.seek(0)
    raise AssertionError(log.read() or 'Bar did not map its windows')


def main():
    binary = Path(__file__).resolve().parents[1] / 'build/linux/x64/debug/bundle/remya_bar'
    before = {monitor['name']: monitor['reserved'] for monitor in hyprctl('monitors')}
    assert before, 'No connected outputs'
    with subprocess.Popen(['dbus-daemon', '--session', '--nofork', '--print-address=1'],
                          stdout=subprocess.PIPE, text=True) as daemon:
        try:
            address = daemon.stdout.readline().strip()
            bus = dbus.bus.BusConnection(address)
            assert bus.request_name('org.freedesktop.login1') == dbus.bus.REQUEST_NAME_REPLY_PRIMARY_OWNER
            driver = dbus.Interface(bus.get_object('org.freedesktop.DBus', '/org/freedesktop/DBus'),
                                    'org.freedesktop.DBus')
            with tempfile.TemporaryFile(mode='w+') as log:
                with subprocess.Popen([binary], stdout=log, stderr=log,
                                      env={**os.environ, 'DBUS_SYSTEM_BUS_ADDRESS': address}) as bar:
                    try:
                        name = wait_for_bar(bar, log, driver, before)
                        for sleeping in (True, False):
                            signal = dbus.lowlevel.SignalMessage('/org/freedesktop/login1',
                                'org.freedesktop.login1.Manager', 'PrepareForSleep')
                            signal.append(sleeping, signature='b')
                            bus.send_message(signal)
                            bus.flush()
                            if sleeping:
                                time.sleep(0.5)
                                assert name == wait_for_bar(bar, log, driver, before)
                        wait_for_bar(bar, log, driver, before, previous_name=name)
                    finally:
                        if bar.poll() is None:
                            bar.terminate()
                            try:
                                bar.wait(timeout=5)
                            except subprocess.TimeoutExpired:
                                bar.kill()
                                bar.wait()
        finally:
            daemon.terminate()
    assert all(m['reserved'] == before[m['name']] for m in hyprctl('monitors'))
    print('PASS: sleep leaves the bar running, resume recreates its session and all bar surfaces')


if __name__ == '__main__':
    main()
