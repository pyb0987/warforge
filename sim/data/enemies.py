"""Enemy presets: target CP table + dynamic player-strength scaling.

난이도 철학:
  잘 풀린 빌드(커맨더/장신구/업그레이드 없이) R15 클리어율 1~10%.
  커맨더+장신구+업그레이드 포함 시 보통 난이도 클리어 가능.
  R15 보스 패배 = 즉사 (HP 남아도 게임 패배).

밸런싱 기준: 전투 시뮬 승률 (1차) > CP (2차, 참고).
  CP는 Range/MS 미반영 → 빌드 간 직접 비교 부적합.

R1-R3:  tutorial (100%)
R4-R8:  building phase (75-90%)
R9-R12: real challenge (25-65%)
R13-R14: endgame (10-30%)
R15★:  최종 보스 (잘 풀린 빌드 1~10%)
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

# 긴장감 곡선: 점진적 파동형
#   R1~R3:  튜토리얼 (편함)
#   R4★:    첫 보스 (긴장)
#   R5~R7:  소규모 위험 (HP 점진 소모, ★2 성장 체감)
#   R8★:    두 번째 보스 (긴장 강화)
#   R9:     이완 (신규 카드 투입)
#   R10~R11: 긴장 파동 (적 급등, 점프 완화)
#   R12★:   세 번째 보스 (클라이맥스)
#   R13~R14: 조여옴
#   R15★:   최종 보스 (즉사)
_BASE_CP = {
    1:      450,   #   튜토리얼
    2:      595,   #   튜토리얼
    3:     1186,   #   튜토리얼
    4:     3544,   # ★ 첫 보스
    5:     5200,   #   소규모 위험 (↑12%)
    6:     7000,   #   아슬아슬 (↑14%)
    7:     9500,   #   아슬아슬 (↑18%)
    8:    13000,   # ★ 두 번째 보스 (↑23%, 긴장 강화)
    9:    18000,   #   이완 (신규 카드 투입)
    10:   28000,   #   긴장 파동 (R9→R10 ×1.56 점프)
    11:   40000,   #   긴장 유지
    12:   55000,   # ★ 세 번째 보스 (클라이맥스)
    13:   65000,   #   조여옴
    14:   82000,   #   조여옴
    15:  117000,   # ★ 최종보스 (잘 풀린 빌드 기준 1~10% 클리어)
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
