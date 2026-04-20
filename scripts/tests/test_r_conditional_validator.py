"""Tests for validate_r_conditional_star_parity.

Run:  python3 -m unittest scripts.tests.test_r_conditional_validator

Covers the three historical bug classes that motivated the validator:
  1. Target drift across stars (훈련소 77e0a78)
  2. Amount drift across stars (보급부대 77e0a78)
  3. Nested-param drift across stars (군수공장 18e7cb2)

Plus the opt-in ``star_scalable_actions`` allowlist and the clean military.yaml.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from codegen_card_db import (  # noqa: E402
    validate_r_conditional_star_parity,
)


def _card(r_conditional_by_star: dict, star_scalable: list | None = None) -> dict:
    """Build a minimal card dict with given r_conditional per star."""
    card: dict = {
        "stars": {
            star: {"r_conditional": rc} for star, rc in r_conditional_by_star.items()
        }
    }
    if star_scalable is not None:
        card["star_scalable_actions"] = star_scalable
    return card


class TestRConditionalValidator(unittest.TestCase):
    # Real-YAML clean check is performed by `python3 scripts/codegen_v2.py`
    # (runs validators on all cards). This unit-test file covers the validator
    # logic with synthetic card dicts.

    def test_identical_across_stars_passes(self):
        rc = [{
            "when": {"rank_gte": 4},
            "effects": [{"grant_terazin": {"amount": 1}}],
        }]
        cards = {"military": {"ml_fake": _card({1: rc, 2: rc, 3: rc})}}
        self.assertEqual(validate_r_conditional_star_parity(cards), [])

    def test_target_drift_detected(self):
        """훈련소 bug class: same action/amount, different target across stars."""
        rc1 = [{"when": {"rank_gte": 4}, "effects": [
            {"train": {"target": "left_adj", "amount": 1}}]}]
        rc2 = [{"when": {"rank_gte": 4}, "effects": [
            {"train": {"target": "both_adj", "amount": 1}}]}]
        cards = {"military": {"ml_fake": _card({1: rc1, 2: rc2})}}
        errors = validate_r_conditional_star_parity(cards)
        self.assertEqual(len(errors), 1)
        self.assertIn("train", errors[0])
        self.assertIn("params differ", errors[0])

    def test_amount_drift_detected(self):
        """보급부대 bug class: same action/target, different amount across stars."""
        rc1 = [{"when": {"rank_gte": 10}, "effects": [
            {"grant_terazin": {"amount": 1}}]}]
        rc2 = [{"when": {"rank_gte": 10}, "effects": [
            {"grant_terazin": {"amount": 2}}]}]
        cards = {"military": {"ml_fake": _card({1: rc1, 2: rc2})}}
        errors = validate_r_conditional_star_parity(cards)
        self.assertEqual(len(errors), 1)
        self.assertIn("grant_terazin", errors[0])

    def test_nested_param_drift_detected(self):
        """군수공장 bug class: nested params differ (slot_delta 1 vs 2)."""
        rc1 = [{"when": {"rank_gte": 10}, "effects": [
            {"upgrade_shop_bonus": {"slot_delta": 1, "terazin_discount": 1}}]}]
        rc2 = [{"when": {"rank_gte": 10}, "effects": [
            {"upgrade_shop_bonus": {"slot_delta": 2, "terazin_discount": 2}}]}]
        cards = {"military": {"ml_fake": _card({1: rc1, 2: rc2})}}
        errors = validate_r_conditional_star_parity(cards)
        self.assertEqual(len(errors), 1)
        self.assertIn("upgrade_shop_bonus", errors[0])

    def test_different_rank_milestones_detected(self):
        """Different ``when`` values across stars must fail."""
        rc1 = [{"when": {"rank_gte": 4}, "effects": [
            {"grant_gold": {"amount": 1}}]}]
        rc2 = [{"when": {"rank_gte": 5}, "effects": [
            {"grant_gold": {"amount": 1}}]}]
        cards = {"military": {"ml_fake": _card({1: rc1, 2: rc2})}}
        errors = validate_r_conditional_star_parity(cards)
        self.assertEqual(len(errors), 1)
        self.assertIn("'when' differs", errors[0])

    def test_different_effect_count_detected(self):
        rc1 = [{"when": {"rank_gte": 4}, "effects": [
            {"grant_gold": {"amount": 1}}]}]
        rc2 = [{"when": {"rank_gte": 4}, "effects": [
            {"grant_gold": {"amount": 1}},
            {"grant_terazin": {"amount": 1}}]}]
        cards = {"military": {"ml_fake": _card({1: rc1, 2: rc2})}}
        errors = validate_r_conditional_star_parity(cards)
        self.assertEqual(len(errors), 1)
        self.assertIn("effects count differs", errors[0])

    def test_different_action_name_detected(self):
        rc1 = [{"when": {"rank_gte": 4}, "effects": [
            {"grant_gold": {"amount": 1}}]}]
        rc2 = [{"when": {"rank_gte": 4}, "effects": [
            {"grant_terazin": {"amount": 1}}]}]
        cards = {"military": {"ml_fake": _card({1: rc1, 2: rc2})}}
        errors = validate_r_conditional_star_parity(cards)
        self.assertEqual(len(errors), 1)
        self.assertIn("action name", errors[0])

    def test_allowlist_permits_declared_action(self):
        """star_scalable_actions: [crit_buff] should allow crit_buff.mult drift."""
        rc1 = [{"when": {"rank_gte": 4}, "effects": [
            {"crit_buff": {"target": "self", "chance": 0.2, "mult": 2.0}}]}]
        rc2 = [{"when": {"rank_gte": 4}, "effects": [
            {"crit_buff": {"target": "self", "chance": 0.2, "mult": 6.0}}]}]
        cards = {"military": {"ml_fake": _card(
            {1: rc1, 2: rc2}, star_scalable=["crit_buff"])}}
        self.assertEqual(validate_r_conditional_star_parity(cards), [])

    def test_allowlist_does_not_permit_other_actions(self):
        """star_scalable_actions: [crit_buff] does NOT permit grant_terazin drift."""
        rc1 = [{"when": {"rank_gte": 4}, "effects": [
            {"grant_terazin": {"amount": 1}}]}]
        rc2 = [{"when": {"rank_gte": 4}, "effects": [
            {"grant_terazin": {"amount": 2}}]}]
        cards = {"military": {"ml_fake": _card(
            {1: rc1, 2: rc2}, star_scalable=["crit_buff"])}}
        errors = validate_r_conditional_star_parity(cards)
        self.assertEqual(len(errors), 1)
        self.assertIn("grant_terazin", errors[0])

    def test_single_star_card_skipped(self):
        """Cards with only one star tier have nothing to compare."""
        cards = {"neutral": {"ne_fake": _card({1: [{"when": {"rank_gte": 4},
                                                    "effects": []}]})}}
        self.assertEqual(validate_r_conditional_star_parity(cards), [])

    def test_no_r_conditional_passes(self):
        """Cards without r_conditional (most non-military cards) pass trivially."""
        cards = {"neutral": {"ne_fake": {"stars": {1: {}, 2: {}, 3: {}}}}}
        self.assertEqual(validate_r_conditional_star_parity(cards), [])


if __name__ == "__main__":
    unittest.main()
