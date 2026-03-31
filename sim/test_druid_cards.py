#!/usr/bin/env python3
"""Druid card contribution analysis.

Tests each card's combat impact by removing one at a time.
Pre-applies R14 full-build stats based on actual card design doc.

Usage:
    python3 sim/test_druid_cards.py           # 200 runs
    python3 sim/test_druid_cards.py -n 500    # 500 runs
"""

from __future__ import annotations

import argparse
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from engine.types import UnitType, UnitStack, CardTemplate, TriggerSpec, TriggerTiming
from engine import units
from engine.cards import CardInstance
from engine.combat import (
    materialize_army, run_combat, make_diverse_enemy_army,
    CombatUnit, ALLY_START_X, ENEMY_START_X,
)
from data.unit_pool import register_all as register_steampunk_units
from data.card_pool import register_all as register_steampunk_cards
from data.enemies import generate_enemy, _BASE_CP, BOSS_ROUNDS

# ── Druid units ─────────────────────────────────────────────────

_DRUID_UNITS = [
    UnitType("dr_wolf",    "숲 늑대",       7,  40, 0.5, 0, 3, frozenset({"생체","중형","근접","야수"})),
    UnitType("dr_boar",    "가시 멧돼지",   9,  60, 1.0, 0, 2, frozenset({"생체","중형","근접","야수"})),
    UnitType("dr_treant",  "젊은 나무정령", 8,  80, 1.0, 0, 1, frozenset({"생체","중형","근접","수목"})),
    UnitType("dr_spirit",  "숲의 정령",     7,  60, 1.0, 2, 2, frozenset({"생체","중형","근접","정령"})),
    UnitType("dr_turtle",  "이끼 거북",     4, 100, 1.5, 0, 2, frozenset({"생체","대형","근접","야수"})),
    UnitType("dr_ancient", "고대 나무정령", 6, 150, 1.5, 0, 1, frozenset({"생체","대형","근접","수목"})),
    UnitType("dr_root",    "뿌리 수호자",   5,  70, 1.0, 2, 1, frozenset({"생체","중형","근접","수목","뿌리"})),
    UnitType("dr_vine",    "가시 덩굴",     8,  50, 1.0, 4, 1, frozenset({"생체","중형","원거리","수목"})),
    UnitType("dr_toad",    "독 두꺼비",     7,  45, 1.0, 4, 2, frozenset({"생체","중형","원거리","야수","독"})),
    UnitType("dr_spore",   "포자 대포",    14,  40, 1.5, 6, 1, frozenset({"생체","중형","원거리","균류"})),
]


def register_druid_units():
    for u in _DRUID_UNITS:
        units.register(u)


# ── Card templates ─────────────────────────────────────────────

def _tmpl(id_: str, name: str, tier: int,
          comp: tuple[tuple[str, int], ...]) -> CardTemplate:
    return CardTemplate(
        id=id_, name=name, tier=tier, theme="druid",
        composition=comp,
        trigger=TriggerSpec(timing=TriggerTiming.ROUND_START),
        effects=(), max_activations=None,
        card_tags=frozenset({"드루이드"}),
    )


# R14 6-card build: 요람, 뿌리깊은자, 포자, 태고, 세계수뿌리, 세계수
# (맥동은 R8에 판매, 은혜는 경제전용 → 전투 테스트에서 제외)
# 근원은 번식으로 유닛 추가
CARD_DEFS = {
    "cradle":   ("dr_cradle",  "숲의 요람",     1, (("dr_treant", 1), ("dr_wolf", 1))),
    "origin":   ("dr_origin",  "오래된 근원",   2, (("dr_turtle", 1), ("dr_vine", 1))),
    "deep":     ("dr_deep",    "뿌리깊은 자",   3, (("dr_ancient", 1), ("dr_root", 1))),
    "spore":    ("dr_spore_c", "포자 구름",     3, (("dr_spore", 1), ("dr_toad", 1))),
    "wrath":    ("dr_wrath",   "태고의 분노",   4, (("dr_spore", 1), ("dr_boar", 1))),
    "wt_root":  ("dr_wt_root", "세계수의 뿌리", 4, (("dr_ancient", 1), ("dr_turtle", 1))),
    "world":    ("dr_world",   "세계수",        5, (("dr_ancient", 1), ("dr_turtle", 1), ("dr_spirit", 1))),
}


# ── R14 🌳 estimates per card ──────────────────────────────────
# Based on timeline doc:
# 요람: +1자기+1인접/R. R1부터. ~14🌳 (자기 축적)
# 근원: +1자기+흡수1/R. R4부터. ~22🌳 (흡수 포함)
# 뿌리깊은자: +1/R. R5부터. ~10🌳
# 세계수뿌리: +1/R. R7부터. ~8🌳 (자기) + 분배 효과
# 세계수: +2/R. R9부터. ~12🌳 (자기)
# 포자: 비생성. 세계수뿌리/세계수로 ~8🌳
# 태고: 비생성. 세계수뿌리/세계수로 ~8🌳

SAPLING_R14 = {
    "cradle": 14, "origin": 16, "deep": 12, "spore": 8,
    "wrath": 8, "wt_root": 10, "world": 14,
}


def build_board(exclude: str | None = None,
                world_tree_mode: str = "iter3") -> tuple[list[CardInstance], float]:
    """Build R14 druid board, optionally excluding one card.

    world_tree_mode: "iter2" (ATK/HP ×1.9) or "iter3" (ATK ×1.9 only)
    Returns: (board, enemy_as_debuff_pct)
    """
    cards_to_use = [k for k in CARD_DEFS if k != exclude]
    board = []
    card_map = {}

    for key in cards_to_use:
        id_, name, tier, comp = CARD_DEFS[key]
        tmpl = _tmpl(id_, name, tier, comp)
        card = CardInstance(tmpl)
        board.append(card)
        card_map[key] = card

    # ── 1. Periodic upgrade: (1.15)^7 = 2.66 ─────────────────
    for card in board:
        card.multiply_stats(1.66, 1.66)

    # ── 2. 숲의 각성 (시스템 임계점) ──────────────────────────
    # 🌳20: HP +10%, 🌳40: ATK+HP +10%, 🌳60: 방어막 15%
    # Assume all 3 triggered by R14 (숲의 깊이 ~60+)
    for card in board:
        card.growth_atk_pct += 0.10   # 🌳40
        card.growth_hp_pct += 0.20    # 🌳20 + 🌳40
        card.shield_hp_pct += 0.15    # 🌳60

    # ── 3. 뿌리깊은 자: 🌳×2% ATK+HP growth + ×1.5 ATK ──────
    if "deep" in card_map:
        deep = card_map["deep"]
        sap = SAPLING_R14["deep"]
        # Accumulated growth: 🌳×2% per round from R5 to R14 (10 rounds)
        # But 🌳 increases each round: avg ~6 over 10 rounds → 6×2%×10 = 120%
        # Simplified: total accumulated growth ≈ sum(r×2% for r=1..10) = 110%
        deep.growth_atk_pct += 1.10
        deep.growth_hp_pct += 1.10
        # ×1.5 ATK multiplier (🌳≥10, self only)
        deep.multiply_stats(0.50, 0.0)

    # ── 4. 태고의 분노: ATK +(80%+🌳×5%) (self only) ─────────
    if "wrath" in card_map:
        wrath = card_map["wrath"]
        sap = SAPLING_R14.get("wrath", 0) if exclude != "wrath" else 0
        atk_bonus = 0.80 + sap * 0.05  # 80% + 8×5% = 120%
        wrath.growth_atk_pct += atk_bonus

    # ── 5. 근원: 번식 (인접 카드에 유닛 추가) ─────────────────
    if "origin" in card_map:
        origin = card_map["origin"]
        # R6~R14 = 9 rounds of breeding, 1 unit/R to adjacent
        # ~9 extra units distributed to adjacent cards
        rng = random.Random(42)
        idx = cards_to_use.index("origin")
        # Add units to adjacent cards
        for adj_idx in [idx - 1, idx + 1]:
            if 0 <= adj_idx < len(board):
                for _ in range(4):  # ~4 per adjacent
                    board[adj_idx].spawn_random(rng)

    # ── 6. 맥동 효과 (R8판매 전 방어막 누적) ──────────────────
    # 맥동은 R8에 판매. R1~R7 방어막: 5%+🌳×4%.
    # R7 🌳~8 → 37% shield. 이미 shield_hp_pct에 숲의 각성 15% 있음.
    # 실전에서는 전투 시작 시 적용 → growth modifier가 아닌 임시 방어막.
    # 판매 후에는 없음 → R14에서 맥동 효과 없음.

    # ── 7. 세계수 곱연산 ──────────────────────────────────────
    if "world" in card_map:
        # 숲의 깊이 R14: ~60~70. ATK ×1.7~1.9 (상한 ×2.0)
        # iter2: ATK/HP 둘 다 적용
        # iter3: ATK만 적용 (현재 설계)
        if world_tree_mode == "iter2":
            for card in board:
                card.multiply_stats(0.90, 0.90)  # ×1.9 ATK+HP
        else:  # iter3
            for card in board:
                card.multiply_stats(0.90, 0.0)   # ×1.9 ATK only

    # ── 8. 포자 구름: 적 AS 감소 ──────────────────────────────
    enemy_as_debuff = 0.0
    if "spore" in card_map:
        sap = SAPLING_R14.get("spore", 0)
        enemy_as_debuff = min(0.20 + sap * 0.02, 0.80)  # 20%+8×2%=36%

    return board, enemy_as_debuff


def materialize_army(board: list[CardInstance]) -> list[CombatUnit]:
    """Create CombatUnits from board."""
    army = []
    for card in board:
        for stack in card.stacks:
            atk = card.eff_atk_for(stack)
            hp = card.eff_hp_for(stack)
            for _ in range(stack.count):
                army.append(CombatUnit(
                    atk=atk, hp=hp, max_hp=hp,
                    attack_speed=stack.unit_type.attack_speed,
                    range=float(stack.unit_type.range),
                    move_speed=float(stack.unit_type.move_speed),
                    x=ALLY_START_X, is_ally=True,
                ))
    return army


def apply_enemy_as_debuff(enemies: list[CombatUnit], debuff_pct: float):
    """Slow enemy attack speed (increase AS value = slower attacks)."""
    if debuff_pct <= 0:
        return
    # AS debuff: multiply attack_speed by 1/(1-debuff)
    # e.g. 36% debuff → AS ×1.5625 (attacks 56% slower)
    factor = 1.0 / (1.0 - debuff_pct)
    for e in enemies:
        e.attack_speed *= factor


def run_combat_test(board: list[CardInstance], enemy_as_debuff: float,
                    target_round: int, num_runs: int, seed: int):
    """Run combat tests and return stats."""
    wins = 0
    total_cp = 0
    total_surv = 0
    total_units = 0

    for i in range(num_runs):
        rng = random.Random(seed + i)
        allies = materialize_army(board)
        total_units = len(allies)
        ally_cp = sum(u.atk / u.attack_speed * u.hp for u in allies)
        total_cp += ally_cp

        n_enemy, enemy_cp = generate_enemy(target_round, len(allies))
        enemies = make_diverse_enemy_army(n_enemy, enemy_cp)
        apply_enemy_as_debuff(enemies, enemy_as_debuff)

        result = run_combat(allies, enemies, rng)
        if result.won:
            wins += 1
        total_surv += result.ally_survivors

    return {
        "win_rate": wins / num_runs * 100,
        "avg_cp": total_cp / num_runs,
        "avg_surv": total_surv / num_runs,
        "units": total_units,
    }


CARD_NAMES = {
    "cradle": "숲의 요람",
    "origin": "오래된 근원",
    "deep":   "뿌리깊은 자",
    "spore":  "포자 구름",
    "wrath":  "태고의 분노",
    "wt_root":"세계수의 뿌리",
    "world":  "세계수",
}


def run_analysis(num_runs: int, seed: int):
    register_steampunk_units()
    register_druid_units()
    register_steampunk_cards()

    print(f"\n{'=' * 78}")
    print(f"  드루이드 카드별 기여도 분석 (R14/R15★)")
    print(f"  {num_runs} runs, seed={seed}")
    print(f"{'=' * 78}")

    for mode in ["iter2", "iter3"]:
        mode_label = "ATK/HP ×1.9" if mode == "iter2" else "ATK ×1.9 (현재 설계)"

        for target_round in [14, 15]:
            enemy_cp = _BASE_CP.get(target_round, 0)
            boss = "★" if target_round in BOSS_ROUNDS else ""
            print(f"\n  ── {mode_label} | R{target_round}{boss} (적 CP {enemy_cp:,}) ──")
            print(f"  {'Config':<30s} | {'Units':>5s} | {'CP':>10s} | {'Win%':>5s} | {'Surv':>5s} | {'ΔWIN':>6s}")
            print(f"  {'-' * 75}")

            # Full build
            board, debuff = build_board(exclude=None, world_tree_mode=mode)
            full = run_combat_test(board, debuff, target_round, num_runs, seed)
            print(f"  {'풀 빌드 (7장)':<30s} | {full['units']:>5d} | {full['avg_cp']:>10,.0f} | "
                  f"{full['win_rate']:>4.0f}% | {full['avg_surv']:>5.1f} | {'—':>6s}")

            # Remove each card
            impacts = []
            for card_key in CARD_DEFS:
                board, debuff = build_board(exclude=card_key, world_tree_mode=mode)
                r = run_combat_test(board, debuff, target_round, num_runs, seed)
                delta = r["win_rate"] - full["win_rate"]
                impacts.append((card_key, r, delta))
                print(f"  {'-' + CARD_NAMES[card_key]:<30s} | {r['units']:>5d} | {r['avg_cp']:>10,.0f} | "
                      f"{r['win_rate']:>4.0f}% | {r['avg_surv']:>5.1f} | {delta:>+5.0f}%p")

            # Sort by impact
            impacts.sort(key=lambda x: x[2])
            print(f"\n  기여도 순위 (제거 시 승률 하락):")
            for i, (key, r, delta) in enumerate(impacts):
                if delta < 0:
                    print(f"    {i+1}. {CARD_NAMES[key]}: {delta:+.0f}%p "
                          f"(CP {full['avg_cp']:,.0f}→{r['avg_cp']:,.0f})")

    print()


def main():
    p = argparse.ArgumentParser(description="Druid card contribution analysis")
    p.add_argument("-n", "--runs", type=int, default=200)
    p.add_argument("--seed", type=int, default=42)
    args = p.parse_args()
    run_analysis(args.runs, args.seed)


if __name__ == "__main__":
    main()
