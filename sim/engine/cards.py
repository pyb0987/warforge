"""CardInstance: a card on the player's board.

Stat formula (3-layer multiplicative):
  ATK = base × (1 + growth%) × upgrade_mult + temp_atk
        ─────   ── Layer 1 ──   ── Layer 2 ──   ─ combat ─
        유닛 DB   성장 누적       업그레이드       전투 버프

Layer 1 (growth): card-level, additive within layer. All units benefit equally.
Layer 2 (upgrade): per-unit multiplicative (simulated as periodic ×1.15).
Layer 1 × Layer 2 = multiplicative between layers.
"""

from __future__ import annotations

import random  # noqa: F401

from .types import CardTemplate, UnitStack
from . import units

UNIT_CAP_PER_CARD = 60


class CardInstance:
    def __init__(self, template: CardTemplate):
        self.template = template
        self.stacks: list[UnitStack] = [
            UnitStack(units.get(uid), count)
            for uid, count in template.composition
        ]
        self.activations_used: int = 0
        self.tenure: int = 0
        self.threshold_fired: bool = False
        # Layer 1: card-level growth modifier (카드 귀속 누적)
        self.growth_atk_pct: float = 0.0
        self.growth_hp_pct: float = 0.0
        self.tag_growth_atk: dict[str, float] = {}  # tag -> atk%
        self.tag_growth_hp: dict[str, float] = {}   # tag -> hp%
        # Layer 1 bonus HP from shields (1회성, base %)
        self.shield_hp_pct: float = 0.0
        # Druid 🌳 sapling tracking
        self.saplings: int = 0
        self._deep_mult_active: bool = False  # 뿌리깊은 자 ×1.5 applied

    def _growth_atk_for(self, stack: UnitStack) -> float:
        """Total Layer 1 growth % for a unit stack's ATK."""
        pct = self.growth_atk_pct
        for tag, apct in self.tag_growth_atk.items():
            if tag in stack.unit_type.tags:
                pct += apct
        return pct

    def _growth_hp_for(self, stack: UnitStack) -> float:
        """Total Layer 1 growth % for a unit stack's HP."""
        pct = self.growth_hp_pct
        for tag, hpct in self.tag_growth_hp.items():
            if tag in stack.unit_type.tags:
                pct += hpct
        return pct

    def eff_atk_for(self, stack: UnitStack) -> float:
        """Effective ATK: base × (1+growth%) × upgrade_mult × temp_mult + temp."""
        base = stack.unit_type.atk
        layer1 = 1.0 + self._growth_atk_for(stack)
        layer2 = stack.upgrade_atk_mult
        return (base * layer1 * layer2) * stack.temp_atk_mult + stack.temp_atk

    def eff_hp_for(self, stack: UnitStack) -> float:
        """Effective HP: base × (1+growth%) × upgrade_mult + shield."""
        base = stack.unit_type.hp
        layer1 = 1.0 + self._growth_hp_for(stack)
        layer2 = stack.upgrade_hp_mult
        shield = base * self.shield_hp_pct
        return base * layer1 * layer2 + shield

    @property
    def total_units(self) -> int:
        return sum(s.count for s in self.stacks)

    @property
    def total_atk(self) -> float:
        return sum(s.count * self.eff_atk_for(s) for s in self.stacks)

    @property
    def total_hp(self) -> float:
        return sum(s.count * self.eff_hp_for(s) for s in self.stacks)

    def spawn_random(self, rng: random.Random) -> bool:
        """Add 1 unit (random type weighted by current count).

        New units automatically benefit from card's growth modifier.
        Returns False if card is at unit cap.
        """
        if not self.stacks or self.total_units >= UNIT_CAP_PER_CARD:
            return False
        weights = [max(s.count, 1) for s in self.stacks]
        chosen = rng.choices(self.stacks, weights=weights, k=1)[0]
        chosen.count += 1
        return True

    def enhance(self, tag_filter: str | None,
                atk_pct: float, hp_pct: float) -> int:
        """Enhance card's growth modifier (Layer 1, card-level).

        tag_filter: None → all units, "태엽" → tag-specific, "태엽,전기" → any match.
        Returns number of matching stacks (for event emission check).
        """
        if tag_filter is None:
            # Card-wide growth
            if atk_pct:
                self.growth_atk_pct += atk_pct
            if hp_pct:
                self.growth_hp_pct += hp_pct
            return len(self.stacks)
        else:
            # Tag-specific growth
            tags = tag_filter.split(",") if "," in tag_filter else [tag_filter]
            count = 0
            for s in self.stacks:
                if any(t in s.unit_type.tags for t in tags):
                    count += 1
            if count > 0:
                for tag in tags:
                    if atk_pct:
                        self.tag_growth_atk[tag] = self.tag_growth_atk.get(tag, 0.0) + atk_pct
                    if hp_pct:
                        self.tag_growth_hp[tag] = self.tag_growth_hp.get(tag, 0.0) + hp_pct
            return count

    def multiply_stats(self, atk_pct: float, hp_pct: float) -> None:
        """Multiplicative upgrade (Layer 2): upgrade_mult *= (1 + pct)."""
        for s in self.stacks:
            s.upgrade_atk_mult *= (1.0 + atk_pct)
            s.upgrade_hp_mult *= (1.0 + hp_pct)

    def temp_buff(self, tag_filter: str | None, atk_pct: float) -> None:
        """Apply temporary combat buff (cleared after combat)."""
        for s in self.stacks:
            if tag_filter is not None and tag_filter not in s.unit_type.tags:
                continue
            s.temp_atk += s.unit_type.atk * atk_pct

    def clear_temp_buffs(self) -> None:
        for s in self.stacks:
            s.temp_atk = 0.0
            s.temp_atk_mult = 1.0

    def temp_mult_buff(self, atk_mult: float) -> None:
        """Apply temporary multiplicative combat buff."""
        for s in self.stacks:
            s.temp_atk_mult *= atk_mult

    def breed_strongest(self) -> bool:
        """Add 1 copy of the strongest unit (by CP) in this card."""
        if not self.stacks or self.total_units >= UNIT_CAP_PER_CARD:
            return False
        best = max(self.stacks, key=lambda s: (
            s.unit_type.atk / s.unit_type.attack_speed * s.unit_type.hp))
        best.count += 1
        return True

    def evolve(self, new_template: CardTemplate) -> None:
        """Evolve to ★2/★3. Keeps units, growth, and upgrade multipliers."""
        self.template = new_template

    def reset_round(self) -> None:
        self.activations_used = 0
        self.tenure += 1

    def __repr__(self) -> str:
        growth = self.growth_atk_pct
        return (f"{self.template.name}"
                f"({self.total_units}u A{self.total_atk:.0f} H{self.total_hp:.0f}"
                f" g+{growth:.0%})")
