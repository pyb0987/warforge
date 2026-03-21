#!/usr/bin/env python3
"""Chain Army minimum simulator.

Usage:
    python3 sim/simulate.py -v                  # verbose 1 run
    python3 sim/simulate.py --chain-only -v     # chain only
    python3 sim/simulate.py --combat-only -v    # combat only
    python3 sim/simulate.py -n 50 --seed 42     # batch
    python3 sim/simulate.py -p factory -v       # different preset
"""

from __future__ import annotations

import argparse
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from data.unit_pool import register_all as register_units
from data.card_pool import register_all as register_cards, get_template, get_s2_id
from data.enemies import generate_enemy, BOSS_ROUNDS
from engine.cards import CardInstance
from engine.game import run_game, GameState, TOTAL_ROUNDS

# ── Preset boards ────────────────────────────────────────────────

PRESETS = {
    "basic": {
        "name": "스팀펑크 기본",
        "cards": [
            "sp_assembly",   # 증기 조립소
            "sp_workshop",   # 태엽 공방
            "sp_line",       # 조립 라인
            "ne_wanderers",  # 떠돌이 무리
            "ne_wildforce",  # 야생의 힘
            "sp_warmachine", # 전쟁 기계
            "ne_merchant",   # 방랑 상인
        ],
    },
    "overload": {
        "name": "과부하 코일",
        "cards": [
            "sp_overload",   # 과부하 코일
            "sp_assembly",   # 증기 조립소
            "sp_workshop",   # 태엽 공방
            "sp_line",       # 조립 라인
            "sp_boiler",     # 시한 보일러
            "ne_wanderers",  # 떠돌이 무리
            "ne_wildforce",  # 야생의 힘
        ],
    },
    "factory": {
        "name": "제국 공장",
        "cards": [
            "sp_factory",    # 제국 공장
            "sp_assembly",   # 증기 조립소
            "sp_line",       # 조립 라인
            "sp_workshop",   # 태엽 공방
            "sp_forge",      # 증기 대장간
            "ne_wanderers",  # 떠돌이 무리
            "sp_warmachine", # 전쟁 기계
        ],
    },
    "endurance": {
        "name": "인내형",
        "cards": [
            "sp_assembly",   # 증기 조립소
            "sp_workshop",   # 태엽 공방
            "sp_boiler",     # 시한 보일러
            "sp_line",       # 조립 라인
            "ne_ruins",      # 고대의 잔해
            "ne_wanderers",  # 떠돌이 무리
            "ne_awakening",  # 고대의 각성
        ],
    },

    # ── Progressive presets (realistic board growth) ──────────────

    "strong": {
        "name": "점진적 (좋은 빌드)",
        # R1: 5g → T1×2 (4g). 좋은 체인 시작점.
        # R2: 7g → +T1 (2g). 체인 반응 카드 추가.
        # R3: 8g → +T2 (3g). 전투 보강.
        # R4: 8g → +T3 (4g). 체인 증폭. 보스 전 5장.
        # R6: 9g → +T2 (3g). 전투 보강.
        # R8: 9g → +T4 (5g). 전투력 강화. 7장 완성.
        "schedule": {
            1: ["sp_assembly", "ne_wanderers"],        # 조립소+떠돌이 (체인 시작)
            2: ["sp_workshop"],                         # 공방 (제조→개량 연결)
            3: ["ne_wildforce"],                        # 야생의 힘 (전투 버프)
            4: ["sp_line"],                             # 조립 라인 (체인 증폭)
            6: ["ne_ruins"],                            # 고대의 잔해 (경제+유닛)
            8: ["sp_warmachine"],                       # 전쟁 기계 (전투력)
        },
    },
    "weak": {
        "name": "점진적 (약한 빌드)",
        "schedule": {
            1: ["ne_merchant", "ne_wanderers"],
            3: ["sp_assembly"],
            4: ["ne_wildforce"],
            5: ["sp_workshop"],
            7: ["ne_ruins"],
            9: ["ne_chimera_cry"],
        },
    },

    # ── ★2 progressive presets ───────────────────────────────────

    "strong_s2": {
        "name": "점진적 ★2 (좋은 빌드)",
        "schedule": {
            1: ["sp_assembly", "ne_wanderers"],
            2: ["sp_workshop"],
            3: ["ne_wildforce"],
            4: ["sp_line"],
            6: ["ne_ruins"],
            8: ["sp_warmachine"],
        },
        # ★2 진화: R6 조립소, R7 공방, R8 조립라인 (핵심 체인 카드 우선)
        "evolve": {
            6: ["sp_assembly"],
            7: ["sp_workshop"],
            8: ["sp_line"],
        },
    },
    "weak_s2": {
        "name": "점진적 ★2 (약한 빌드)",
        "schedule": {
            1: ["ne_merchant", "ne_wanderers"],
            3: ["sp_assembly"],
            4: ["ne_wildforce"],
            5: ["sp_workshop"],
            7: ["ne_ruins"],
            9: ["ne_chimera_cry"],
        },
        # ★2 진화: R8 조립소, R10 떠돌이 (늦고 비핵심)
        "evolve": {
            8: ["sp_assembly"],
            10: ["ne_wanderers"],
        },
    },
}


def make_board_and_schedule(preset_id: str):
    """Returns (initial_board, card_schedule, evolve_schedule)."""
    preset = PRESETS[preset_id]

    # Card schedule
    card_sched = None
    if "schedule" in preset:
        sched = preset["schedule"]
        initial = [CardInstance(get_template(cid)) for cid in sched.get(1, [])]
        card_sched = {}
        for rnd, cids in sched.items():
            if rnd == 1:
                continue
            card_sched[rnd] = [CardInstance(get_template(cid)) for cid in cids]
    else:
        initial = [CardInstance(get_template(cid)) for cid in preset["cards"]]

    # Evolve schedule: {round: [(card_id, new_template)]}
    evolve_sched = None
    if "evolve" in preset:
        evolve_sched = {}
        for rnd, card_ids in preset["evolve"].items():
            evolve_sched[rnd] = [
                (cid, get_template(get_s2_id(cid))) for cid in card_ids
            ]

    return initial, card_sched, evolve_sched


# ── Batch runner ─────────────────────────────────────────────────


def run_batch(preset_id: str, num_runs: int, base_seed: int | None,
              verbose: bool, chain_only: bool, combat_only: bool):
    preset = PRESETS[preset_id]
    all_states: list[GameState] = []

    for i in range(num_runs):
        seed = (base_seed + i) if base_seed is not None else None
        rng = random.Random(seed)
        board, card_sched, evolve_sched = make_board_and_schedule(preset_id)

        show = verbose and (i == num_runs - 1)
        if show:
            print(f"\n{'=' * 70}")
            print(f"  Preset: \"{preset['name']}\"")
            if "schedule" in preset:
                for rnd in sorted(list(preset["schedule"].keys())):
                    cards = preset["schedule"].get(rnd, [])
                    names = ", ".join(get_template(c).name for c in cards)
                    evos = preset.get("evolve", {}).get(rnd, [])
                    evo_str = " | ★2: " + ", ".join(evos) if evos else ""
                    print(f"    R{rnd}: +[{names}]{evo_str}")
            else:
                names = " → ".join(c.template.name for c in board)
                print(f"  Board:  [{names}]")
            print(f"{'=' * 70}")

        state = run_game(board, rng, generate_enemy, show,
                         chain_only, combat_only,
                         schedule=card_sched,
                         evolve_schedule=evolve_sched)
        all_states.append(state)

    print_summary(preset, all_states, num_runs, chain_only, combat_only)


# ── Summary report ───────────────────────────────────────────────


def print_summary(preset: dict, all_states: list[GameState],
                  num_runs: int, chain_only: bool, combat_only: bool):
    print(f"\n{'=' * 78}")
    mode = ""
    if chain_only:
        mode = " [chain-only]"
    elif combat_only:
        mode = " [combat-only]"
    print(f"  Report: {num_runs} runs, \"{preset['name']}\"{mode}")
    print(f"{'=' * 78}")

    # Aggregate per-round stats
    from collections import defaultdict
    stats: dict[int, dict] = defaultdict(lambda: {
        "n": 0, "wins": 0, "chains": [], "units": [],
        "pcp": [], "ecp": [], "player_hp": [],
    })

    clears = 0
    for state in all_states:
        for rec in state.round_records:
            s = stats[rec.round]
            s["n"] += 1
            if rec.combat and rec.combat.won:
                s["wins"] += 1
            s["chains"].append(rec.chain_count)
            s["units"].append(rec.total_units)
            s["pcp"].append(rec.player_cp)
            s["ecp"].append(rec.enemy_cp)
            s["player_hp"].append(rec.player_hp)
        if state.round_records:
            last = state.round_records[-1]
            if last.round == TOTAL_ROUNDS and last.player_hp > 0:
                clears += 1

    avg = lambda lst: sum(lst) / len(lst) if lst else 0

    hdr = (f"  R  | {'Win%':>5s} | {'Chain':>5s} | {'Units':>5s} | "
           f"{'PlayerCP':>9s} | {'EnemyCP':>9s} | {'Ratio':>6s} | {'HP':>4s}")
    sep = "  " + "-" * (len(hdr) - 2)
    print(f"\n{hdr}")
    print(sep)

    for rnd in range(1, TOTAL_ROUNDS + 1):
        s = stats[rnd]
        if s["n"] == 0:
            continue
        wr = s["wins"] / s["n"] * 100 if not chain_only else 0
        boss = "★" if rnd in BOSS_ROUNDS else " "
        pcp = avg(s["pcp"])
        ecp = avg(s["ecp"])
        ratio = pcp / ecp if ecp > 0 else 999
        wr_str = f"{wr:4.0f}%" if not chain_only else "  —  "
        print(f"  {rnd:2d}{boss}| {wr_str} | {avg(s['chains']):5.1f} | "
              f"{avg(s['units']):5.0f} | "
              f"{pcp:9.0f} | {ecp:9.0f} | {ratio:5.1f}× | "
              f"{avg(s['player_hp']):4.0f}")

    print(sep)

    if not chain_only:
        clear_rate = clears / num_runs * 100
        print(f"\n  Clear rate: {clear_rate:.1f}% ({clears}/{num_runs})")

        # Balance alerts
        alerts = []
        for rnd in range(1, TOTAL_ROUNDS + 1):
            s = stats[rnd]
            if s["n"] == 0:
                continue
            wr = s["wins"] / s["n"] * 100
            if rnd <= 3 and wr < 80:
                alerts.append(f"R{rnd} win {wr:.0f}% < 80% (early)")
            if rnd in BOSS_ROUNDS and wr > 80:
                alerts.append(f"R{rnd}★ win {wr:.0f}% > 80% (boss too easy)")
            if rnd in BOSS_ROUNDS and wr < 10:
                alerts.append(f"R{rnd}★ win {wr:.0f}% < 10% (boss too hard)")

        if alerts:
            print(f"\n  Alerts:")
            for a in alerts:
                print(f"    ! {a}")
        else:
            print(f"\n  No balance alerts.")

    print()


# ── Main ─────────────────────────────────────────────────────────


def main():
    register_units()
    register_cards()

    p = argparse.ArgumentParser(description="Chain Army simulator")
    p.add_argument("-p", "--preset", default="basic",
                   choices=list(PRESETS.keys()),
                   help="Board preset")
    p.add_argument("-n", "--runs", type=int, default=1,
                   help="Number of runs (default 1)")
    p.add_argument("-v", "--verbose", action="store_true",
                   help="Show detailed round output")
    p.add_argument("--seed", type=int, default=None,
                   help="Random seed for reproducibility")
    p.add_argument("--chain-only", action="store_true",
                   help="Skip combat, show chain stats only")
    p.add_argument("--combat-only", action="store_true",
                   help="Skip growth chain, use base stats")
    args = p.parse_args()

    run_batch(args.preset, args.runs, args.seed,
              args.verbose, args.chain_only, args.combat_only)


if __name__ == "__main__":
    main()
