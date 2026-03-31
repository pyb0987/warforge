"""1D tick-based combat engine."""

from __future__ import annotations

from dataclasses import dataclass, field
import random

from .types import UnitStack


TICK_DT = 0.1          # seconds per tick
MAX_TICKS = 600        # 60 seconds
ALLY_START_X = 0.0
ENEMY_START_X = 30.0
MELEE_RANGE = 1.0      # Range 0 units attack within this distance


@dataclass
class CombatUnit:
    atk: float
    hp: float
    max_hp: float
    attack_speed: float
    range: float
    move_speed: float
    x: float
    cooldown: float = 0.0
    is_ally: bool = True

    @property
    def alive(self) -> bool:
        return self.hp > 0

    @property
    def effective_range(self) -> float:
        return max(self.range, MELEE_RANGE)


@dataclass
class CombatResult:
    won: bool
    ally_survivors: int
    enemy_survivors: int
    ticks: int
    time_seconds: float


def materialize_army(stacks_with_stats: list[tuple[UnitStack, float, float]],
                     start_x: float,
                     is_ally: bool) -> list[CombatUnit]:
    """Convert unit stacks to individual CombatUnit objects.

    stacks_with_stats: list of (stack, eff_atk, eff_hp) tuples.
    CardInstance computes eff values via 3-layer formula.
    """
    army: list[CombatUnit] = []
    for s, atk, hp in stacks_with_stats:
        for _ in range(s.count):
            army.append(CombatUnit(
                atk=atk,
                hp=hp,
                max_hp=hp,
                attack_speed=s.unit_type.attack_speed,
                range=float(s.unit_type.range),
                move_speed=float(s.unit_type.move_speed),
                x=start_x,
                is_ally=is_ally,
            ))
    return army


def run_combat(allies: list[CombatUnit], enemies: list[CombatUnit],
               rng: random.Random) -> CombatResult:
    """Run 1D tick-based combat. Returns CombatResult."""
    final_tick = 0
    for tick in range(MAX_TICKS):
        if not allies or not enemies:
            break
        final_tick = tick + 1

        # Each unit acts
        for unit in allies + enemies:
            if not unit.alive:
                continue

            targets = enemies if unit.is_ally else allies
            if not targets:
                continue

            closest = min(targets, key=lambda t: abs(t.x - unit.x))
            dist = abs(closest.x - unit.x)

            if dist <= unit.effective_range:
                # In range: attack if cooldown ready
                unit.cooldown -= TICK_DT
                if unit.cooldown <= 0:
                    dmg = max(unit.atk, 1.0)
                    closest.hp -= dmg
                    unit.cooldown = unit.attack_speed
            else:
                # Out of range: move toward closest enemy
                direction = 1.0 if closest.x > unit.x else -1.0
                unit.x += direction * unit.move_speed * TICK_DT

        # Remove dead
        allies = [u for u in allies if u.alive]
        enemies = [u for u in enemies if u.alive]

    won = len(enemies) == 0 and len(allies) > 0
    return CombatResult(
        won=won,
        ally_survivors=len(allies),
        enemy_survivors=len(enemies),
        ticks=final_tick,
        time_seconds=final_tick * TICK_DT,
    )


def make_enemy_army(count: int, atk: int, hp: int) -> list[CombatUnit]:
    """Create a homogeneous enemy army (legacy)."""
    return [
        CombatUnit(
            atk=float(atk), hp=float(hp), max_hp=float(hp),
            attack_speed=1.0, range=0.0, move_speed=2.0,
            x=ENEMY_START_X, is_ally=False,
        )
        for _ in range(count)
    ]


def make_diverse_enemy_army(count: int, target_cp: float) -> list[CombatUnit]:
    """Create a diverse enemy army using all 20 unit types from the pool.

    Units are distributed round-robin across all types.
    ATK/HP are scaled by a multiplier to match target_cp.
    AS/Range/MS use the original unit type values.
    """
    from . import units as unit_reg

    all_types = unit_reg.all_units()
    if not all_types:
        return make_enemy_army(count, 5, 50)

    # Distribute count across unit types (round-robin)
    assigned = [all_types[i % len(all_types)] for i in range(count)]

    # Base CP = sum(atk/AS * hp) for unscaled units
    base_cp = sum(ut.atk / ut.attack_speed * ut.hp for ut in assigned)
    if base_cp <= 0:
        return []

    # target_cp = mult^2 * base_cp  →  mult = sqrt(target_cp / base_cp)
    mult = (target_cp / base_cp) ** 0.5

    return [
        CombatUnit(
            atk=ut.atk * mult,
            hp=ut.hp * mult,
            max_hp=ut.hp * mult,
            attack_speed=ut.attack_speed,
            range=float(ut.range),
            move_speed=float(ut.move_speed),
            x=ENEMY_START_X,
            is_ally=False,
        )
        for ut in assigned
    ]
