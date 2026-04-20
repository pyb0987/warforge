#!/usr/bin/env python3
"""
codegen_v2.py — Phase 1 bridge: read v2 YAMLs, revert to v1 layout, and call
existing codegen_card_db logic. Output goes to /tmp so we can byte-diff against
the live card_db.gd without touching it.

When the diff is clean for 55 cards and GUT remains green, Phase 2 will:
  - extend this codegen to emit the timing-block structure directly in card_db.gd
  - drop the v2→v1 revert path
  - promote `data/cards_v2/` over `data/cards/`
"""

from __future__ import annotations

import sys
from collections import OrderedDict
from pathlib import Path
from typing import Any

import yaml

# Reuse the v1 codegen module wholesale.
sys.path.insert(0, str(Path(__file__).resolve().parent))
import codegen_card_db as v1cg  # noqa: E402
from card_desc_gen import generate_all_descs  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
CARDS_V2_DIR = ROOT / "data" / "cards_v2"
OUT_TMP_DB = Path("/tmp/card_db_v2.gd")
OUT_TMP_DESCS = Path("/tmp/card_descs_v2.gd")

# Keys that describe the timing block itself (metadata). Every other key inside
# the block is an action name.
BLOCK_META_KEYS = frozenset({
    "trigger_timing",
    "max_act",
    "listen",
    "require_tenure",
    "require_other",
    "is_threshold",
    "conditional",
    "r_conditional",
    "post_threshold",
})

# Fields that, in v2, live inside each timing block but belong at the card top
# level in v1 (inherited, card-global state).
CARD_LEVEL_INHERITED = ("listen", "require_tenure", "require_other", "is_threshold")


def _block_to_effects(block: dict) -> list[dict]:
    """Extract action entries from a v2 block into the v1 flat effects list.

    Iterates in dict-insertion order (Python 3.7+ guarantee), so the resulting
    effects list matches the order actions were declared in YAML.
    """
    effects: list[dict] = []
    for key, value in block.items():
        if key in BLOCK_META_KEYS:
            continue
        # Duplicate action → value is a list of params dicts. Expand.
        if isinstance(value, list) and all(isinstance(v, dict) for v in value):
            for params in value:
                effects.append({key: params})
        else:
            effects.append({key: value})
    return effects


def v2_to_v1_card(card_v2: dict) -> dict:
    """Revert a v2 card dict (timing blocks) to the v1 layout.

    Phase 1 assumption: every star has exactly one block. The block's
    `trigger_timing` of ★1 is promoted to card-level `timing`; other stars
    override only if their block timing differs.
    """
    stars_v2 = card_v2["stars"]

    # Phase 1 assumption enforcement: exactly one block per star. Phase 2 will
    # relax this; until then, any second block is a silent-drop landmine.
    for star_n, star_data in stars_v2.items():
        blocks = star_data.get("effects", [])
        if len(blocks) != 1:
            raise ValueError(
                f"★{star_n}: Phase 1 supports exactly one timing block per "
                f"star, found {len(blocks)}. Phase 2 will extend this — until "
                f"then, multi-block cards cannot round-trip to v1."
            )

    # Resolve card-level timing from the ★1 block.
    star1_block = stars_v2[1]["effects"][0]
    card_timing = star1_block["trigger_timing"]

    # Inherited fields (listen, require_tenure, etc.) must be identical across
    # all stars' blocks, because v1 carries them only at card top-level. Any
    # per-star drift is a silent-drop landmine during revert.
    inherited: dict[str, Any] = {}
    for f in CARD_LEVEL_INHERITED:
        if f in star1_block:
            inherited[f] = star1_block[f]
    for star_n, star_data in stars_v2.items():
        block = star_data["effects"][0]
        for f in CARD_LEVEL_INHERITED:
            star_val = block.get(f)
            base_val = inherited.get(f)
            if star_val != base_val:
                raise ValueError(
                    f"★{star_n}: inherited field '{f}' drifts from ★1 "
                    f"(★1={base_val!r}, ★{star_n}={star_val!r}). "
                    f"v1 schema has no per-star inheritance — either align "
                    f"values across stars, or extend the v2→v1 revert path."
                )

    # Build v1 card top-level
    card_v1: dict = {}
    for k, v in card_v2.items():
        if k == "stars":
            continue
        card_v1[k] = v
    card_v1["timing"] = card_timing
    card_v1.update(inherited)

    # Rebuild stars in v1 form
    stars_v1: dict[int, dict] = {}
    for star_n, star_data in stars_v2.items():
        block = star_data["effects"][0]
        star_v1: dict = {"max_act": block["max_act"]}

        # Star-level timing override (only when it differs from card timing)
        if block["trigger_timing"] != card_timing:
            star_v1["timing"] = block["trigger_timing"]

        # Fields that live under `star` in v1
        for f in ("conditional", "r_conditional", "post_threshold"):
            if f in block:
                star_v1[f] = block[f]

        # Actions → effects list (flat, single-key dict per effect)
        star_v1["effects"] = _block_to_effects(block)

        stars_v1[star_n] = star_v1

    card_v1["stars"] = stars_v1
    return card_v1


def load_v2_as_v1() -> "dict[str, dict[str, dict]]":
    """Load all v2 YAMLs and return {theme: {card_id: card_v1_dict}}.

    Shape is identical to `v1cg.load_all_cards()` so downstream generate()
    functions are reused verbatim.
    """
    all_cards: "dict[str, dict[str, dict]]" = {}
    for theme in v1cg.THEME_ORDER:
        path = CARDS_V2_DIR / f"{theme}.yaml"
        if not path.exists():
            print(f"WARNING: {path} not found, skipping {theme}")
            continue
        with open(path) as f:
            data = yaml.safe_load(f)
        if not data or "cards" not in data:
            continue
        cards = data["cards"]
        converted: dict[str, dict] = {}
        for card_id, card in cards.items():
            # Coerce star keys to int (YAML may parse them as int already)
            if "stars" in card:
                card["stars"] = {int(k): v for k, v in card["stars"].items()}
            try:
                converted[card_id] = v2_to_v1_card(card)
            except Exception as e:
                raise RuntimeError(f"{theme}.yaml:{card_id}: {e}") from e
        all_cards[theme] = converted
    return all_cards


def main() -> None:
    all_cards = load_v2_as_v1()
    if not all_cards:
        print("ERROR: no v2 YAML files loaded")
        sys.exit(1)

    # Reuse v1 validators — they expect the v1 shape we just produced.
    ec_errors = v1cg.validate_conscript_enhanced_count(all_cards)
    if ec_errors:
        print("❌ conscript.enhanced_count violations (in v2 source):")
        for e in ec_errors:
            print(f"  - {e}")
        sys.exit(2)

    parity_errors = v1cg.validate_r_conditional_star_parity(all_cards)
    if parity_errors:
        print("❌ r_conditional ★ parity violations (in v2 source):")
        for e in parity_errors:
            print(f"  - {e}")
        sys.exit(2)

    generated_db = v1cg.generate(all_cards)
    descs = generate_all_descs(all_cards)
    generated_descs = v1cg.generate_descs_gd(all_cards, descs)

    OUT_TMP_DB.write_text(generated_db)
    OUT_TMP_DESCS.write_text(generated_descs)

    total = sum(len(c) for c in all_cards.values())
    print(f"v2 codegen: {total} cards")
    print(f"  → {OUT_TMP_DB}")
    print(f"  → {OUT_TMP_DESCS}")


if __name__ == "__main__":
    main()
