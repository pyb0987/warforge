#!/usr/bin/env python3
"""Druid balance test: compare 4 world tree iterations in actual combat.

Tests R14 full-build druid (13 units) vs R14 enemies (~72k CP).
Pre-applies growth modifiers to simulate 🌳 accumulation without
implementing the full sapling system.

Usage:
    python3 sim/test_druid_balance.py          # 100 runs
    python3 sim/test_druid_balance.py -n 500   # 500 runs
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
from data.card_pool import register_all as register_steampunk_cards, get_template
from data.enemies import generate_enemy

# ── Druid units ─────────────────────────────────────────────────

_DRUID_UNITS = [
    UnitType("dr_wolf",    "숲 늑대",       7,  40, 0.5, 0, 3, frozenset({"생체","중형","근접","야수"})),
    UnitType("dr_boar",    "가시 멧돼지",   9,  60, 1.0, 0, 2, frozenset({"생체","중형","근접","야수"})),
    UnitType("dr_treant",  "젊은 나무정령", 8,  80, 1.0, 0, 1, frozenset({"생체","중형","근접","수목"})),
    UnitType("dr_spirit",  "숲의 정령",     7,  60, 1.0, 2, 2, frozenset({"생체","중형","근접","정령"})),
    UnitType("dr_turtle",  "이끼 거북",     4, 100, 1.5, 0, 2, frozenset({"생체","대형","근접","야수"})),
    UnitType("dr_ancient","고대 나무정령",  6, 150, 1.5, 0, 1, frozenset({"생체","대형","근접","수목"})),
    UnitType("dr_root",   "뿌리 수호자",    5,  70, 1.0, 2, 1, frozenset({"생체","중형","근접","수목","뿌리"})),
    UnitType("dr_vine",   "가시 덩굴",      8,  50, 1.0, 4, 1, frozenset({"생체","중형","원거리","수목"})),
    UnitType("dr_toad",   "독 두꺼비",      7,  45, 1.0, 4, 2, frozenset({"생체","중형","원거리","야수","독"})),
    UnitType("dr_spore",  "포자 대포",     14,  40, 1.5, 6, 1, frozenset({"생체","중형","원거리","균류"})),
]


def register_druid_units():
    for u in _DRUID_UNITS:
        units.register(u)


# ── Druid card templates (minimal, no triggers) ────────────────

def _make_druid_template(id_: str, name: str, tier: int,
                         comp: tuple[tuple[str, int], ...]) -> CardTemplate:
    return CardTemplate(
        id=id_, name=name, tier=tier, theme="druid",
        composition=comp,
        trigger=TriggerSpec(timing=TriggerTiming.ROUND_START),
        effects=(),
        max_activations=None,
        card_tags=frozenset({"드루이드"}),
    )


# 6-card R14 druid build
DRUID_CARDS = {
    "cradle":  _make_druid_template("dr_cradle", "숲의 요람", 1,
                (("dr_treant", 1), ("dr_wolf", 1))),
    "deep":    _make_druid_template("dr_deep", "뿌리깊은 자", 3,
                (("dr_ancient", 1), ("dr_root", 1))),
    "spore":   _make_druid_template("dr_spore_cloud", "포자 구름", 3,
                (("dr_spore", 1), ("dr_toad", 1))),
    "wrath":   _make_druid_template("dr_wrath", "태고의 분노", 4,
                (("dr_spore", 1), ("dr_boar", 1))),
    "roots":   _make_druid_template("dr_roots", "세계수의 뿌리", 4,
                (("dr_ancient", 1), ("dr_turtle", 1))),
    "world":   _make_druid_template("dr_world", "세계수", 5,
                (("dr_ancient", 1), ("dr_turtle", 1), ("dr_spirit", 1))),
}


# ── Iteration configs ──────────────────────────────────────────

"""
Each iteration defines how the world tree multiplier is applied.
All share:
  - Upgrade ×1.4 (ATK+HP) via multiply_stats
  - 숲의 각성: ATK+10%, HP+20% (growth modifier)
  - 뿌리깊은 자: +20% growth (ATK+HP), ×1.5 ATK (곱연산, self only)
  - 태고: varies by iteration

World tree multiplier applied as multiplicative upgrade (Layer 2).
"""

ITERATIONS = {
    "iter0": {
        "label": "Iter0: ATK/HP/AS ×2.2, 태고 전체",
        "world_tree_atk": 2.2,
        "world_tree_hp": 2.2,
        "world_tree_as": 2.2,   # AS = divide attack_speed
        "tago_target": "all",   # all druid cards
        "tago_atk_bonus": 1.40, # +140% base ATK
    },
    "iter1": {
        "label": "Iter1: ATK/HP/AS ×2.2, 태고 자카드",
        "world_tree_atk": 2.2,
        "world_tree_hp": 2.2,
        "world_tree_as": 2.2,
        "tago_target": "self",
        "tago_atk_bonus": 1.40,
    },
    "iter2": {
        "label": "Iter2: ATK/HP ×1.9, 태고 자카드",
        "world_tree_atk": 1.9,
        "world_tree_hp": 1.9,
        "world_tree_as": 1.0,   # no AS multiplier
        "tago_target": "self",
        "tago_atk_bonus": 1.40,
    },
    "iter3": {
        "label": "Iter3: ATK ×1.9, 태고 자카드",
        "world_tree_atk": 1.9,
        "world_tree_hp": 1.0,   # no HP multiplier
        "world_tree_as": 1.0,
        "tago_target": "self",
        "tago_atk_bonus": 1.40,
    },
}


def build_druid_board(config: dict) -> list[CardInstance]:
    """Build R14 druid board with pre-applied modifiers."""
    board = []
    card_map = {}

    for key, tmpl in DRUID_CARDS.items():
        card = CardInstance(tmpl)
        board.append(card)
        card_map[key] = card

    # ── Common modifiers ──────────────────────────────────────

    # 1. Periodic upgrade: every 2 rounds for 14 rounds = 7 upgrades of ×1.15
    # (1.15)^7 = 2.66 ATK+HP
    for card in board:
        card.multiply_stats(1.66, 1.66)  # (1.15)^7 = 2.66, so +1.66

    # 2. 숲의 각성: ATK+10%, HP+20% (growth modifier, base%)
    for card in board:
        card.growth_atk_pct += 0.10
        card.growth_hp_pct += 0.20

    # 3. 뿌리깊은 자: +20% growth (ATK+HP, self only)
    deep = card_map["deep"]
    deep.growth_atk_pct += 0.20
    deep.growth_hp_pct += 0.20

    # ── Iteration-specific modifiers ──────────────────────────

    wt_atk = config["world_tree_atk"]
    wt_hp = config["world_tree_hp"]
    wt_as = config["world_tree_as"]

    # 4. World tree multiplier (applied as Layer 2)
    for card in board:
        if wt_atk > 1.0:
            card.multiply_stats(wt_atk - 1.0, 0.0)
        if wt_hp > 1.0:
            card.multiply_stats(0.0, wt_hp - 1.0)

    # 5. 뿌리깊은 자 ×1.5 ATK (self only, 곱연산)
    deep.multiply_stats(0.50, 0.0)

    # 6. 태고의 분노: ATK bonus
    tago_bonus = config["tago_atk_bonus"]
    if config["tago_target"] == "all":
        for card in board:
            card.growth_atk_pct += tago_bonus
    else:
        card_map["wrath"].growth_atk_pct += tago_bonus

    # 7. AS multiplier (for iter0/iter1: divide attack_speed)
    # We need to modify the actual units for AS
    if wt_as > 1.0:
        for card in board:
            for stack in card.stacks:
                # Faster AS = lower attack_speed value
                # Can't modify frozen UnitType, so we create modified stacks
                pass  # Handle in materialize step

    return board, wt_as


def materialize_druid_army(board: list[CardInstance], as_mult: float) -> list[CombatUnit]:
    """Create CombatUnits from druid board, applying AS multiplier."""
    army = []
    for card in board:
        for stack in card.stacks:
            atk = card.eff_atk_for(stack)
            hp = card.eff_hp_for(stack)
            for _ in range(stack.count):
                effective_as = stack.unit_type.attack_speed / as_mult
                army.append(CombatUnit(
                    atk=atk, hp=hp, max_hp=hp,
                    attack_speed=effective_as,
                    range=float(stack.unit_type.range),
                    move_speed=float(stack.unit_type.move_speed),
                    x=ALLY_START_X,
                    is_ally=True,
                ))
    return army


# ── Steampunk reference build ──────────────────────────────────

def build_steampunk_board() -> list[CardInstance]:
    """Build R14 steampunk 7-card matching strong preset R14 stats.

    Strong preset R14: ~88 units, CP ~98k, 개량 누적 ~150%.
    Cards: 조립소, 공방, 조립라인, 야생의힘, 고대잔해, 전쟁기계, 떠돌이
    We add ~70 extra units (제조 chain result) to match ~88 total.
    """
    card_ids = [
        "sp_assembly", "sp_workshop", "sp_line",
        "ne_wildforce", "ne_ruins", "sp_warmachine", "ne_wanderers",
    ]
    board = [CardInstance(get_template(cid)) for cid in card_ids]

    # 1. Periodic upgrade: (1.15)^7 = 2.66
    for card in board:
        card.multiply_stats(1.66, 1.66)

    # 2. 개량 누적: ATK +150% (14 rounds of chain)
    for card in board:
        card.growth_atk_pct += 1.50

    # 3. ~70 extra units from 제조 chain (88 total - 18 base ≈ 70)
    rng = random.Random(42)
    for card in board:
        for _ in range(10):
            card.spawn_random(rng)

    return board


# ── Test runner ────────────────────────────────────────────────

def run_test(num_runs: int, seed: int):
    register_steampunk_units()
    register_druid_units()
    register_steampunk_cards()

    print(f"\n{'=' * 78}")
    print(f"  드루이드 밸런스 테스트: R14 전투 (적 CP ~55,000)")
    print(f"  {num_runs} runs, seed={seed}")
    print(f"{'=' * 78}")

    # Enemy config: test R12★, R14, R15★
    test_rounds = [12, 14, 15]
    for target_round in test_rounds:
        results = {}

        # ── Test each druid iteration ─────────────────────────
        for iter_id, config in ITERATIONS.items():
            wins = 0
            total_ally_survivors = 0
            total_enemy_survivors = 0
            total_ally_cp = 0

            for i in range(num_runs):
                rng = random.Random(seed + i)
                board, as_mult = build_druid_board(config)
                allies = materialize_druid_army(board, as_mult)

                enemy_rng = random.Random(seed + i + 10000)
                n_enemy, enemy_cp = generate_enemy(target_round, len(allies))
                enemies = make_diverse_enemy_army(n_enemy, enemy_cp)

                ally_cp = sum(u.atk / u.attack_speed * u.hp for u in allies)
                total_ally_cp += ally_cp

                result = run_combat(allies, enemies, rng)
                if result.won:
                    wins += 1
                total_ally_survivors += result.ally_survivors
                total_enemy_survivors += result.enemy_survivors

            results[iter_id] = {
                "label": config["label"],
                "win_rate": wins / num_runs * 100,
                "avg_cp": total_ally_cp / num_runs,
                "avg_survivors": total_ally_survivors / num_runs,
                "avg_enemy_surv": total_enemy_survivors / num_runs,
                "units": len(materialize_druid_army(
                    build_druid_board(config)[0], 1.0)),
            }

        # ── Steampunk reference ───────────────────────────────
        sp_wins = 0
        sp_total_cp = 0
        sp_total_surv = 0
        sp_total_enemy_surv = 0
        sp_units = 0

        for i in range(num_runs):
            rng = random.Random(seed + i)
            board = build_steampunk_board()
            allies = []
            for card in board:
                for stack in card.stacks:
                    atk = card.eff_atk_for(stack)
                    hp = card.eff_hp_for(stack)
                    for _ in range(stack.count):
                        allies.append(CombatUnit(
                            atk=atk, hp=hp, max_hp=hp,
                            attack_speed=stack.unit_type.attack_speed,
                            range=float(stack.unit_type.range),
                            move_speed=float(stack.unit_type.move_speed),
                            x=ALLY_START_X, is_ally=True,
                        ))
            sp_units = len(allies)
            sp_total_cp += sum(u.atk / u.attack_speed * u.hp for u in allies)

            enemy_rng = random.Random(seed + i + 10000)
            n_enemy, enemy_cp = generate_enemy(target_round, len(allies))
            enemies = make_diverse_enemy_army(n_enemy, enemy_cp)

            result = run_combat(allies, enemies, rng)
            if result.won:
                sp_wins += 1
            sp_total_surv += result.ally_survivors
            sp_total_enemy_surv += result.enemy_survivors

        results["steampunk"] = {
            "label": "스팀펑크 (개량+150%, 제조+70유닛)",
            "win_rate": sp_wins / num_runs * 100,
            "avg_cp": sp_total_cp / num_runs,
            "avg_survivors": sp_total_surv / num_runs,
            "avg_enemy_surv": sp_total_enemy_surv / num_runs,
            "units": sp_units,
        }

        # ── Print results ─────────────────────────────────────
        from data.enemies import _BASE_CP, BOSS_ROUNDS
        enemy_cp_val = _BASE_CP.get(target_round, 0)
        boss = "★" if target_round in BOSS_ROUNDS else ""
        print(f"\n  ── R{target_round}{boss} (적 CP {enemy_cp_val:,}) ──")
        print(f"  {'Config':<44s} | {'Units':>5s} | {'CP':>10s} | "
              f"{'Win%':>5s} | {'Surv':>5s} | {'E.Surv':>6s}")
        print(f"  {'-' * 85}")

        for iter_id, r in results.items():
            marker = " ◄" if iter_id == "iter3" else ""
            print(f"  {r['label']:<44s} | {r['units']:>5d} | {r['avg_cp']:>10,.0f} | "
                  f"{r['win_rate']:>4.0f}% | {r['avg_survivors']:>5.1f} | "
                  f"{r['avg_enemy_surv']:>6.1f}{marker}")

    print()


def main():
    p = argparse.ArgumentParser(description="Druid balance test")
    p.add_argument("-n", "--runs", type=int, default=100)
    p.add_argument("--seed", type=int, default=42)
    args = p.parse_args()
    run_test(args.runs, args.seed)


if __name__ == "__main__":
    main()
