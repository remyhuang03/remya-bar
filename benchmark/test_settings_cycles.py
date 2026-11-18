import unittest

from settings_cycles import own_settings


class SettingsCyclesTest(unittest.TestCase):
    def test_only_our_mapped_settings_window_matches(self):
        window = {"pid": 12, "class": "top.remya.bar", "title": "Remy'a Bar Settings"}
        clients = [{**window, "pid": 34}, {**window, "mapped": False}, window]
        self.assertIs(own_settings(clients, 12), window)
        self.assertIsNone(own_settings(clients, 56))
