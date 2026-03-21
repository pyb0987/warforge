"""Core types: enums, dataclasses, event model."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum, auto


# ── Layer 1: Result categories (theme-independent) ──────────────


class Layer1(Enum):
    UNIT_ADDED = auto()
    ENHANCED = auto()


# ── Layer 2: Theme keyword events ────────────────────────────────


class Layer2(Enum):
    MANUFACTURE = auto()  # 제조 (steampunk)
    UPGRADE = auto()      # 개량 (steampunk)


# ── Trigger timing ───────────────────────────────────────────────


class TriggerTiming(Enum):
    ROUND_START = auto()
    ON_EVENT = auto()
    BATTLE_START = auto()
    ON_COMBAT_ATTACK = auto()
    POST_COMBAT_DEFEAT = auto()


# ── Unit type (shared DB entry) ──────────────────────────────────


@dataclass(frozen=True)
class UnitType:
    id: str
    name: str
    atk: int
    hp: int
    attack_speed: float  # seconds between attacks
    range: int
    move_speed: int
    tags: frozenset[str]


# ── Unit stack (group of same-type units in a card) ──────────────


@dataclass
class UnitStack:
    unit_type: UnitType
    count: int
    bonus_atk: float = 0.0
    bonus_hp: float = 0.0
    temp_atk: float = 0.0  # cleared after each combat

    @property
    def eff_atk(self) -> float:
        return self.unit_type.atk + self.bonus_atk + self.temp_atk

    @property
    def eff_hp(self) -> float:
        return self.unit_type.hp + self.bonus_hp


# ── Trigger / Effect specs (declarative card definition) ─────────


@dataclass(frozen=True)
class TriggerSpec:
    timing: TriggerTiming
    listen_layer1: Layer1 | None = None
    listen_layer2: Layer2 | None = None
    require_other_card: bool = False
    require_tenure: int = 0
    is_threshold: bool = False
    is_non_combatant: bool = False


@dataclass(frozen=True)
class EffectSpec:
    action: str   # spawn | enhance_pct | buff_pct | grant_gold | retrigger | shield_pct
    target: str   # self | right_adj | both_adj | all_allies | event_target
    spawn_count: int = 0
    enhance_atk_pct: float = 0.0
    enhance_hp_pct: float = 0.0
    buff_atk_pct: float = 0.0
    gold_amount: int = 0
    shield_hp_pct: float = 0.0
    unit_tag_filter: str | None = None
    output_layer1: Layer1 | None = None
    output_layer2: Layer2 | None = None


# ── Card template (immutable shared definition) ──────────────────


@dataclass(frozen=True)
class CardTemplate:
    id: str
    name: str
    tier: int
    theme: str  # "steampunk" | "neutral"
    composition: tuple[tuple[str, int], ...]  # (unit_type_id, count)
    trigger: TriggerSpec
    effects: tuple[EffectSpec, ...]
    max_activations: int | None = None  # None = unlimited
    card_tags: frozenset[str] = frozenset()


# ── Chain event (BFS queue item) ─────────────────────────────────


@dataclass
class ChainEvent:
    layer1: Layer1
    layer2: Layer2 | None
    source_card_idx: int
    target_card_idx: int
