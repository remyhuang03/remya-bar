"""Exercise packaging in temporary XDG roots without touching the live desktop."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('bar_install', ROOT / 'tool/install.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallTest(unittest.TestCase):
    def test_core_preflight_and_installed_contract(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            data = home / 'data'
            root = home / 'repo'
            bundle = root / 'build/linux/x64/release/bundle'
            bundle.mkdir(parents=True)
            (bundle / 'remya_bar').write_text('test bundle')
            (root / 'linux').symlink_to(ROOT / 'linux', target_is_directory=True)
            (root / 'assets').symlink_to(ROOT / 'assets', target_is_directory=True)
            env = {'HOME': str(home), 'XDG_DATA_HOME': str(data), 'XDG_DATA_DIRS': 'relative'}
            with patch.object(installer, 'require_inter_font'), patch.object(installer.shutil, 'which', return_value=None):
                with self.assertRaisesRegex(RuntimeError, 'Remya Core'):
                    installer.install(root, env)
                self.assertFalse((data / 'remya').exists())
                activation = data / 'dbus-1/services/top.remya.Core1.service'
                activation.parent.mkdir(parents=True)
                activation.write_text('[D-BUS Service]')
                installer.install(root, env)
            self.assertEqual((data / 'remya/apps/remya-bar.json').read_bytes(),
                             (ROOT / 'linux/packaging/remya-bar.json').read_bytes())
            desktop = (data / 'applications/top.remya.bar.desktop').read_text()
            self.assertIn('[Desktop Action settings]', desktop)
            self.assertIn(' --settings\n', desktop)
            unit = (data / 'systemd/user/top.remya.bar.service').read_text()
            self.assertIn('Wants=top.remya.core.service', unit)
            self.assertIn('After=top.remya.core.service', unit)
            self.assertNotIn('top.remya.settings', unit)
            self.assertTrue((home / '.local/bin/remya_bar').resolve().is_file())


if __name__ == '__main__':
    unittest.main()
