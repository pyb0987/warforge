"""Enemy presets: target CP table + dynamic player-strength scaling.

CP table calibrated from weak build + 15% multiplicative upgrades.
Target: weak build ≈ listed win rate, strong build ≈ +20-30%.

R1-R3:  tutorial (100%)
R4-R8:  building phase (75-90%)
R9-R12: real challenge (25-65%)
R13-R15: endgame (8-20%)
"""

from __future__ import annotations

BOSS_ROUNDS = {4, 8, 12, 15}

# ── Target enemy CP per round (before dynamic scaling) ───────────
# Derived from: weak_build_CP × ratio_for_target_win_rate
#
#  R  | weak CP | target win% | ratio | enemy CP
# ----|---------|-------------|-------|----------
#  1  |     675 |     100%    | 0.55  |      370
#  4★ |   3,899 |      88%   | 0.78  |    3,040
#  8★ |  12,070 |      75%   | 0.95  |   11,470
# 12★ |  32,901 |      25%   | 1.45  |   47,710
# 15★ |  52,811 |       8%   | 1.65  |   87,140

_BASE_CP = {
    1:      450,   #   튜토리얼
    2:      595,   #   튜토리얼
    3:     1186,   #   튜토리얼
    4:     3544,   # ★ 앵커
    5:     4662,   #   ×1.315/R 균등 성장
    6:     6132,   #
    7:     8067,   #
    8:    10612,   # ★
    9:    13960,   #
    10:   18364,   #
    11:   24158,   #
    12:   31780,   # ★
    13:   41805,   #
    14:   54994,   #
    15:   72343,   # ★
}

def target_cp(rnd: int, player_units: int = 0) -> float:
    """Target enemy CP for a round."""
    return float(_BASE_CP.get(rnd, 50000))


def generate_enemy(rnd: int, player_units: int = 0) -> tuple[int, float]:
    """Generate (count, target_cp) for a round.

    Enemy army uses diverse unit types (all 20 from pool).
    Count scales with player units for comparable army sizes.
    """
    cp = target_cp(rnd, player_units)

    min_count = int(5 + (rnd - 1) * 1.5)
    if player_units > 10:
        ratio = 0.70 + rnd * 0.02
        count = max(min_count, int(player_units * ratio))
    else:
        count = min_count

    return (count, cp)
