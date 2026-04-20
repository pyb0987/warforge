#!/usr/bin/env python3
"""
migrate_conditional_depth.py — Flatten the `effects:` key out of
conditional / r_conditional / post_threshold.

Before (v2 original):
    conditional:
      - when: {unit_count_gte: 8}
        effects:
          - spawn: {target: both_adj}
          - enhance: {target: self, atk_pct: 0.03}
    post_threshold:
      - spawn: {target: all_allies}
      - shield: {target: all_allies, hp_pct: 0.1}

After (depth-reduced):
    conditional:
      - when: {unit_count_gte: 8}
        spawn: {target: both_adj}
        enhance: {target: self, atk_pct: 0.03}
    post_threshold:
      spawn: {target: all_allies}
      shield: {target: all_allies, hp_pct: 0.1}

Rules:
  - conditional / r_conditional: each list entry becomes {when, ...actions}.
    Same-name actions collapse to a params list (matches the top-level
    block convention).
  - post_threshold: entire list → actions dict (single entry). Same-name
    collapse to params list.
  - YAML action order is preserved (Python 3.7+ dict insertion order).
"""

from __future__ import annotations

from collections import OrderedDict
from pathlib import Path
from typing import Any

import yaml

ROOT = Path(__file__).resolve().parent.parent
CARDS_DIR = ROOT / "data" / "cards"
THEMES = ["druid", "military", "neutral", "predator", "steampunk"]


def _effects_list_to_actions_dict(effects: list) -> "OrderedDict[str, Any]":
    """Convert v1-style flat action list → dict-of-actions (same-name → list)."""
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


def _migrate_cond_entry(entry: dict) -> "OrderedDict[str, Any]":
    """conditional/r_conditional list entry: {when, effects: [...]} → {when, ...actions}"""
    if "when" not in entry:
        raise ValueError(f"conditional entry missing 'when': {entry!r}")
    if "effects" not in entry:
        # Already migrated or malformed — assume already migrated (idempotent).
        return OrderedDict(entry)
    result: "OrderedDict[str, Any]" = OrderedDict()
    result["when"] = entry["when"]
    actions = _effects_list_to_actions_dict(entry["effects"])
    for k, v in actions.items():
        if k in result:
            raise ValueError(f"action name {k!r} collides with reserved 'when'")
        result[k] = v
    return result


def _migrate_block(block: dict) -> dict:
    """In-place migrate one timing block's conditional / r_conditional / post_threshold."""
    if "conditional" in block and isinstance(block["conditional"], list):
        block["conditional"] = [_migrate_cond_entry(c) for c in block["conditional"]]
    if "r_conditional" in block and isinstance(block["r_conditional"], list):
        block["r_conditional"] = [_migrate_cond_entry(c) for c in block["r_conditional"]]
    if "post_threshold" in block and isinstance(block["post_threshold"], list):
        # List of single-key action dicts → single dict-of-actions.
        block["post_threshold"] = _effects_list_to_actions_dict(block["post_threshold"])
    return block


def _migrate_card(card: dict) -> dict:
    for _star_n, star in (card.get("stars") or {}).items():
        for block in star.get("effects", []) or []:
            if isinstance(block, dict):
                _migrate_block(block)
    return card


class _Dumper(yaml.SafeDumper):
    # Inline-represent the dict without aliases — match existing v2 style.
    def ignore_aliases(self, data: Any) -> bool:  # type: ignore[override]
        return True


def _represent_ordered(dumper: yaml.Dumper, data: OrderedDict) -> Any:
    return dumper.represent_mapping("tag:yaml.org,2002:map", data.items())


_Dumper.add_representer(OrderedDict, _represent_ordered)


def migrate_file(path: Path) -> int:
    with open(path) as f:
        data = yaml.safe_load(f)
    if not data or "cards" not in data:
        return 0
    touched = 0
    for _cid, card in data["cards"].items():
        before = yaml.dump(card, default_flow_style=False, sort_keys=False, allow_unicode=True)
        _migrate_card(card)
        after = yaml.dump(card, default_flow_style=False, sort_keys=False, allow_unicode=True)
        if before != after:
            touched += 1
    with open(path, "w") as f:
        yaml.dump(
            data, f, Dumper=_Dumper, sort_keys=False, allow_unicode=True,
            default_flow_style=False, indent=2, width=120,
        )
    return touched


def main() -> None:
    total_files = 0
    total_touched = 0
    for theme in THEMES:
        path = CARDS_DIR / f"{theme}.yaml"
        if not path.exists():
            continue
        n = migrate_file(path)
        total_files += 1
        total_touched += n
        print(f"  {theme}: {n} cards modified → {path.name}")
    print(f"\n{total_touched} cards across {total_files} files migrated.")


if __name__ == "__main__":
    main()
