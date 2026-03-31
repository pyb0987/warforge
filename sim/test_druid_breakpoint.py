#!/usr/bin/env python3
"""Find the enemy CP breakpoint (50% win rate) for each druid config.

Binary-searches enemy CP to find where each configuration starts losing.
This measures actual combat effectiveness independent of the CP table.

Usage:
    python3 sim/test_druid_breakpoint.py
    python3 sim/test_druid_breakpoint.py -n 300
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
    run_combat, make_diverse_enemy_army,
    CombatUnit, ALLY_START_X,
)
from data.unit_pool import register_all as register_steampunk_units
from data.card_pool import register_all as register_steampunk_cards, get_template
from data.enemies import generate_enemy

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


def _tmpl(id_: str, name: str, tier: int,
          comp: tuple[tuple[str, int], ...]) -> CardTemplate:
    return CardTemplate(
        id=id_, name=name, tier=tier, theme="druid",
        composition=comp,
        trigger=TriggerSpec(timing=TriggerTiming.ROUND_START),
        effects=(), max_activations=None,
        card_tags=frozenset({"드루이드"}),
    )


CARD_DEFS = {
    "cradle":   ("dr_cradle",  "숲의 요람",     1, (("dr_treant", 1), ("dr_wolf", 1))),
    "origin":   ("dr_origin",  "오래된 근원",   2, (("dr_turtle", 1), ("dr_vine", 1))),
    "deep":     ("dr_deep",    "뿌리깊은 자",   3, (("dr_ancient", 1), ("dr_root", 1))),
    "spore":    ("dr_spore_c", "포자 구름",     3, (("dr_spore", 1), ("dr_toad", 1))),
    "wrath":    ("dr_wrath",   "태고의 분노",   4, (("dr_spore", 1), ("dr_boar", 1))),
    "wt_root":  ("dr_wt_root", "세계수의 뿌리", 4, (("dr_ancient", 1), ("dr_turtle", 1))),
    "world":    ("dr_world",   "세계수",        5, (("dr_ancient", 1), ("dr_turtle", 1), ("dr_spirit", 1))),
}

SAPLING_R14 = {
    "cradle": 14, "origin": 16, "deep": 12, "spore": 8,
    "wrath": 8, "wt_root": 10, "world": 14,
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


def build_board(exclude: str | None = None,
                world_tree_mode: str = "iter3") -> tuple[list[CardInstance], float]:
    """Build R14 druid board. Returns (board, enemy_as_debuff_pct)."""
    cards_to_use = [k for k in CARD_DEFS if k != exclude]
    board = []
    card_map = {}

    for key in cards_to_use:
        id_, name, tier, comp = CARD_DEFS[key]
        tmpl = _tmpl(id_, name, tier, comp)
        card = CardInstance(tmpl)
        board.append(card)
        card_map[key] = card

    # 1. Periodic upgrade: (1.15)^7 = 2.66
    for card in board:
        card.multiply_stats(1.66, 1.66)

    # 2. 숲의 각성 (ATK+10%, HP+20%, shield 15%)
    for card in board:
        card.growth_atk_pct += 0.10
        card.growth_hp_pct += 0.20
        card.shield_hp_pct += 0.15

    # 3. 뿌리깊은 자: accumulated growth ~110% + ×1.5 ATK
    if "deep" in card_map:
        card_map["deep"].growth_atk_pct += 1.10
        card_map["deep"].growth_hp_pct += 1.10
        card_map["deep"].multiply_stats(0.50, 0.0)

    # 4. 태고: ATK +(80%+🌳×5%) self only
    if "wrath" in card_map:
        sap = SAPLING_R14.get("wrath", 0)
        card_map["wrath"].growth_atk_pct += 0.80 + sap * 0.05

    # 5. 근원: 번식 (~8 extra units to adjacent)
    if "origin" in card_map:
        rng = random.Random(42)
        idx = cards_to_use.index("origin")
        for adj_idx in [idx - 1, idx + 1]:
            if 0 <= adj_idx < len(board):
                for _ in range(4):
                    board[adj_idx].spawn_random(rng)

    # 6. 세계수 곱연산
    if "world" in card_map:
        if world_tree_mode == "iter2":
            for card in board:
                card.multiply_stats(0.90, 0.90)
        else:
            for card in board:
                card.multiply_stats(0.90, 0.0)

    # 7. 포자 AS debuff
    enemy_as_debuff = 0.0
    if "spore" in card_map:
        sap = SAPLING_R14.get("spore", 0)
        enemy_as_debuff = min(0.20 + sap * 0.02, 0.80)

    return board, enemy_as_debuff


def materialize(board: list[CardInstance]) -> list[CombatUnit]:
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


def apply_as_debuff(enemies: list[CombatUnit], debuff_pct: float):
    if debuff_pct <= 0:
        return
    factor = 1.0 / (1.0 - debuff_pct)
    for e in enemies:
        e.attack_speed *= factor


def win_rate_at_cp(board: list[CardInstance], enemy_as_debuff: float,
                   target_cp: float, num_units: int,
                   num_runs: int, seed: int) -> float:
    """Test win rate against enemies of given CP."""
    wins = 0
    for i in range(num_runs):
        rng = random.Random(seed + i)
        allies = materialize(board)
        enemies = make_diverse_enemy_army(num_units, target_cp)
        apply_as_debuff(enemies, enemy_as_debuff)
        result = run_combat(allies, enemies, rng)
        if result.won:
            wins += 1
    return wins / num_runs * 100


def find_breakpoint(board: list[CardInstance], enemy_as_debuff: float,
                    num_runs: int, seed: int) -> float:
    """Binary search for the enemy CP where win rate ≈ 50%."""
    allies = materialize(board)
    n_allies = len(allies)
    n_enemies = max(10, int(n_allies * 0.8))

    # Find upper bound (where we lose)
    low, high = 10_000, 100_000
    while win_rate_at_cp(board, enemy_as_debuff, high, n_enemies,
                          min(num_runs, 50), seed) > 20:
        low = high
        high *= 2
        if high > 10_000_000:
            return high  # never loses

    # Binary search
    for _ in range(12):
        mid = (low + high) / 2
        wr = win_rate_at_cp(board, enemy_as_debuff, mid, n_enemies,
                            num_runs, seed)
        if wr > 50:
            low = mid
        else:
            high = mid

    return (low + high) / 2


def build_steampunk_r14() -> list[CardInstance]:
    """Strong steampunk R14 (89 units, ~98k CP)."""
    card_ids = [
        "sp_assembly", "sp_workshop", "sp_line",
        "ne_wildforce", "ne_ruins", "sp_warmachine", "ne_wanderers",
    ]
    board = [CardInstance(get_template(cid)) for cid in card_ids]
    for card in board:
        card.multiply_stats(1.66, 1.66)
    for card in board:
        card.growth_atk_pct += 1.50
    rng = random.Random(42)
    for card in board:
        for _ in range(10):
            card.spawn_random(rng)
    return board


def run_analysis(num_runs: int, seed: int):
    register_steampunk_units()
    register_druid_units()
    register_steampunk_cards()

    print(f"\n{'=' * 78}")
    print(f"  드루이드 한계점 분석: 50% 승률 달성 적 CP")
    print(f"  {num_runs} runs/test, seed={seed}")
    print(f"{'=' * 78}")

    for mode in ["iter2", "iter3"]:
        mode_label = "Iter2 ATK/HP ×1.9" if mode == "iter2" else "Iter3 ATK ×1.9 (현재)"
        print(f"\n  ── {mode_label} ──")
        print(f"  {'Config':<32s} | {'Units':>5s} | {'CP':>10s} | {'한계 적CP':>10s} | {'효율':>6s}")
        print(f"  {'-' * 75}")

        # Full build
        board, debuff = build_board(exclude=None, world_tree_mode=mode)
        allies = materialize(board)
        ally_cp = sum(u.atk / u.attack_speed * u.hp for u in allies)
        bp = find_breakpoint(board, debuff, num_runs, seed)
        eff = bp / ally_cp if ally_cp > 0 else 0
        print(f"  {'풀 빌드 (7장)':<32s} | {len(allies):>5d} | {ally_cp:>10,.0f} | "
              f"{bp:>10,.0f} | {eff:>5.2f}×")

        full_bp = bp

        # Remove each card
        impacts = []
        for card_key in CARD_DEFS:
            board, debuff = build_board(exclude=card_key, world_tree_mode=mode)
            allies = materialize(board)
            acp = sum(u.atk / u.attack_speed * u.hp for u in allies)
            bp_val = find_breakpoint(board, debuff, num_runs, seed)
            eff_val = bp_val / acp if acp > 0 else 0
            delta_bp = bp_val - full_bp
            impacts.append((card_key, len(allies), acp, bp_val, eff_val, delta_bp))
            print(f"  {'-' + CARD_NAMES[card_key]:<32s} | {len(allies):>5d} | {acp:>10,.0f} | "
                  f"{bp_val:>10,.0f} | {eff_val:>5.2f}×")

        # Rank by breakpoint impact
        impacts.sort(key=lambda x: x[5])
        print(f"\n  제거 시 한계점 하락 순위:")
        for i, (key, units, acp, bp_val, eff_val, delta) in enumerate(impacts):
            pct = delta / full_bp * 100 if full_bp > 0 else 0
            bar = "█" * max(1, int(abs(pct) / 3))
            print(f"    {i+1}. {CARD_NAMES[key]:<14s}: {delta:>+10,.0f} ({pct:>+5.1f}%) {bar}")

    # Steampunk reference
    print(f"\n  ── 스팀펑크 참조 ──")
    board = build_steampunk_r14()
    allies = materialize(board)
    ally_cp = sum(u.atk / u.attack_speed * u.hp for u in allies)
    bp = find_breakpoint(board, 0.0, num_runs, seed)
    eff = bp / ally_cp if ally_cp > 0 else 0
    print(f"  {'스팀펑크 strong':<32s} | {len(allies):>5d} | {ally_cp:>10,.0f} | "
          f"{bp:>10,.0f} | {eff:>5.2f}×")

    print()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("-n", "--runs", type=int, default=100)
    p.add_argument("--seed", type=int, default=42)
    args = p.parse_args()
    run_analysis(args.runs, args.seed)


if __name__ == "__main__":
    main()
