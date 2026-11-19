"""serve/test_family_name.py - the API's model name: the config's "model_name" wins; without one, the model's own
("deepseek-v4.1-flash").

    python -m unittest serve.test_family_name
"""
from __future__ import annotations

import unittest

from serve.server import FAMILY_MODEL_NAMES, default_model_name


class FamilyName(unittest.TestCase):
    def test_config_name_wins(self):
        self.assertEqual(default_model_name({"model_name": "deepseek-v4.1-flash-coder", "arch": "deepseek41"}),
                         "deepseek-v4.1-flash-coder")

    def test_without_a_name(self):
        self.assertEqual(default_model_name({"arch": "deepseek41"}), "deepseek-v4.1-flash")
        self.assertEqual(default_model_name({}), "deepseek-v4.1-flash")
        self.assertEqual(set(FAMILY_MODEL_NAMES), {"deepseek41"})


if __name__ == "__main__":
    unittest.main()
