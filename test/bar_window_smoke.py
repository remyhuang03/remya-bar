"""Check the built bar's real window behavior in the current Hyprland session."""

import json
from pathlib import Path
import subprocess
import tempfile
import time


def hyprctl(command):
    return json.loads(subprocess.check_output(['hyprctl', command, '-j']))


def check_bars(process, before):
    layers = hyprctl('layers')
    monitors = hyprctl('monitors')
    assert {m['name'] for m in monitors} == set(before), 'Outputs changed during test'
    for monitor in monitors:
        bars = [
            (level, layer)
            for level, entries in layers[monitor['name']]['levels'].items()
            for layer in entries
            if layer['pid'] == process.pid
        ]
        assert len(bars) == 1, (monitor['name'], bars)
        level, bar = bars[0]
        width = monitor['height'] if monitor['transform'] % 2 else monitor['width']
        assert level == '2' and bar['h'] == 40, bar
        assert abs(bar['w'] - width / monitor['scale']) <= 1, bar
        assert bar['namespace'] == 'top.remya.bar', bar
        assert bar['x'] == monitor['x'], bar
        assert bar['y'] == monitor['y'] + before[monitor['name']][1], bar
        assert monitor['reserved'][1] == before[monitor['name']][1] + 40
    assert hyprctl('activewindow').get('pid') != process.pid, 'Bar took focus'
    assert all(c['pid'] != process.pid for c in hyprctl('clients'))


def check_settings(binary, process, before):
    for page in ('layout', 'notifications'):
        forwarded = subprocess.run([str(binary), '--settings', page],
                                   capture_output=True, text=True, timeout=10)
        assert forwarded.returncode == 0, forwarded.stderr
        deadline = time.monotonic() + 10
        while True:
            clients = [c for c in hyprctl('clients') if c['pid'] == process.pid]
            if len(clients) == 1 and clients[0]['title'] == 'Remya Bar Settings':
                break
            assert time.monotonic() < deadline, clients
            time.sleep(0.1)
        assert clients[0]['class'] == 'top.remya.bar', clients
        assert {m['name']: m['reserved'] for m in hyprctl('monitors')} == {
            name: [value[0], value[1] + 40, value[2], value[3]]
            for name, value in before.items()
        }
    address = clients[0]['address']
    subprocess.run(['hyprctl', 'dispatch', f'hl.dsp.window.close({{window = "address:{address}"}})'],
                   check=True, capture_output=True)
    deadline = time.monotonic() + 10
    while any(c['pid'] == process.pid for c in hyprctl('clients')):
        assert time.monotonic() < deadline, 'Settings window did not close'
        time.sleep(0.1)
    assert process.poll() is None, 'Closing settings stopped Bar'
    # Reopen via the optional-page form; the resident process must still own it.
    result = subprocess.run([str(binary), '--settings'], timeout=10)
    assert result.returncode == 0
    deadline = time.monotonic() + 10
    while not any(c['pid'] == process.pid for c in hyprctl('clients')):
        assert time.monotonic() < deadline, 'Settings did not reopen'
        time.sleep(0.1)
    invalid = subprocess.run([str(binary), '--settings', '../invalid'],
                             capture_output=True, timeout=10)
    assert invalid.returncode == 1
    print('PASS: forwarded settings command lines, one normal toplevel, close/reopen and invalid page')


def main():
    root = Path(__file__).resolve().parents[1]
    binary = root / 'build/linux/x64/debug/bundle/remya_bar'
    before = {m['name']: m['reserved'] for m in hyprctl('monitors')}
    assert before, 'No connected outputs'
    with tempfile.TemporaryFile(mode='w+') as log:
        process = subprocess.Popen([str(binary)], stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 20
            while True:
                if process.poll() is not None:
                    log.seek(0)
                    raise AssertionError(log.read())
                try:
                    check_bars(process, before)
                    break
                except AssertionError:
                    if time.monotonic() >= deadline:
                        raise
                    time.sleep(0.2)
            print(f'PASS: one 40-pixel top bar on each of {len(before)} outputs; '
                  'reserved space, no keyboard focus, no normal windows.')
            check_settings(binary, process, before)
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
    assert all(m['reserved'] == before[m['name']] for m in hyprctl('monitors'))


if __name__ == '__main__':
    main()
