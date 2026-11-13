"""Validate the installed registration's schemas and defaults (python-jsonschema)."""
import json
from pathlib import Path
import unittest

from jsonschema import Draft202012Validator


class RegistrationTest(unittest.TestCase):
    def setUp(self):
        self.registration = json.loads((Path(__file__).resolve().parents[1] /
                                   'linux/packaging/remya-bar.json').read_text())

    def test_schemas_and_defaults(self):
        registration = self.registration
        self.assertEqual(registration['id'], 'remya-bar')
        pages = {page['id'] for page in registration['pages']}
        for key, setting in registration['settings'].items():
            with self.subTest(key=key):
                self.assertIn(setting['page'], pages)
                Draft202012Validator.check_schema(setting['schema'])
                Draft202012Validator(setting['schema']).validate(setting['default'])

    def test_text_time_and_collection_boundaries(self):
        settings = self.registration['settings']
        for key, values in {
            'folded-apps': [['a\n'], [''], [' '], ['a', 'a'], ['a' * 257]],
            'sidebar-layout': [['vpn'], ['audio', 'audio']],
            'ai-ring': [{**settings['ai-ring']['default'], 'pinned': ['a', 'b', 'c', 'd']}],
            'quiet-schedule': [{**settings['quiet-schedule']['default'], 'start': time}
                               for time in ['24:00', '22:00\n', '7:00']],
        }.items():
            validator = Draft202012Validator(settings[key]['schema'])
            for value in values:
                with self.subTest(key=key, value=value):
                    self.assertFalse(validator.is_valid(value))


if __name__ == '__main__':
    unittest.main()
