"""CardInstance: a card on the player's board."""

from __future__ import annotations

import random  # noqa: F401 — used in type hints

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

    @property
    def total_units(self) -> int:
        return sum(s.count for s in self.stacks)

    @property
    def total_atk(self) -> float:
        return sum(s.count * s.eff_atk for s in self.stacks)

    @property
    def total_hp(self) -> float:
        return sum(s.count * s.eff_hp for s in self.stacks)

    def spawn_random(self, rng: random.Random) -> bool:
        """Add 1 unit (random type weighted by current count).

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
        """Enhance matching units by % of base stats.

        tag_filter: None (all), "태엽" (single), "태엽,전기" (any match).
        Returns number of stacks enhanced.
        """
        count = 0
        for s in self.stacks:
            if tag_filter is not None:
                tags = tag_filter.split(",") if "," in tag_filter else [tag_filter]
                if not any(t in s.unit_type.tags for t in tags):
                    continue
            if atk_pct:
                s.bonus_atk += s.unit_type.atk * atk_pct
            if hp_pct:
                s.bonus_hp += s.unit_type.hp * hp_pct
            count += 1
        return count

    def multiply_stats(self, atk_pct: float, hp_pct: float) -> None:
        """Multiplicative upgrade: eff_atk *= (1 + pct), eff_hp *= (1 + pct)."""
        for s in self.stacks:
            s.bonus_atk += s.eff_atk * atk_pct
            s.bonus_hp += s.eff_hp * hp_pct

    def temp_buff(self, tag_filter: str | None, atk_pct: float) -> None:
        """Apply temporary combat buff (cleared after combat)."""
        for s in self.stacks:
            if tag_filter is not None and tag_filter not in s.unit_type.tags:
                continue
            s.temp_atk += s.unit_type.atk * atk_pct

    def clear_temp_buffs(self) -> None:
        for s in self.stacks:
            s.temp_atk = 0.0

    def evolve(self, new_template: CardTemplate) -> None:
        """Evolve to ★2/★3. Keeps units and bonuses."""
        self.template = new_template

    def reset_round(self) -> None:
        self.activations_used = 0
        self.tenure += 1

    def __repr__(self) -> str:
        return (f"{self.template.name}"
                f"({self.total_units}u A{self.total_atk:.0f} H{self.total_hp:.0f})")
