"""Exercise the real runner on Hyprland with a private logind bus (python-dbus)."""

import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import time

import dbus

from bar_window_smoke import check_bars, hyprctl

NOTIFICATIONS = 'org.freedesktop.Notifications'
NOTIFICATION_PATH = '/org/freedesktop/Notifications'
BUS_CONFIG = """
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <policy context="default">
    <allow own="*"/>
    <allow send_destination="*"/>
    <allow receive_sender="*"/>
  </policy>
</busconfig>
"""


def wait_for_bar(process, log, driver, before, previous_name=None):
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline and process.poll() is None:
        if driver.NameHasOwner(NOTIFICATIONS):
            name = driver.GetNameOwner(NOTIFICATIONS)
            if name != previous_name and driver.GetConnectionUnixProcessID(name) == process.pid:
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
    with tempfile.TemporaryDirectory() as state, tempfile.TemporaryFile(mode='w+') as log:
        config = Path(state) / 'bus.conf'
        config.write_text(BUS_CONFIG)
        with subprocess.Popen(['dbus-daemon', f'--config-file={config}', '--nofork', '--print-address=1'],
                              stdout=subprocess.PIPE, text=True) as daemon:
            try:
                address = daemon.stdout.readline().strip()
                bus = dbus.bus.BusConnection(address)
                assert bus.request_name('org.freedesktop.login1') == dbus.bus.REQUEST_NAME_REPLY_PRIMARY_OWNER
                driver = dbus.Interface(bus.get_object('org.freedesktop.DBus', '/org/freedesktop/DBus'),
                                        'org.freedesktop.DBus')
                env = {**os.environ, 'DBUS_SYSTEM_BUS_ADDRESS': address,
                       'DBUS_SESSION_BUS_ADDRESS': address, 'XDG_STATE_HOME': state}
                with subprocess.Popen([binary], stdout=log, stderr=log,
                                      env=env) as bar:
                    try:
                        name = wait_for_bar(bar, log, driver, before)
                        notifications = dbus.Interface(
                            bus.get_object(name, NOTIFICATION_PATH), NOTIFICATIONS)
                        note = notifications.Notify('Bar smoke test', 0, '', 'Before sleep', '',
                            dbus.Array([], signature='s'), {'suppress-sound': True}, 100)
                        database = Path(state) / 'remya/bar/notifications.sqlite3'
                        with sqlite3.connect(database) as history:
                            assert history.execute('SELECT id FROM history').fetchall() == [(note,)]
                        for sleeping in (True, False):
                            signal = dbus.lowlevel.SignalMessage('/org/freedesktop/login1',
                                'org.freedesktop.login1.Manager', 'PrepareForSleep')
                            signal.append(sleeping, signature='b')
                            bus.send_message(signal)
                            bus.flush()
                            if sleeping:
                                time.sleep(0.5)
                                assert name == wait_for_bar(bar, log, driver, before)
                        resumed = wait_for_bar(bar, log, driver, before, previous_name=name)
                        # Only the restored daemon can dismiss a notification from before resume.
                        bus.call_blocking(resumed, NOTIFICATION_PATH, NOTIFICATIONS,
                                          'CloseNotification', 'u', (note,))
                        with sqlite3.connect(database) as history:
                            assert history.execute('SELECT id FROM history').fetchall() == []
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
    print('PASS: resume recreates all bar surfaces and restores dismissible notification history')


if __name__ == '__main__':
    main()
