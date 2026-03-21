"""Round loop: growth chain, combat, post-combat."""

from __future__ import annotations

from dataclasses import dataclass, field
import random

from .types import TriggerTiming
from .cards import CardInstance
from .chain import run_growth_chain
from .combat import (
    materialize_army, run_combat, make_diverse_enemy_army,
    CombatResult, ALLY_START_X,
)


PLAYER_HP = 30
TOTAL_ROUNDS = 15
BASE_INCOME = 5
UPGRADE_EVERY = 2       # every N rounds, apply upgrade
UPGRADE_ATK_PCT = 0.15  # ×1.15 ATK (multiplicative)
UPGRADE_HP_PCT = 0.15   # ×1.15 HP (multiplicative)


@dataclass
class RoundRecord:
    round: int
    chain_count: int
    total_units: int
    total_atk: float
    total_hp: float
    player_cp: float
    enemy_units: int
    enemy_cp: float
    combat: CombatResult | None
    player_hp: int
    gold: int


@dataclass
class GameState:
    board: list[CardInstance]
    rng: random.Random
    player_hp: int = PLAYER_HP
    gold: int = 0
    round_records: list[RoundRecord] = field(default_factory=list)


def combat_power_board(board: list[CardInstance]) -> float:
    """Compute player combat power: sum(count * DPS * HP).

    DPS = ATK / AS. This weights fast attackers higher than raw ATK × HP.
    """
    cp = 0.0
    for card in board:
        for s in card.stacks:
            dps = s.eff_atk / s.unit_type.attack_speed
            cp += s.count * dps * s.eff_hp
    return cp


def combat_power_enemy(count: int, atk: int, hp: int,
                       attack_speed: float = 1.0) -> float:
    """Compute enemy combat power with same formula."""
    return count * (atk / attack_speed) * hp


def run_game(board: list[CardInstance], rng: random.Random,
             enemy_gen,  # callable(rnd, player_units) -> (count, atk, hp)
             verbose: bool = False,
             chain_only: bool = False,
             combat_only: bool = False,
             schedule: dict | None = None,
             ) -> GameState:
    """Run a full game (R1-R15).

    schedule: optional {round: [CardInstance]} to add cards mid-game.
    """
    state = GameState(board=board, rng=rng)

    for rnd in range(1, TOTAL_ROUNDS + 1):
        if state.player_hp <= 0:
            break
        # Add scheduled cards for this round
        if schedule and rnd in schedule:
            for card in schedule[rnd]:
                pos = _find_insert_position(state.board, card)
                state.board.insert(pos, card)
                if verbose:
                    print(f"    +++ R{rnd}: {card.template.name} → "
                          f"위치 {pos} (보드 {len(state.board)}장)")
        rec = _run_round(state, rnd, enemy_gen, verbose,
                         chain_only, combat_only)
        state.round_records.append(rec)

    return state


def _run_round(state: GameState, rnd: int,
               enemy_gen,
               verbose: bool,
               chain_only: bool,
               combat_only: bool) -> RoundRecord:
    board = state.board
    rng = state.rng

    # 0. Periodic upgrade (every N rounds, ×1.15 multiplicative)
    if rnd > 1 and rnd % UPGRADE_EVERY == 0:
        for card in board:
            card.multiply_stats(UPGRADE_ATK_PCT, UPGRADE_HP_PCT)
        if verbose:
            print(f"    ⬆ R{rnd}: 전체 유닛 업그레이드 "
                  f"(×{1+UPGRADE_ATK_PCT:.2f} ATK/HP, 곱연산)")

    # 1. Growth chain (skip if combat_only)
    chain_count = 0
    gold_from_chain = 0
    if not combat_only:
        chain_count, gold_from_chain = run_growth_chain(board, rng, verbose)
    else:
        for card in board:
            card.reset_round()

    state.gold += gold_from_chain

    # Snapshot post-chain stats
    total_units = sum(c.total_units for c in board)
    total_atk = sum(c.total_atk for c in board)
    total_hp = sum(c.total_hp for c in board)
    player_cp = combat_power_board(board)

    # 2. Enemy (dynamic scaling based on player unit count)
    eu, enemy_cp = enemy_gen(rnd, total_units)

    # 3. Combat (skip if chain_only)
    combat_result: CombatResult | None = None
    if not chain_only:
        # Pre-combat: apply all temp buffs before materializing
        _apply_battle_start(board)
        _apply_combat_attack_buffs(board)

        # Gather ally units (exclude non-combatant cards)
        ally_stacks = []
        for card in board:
            if card.template.trigger.is_non_combatant:
                continue
            ally_stacks.extend(card.stacks)
        allies = materialize_army(ally_stacks, ALLY_START_X, is_ally=True)

        enemies = make_diverse_enemy_army(eu, enemy_cp)
        combat_result = run_combat(allies, enemies, rng)

        # Clear temporary combat buffs
        for card in board:
            card.clear_temp_buffs()

        # Post-combat
        if not combat_result.won:
            dmg = max(1, combat_result.enemy_survivors)
            state.player_hp -= dmg
            _apply_post_combat_defeat(board, state, rng)

    # 4. Income
    state.gold += BASE_INCOME

    rec = RoundRecord(
        round=rnd,
        chain_count=chain_count,
        total_units=total_units,
        total_atk=total_atk,
        total_hp=total_hp,
        player_cp=player_cp,
        enemy_units=eu,
        enemy_cp=enemy_cp,
        combat=combat_result,
        player_hp=state.player_hp,
        gold=state.gold,
    )

    if verbose:
        _print_round(rec)

    return rec


# ── Card placement logic ─────────────────────────────────────────


def _find_insert_position(board: list[CardInstance],
                          card: CardInstance) -> int:
    """Determine where to insert a new card on the board.

    ROUND_START cards go left (chain starters).
    ON_EVENT cards go right (chain responders).
    BATTLE/POST_COMBAT cards go rightmost (non-chain).
    """
    timing = card.template.trigger.timing
    if timing == TriggerTiming.ROUND_START:
        # Insert before the first non-ROUND_START card
        for i, c in enumerate(board):
            if c.template.trigger.timing != TriggerTiming.ROUND_START:
                return i
        return len(board)
    elif timing == TriggerTiming.ON_EVENT:
        # Insert after ROUND_START cards, before BATTLE/POST cards
        last_chain = 0
        for i, c in enumerate(board):
            t = c.template.trigger.timing
            if t in (TriggerTiming.ROUND_START, TriggerTiming.ON_EVENT):
                last_chain = i + 1
        return last_chain
    else:
        # BATTLE_START, POST_COMBAT, ON_COMBAT → rightmost
        return len(board)


# ── Pre/post combat helpers ──────────────────────────────────────


def _apply_battle_start(board: list[CardInstance]) -> None:
    """Apply BATTLE_START effects as temporary buffs."""
    for card in board:
        t = card.template.trigger
        if t.timing != TriggerTiming.BATTLE_START:
            continue
        for eff in card.template.effects:
            if eff.action == "buff_pct":
                card.temp_buff(eff.unit_tag_filter, eff.buff_atk_pct)


def _apply_combat_attack_buffs(board: list[CardInstance]) -> None:
    """Simplify ON_COMBAT_ATTACK as pre-combat temp buff."""
    for card in board:
        t = card.template.trigger
        if t.timing != TriggerTiming.ON_COMBAT_ATTACK:
            continue
        for eff in card.template.effects:
            if eff.action == "buff_pct":
                card.temp_buff(eff.unit_tag_filter, eff.buff_atk_pct)


def _apply_post_combat_defeat(board: list[CardInstance],
                               state: GameState,
                               rng: random.Random) -> None:
    """Apply POST_COMBAT_DEFEAT effects."""
    for card in board:
        t = card.template.trigger
        if t.timing != TriggerTiming.POST_COMBAT_DEFEAT:
            continue
        for eff in card.template.effects:
            if eff.action == "grant_gold":
                state.gold += eff.gold_amount
            elif eff.action == "spawn":
                for _ in range(eff.spawn_count):
                    card.spawn_random(rng)


# ── Output ───────────────────────────────────────────────────────


def _print_round(rec: RoundRecord) -> None:
    result = "—"
    if rec.combat:
        result = "WIN" if rec.combat.won else "LOSE"
    ratio = rec.player_cp / rec.enemy_cp if rec.enemy_cp > 0 else 999
    print(f"  R{rec.round:2d} | chain {rec.chain_count:3d} | "
          f"{rec.total_units:3d}u vs {rec.enemy_units:3d}u | "
          f"CP {rec.player_cp:7.0f} vs {rec.enemy_cp:7.0f} ({ratio:4.1f}×) | "
          f"{result:4s} | hp {rec.player_hp:3d}")
