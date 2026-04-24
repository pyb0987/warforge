"""Unit tests for calibrate_target_cp math layer.

Tests the pure-math part (derive_target_survival, derive_target_wr)
that does NOT require godot simulation.
"""

import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SIM_DIR = os.path.abspath(os.path.join(HERE, "..", "..", "godot", "sim"))
sys.path.insert(0, SIM_DIR)

from calibrate_target_cp import (  # noqa: E402
    derive_target_survival,
    derive_target_wr,
    _segment_of,
    _check_segment_convergence,
    SEGMENT_TOLERANCES_PP,
)


class TestDeriveTargetSurvival(unittest.TestCase):
    def test_user_anchors_R4_R8_R12_R15(self):
        """User-specified anchors: R4=0.80, R8=0.50, R12=0.25, R15=0.07."""
        anchors = {
            "rounds": [0, 4, 8, 12, 15],
            "values": [1.0, 0.80, 0.50, 0.25, 0.07],
        }
        s = derive_target_survival(anchors)
        self.assertEqual(len(s), 15)
        # Anchor rounds must match exactly
        self.assertAlmostEqual(s[3], 0.80, places=3)   # R4
        self.assertAlmostEqual(s[7], 0.50, places=3)   # R8
        self.assertAlmostEqual(s[11], 0.25, places=3)  # R12
        self.assertAlmostEqual(s[14], 0.07, places=3)  # R15

    def test_monotonic_nonincreasing(self):
        anchors = {"rounds": [0, 4, 8, 12, 15], "values": [1.0, 0.80, 0.50, 0.25, 0.07]}
        s = derive_target_survival(anchors)
        for i in range(1, 15):
            self.assertLessEqual(s[i], s[i - 1])

    def test_geometric_segment_uniform_per_round_clear(self):
        """Within a segment, per-round clear rate is constant."""
        anchors = {"rounds": [0, 4, 8, 12, 15], "values": [1.0, 0.80, 0.50, 0.25, 0.07]}
        s = derive_target_survival(anchors)
        # Segment 0 (R0→R4): clear ratio should be constant
        ratios_seg0 = [s[0] / 1.0, s[1] / s[0], s[2] / s[1], s[3] / s[2]]
        for i in range(1, 4):
            self.assertAlmostEqual(ratios_seg0[i], ratios_seg0[0], places=4)

    def test_rejects_nonmonotonic_anchors(self):
        anchors = {"rounds": [0, 4, 8, 12, 15], "values": [1.0, 0.80, 0.90, 0.25, 0.07]}
        with self.assertRaises(AssertionError):
            derive_target_survival(anchors)

    def test_rejects_first_round_nonzero(self):
        anchors = {"rounds": [1, 4, 8, 12, 15], "values": [1.0, 0.80, 0.50, 0.25, 0.07]}
        with self.assertRaises(AssertionError):
            derive_target_survival(anchors)

    def test_rejects_first_value_not_1(self):
        anchors = {"rounds": [0, 4, 8, 12, 15], "values": [0.95, 0.80, 0.50, 0.25, 0.07]}
        with self.assertRaises(AssertionError):
            derive_target_survival(anchors)


class TestDeriveTargetWR(unittest.TestCase):
    def test_conditional_clear_rate(self):
        """target_wr[r] = survival[r] / survival[r-1]."""
        survival = [0.9, 0.8, 0.6, 0.3, 0.1] + [0.05] * 10
        wr = derive_target_wr(survival)
        self.assertAlmostEqual(wr[0], 0.9 / 1.0)
        self.assertAlmostEqual(wr[1], 0.8 / 0.9)
        self.assertAlmostEqual(wr[2], 0.6 / 0.8)

    def test_product_reconstructs_survival(self):
        """∏(wr[0..r]) should equal survival[r]."""
        anchors = {"rounds": [0, 4, 8, 12, 15], "values": [1.0, 0.80, 0.50, 0.25, 0.07]}
        s = derive_target_survival(anchors)
        wr = derive_target_wr(s)
        prod = 1.0
        for r in range(15):
            prod *= wr[r]
            self.assertAlmostEqual(prod, s[r], places=4)


class TestEndToEndExpectedValues(unittest.TestCase):
    """Verify the exact per-round WR values I reported to the user."""

    def test_reported_per_round_wr(self):
        anchors = {"rounds": [0, 4, 8, 12, 15], "values": [1.0, 0.80, 0.50, 0.25, 0.07]}
        s = derive_target_survival(anchors)
        wr = derive_target_wr(s)

        # Phase 1 (R1-R4): per-round clear = 0.80^(1/4) ≈ 0.9457
        for r in range(4):
            self.assertAlmostEqual(wr[r], 0.80 ** 0.25, places=3)
        # Phase 2 (R5-R8): (0.50/0.80)^(1/4) ≈ 0.8891
        for r in range(4, 8):
            self.assertAlmostEqual(wr[r], (0.50 / 0.80) ** 0.25, places=3)
        # Phase 3 (R9-R12): (0.25/0.50)^(1/4) ≈ 0.8409
        for r in range(8, 12):
            self.assertAlmostEqual(wr[r], (0.25 / 0.50) ** 0.25, places=3)
        # Phase 4 (R13-R15): (0.07/0.25)^(1/3) ≈ 0.6540
        for r in range(12, 15):
            self.assertAlmostEqual(wr[r], (0.07 / 0.25) ** (1.0 / 3.0), places=3)

    def test_reported_survival_endpoints(self):
        anchors = {"rounds": [0, 4, 8, 12, 15], "values": [1.0, 0.80, 0.50, 0.25, 0.07]}
        s = derive_target_survival(anchors)
        # Values I reported to user
        self.assertAlmostEqual(s[0], 0.946, places=2)   # R1
        self.assertAlmostEqual(s[6], 0.562, places=2)   # R7
        self.assertAlmostEqual(s[9], 0.354, places=2)   # R10
        self.assertAlmostEqual(s[10], 0.297, places=2)  # R11
        self.assertAlmostEqual(s[14], 0.070, places=2)  # R15


class TestSegmentOf(unittest.TestCase):
    def test_early_R1_to_R8(self):
        for r in range(8):  # rounds 1..8 → 0-indexed 0..7
            self.assertEqual(_segment_of(r), "early", f"R{r+1} should be early")

    def test_mid_R9_to_R12(self):
        for r in range(8, 12):  # rounds 9..12 → 0-indexed 8..11
            self.assertEqual(_segment_of(r), "mid", f"R{r+1} should be mid")

    def test_late_R13_to_R15(self):
        for r in range(12, 15):
            self.assertEqual(_segment_of(r), "late", f"R{r+1} should be late")


class TestCheckSegmentConvergence(unittest.TestCase):
    def test_all_within_tolerance(self):
        # 2pp error everywhere, well within all segment tolerances
        errors = [0.02] * 15
        totals = [100] * 15
        converged, seg_max = _check_segment_convergence(errors, totals, min_samples=10)
        self.assertTrue(converged)
        self.assertAlmostEqual(seg_max["early"], 2.0)
        self.assertAlmostEqual(seg_max["mid"], 2.0)
        self.assertAlmostEqual(seg_max["late"], 2.0)

    def test_early_violates_5pp(self):
        errors = [0.06] + [0.02] * 14  # R1 has 6pp error
        totals = [100] * 15
        converged, seg_max = _check_segment_convergence(errors, totals, min_samples=10)
        self.assertFalse(converged)
        self.assertAlmostEqual(seg_max["early"], 6.0)

    def test_late_allows_10pp(self):
        # Late 10pp is WITHIN late tolerance (12pp), others fine
        errors = [0.02] * 12 + [0.10, 0.10, 0.10]
        totals = [100] * 15
        converged, seg_max = _check_segment_convergence(errors, totals, min_samples=10)
        self.assertTrue(converged)
        self.assertAlmostEqual(seg_max["late"], 10.0)

    def test_late_violates_13pp(self):
        errors = [0.02] * 12 + [0.13, 0.02, 0.02]
        totals = [100] * 15
        converged, seg_max = _check_segment_convergence(errors, totals, min_samples=10)
        self.assertFalse(converged)

    def test_skips_insufficient_samples(self):
        # R13-R15 have big errors but totals=5 < min_samples=10 → skipped
        errors = [0.02] * 12 + [0.30, 0.30, 0.30]
        totals = [100] * 12 + [5, 5, 5]
        converged, seg_max = _check_segment_convergence(errors, totals, min_samples=10)
        self.assertTrue(converged)
        # "late" segment has no samples, so not in seg_max
        self.assertNotIn("late", seg_max)

    def test_tolerance_constants(self):
        self.assertEqual(SEGMENT_TOLERANCES_PP["early"], 5.0)
        self.assertEqual(SEGMENT_TOLERANCES_PP["mid"], 8.0)
        self.assertEqual(SEGMENT_TOLERANCES_PP["late"], 12.0)


if __name__ == "__main__":
    unittest.main()
