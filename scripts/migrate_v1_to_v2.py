#!/usr/bin/env python3
"""
migrate_v1_to_v2.py — Mechanically transform data/cards/*.yaml to data/cards_v2/*.yaml.

V1 schema (flat effects, card-level timing):
    card_id:
      name, tier, theme, timing, listen, require_tenure, require_other, is_threshold
      stars:
        1:
          max_act, effects: [{action: params}, ...], conditional, r_conditional, post_threshold

V2 schema (timing blocks, actions as dict keys):
    card_id:
      name, tier, theme, star_scalable_actions
      stars:
        1:
          effects:
            - trigger_timing: RS
              max_act: -1
              listen: {l1, l2}             # (optional, inherited from card)
              require_tenure: N            # (optional, inherited from card)
              require_other: bool          # (optional, inherited from card)
              is_threshold: bool           # (optional, inherited from card)
              conditional: [...]           # (optional, moved from star)
              r_conditional: [...]         # (optional, moved from star)
              post_threshold: [...]        # (optional, moved from star)
              <action1>: <params1>         # actions (dict key per action; list value if duplicate)
              <action2>: <params2>

Phase 1 assumption: every card has exactly one timing block per star (v1 was single-timing).
Phase 2 will introduce multi-block cards (sp_warmachine).
"""

from __future__ import annotations

import sys
from collections import OrderedDict
from pathlib import Path
from typing import Any

import yaml

ROOT = Path(__file__).resolve().parent.parent
CARDS_V1_DIR = ROOT / "data" / "cards"
CARDS_V2_DIR = ROOT / "data" / "cards_v2"

THEME_FILES = ["druid", "military", "neutral", "predator", "steampunk"]

# Fields inherited from card top-level into every timing block
INHERIT_FIELDS = ("listen", "require_tenure", "require_other", "is_threshold")
# Fields moved from star level into the timing block
STAR_TO_BLOCK_FIELDS = ("conditional", "r_conditional", "post_threshold")
# Card-level fields dropped after migration
CARD_FIELDS_TO_REMOVE = ("timing",) + INHERIT_FIELDS
# Star-level fields moved/dropped
STAR_FIELDS_TO_REMOVE = ("timing", "max_act", "effects") + STAR_TO_BLOCK_FIELDS


def effects_to_actions(effects: list) -> "OrderedDict[str, Any]":
    """Convert v1 flat effects list to v2 actions dict.

    Each v1 effect = {action_name: params}. If an action appears twice in one
    star, its value becomes a list of params dicts.
    """
    result: "OrderedDict[str, Any]" = OrderedDict()
    for eff in effects:
        if not isinstance(eff, dict) or len(eff) != 1:
            raise ValueError(f"Unexpected effect shape (expected single-key dict): {eff!r}")
        action = next(iter(eff))
        params = eff[action]
        if action in result:
            existing = result[action]
            if isinstance(existing, list):
                existing.append(params)
            else:
                result[action] = [existing, params]
        else:
            result[action] = params
    return result


def build_block(card: dict, star: dict) -> "OrderedDict[str, Any]":
    """Build a single v2 timing block from v1 card + star data."""
    block: "OrderedDict[str, Any]" = OrderedDict()

    # Required fields first
    block["trigger_timing"] = star.get("timing", card["timing"])
    block["max_act"] = star["max_act"]

    # Inherited from card top-level
    for f in INHERIT_FIELDS:
        if f in card:
            block[f] = card[f]

    # Moved from star level
    for f in STAR_TO_BLOCK_FIELDS:
        if f in star:
            block[f] = star[f]

    # Actions (from v1 effects list). Goes last so metadata reads at the top.
    actions = effects_to_actions(star.get("effects", []))
    for action, params in actions.items():
        if action in block:
            raise ValueError(
                f"action name {action!r} collides with a reserved block key"
            )
        block[action] = params

    return block


def migrate_card(card_v1: dict) -> "OrderedDict[str, Any]":
    """Migrate a single v1 card dict to v2 layout, preserving a natural key order."""
    card_v2: "OrderedDict[str, Any]" = OrderedDict()

    # Top-level identity fields kept in a stable order for readability
    for key in ("name", "tier", "theme", "comp", "tags", "impl", "star_scalable_actions"):
        if key in card_v1:
            card_v2[key] = card_v1[key]

    # Rebuild stars with blocks
    stars_v1 = card_v1.get("stars", {})
    stars_v2: "OrderedDict[int, Any]" = OrderedDict()
    for star_n in sorted(stars_v1.keys()):
        star = stars_v1[star_n]
        block = build_block(card_v1, star)
        stars_v2[star_n] = OrderedDict([("effects", [block])])
    card_v2["stars"] = stars_v2

    # Validate: no unknown keys should remain in v1 that we haven't handled
    handled_card_keys = set(card_v2.keys()) | set(CARD_FIELDS_TO_REMOVE)
    for k in card_v1.keys():
        if k not in handled_card_keys and k != "stars":
            raise ValueError(f"Unhandled card-level key in v1: {k!r}")

    return card_v2


# ═══════════════════════════════════════════════════════════════════
# YAML dumper with OrderedDict preservation and readable flow style
# ═══════════════════════════════════════════════════════════════════

class V2Dumper(yaml.SafeDumper):
    # Disable YAML anchors/aliases — we want a flat, human-readable output even
    # when structurally identical dicts (e.g., shared `listen`) recur.
    def ignore_aliases(self, data: Any) -> bool:  # type: ignore[override]
        return True


def _represent_ordered_dict(dumper: yaml.Dumper, data: OrderedDict) -> Any:
    return dumper.represent_mapping("tag:yaml.org,2002:map", data.items())


V2Dumper.add_representer(OrderedDict, _represent_ordered_dict)


def migrate_file(src: Path, dst: Path) -> int:
    """Migrate one theme YAML file. Returns card count."""
    with open(src) as f:
        data = yaml.safe_load(f)

    if not data or "cards" not in data:
        raise ValueError(f"{src}: missing top-level 'cards' key")

    cards_v1 = data["cards"]
    cards_v2: "OrderedDict[str, Any]" = OrderedDict()
    for card_id, card in cards_v1.items():
        if "stars" in card:
            card["stars"] = {int(k): v for k, v in card["stars"].items()}
        try:
            cards_v2[card_id] = migrate_card(card)
        except Exception as e:
            raise RuntimeError(f"{src.name}:{card_id}: {e}") from e

    out = OrderedDict([("cards", cards_v2)])
    dst.parent.mkdir(parents=True, exist_ok=True)
    with open(dst, "w") as f:
        yaml.dump(
            out,
            f,
            Dumper=V2Dumper,
            sort_keys=False,
            allow_unicode=True,
            default_flow_style=False,
            indent=2,
            width=120,
        )
    return len(cards_v2)


def main() -> None:
    total = 0
    for theme in THEME_FILES:
        src = CARDS_V1_DIR / f"{theme}.yaml"
        dst = CARDS_V2_DIR / f"{theme}.yaml"
        if not src.exists():
            print(f"SKIP {src} (not found)")
            continue
        n = migrate_file(src, dst)
        total += n
        print(f"  {theme}: {n} cards → {dst}")
    print(f"\nMigrated {total} cards to {CARDS_V2_DIR}")


if __name__ == "__main__":
    main()
