#!/usr/bin/env python3
"""Compare druid before/after nerfs to spore cloud and deep root.

Nerf 1: 포자 구름 AS debuff 20%+🌳×2% (cap80%) → 15%+🌳×1.5% (cap60%)
Nerf 2: 뿌리깊은 자 growth 🌳×2% → 🌳×1.5%

Usage:
    python3 sim/test_druid_nerf.py
    python3 sim/test_druid_nerf.py -n 200
"""

from __future__ import annotations

import argparse
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from engine.types import UnitType, CardTemplate, TriggerSpec, TriggerTiming
from engine import units
from engine.cards import CardInstance
from engine.combat import (
    run_combat, make_diverse_enemy_army,
    CombatUnit, ALLY_START_X,
)
from data.unit_pool import register_all as register_steampunk_units
from data.card_pool import register_all as register_steampunk_cards, get_template
from data.enemies import _BASE_CP

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


def _tmpl(id_, name, tier, comp):
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


# ── Two versions of build_board ────────────────────────────────

def build_board(nerf: bool = False) -> tuple[list[CardInstance], float]:
    """Build R14 druid full board (Iter3: ATK ×1.9).

    nerf=True applies:
      - 포자: 15%+🌳×1.5% (cap 60%)  [was 20%+🌳×2%, cap 80%]
      - 뿌리깊은 자: 🌳×1.5% growth   [was 🌳×2%]
    """
    board = []
    card_map = {}

    for key, (id_, name, tier, comp) in CARD_DEFS.items():
        tmpl = _tmpl(id_, name, tier, comp)
        card = CardInstance(tmpl)
        board.append(card)
        card_map[key] = card

    cards_list = list(CARD_DEFS.keys())

    # 1. Periodic upgrade: (1.15)^7 = 2.66
    for card in board:
        card.multiply_stats(1.66, 1.66)

    # 2. 숲의 각성 (ATK+10%, HP+20%, shield 15%)
    for card in board:
        card.growth_atk_pct += 0.10
        card.growth_hp_pct += 0.20
        card.shield_hp_pct += 0.15

    # 3. 뿌리깊은 자
    deep = card_map["deep"]
    sap_deep = SAPLING_R14["deep"]  # 12
    if nerf:
        # 🌳×1.5% → accumulated over 10R: sum(1..10)×1.5% = 82.5%
        deep.growth_atk_pct += 0.825
        deep.growth_hp_pct += 0.825
    else:
        # 🌳×2% → accumulated over 10R: sum(1..10)×2% = 110%
        deep.growth_atk_pct += 1.10
        deep.growth_hp_pct += 1.10
    # ×1.5 ATK if 🌳≥10 (unchanged)
    deep.multiply_stats(0.50, 0.0)

    # 4. 태고: ATK +(80%+🌳×5%) self only (unchanged)
    wrath = card_map["wrath"]
    sap_wrath = SAPLING_R14["wrath"]
    wrath.growth_atk_pct += 0.80 + sap_wrath * 0.05

    # 5. 근원: 번식 (~8 extra units)
    rng = random.Random(42)
    idx = cards_list.index("origin")
    for adj_idx in [idx - 1, idx + 1]:
        if 0 <= adj_idx < len(board):
            for _ in range(4):
                board[adj_idx].spawn_random(rng)

    # 6. 세계수: ATK ×1.9 (Iter3, unchanged)
    for card in board:
        card.multiply_stats(0.90, 0.0)

    # 7. 포자 AS debuff
    sap_spore = SAPLING_R14["spore"]
    if nerf:
        enemy_as_debuff = min(0.15 + sap_spore * 0.015, 0.60)  # 15%+8×1.5%=27%
    else:
        enemy_as_debuff = min(0.20 + sap_spore * 0.02, 0.80)   # 20%+8×2%=36%

    return board, enemy_as_debuff


def build_steampunk_r14() -> list[CardInstance]:
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


def materialize(board):
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


def apply_as_debuff(enemies, debuff_pct):
    if debuff_pct <= 0:
        return
    factor = 1.0 / (1.0 - debuff_pct)
    for e in enemies:
        e.attack_speed *= factor


def find_breakpoint(board, enemy_as_debuff, num_runs, seed):
    """Binary search for 50% win rate enemy CP."""
    allies = materialize(board)
    n_enemies = max(10, int(len(allies) * 0.8))

    low, high = 10_000, 100_000
    while True:
        wins = 0
        for i in range(min(num_runs, 50)):
            rng = random.Random(seed + i)
            a = materialize(board)
            e = make_diverse_enemy_army(n_enemies, high)
            apply_as_debuff(e, enemy_as_debuff)
            if run_combat(a, e, rng).won:
                wins += 1
        if wins / min(num_runs, 50) <= 0.20:
            break
        low = high
        high *= 2
        if high > 10_000_000:
            return high

    for _ in range(12):
        mid = (low + high) / 2
        wins = 0
        for i in range(num_runs):
            rng = random.Random(seed + i)
            a = materialize(board)
            e = make_diverse_enemy_army(n_enemies, mid)
            apply_as_debuff(e, enemy_as_debuff)
            if run_combat(a, e, rng).won:
                wins += 1
        if wins / num_runs > 0.50:
            low = mid
        else:
            high = mid

    return (low + high) / 2


def run_analysis(num_runs, seed):
    register_steampunk_units()
    register_druid_units()
    register_steampunk_cards()

    print(f"\n{'=' * 78}")
    print(f"  포자 구름 + 뿌리깊은 자 너프 비교 (Iter3: ATK ×1.9)")
    print(f"  {num_runs} runs/test, seed={seed}")
    print(f"{'=' * 78}")

    configs = [
        ("변경 전", False),
        ("변경 후", True),
    ]

    print(f"\n  변경 내용:")
    print(f"    포자 구름:   AS -(20%+🌳×2%, 상한80%) → -(15%+🌳×1.5%, 상한60%)")
    print(f"    뿌리깊은 자: 🌳×2% 성장 → 🌳×1.5% 성장")

    print(f"\n  {'Config':<16s} | {'Units':>5s} | {'CP':>10s} | {'한계 적CP':>10s} | {'효율':>6s} | AS디버프")
    print(f"  {'-' * 78}")

    results = {}
    for label, nerf in configs:
        board, debuff = build_board(nerf=nerf)
        allies = materialize(board)
        ally_cp = sum(u.atk / u.attack_speed * u.hp for u in allies)
        bp = find_breakpoint(board, debuff, num_runs, seed)
        eff = bp / ally_cp if ally_cp > 0 else 0
        results[label] = {"cp": ally_cp, "bp": bp, "eff": eff,
                          "units": len(allies), "debuff": debuff}
        print(f"  {label:<16s} | {len(allies):>5d} | {ally_cp:>10,.0f} | "
              f"{bp:>10,.0f} | {eff:>5.2f}× | {debuff:.0%}")

    # Steampunk reference
    board = build_steampunk_r14()
    allies = materialize(board)
    sp_cp = sum(u.atk / u.attack_speed * u.hp for u in allies)
    sp_bp = find_breakpoint(board, 0.0, num_runs, seed)
    sp_eff = sp_bp / sp_cp if sp_cp > 0 else 0
    print(f"  {'스팀펑크 참조':<16s} | {len(allies):>5d} | {sp_cp:>10,.0f} | "
          f"{sp_bp:>10,.0f} | {sp_eff:>5.2f}× | —")

    # Comparison
    before = results["변경 전"]
    after = results["변경 후"]
    print(f"\n  {'─' * 78}")
    print(f"  비교:")
    print(f"    CP 변화:      {before['cp']:>10,.0f} → {after['cp']:>10,.0f} "
          f"({(after['cp']/before['cp']-1)*100:>+.1f}%)")
    print(f"    한계 적CP:    {before['bp']:>10,.0f} → {after['bp']:>10,.0f} "
          f"({(after['bp']/before['bp']-1)*100:>+.1f}%)")
    print(f"    AS 디버프:    {before['debuff']:.0%} → {after['debuff']:.0%}")
    print(f"    vs 스팀펑크:  {before['bp']/sp_bp:.2f}× → {after['bp']/sp_bp:.2f}×")

    # Win rate at specific enemy CPs (R12★, R14, R15★)
    print(f"\n  라운드별 승률 비교:")
    print(f"  {'라운드':<8s} | {'적 CP':>8s} | {'변경 전':>8s} | {'변경 후':>8s} | {'스팀펑크':>8s}")
    print(f"  {'-' * 50}")

    for rnd in [8, 10, 12, 14, 15]:
        ecp = _BASE_CP[rnd]
        n_enemies = max(10, 18)

        wrs = {}
        for label, nerf in configs:
            board, debuff = build_board(nerf=nerf)
            wins = 0
            for i in range(num_runs):
                rng = random.Random(seed + i)
                a = materialize(board)
                e = make_diverse_enemy_army(n_enemies, ecp)
                apply_as_debuff(e, debuff)
                if run_combat(a, e, rng).won:
                    wins += 1
            wrs[label] = wins / num_runs * 100

        # Steampunk
        board = build_steampunk_r14()
        wins = 0
        for i in range(num_runs):
            rng = random.Random(seed + i)
            a = materialize(board)
            e = make_diverse_enemy_army(n_enemies, ecp)
            if run_combat(a, e, rng).won:
                wins += 1
        sp_wr = wins / num_runs * 100

        boss = "★" if rnd in {4, 8, 12, 15} else " "
        print(f"  R{rnd:2d}{boss}    | {ecp:>8,d} | {wrs['변경 전']:>7.0f}% | "
              f"{wrs['변경 후']:>7.0f}% | {sp_wr:>7.0f}%")

    print()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("-n", "--runs", type=int, default=100)
    p.add_argument("--seed", type=int, default=42)
    args = p.parse_args()
    run_analysis(args.runs, args.seed)


if __name__ == "__main__":
    main()
