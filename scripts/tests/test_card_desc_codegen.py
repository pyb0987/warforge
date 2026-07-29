"""Regression tests for generated card descriptions.

Run: python3 -m unittest scripts.tests.test_card_desc_codegen
"""

from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from card_desc_gen import generate_all_descs  # noqa: E402
from codegen_card_db import _project_to_desc_gen_input, load_cards  # noqa: E402


class TestCardDescCodegen(unittest.TestCase):
    def _generate_descs(self) -> dict:
        cards = load_cards()
        projected = _project_to_desc_gen_input(cards)
        return generate_all_descs(projected)

    def test_pr_transcend_keeps_oe_listen_sections_separate(self) -> None:
        descs = self._generate_descs()

        star1 = descs["pr_transcend"][1]
        self.assertIn("[반응] 다른 카드의 부화 시:", star1)
        self.assertIn("[반응] 다른 카드의 변태 시:", star1)
        self.assertEqual(star1.count("[반응]"), 2)
        self.assertLess(star1.index("부화 시:"), star1.index("변태 시:"))

    def test_pr_transcend_keeps_per_listen_max_act_suffixes(self) -> None:
        descs = self._generate_descs()

        star2 = descs["pr_transcend"][2]
        self.assertEqual(star2.count("(최대 5/R)"), 2)

    def test_sp_arsenal_uses_steampunk_upgrade_wording(self) -> None:
        descs = self._generate_descs()

        for star in (1, 2, 3):
            desc = descs["sp_arsenal"][star]
            self.assertIn("누적 개량", desc)
            self.assertNotIn("성장률", desc)
            self.assertNotIn("🌳", desc)


if __name__ == "__main__":
    unittest.main()
