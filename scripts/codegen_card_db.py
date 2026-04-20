#!/usr/bin/env python3
"""
codegen_card_db.py — Generate card_db.gd from YAML card definitions.

Usage:
    python3 scripts/codegen_card_db.py           # Regenerate card_db.gd
    python3 scripts/codegen_card_db.py --check    # Verify generated == current

v2 block format: effects are a list of timing blocks in `_templates[id].effects`.
Theme systems access per-star effects via `get_star_template().effects` and
search actions inside the matching block.
"""

from __future__ import annotations

import sys
from collections import OrderedDict
from pathlib import Path
from typing import Any, Optional

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
# Reuse enum maps, action-level generators, validators.
from card_desc_gen import generate_all_descs  # noqa: E402

# ═══════════════════════════════════════════════════════════════════
# Enum mappings: YAML string → GDScript expression
# ═══════════════════════════════════════════════════════════════════

TIMING_MAP = {
    "RS": "Enums.TriggerTiming.ROUND_START",
    "OE": "Enums.TriggerTiming.ON_EVENT",
    "BS": "Enums.TriggerTiming.BATTLE_START",
    "CA": "Enums.TriggerTiming.ON_COMBAT_ATTACK",
    "PC": "Enums.TriggerTiming.POST_COMBAT",
    "PCD": "Enums.TriggerTiming.POST_COMBAT_DEFEAT",
    "PCV": "Enums.TriggerTiming.POST_COMBAT_VICTORY",
    "REROLL": "Enums.TriggerTiming.ON_REROLL",
    "MERGE": "Enums.TriggerTiming.ON_MERGE",
    "SELL": "Enums.TriggerTiming.ON_SELL",
    "DEATH": "Enums.TriggerTiming.ON_COMBAT_DEATH",
    "PERSISTENT": "Enums.TriggerTiming.PERSISTENT",
}

LAYER1_MAP = {"UA": "Enums.Layer1.UNIT_ADDED", "EN": "Enums.Layer1.ENHANCED"}

LAYER2_MAP = {
    "MF": "Enums.Layer2.MANUFACTURE",
    "UP": "Enums.Layer2.UPGRADE",
    "TG": "Enums.Layer2.TREE_GROW",
    "BR": "Enums.Layer2.BREED",
    "HA": "Enums.Layer2.HATCH",
    "MT": "Enums.Layer2.METAMORPHOSIS",
    "TR": "Enums.Layer2.TRAIN",
    "CO": "Enums.Layer2.CONSCRIPT",
}

THEME_MAP = {
    "neutral": "Enums.CardTheme.NEUTRAL",
    "steampunk": "Enums.CardTheme.STEAMPUNK",
    "druid": "Enums.CardTheme.DRUID",
    "predator": "Enums.CardTheme.PREDATOR",
    "military": "Enums.CardTheme.MILITARY",
}

# Registration order (matches current card_db.gd)
THEME_ORDER = ["steampunk", "neutral", "druid", "predator", "military"]

# Default output layers per effect type
SPAWN_DEFAULT_OL1 = "UA"
ENHANCE_DEFAULT_OL1 = "EN"


# ═══════════════════════════════════════════════════════════════════
# Effect code generation
# ═══════════════════════════════════════════════════════════════════

def gen_layer(yaml_val: Any, map_dict: dict) -> str:
    """Convert YAML layer value to GDScript expression. None/-1/null → -1."""
    if yaml_val is None:
        return "-1"
    return map_dict.get(str(yaml_val), "-1")


# Actions that produce card_db.gd effects entries. Any YAML action encountered
# by gen_effect() that is NOT in this set results in a hard-fail — previously
# this path silently generated a raw_dict fallback that chain_engine could not
# interpret (silent drop, trace 015). Theme-system cards are routed before
# gen_effect via impl == "theme_system", so unknown actions arriving here are
# definitionally bugs.
CARD_DB_ACTIONS = frozenset([
    "spawn", "enhance", "buff", "gold", "terazin",
    "shield", "scrap", "diversity_gold", "absorb",
])


def gen_effect(effect: dict) -> str:
    """Convert a single YAML effect to a GDScript expression string.

    Raises ValueError when the action is unknown — codegen fails fast rather
    than emitting a dict that chain_engine cannot dispatch.
    """
    # Each effect has exactly one key (the action type)
    action = next(iter(effect))
    params = effect[action]

    if action == "spawn":
        return _gen_spawn(params)
    elif action == "enhance":
        return _gen_enhance(params)
    elif action == "buff":
        return _gen_buff(params)
    elif action == "gold":
        return f"_gold({params})"  # params is just the int
    elif action == "terazin":
        return _gen_raw_dict({
            "action": "grant_terazin", "target": "self",
            "terazin_amount": params,
        })
    elif action == "shield":
        return _gen_shield(params)
    elif action == "scrap":
        return _gen_scrap(params)
    elif action == "diversity_gold":
        return _gen_diversity_gold(params)
    elif action == "absorb":
        return _gen_absorb(params)
    else:
        raise ValueError(
            f"Unknown card_db action '{action}' in base effects "
            f"(params={params}). If this is a theme-system effect, set "
            f"'impl: theme_system' on the card so it is dispatched via "
            f"_theme_effects instead. Otherwise, add a handler in "
            f"gen_effect() and update CARD_DB_ACTIONS. Known actions: "
            f"{sorted(CARD_DB_ACTIONS)}"
        )


def _gen_spawn(p: dict) -> str:
    target = p["target"]
    count = p.get("count", 1)
    strongest = p.get("strongest", False)
    ol1 = p.get("ol1", SPAWN_DEFAULT_OL1)
    ol2 = p.get("ol2", None)

    ol1_gd = gen_layer(ol1, LAYER1_MAP)
    ol2_gd = gen_layer(ol2, LAYER2_MAP)

    if strongest:
        # breed_strongest requires raw dict (not expressible via _spawn helper)
        d = {
            "action": "spawn", "target": target,
            "spawn_count": count,
            "output_layer1": ol1_gd, "output_layer2": ol2_gd,
            "breed_strongest": True,
        }
        return _gen_raw_dict(d, raw_values={"output_layer1", "output_layer2"})

    # Determine minimal _spawn() call
    default_ol1 = gen_layer(SPAWN_DEFAULT_OL1, LAYER1_MAP)
    default_ol2 = "-1"

    if ol1_gd == default_ol1 and ol2_gd == default_ol2:
        # All layer defaults
        if count == 1:
            return f'_spawn("{target}")'
        return f'_spawn("{target}", {count})'
    elif ol1_gd == default_ol1:
        # ol1 is default, ol2 is custom
        return f'_spawn("{target}", {count}, {ol1_gd}, {ol2_gd})'
    else:
        # ol1 is custom (likely -1 for no-emit)
        return f'_spawn("{target}", {count}, {ol1_gd}, {ol2_gd})'


def _gen_enhance(p: dict) -> str:
    target = p["target"]
    atk = p["atk_pct"]
    hp = p.get("hp_pct", 0.0)
    tag = p.get("tag", "")
    ol1 = p.get("ol1", ENHANCE_DEFAULT_OL1)
    ol2 = p.get("ol2", None)

    ol1_gd = gen_layer(ol1, LAYER1_MAP)
    ol2_gd = gen_layer(ol2, LAYER2_MAP)
    default_ol1 = gen_layer(ENHANCE_DEFAULT_OL1, LAYER1_MAP)

    # Build args from right, stopping when defaults are hit
    args = [f'"{target}"', _fmt_float(atk)]

    needs_ol = ol1_gd != default_ol1 or ol2_gd != "-1"
    needs_tag = tag != "" or needs_ol
    needs_hp = hp != 0.0 or needs_tag

    if needs_hp:
        args.append(_fmt_float(hp))
    if needs_tag:
        args.append(f'"{tag}"')
    if needs_ol:
        args.append(ol1_gd)
        args.append(ol2_gd)

    return f'_enhance({", ".join(args)})'


def _gen_buff(p: dict) -> str:
    target = p["target"]
    atk = p["atk_pct"]
    tag = p.get("tag", "")
    if tag:
        return f'_buff("{target}", {_fmt_float(atk)}, "{tag}")'
    return f'_buff("{target}", {_fmt_float(atk)})'


def _gen_shield(p: dict) -> str:
    return f'_shield("{p["target"]}", {_fmt_float(p["hp_pct"])})'


def _gen_scrap(p: dict) -> str:
    return _gen_raw_dict({
        "action": "scrap_adjacent", "target": p.get("target", "self"),
        "scrap_count": p["count"], "reroll_gain": p["reroll_gain"],
        "gold_per_unit": p.get("gold_per_unit", 0),
    })


def _gen_diversity_gold(p: dict) -> str:
    d: dict[str, Any] = {"action": "diversity_gold", "target": "self"}
    if p:  # p might be empty dict for default
        for k, v in p.items():
            if v is not None:
                d[k] = v
    return _gen_raw_dict(d)


def _gen_absorb(p: dict) -> str:
    d: dict[str, Any] = {
        "action": "absorb_units", "target": p.get("target", "self"),
        "absorb_count": p["count"],
    }
    if p.get("transfer_upgrades"):
        d["transfer_upgrades"] = True
    if p.get("majority_atk_bonus") is not None:
        d["majority_atk_bonus"] = p["majority_atk_bonus"]
    return _gen_raw_dict(d)


def _gd_value(v: Any, raw_values: Optional[set] = None, key: str = "") -> str:
    """Convert a Python value to GDScript literal (recursive)."""
    if raw_values and key in raw_values:
        return str(v)
    if v is None:
        return "-1"  # GDScript null sentinel for optional layers
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return _fmt_float(v)
    if isinstance(v, str):
        return f'"{v}"'
    if isinstance(v, list):
        items = [_gd_value(item) for item in v]
        return "[" + ", ".join(items) + "]"
    if isinstance(v, dict):
        parts = []
        for dk, dv in v.items():
            parts.append(f'"{dk}": {_gd_value(dv)}')
        return "{" + ", ".join(parts) + "}"
    return str(v)


def _gen_raw_dict(d: dict, raw_values: Optional[set] = None) -> str:
    """Generate a GDScript dict literal. raw_values are emitted without quoting."""
    parts = []
    for k, v in d.items():
        parts.append(f'"{k}": {_gd_value(v, raw_values, k)}')
    return "{" + ", ".join(parts) + "}"


def _fmt_float(f: float) -> str:
    """Format float for GDScript (always show decimal point)."""
    if f == int(f):
        return f"{int(f)}.0" if f != 0 else "0.0"
    # Remove trailing zeros but keep at least one decimal
    s = f"{f:.4f}".rstrip("0")
    if s.endswith("."):
        s += "0"
    return s

def _convert_nested_effects(params: dict) -> dict:
    """Recursively convert nested YAML effect structures to clean dicts.
    Handles 'effects' sub-arrays (e.g., on_combat_result.effects).

    NOTE (multi-review 2026-04-17, H1): ``None`` values are intentionally
    dropped from the generated dict. This is the CORRECT behavior for the
    theme_system path because:
      - card_db impl cards route ol1 via ``_gen_spawn``/``_gen_enhance`` which
        read from the raw YAML dict via ``p.get("ol1", DEFAULT)`` — None is
        preserved there as an explicit null.
      - theme_system impl cards (e.g., ml_academy.enhance) have handlers that
        emit events themselves (or choose not to) — they do NOT consume the
        ``ol1`` field from _theme_effects. Dropping None-valued keys here
        keeps the generated dict minimal.
    If a future theme_system handler starts reading ``ol1`` from the stored
    dict, change this filter to preserve explicit null (e.g. serialize as
    ``-1`` or ``None`` sentinel) rather than dropping.
    """
    result = {}
    for k, v in params.items():
        if v is None:
            continue
        if k == "effects" and isinstance(v, list):
            # Convert inner effects list: each item is {action_name: params}
            result[k] = []
            for inner_eff in v:
                if isinstance(inner_eff, dict):
                    inner_action = next(iter(inner_eff))
                    inner_params = inner_eff[inner_action]
                    if isinstance(inner_params, dict):
                        clean = {pk: pv for pk, pv in inner_params.items() if pv is not None}
                        result[k].append({"action": inner_action, **clean})
                    else:
                        result[k].append({"action": inner_action, "value": inner_params})
                else:
                    result[k].append(inner_eff)
        else:
            result[k] = v
    return result

def make_var_prefix(card_id: str) -> str:
    """Generate a short variable prefix from card_id."""
    # sp_assembly → asm, ne_earth_echo → ee, etc.
    # Use last part's first 2-3 chars for uniqueness
    parts = card_id.split("_")
    if len(parts) <= 2:
        return parts[-1][:3]
    return "".join(p[0] for p in parts[1:])

def _write_file(output_path: Path, generated: str):
    """Write generated content with chmod 444 protection."""
    import os, stat as stat_mod
    if output_path.exists():
        current_mode = os.stat(output_path).st_mode
        if not (current_mode & stat_mod.S_IWUSR):
            os.chmod(output_path, current_mode | stat_mod.S_IWUSR)
    output_path.write_text(generated)
    os.chmod(output_path,
             stat_mod.S_IRUSR | stat_mod.S_IRGRP | stat_mod.S_IROTH)


def generate_descs_gd(
    all_cards: dict[str, dict[str, dict]],
    descs: dict[str, dict[int, str]],
) -> str:
    """Generate card_descs.gd file content."""
    theme_label = {
        "neutral": "NEUTRAL", "steampunk": "STEAMPUNK",
        "druid": "DRUID", "predator": "PREDATOR", "military": "MILITARY",
    }
    lines = [
        "# AUTO-GENERATED from data/cards/*.yaml — DO NOT EDIT",
        "# Run: python3 scripts/codegen_card_db.py",
        "extends Node",
        "## 카드 효과 한 줄 설명. 툴팁에서 ★별 독립적 설명 제공.",
        "",
        "var _descs := {",
    ]
    for theme in THEME_ORDER:
        cards = all_cards.get(theme, {})
        if not cards:
            continue
        label = theme_label.get(theme, theme.upper())
        lines.append(
            f"\t# ═══════════════════════ {label} ({len(cards)}) "
            f"═══════════════════════")
        for card_id in cards:
            d = descs.get(card_id, {})
            lines.append(f'\t"{card_id}": {{')
            for star in (1, 2, 3):
                if star in d:
                    # Escape for GDScript string literal: " → \" and raw newline → \n
                    text = d[star].replace('"', '\\"').replace("\n", "\\n")
                    lines.append(f'\t\t{star}: "{text}",')
            lines.append("\t},")
    lines.append("}")
    lines.append("")
    lines.append("")
    lines.append("func get_desc(card_id: String, star: int = 1) -> String:")
    lines.append('\tif not _descs.has(card_id):\n\t\treturn ""')
    lines.append("\tvar per_star: Dictionary = _descs[card_id]")
    lines.append("\tif per_star.has(star):\n\t\treturn per_star[star]")
    lines.append('\treturn per_star.get(1, "")')
    lines.append("")
    return "\n".join(lines)


def _diff_r_conditional(
    baseline: Optional[list],
    other: Optional[list],
    allowed_actions: set,
) -> Optional[str]:
    """Return a human-readable diff, or None if equivalent modulo allowed actions.

    ``allowed_actions`` is a set of action names whose parameters are permitted
    to differ across stars (e.g. star-scaling combat buffs). All other actions
    must have byte-identical params.
    """
    if baseline is None and other is None:
        return None
    if baseline is None or other is None:
        return "one star defines r_conditional, the other does not"
    if len(baseline) != len(other):
        return (
            f"different number of rank milestones "
            f"(baseline={len(baseline)}, other={len(other)})"
        )
    for i, (rb, ro) in enumerate(zip(baseline, other)):
        if rb.get("when") != ro.get("when"):
            return (
                f"milestone #{i} 'when' differs: "
                f"{rb.get('when')} vs {ro.get('when')}"
            )
        effs_b = rb.get("effects") or []
        effs_o = ro.get("effects") or []
        if len(effs_b) != len(effs_o):
            return (
                f"milestone {rb.get('when')} effects count differs: "
                f"{len(effs_b)} vs {len(effs_o)}"
            )
        for j, (eb, eo) in enumerate(zip(effs_b, effs_o)):
            # Each effect is a single-key dict {action: params}
            actions_b = list(eb.keys())
            actions_o = list(eo.keys())
            if actions_b != actions_o:
                return (
                    f"milestone {rb.get('when')} effect #{j} action name "
                    f"differs: {actions_b} vs {actions_o}"
                )
            action = actions_b[0]
            if eb[action] != eo[action]:
                if action in allowed_actions:
                    continue
                return (
                    f"milestone {rb.get('when')} action '{action}' params "
                    f"differ (not in star_scalable_actions allowlist): "
                    f"{eb[action]} vs {eo[action]}"
                )
    return None


def validate_r_conditional_star_parity(
    all_cards: dict[str, dict[str, dict]],
) -> list[str]:
    """Verify r_conditional is structurally identical across stars within a card.

    Rationale: r_conditional represents rank-based milestones (R4/R10) that fire
    identically regardless of card ★ tier. The base ``effects`` block already
    scales with ★; per-star variance in ``r_conditional`` has historically
    signalled copy-paste drift, not intent.

    Evidence of 3 past drift bugs (all military theme):
      - 훈련소 ★2/★3 (commit 77e0a78): R4/R10 target diverged from ★1
        (``both_adj`` / ``all_military`` instead of ``left_adj`` / ``far_military``)
      - 보급부대 ★2/★3 (commit 77e0a78): R10 ``grant_terazin.amount`` was 2
        instead of 1, double-counting with R4's delta
      - 군수공장 ★1-★3 (commit 18e7cb2): R10 ``upgrade_shop_bonus``
        ``slot_delta``/``terazin_discount`` were 2 instead of 1, again double-
        counting the cumulative intent against the delta convention

    Opt-in variance: some cards (e.g. 돌격편대 swarm_buff, 특수작전대 crit_buff)
    legitimately scale a combat-buff effect across ★. Declare those via a
    per-card top-level field ``star_scalable_actions: [action_name, ...]``.
    Only the listed action names are permitted to have per-star param drift.

    Returns an empty list when all cards are clean.
    """
    errors: list[str] = []
    for _theme, cards in all_cards.items():
        for card_id, card in cards.items():
            stars = card.get("stars") or {}
            if len(stars) < 2:
                continue
            allowed = set(card.get("star_scalable_actions") or [])
            star_keys = sorted(stars.keys())
            baseline_star = star_keys[0]
            baseline = stars[baseline_star].get("r_conditional")
            for other_star in star_keys[1:]:
                other = stars[other_star].get("r_conditional")
                diff = _diff_r_conditional(baseline, other, allowed)
                if diff is not None:
                    errors.append(
                        f"{card_id}: ★{other_star} vs ★{baseline_star} — {diff}"
                    )
    return errors


def validate_conscript_enhanced_count(
    all_cards: dict[str, dict[str, dict]],
) -> list[str]:
    """Verify conscript.enhanced_count is within [0, count].

    P1-1 migration (2026-04-17): 'enhanced: partial/all' 문자열 필드를
    'enhanced_count: N' 수량 필드로 교체. 이 validator는 schema의 핵심 불변식
    (0 ≤ enhanced_count ≤ count)을 codegen 시점에 강제해 드리프트를 차단한다.
    """
    errors: list[str] = []
    def walk(cid: str, star: int, ctx: str, effs: list) -> None:
        for eff in effs or []:
            if not isinstance(eff, dict):
                continue
            action = next(iter(eff))
            params = eff[action]
            if action == "conscript" and isinstance(params, dict):
                count = int(params.get("count", 1))
                if "enhanced_count" in params:
                    ec = int(params["enhanced_count"])
                    if ec < 0 or ec > count:
                        errors.append(
                            f"{cid} ★{star} ({ctx}): conscript "
                            f"enhanced_count={ec} outside [0, count={count}]"
                        )
                # 구 필드 검출 → 마이그레이션 필요
                if "enhanced" in params:
                    errors.append(
                        f"{cid} ★{star} ({ctx}): deprecated "
                        f"'enhanced: {params['enhanced']}' field — "
                        f"migrate to 'enhanced_count: N' (P1-1)"
                    )
            # Recurse into nested effects (e.g. r_conditional.effects)
            if isinstance(params, dict) and isinstance(params.get("effects"), list):
                walk(cid, star, f"{ctx}→{action}.effects", params["effects"])
    for _theme, cards in all_cards.items():
        for cid, card in cards.items():
            for star, sd in (card.get("stars") or {}).items():
                walk(cid, star, "effects", sd.get("effects", []))
                for cond in sd.get("conditional") or []:
                    walk(cid, star, "conditional", cond.get("effects", []))
                for rc in sd.get("r_conditional") or []:
                    walk(cid, star, "r_conditional", rc.get("effects", []))
    return errors
ROOT = Path(__file__).resolve().parent.parent
CARDS_DIR = ROOT / "data" / "cards"
# C3+ onward: write directly to the official runtime paths so chain_engine and
# theme_systems can be developed against the new block format. Uses the v1
# codegen's `_write_file` helper (chmod +w → write → chmod 444), which keeps
# the codegen-protect hook's invariant intact.
OUTPUT_DB = ROOT / "godot" / "core" / "data" / "card_db.gd"
OUTPUT_DESCS = ROOT / "godot" / "core" / "data" / "card_descs.gd"

# Block metadata keys — everything else in a v2 block is an action.
BLOCK_META_KEYS = frozenset({
    "trigger_timing", "max_act",
    "listen", "require_tenure", "require_other", "is_threshold",
    "conditional", "r_conditional", "post_threshold",
})


# ═══════════════════════════════════════════════════════════════════
# v2 YAML loader
# ═══════════════════════════════════════════════════════════════════

def load_cards() -> "dict[str, dict[str, dict]]":
    """Load all v2 YAMLs. Returns {theme: {card_id: card_v2}}."""
    all_cards: "dict[str, dict[str, dict]]" = {}
    for theme in THEME_ORDER:
        path = CARDS_DIR / f"{theme}.yaml"
        if not path.exists():
            print(f"WARNING: {path} not found, skipping {theme}")
            continue
        with open(path) as f:
            data = yaml.safe_load(f)
        if not data or "cards" not in data:
            continue
        cards = data["cards"]
        for card_id, card in cards.items():
            if "stars" in card:
                card["stars"] = {int(k): v for k, v in card["stars"].items()}
        all_cards[theme] = cards
    return all_cards


# ═══════════════════════════════════════════════════════════════════
# Block → GDScript block dict generator
# ═══════════════════════════════════════════════════════════════════

def split_block(block: dict) -> tuple[dict, list[tuple[str, Any]]]:
    """Split a v2 block into (metadata, ordered actions list).

    Actions preserve dict insertion order. Duplicate-action values (list of
    params) expand into multiple (action, params) entries.
    """
    meta: dict = {}
    actions: list[tuple[str, Any]] = []
    for key, value in block.items():
        if key in BLOCK_META_KEYS:
            meta[key] = value
            continue
        if isinstance(value, list) and value and all(isinstance(v, dict) for v in value):
            for p in value:
                actions.append((key, p))
        else:
            actions.append((key, value))
    return meta, actions


def gen_action_dict(action: str, params: Any, impl: str = "card_db") -> str:
    """Convert one (action, params) to a GDScript dict literal.

    impl == "card_db": CARD_DB_ACTIONS get helper-func output (spawn/enhance/…);
    anything else falls through to a raw dict.
    impl == "theme_system": every action emits a raw dict. Theme systems own
    the interpretation, so e.g. theme `enhance` shape differs from card_db
    `enhance_pct` and must not be routed through _gen_enhance.
    """
    # Simple scalar value (e.g. gold: 3, terazin: 2)
    if not isinstance(params, dict):
        if impl == "card_db" and action == "gold":
            return f"_gold({params})"
        if impl == "card_db" and action == "terazin":
            return _gen_raw_dict({
                "action": "grant_terazin", "target": "self",
                "terazin_amount": params,
            })
        return _gen_raw_dict({"action": action, "value": params})

    if impl == "card_db" and action in CARD_DB_ACTIONS:
        return gen_effect({action: params})

    # Theme-system path — emit raw dict with nested `effects` flattening.
    d = {"action": action, **_convert_nested_effects(params)}
    return _gen_raw_dict(d)


## Conditional / r_conditional entries in v2 YAML use a depth-reduced
## {when, ...actions} shape — the `effects:` key was removed so there is a
## single action-dict convention across block / conditional / post_threshold.
## This helper normalizes a cond entry back to a v1-style flat action list
## for downstream consumers (desc_gen, runtime dict emission).
def _cond_actions(cond: dict) -> list[dict]:
    result: list[dict] = []
    for key, val in cond.items():
        if key == "when":
            continue
        if isinstance(val, list) and val and all(isinstance(v, dict) for v in val):
            for p in val:
                result.append({key: p})
        else:
            result.append({key: val})
    return result


## post_threshold is now a single dict-of-actions (no `when`). Convert to
## v1-style flat action list for desc_gen / runtime.
def _post_threshold_actions(pt: Any) -> list[dict]:
    if isinstance(pt, list):
        return pt  # idempotent: already flat
    if not isinstance(pt, dict):
        return []
    result: list[dict] = []
    for key, val in pt.items():
        if isinstance(val, list) and val and all(isinstance(v, dict) for v in val):
            for p in val:
                result.append({key: p})
        else:
            result.append({key: val})
    return result


def gen_conditional_entry(cond: dict, indent: str, impl: str) -> str:
    """Generate one conditional/r_conditional entry as a GDScript dict."""
    when = cond["when"]
    cond_type = next(iter(when))
    threshold = when[cond_type]
    inner_actions = []
    for e in _cond_actions(cond):
        # Inner effects are v1-style {action: params} dicts
        action = next(iter(e))
        params = e[action]
        inner_actions.append(gen_action_dict(action, params, impl))
    actions_src = ", ".join(inner_actions)
    return (
        f'{{"condition": "{cond_type}", "threshold": {threshold}, '
        f'"effects": [{actions_src}]}}'
    )


def gen_post_threshold_list(effects: Any, impl: str) -> str:
    """Post-threshold emits as a flat GDScript action list (runtime contract)."""
    parts = []
    for e in _post_threshold_actions(effects):
        action = next(iter(e))
        params = e[action]
        parts.append(gen_action_dict(action, params, impl))
    return "[" + ", ".join(parts) + "]"


def gen_block_dict(block: dict, indent: str, impl: str) -> list[str]:
    """Generate one v2 timing block as a multi-line GDScript dict literal.

    Returns a list of lines (not joined) so callers can control indentation
    inside the surrounding effects array.
    """
    meta, actions = split_block(block)

    timing_short: str = meta["trigger_timing"]
    timing_gd = TIMING_MAP[timing_short]
    max_act: int = meta["max_act"]

    listen = meta.get("listen") or {}
    l1_gd = gen_layer(listen.get("l1"), LAYER1_MAP)
    l2_gd = gen_layer(listen.get("l2"), LAYER2_MAP)

    require_tenure: int = meta.get("require_tenure", 0)
    require_other: bool = meta.get("require_other", False)
    is_threshold: bool = meta.get("is_threshold", False)

    # Actions list
    action_srcs = [gen_action_dict(name, params, impl) for name, params in actions]
    if not action_srcs:
        actions_field = '"actions": []'
    elif len(action_srcs) == 1 and len(action_srcs[0]) < 80:
        actions_field = f'"actions": [{action_srcs[0]}]'
    else:
        sep = f",\n{indent}\t\t"
        inner = action_srcs[0] + sep + sep.join(action_srcs[1:]) if len(action_srcs) > 1 else action_srcs[0]
        actions_field = f'"actions": [\n{indent}\t\t{inner}\n{indent}\t]'

    # Conditional family
    conditional_field = None
    if meta.get("conditional"):
        entries = [gen_conditional_entry(c, indent, impl) for c in meta["conditional"]]
        sep = f",\n{indent}\t\t"
        conditional_field = (
            f'"conditional_effects": [\n{indent}\t\t' + sep.join(entries) +
            f"\n{indent}\t]"
        )

    r_conditional_field = None
    if meta.get("r_conditional"):
        entries = [gen_conditional_entry(c, indent, impl) for c in meta["r_conditional"]]
        sep = f",\n{indent}\t\t"
        r_conditional_field = (
            f'"r_conditional_effects": [\n{indent}\t\t' + sep.join(entries) +
            f"\n{indent}\t]"
        )

    post_threshold_field = None
    if meta.get("post_threshold"):
        post_threshold_field = (
            f'"post_threshold_effects": {gen_post_threshold_list(meta["post_threshold"], impl)}'
        )

    # Assemble
    lines = [f"{indent}{{"]
    lines.append(f'{indent}\t"trigger_timing": {timing_gd}, "max_activations": {max_act},')
    lines.append(f'{indent}\t"trigger_layer1": {l1_gd}, "trigger_layer2": {l2_gd},')
    lines.append(
        f'{indent}\t"require_tenure": {require_tenure}, '
        f'"require_other_card": {"true" if require_other else "false"}, '
        f'"is_threshold": {"true" if is_threshold else "false"},'
    )
    lines.append(f'{indent}\t{actions_field},')
    if conditional_field:
        lines.append(f'{indent}\t{conditional_field},')
    if r_conditional_field:
        lines.append(f'{indent}\t{r_conditional_field},')
    if post_threshold_field:
        lines.append(f'{indent}\t{post_threshold_field},')
    lines.append(f"{indent}}}")
    return lines


def gen_effects_blocks(blocks: list, indent: str, impl: str) -> str:
    """Generate an 'effects' array (list of blocks) as a GDScript expression."""
    if not blocks:
        return "[]"
    parts: list[str] = []
    for i, b in enumerate(blocks):
        block_lines = gen_block_dict(b, indent + "\t", impl)
        # Add comma after the closing } for all but the last
        trailing = "," if i < len(blocks) - 1 else ""
        block_lines[-1] = block_lines[-1] + trailing
        parts.extend(block_lines)
    inner = "\n".join(parts)
    return f"[\n{inner}\n{indent}]"


# ═══════════════════════════════════════════════════════════════════
# Card registration
# ═══════════════════════════════════════════════════════════════════

def gen_card_registration_v2(card_id: str, card: dict) -> list[str]:
    """Generate `_c()` call for one card in block format."""
    lines: list[str] = []
    prefix = card["_var_prefix"]
    impl = card.get("impl", "card_db")

    # Composition variable
    comp_items = ",".join(
        f'{{"unit_id":"{c["unit"]}","count":{c["n"]}}}'
        for c in card["comp"]
    )
    lines.append(f'\tvar {prefix}_comp := [{comp_items}]')

    # Tags variable
    tag_items = ", ".join(f'"{t}"' for t in card["tags"])
    lines.append(f'\tvar {prefix}_tags := PackedStringArray([{tag_items}])')

    # ★1 effects (blocks)
    star1_blocks = card["stars"][1]["effects"]
    star1_effects_code = gen_effects_blocks(star1_blocks, "\t\t", impl)

    # Star overrides (★2, ★3) — emitted as inline dicts because they always
    # differ at minimum in `name`.
    override_lines: list[str] = ["\t\t{"]
    for star_level in (2, 3):
        if star_level not in card["stars"]:
            continue
        star = card["stars"][star_level]
        name_lit = f'"{card["name"]} ★{star_level}"'
        ov_effects = gen_effects_blocks(star["effects"], "\t\t\t", impl)
        override_lines.append(f"\t\t\t{star_level}: {{")
        override_lines.append(f'\t\t\t\t"name": {name_lit},')
        override_lines.append(f'\t\t\t\t"composition": {prefix}_comp,')
        override_lines.append(f'\t\t\t\t"card_tags": {prefix}_tags,')
        override_lines.append(f'\t\t\t\t"effects": {ov_effects},')
        override_lines.append("\t\t\t},")
    override_lines.append("\t\t}")
    overrides_code = "\n".join(override_lines)

    # _c() call
    lines.append(f'\t_c("{card_id}", "{card["name"]}", {card["tier"]}, T,')
    lines.append(f'\t\t{prefix}_comp,')
    lines.append(f'\t\t{star1_effects_code},')
    lines.append(f'\t\t{prefix}_tags,')
    # Pass impl only when non-default to keep the generated code compact.
    if impl == "theme_system":
        lines.append(f'\t\t{overrides_code},')
        lines.append(f'\t\t"{impl}")')
    else:
        lines.append(overrides_code + ")")

    return lines


# ═══════════════════════════════════════════════════════════════════
# Per-theme register function
# ═══════════════════════════════════════════════════════════════════

def collect_used_enums(cards: dict) -> tuple[set, set, set]:
    """Scan all cards for trigger timings and listen/output layers used."""
    used_timings: set = set()
    used_l1: set = set()
    used_l2: set = set()

    for card in cards.values():
        for star_data in card.get("stars", {}).values():
            for block in star_data.get("effects", []):
                used_timings.add(block["trigger_timing"])
                listen = block.get("listen") or {}
                if listen.get("l1"):
                    used_l1.add(listen["l1"])
                if listen.get("l2"):
                    used_l2.add(listen["l2"])
                # Output layers inside actions (ol1/ol2)
                for key, val in block.items():
                    if key in BLOCK_META_KEYS:
                        continue
                    vals = val if (isinstance(val, list) and val and
                                   all(isinstance(v, dict) for v in val)) else [val]
                    for v in vals:
                        if isinstance(v, dict):
                            if v.get("ol1") and v["ol1"] not in (None, "null"):
                                used_l1.add(v["ol1"])
                            if v.get("ol2") and v["ol2"] not in (None, "null"):
                                used_l2.add(v["ol2"])
    return used_timings, used_l1, used_l2


def gen_register_function(theme: str, cards: dict) -> list[str]:
    lines: list[str] = []
    func_name = f"_register_{theme}"
    lines.append("")
    lines.append("")
    lines.append(f"# {'═' * 67}")
    lines.append(f"# {theme.upper()} ({len(cards)} cards)")
    lines.append(f"# {'═' * 67}")
    lines.append(f"func {func_name}() -> void:")
    lines.append(f"\tvar T := {THEME_MAP[theme]}")

    # Local enum declarations for readability
    used_timings, used_l1, used_l2 = collect_used_enums(cards)
    for short in sorted(used_timings):
        full = TIMING_MAP[short]
        lines.append(f"\tvar {short} := {full}")
    for short in sorted(used_l1):
        full = LAYER1_MAP[short]
        lines.append(f"\tvar {short} := {full}")
    for short in sorted(used_l2):
        full = LAYER2_MAP[short]
        lines.append(f"\tvar {short} := {full}")

    # Var prefix assignment + collision handling
    prefixes_used: dict[str, str] = {}
    for card_id, card in cards.items():
        prefix = make_var_prefix(card_id)
        base = prefix
        i = 2
        while prefix in prefixes_used and prefixes_used[prefix] != card_id:
            prefix = base + str(i)
            i += 1
        prefixes_used[prefix] = card_id
        card["_var_prefix"] = prefix

    # Emit card registrations
    card_lines: list[str] = []
    first = True
    for card_id, card in cards.items():
        if not first:
            card_lines.append("")
        first = False
        card_lines.extend(gen_card_registration_v2(card_id, card))

    # Replace full enum paths with locally-declared short names
    local_vars: dict[str, str] = {}
    for t in used_timings:
        local_vars[TIMING_MAP[t]] = t
    for x in used_l1:
        local_vars[LAYER1_MAP[x]] = x
    for x in used_l2:
        local_vars[LAYER2_MAP[x]] = x

    # Second pass: catch enums that slipped through (e.g., inside gen_action_dict
    # output where local vars weren't substituted)
    _ALL_ENUMS: dict[str, str] = {}
    for short, full in TIMING_MAP.items():
        _ALL_ENUMS[full] = short
    for short, full in LAYER1_MAP.items():
        _ALL_ENUMS[full] = short
    for short, full in LAYER2_MAP.items():
        _ALL_ENUMS[full] = short

    joined = "\n".join(card_lines)
    extras = []
    for full_path, short_name in _ALL_ENUMS.items():
        if full_path in joined and full_path not in local_vars:
            local_vars[full_path] = short_name
            extras.append(f"\tvar {short_name} := {full_path}")
    if extras:
        insert_idx = len(lines)
        for i in range(len(lines) - 1, -1, -1):
            if lines[i].startswith("\tvar "):
                insert_idx = i + 1
                break
        for ev in sorted(extras):
            lines.insert(insert_idx, ev)
            insert_idx += 1

    # Longest-first to avoid substring collisions (e.g., POST_COMBAT inside
    # POST_COMBAT_DEFEAT getting replaced to "PC_DEFEAT").
    ordered_subst = sorted(local_vars.items(), key=lambda kv: -len(kv[0]))
    for i, line in enumerate(card_lines):
        for full_path, short_name in ordered_subst:
            line = line.replace(full_path, short_name)
        card_lines[i] = line

    lines.extend(card_lines)
    return lines


# ═══════════════════════════════════════════════════════════════════
# File assembly
# ═══════════════════════════════════════════════════════════════════

HEADER = '''\
# AUTO-GENERATED from data/cards/*.yaml — DO NOT EDIT
# Run: python3 scripts/codegen_card_db.py
extends Node
## Card database. Autoloaded as "CardDB".
##
## Schema (v2 block format):
##   _templates[id] = {
##     id, name, tier, theme, composition, card_tags, cost,
##     effects: [  # list of timing blocks (1+ per card)
##       {
##         trigger_timing, max_activations,
##         trigger_layer1, trigger_layer2,
##         require_tenure, require_other_card, is_threshold,
##         actions: [{action, target, ...}, ...],
##         conditional_effects: [...],
##         r_conditional_effects: [...],
##         post_threshold_effects: [...],
##       }
##     ],
##     star_overrides: {2: {name, composition, card_tags, effects}, 3: {...}},
##   }

var _templates: Dictionary = {}
var _tier_cost := {1: 2, 2: 3, 3: 4, 4: 5, 5: 6}
'''

API_FUNCTIONS = '''
func get_template(id: String) -> Dictionary:
\treturn _templates.get(id, {})


## ★ 레벨별 템플릿 반환. base + star_overrides 병합.
## star_level <= 1 이면 기본 템플릿 반환.
func get_star_template(base_id: String, star_level: int) -> Dictionary:
\tvar base: Dictionary = _templates.get(base_id, {})
\tif base.is_empty():
\t\treturn {}
\tif star_level <= 1:
\t\treturn base.duplicate(true)
\tvar overrides: Dictionary = base.get("star_overrides", {})
\tif not overrides.has(star_level):
\t\treturn base.duplicate(true)
\tvar result := base.duplicate(true)
\tvar ov: Dictionary = overrides[star_level]
\tfor key in ov:
\t\tresult[key] = ov[key]
\tresult.erase("star_overrides")
\treturn result


func get_all_ids() -> Array[String]:
\tvar ids: Array[String] = []
\tids.assign(_templates.keys())
\treturn ids


func get_ids_by_theme(theme: int) -> Array[String]:
\tvar ids: Array[String] = []
\tfor id in _templates:
\t\tif _templates[id].get("theme", -1) == theme:
\t\t\tids.append(id)
\treturn ids


## Return the effect blocks for the given (card_id, star_level).
## In v2 there is a single unified store; this replaces both the old
## get_template().effects access AND the old _theme_effects lookup.
func get_effect_blocks(card_id: String, star_level: int = 1) -> Array:
\tvar tmpl := get_star_template(card_id, star_level)
\treturn tmpl.get("effects", [])


## Return the first block whose trigger_timing matches. {} if none.
func get_block_for_timing(card_id: String, star_level: int, timing: int) -> Dictionary:
\tfor block in get_effect_blocks(card_id, star_level):
\t\tif block.get("trigger_timing") == timing:
\t\t\treturn block
\treturn {}


## Flat view of a card's theme actions across ALL timing blocks.
## Theme actions have globally unique names (spawn_firearm, manufacture,
## range_bonus, hatch_scaled, train, …), so the flat list preserves meaning
## for `_find_eff(effs, action_name)` lookups regardless of which block the
## action lives in.
## Includes reconstructed r_conditional / conditional pseudo-actions so
## theme_systems can still iterate them alongside regular actions.
## Multi-block cards (e.g. sp_warmachine RS+PERSISTENT) are supported: every
## block contributes its actions to the view.
func get_theme_effects(card_id: String, star_level: int) -> Array:
\tvar blocks := get_effect_blocks(card_id, star_level)
\tvar result: Array = []
\tfor block in blocks:
\t\tresult.append_array(block.get("actions", []))
\t\tfor rc in block.get("r_conditional_effects", []):
\t\t\tresult.append({
\t\t\t\t"action": "r_conditional",
\t\t\t\t"condition": rc.get("condition", ""),
\t\t\t\t"threshold": rc.get("threshold", 0),
\t\t\t\t"effects": rc.get("effects", []),
\t\t\t})
\t\tfor c in block.get("conditional_effects", []):
\t\t\tresult.append({
\t\t\t\t"action": "conditional",
\t\t\t\t"condition": c.get("condition", ""),
\t\t\t\t"threshold": c.get("threshold", 0),
\t\t\t\t"effects": c.get("effects", []),
\t\t\t})
\treturn result
'''

HELPER_FUNCTIONS = '''
## Compact card registration (v2 block format).
##
## Template shape (v2):
##   _templates[id] = {
##     id, name, tier, theme, impl, composition, card_tags, cost,
##     effects: [block, block, ...],      # ← primary truth
##     star_overrides: {2: {...}, 3: {...}},
##     # ─── Backward-compat flat accessors (hoisted from effects[0]) ───
##     # Legacy read sites (tests, UI, sim harness, AI evaluator, some
##     # game_manager paths) still expect these top-level fields. They are
##     # a "first-block hoist": for a multi-block card, these reflect the
##     # FIRST block in YAML order (representative timing) only.
##     # Multi-block cards (e.g. sp_warmachine with RS + BS blocks) have
##     # these flat fields pointing to block[0]; block[1..n] are only
##     # reachable via template["effects"]. This is intentional backward-
##     # compat — see docs/design/backlog.md "flat hoist 전면 제거".
##     trigger_timing, max_activations,
##     trigger_layer1, trigger_layer2,
##     require_tenure, require_other_card, is_threshold,
##   }
##
## IMPLICIT CONTRACT (v2 multi-block, see docs/design/backlog.md):
##   - ``effects[0]`` is the *representative* block used for flat-hoist
##     fields above. Its trigger_timing is what the UI and descriptions
##     label as "the card's timing".
##   - A card may have **multiple blocks per star** (v2 supports this).
##     All blocks fire independently via chain_engine's block loop.
##   - ``impl: theme_system`` cards route to their *.gd handler; the
##     handler reads ``get_theme_effects()`` directly — the flat accessors
##     are irrelevant for dispatch but still present for UI compatibility.
##   - If a read site must know ALL timings, iterate template["effects"],
##     not just the flat ``trigger_timing`` field.
func _c(id: String, nm: String, tier: int, theme: int,
\t\tcomp: Array, effects: Array, tags: PackedStringArray,
\t\tstar_overrides: Dictionary = {},
\t\timpl: String = "card_db") -> void:
\tvar first: Dictionary = effects[0] if effects.size() > 0 else {}
\t_templates[id] = {
\t\t"id": id, "name": nm, "tier": tier, "theme": theme,
\t\t"impl": impl,
\t\t"composition": comp,
\t\t"effects": effects,
\t\t"cost": _tier_cost.get(tier, 3),
\t\t"card_tags": tags,
\t\t"star_overrides": _hoist_override_fields(star_overrides),
\t\t# ── Legacy flat accessors (hoisted from first block) ──
\t\t"trigger_timing": first.get("trigger_timing", -1),
\t\t"max_activations": first.get("max_activations", -1),
\t\t"trigger_layer1": first.get("trigger_layer1", -1),
\t\t"trigger_layer2": first.get("trigger_layer2", -1),
\t\t"require_tenure": first.get("require_tenure", 0),
\t\t"require_other_card": first.get("require_other_card", false),
\t\t"is_threshold": first.get("is_threshold", false),
\t}


## Apply the same hoist to each star override so merged templates stay
## consistent when chain_engine / UI still reads flat fields on ★2/★3.
func _hoist_override_fields(star_overrides: Dictionary) -> Dictionary:
\tvar result: Dictionary = {}
\tfor star_level in star_overrides:
\t\tvar ov: Dictionary = star_overrides[star_level]
\t\tvar effs: Array = ov.get("effects", [])
\t\tvar first: Dictionary = effs[0] if effs.size() > 0 else {}
\t\tvar hoisted := ov.duplicate()
\t\thoisted["trigger_timing"] = first.get("trigger_timing", -1)
\t\thoisted["max_activations"] = first.get("max_activations", -1)
\t\thoisted["trigger_layer1"] = first.get("trigger_layer1", -1)
\t\thoisted["trigger_layer2"] = first.get("trigger_layer2", -1)
\t\thoisted["require_tenure"] = first.get("require_tenure", 0)
\t\thoisted["require_other_card"] = first.get("require_other_card", false)
\t\thoisted["is_threshold"] = first.get("is_threshold", false)
\t\tresult[star_level] = hoisted
\treturn result


# --- Effect helpers (action-level dict builders) ---
func _spawn(target: String, count: int = 1, ol1: int = Enums.Layer1.UNIT_ADDED, ol2: int = -1) -> Dictionary:
\treturn {"action": "spawn", "target": target, "spawn_count": count, "output_layer1": ol1, "output_layer2": ol2}

func _enhance(target: String, atk_pct: float, hp_pct: float = 0.0, tag: String = "", ol1: int = Enums.Layer1.ENHANCED, ol2: int = -1) -> Dictionary:
\treturn {"action": "enhance_pct", "target": target, "enhance_atk_pct": atk_pct, "enhance_hp_pct": hp_pct, "unit_tag_filter": tag, "output_layer1": ol1, "output_layer2": ol2}

func _buff(target: String, atk_pct: float, tag: String = "") -> Dictionary:
\treturn {"action": "buff_pct", "target": target, "buff_atk_pct": atk_pct, "unit_tag_filter": tag}

func _gold(amount: int) -> Dictionary:
\treturn {"action": "grant_gold", "target": "self", "gold_amount": amount}

func _shield(target: String, hp_pct: float) -> Dictionary:
\treturn {"action": "shield_pct", "target": target, "shield_hp_pct": hp_pct}
'''


def gen_ready(themes: list[str]) -> str:
    calls = "\n".join(f"\t_register_{t}()" for t in themes)
    return f'''
func _ready() -> void:
{calls}
\tprint("[CardDB] Registered %d cards." % _templates.size())
'''


def generate_card_db(all_cards: dict) -> str:
    present_themes = [t for t in THEME_ORDER if t in all_cards]
    parts = [HEADER, gen_ready(present_themes), API_FUNCTIONS, HELPER_FUNCTIONS]
    for theme in present_themes:
        parts.append("\n".join(gen_register_function(theme, all_cards[theme])))
    parts.append("")
    return "\n".join(parts)


# ═══════════════════════════════════════════════════════════════════
# Card descriptions (reuse card_desc_gen — it already consumes v1-shape dicts
# for action parsing, but actions are identical in v2). We build a v1-ish
# projection just for desc generation.
# ═══════════════════════════════════════════════════════════════════

def _project_to_desc_gen_input(all_cards: dict) -> dict:
    """card_desc_gen expects v1 layout. Reconstruct the minimum fields it reads."""
    out: dict = {}
    for theme, cards in all_cards.items():
        out_cards: dict = {}
        for card_id, card in cards.items():
            # Primary timing = ★1 block's trigger_timing
            star1_block = card["stars"][1]["effects"][0]
            base_timing = star1_block["trigger_timing"]

            projected_card: dict = {
                "name": card["name"],
                "tier": card["tier"],
                "theme": card["theme"],
                "timing": base_timing,
            }
            if "star_scalable_actions" in card:
                projected_card["star_scalable_actions"] = card["star_scalable_actions"]
            if card.get("listen") or star1_block.get("listen"):
                projected_card["listen"] = star1_block.get("listen") or card.get("listen", {})
            if "require_tenure" in star1_block:
                projected_card["require_tenure"] = star1_block["require_tenure"]
            if "require_other" in star1_block:
                projected_card["require_other"] = star1_block["require_other"]
            if "is_threshold" in star1_block:
                projected_card["is_threshold"] = star1_block["is_threshold"]

            projected_stars: dict = {}
            for star_n, star_data in card["stars"].items():
                proj_star: dict = {}
                blocks = star_data["effects"]
                first_block = blocks[0]
                # First block's trigger_timing is the card-level "representative"
                # timing; other blocks' actions get timing_override injected so
                # desc_gen renders them as separate sections.
                proj_star["max_act"] = first_block["max_act"]
                if first_block["trigger_timing"] != base_timing:
                    proj_star["timing"] = first_block["trigger_timing"]
                # conditional/r_conditional: depth-reduced {when, ...actions}
                # form in YAML → project to v1 shape {when, effects: [...]}
                # for legacy desc_gen / runtime dict emission.
                # post_threshold: dict-of-actions in YAML → project to v1 flat list.
                for f in ("conditional", "r_conditional"):
                    if f in first_block:
                        proj_star[f] = [
                            {"when": c["when"], "effects": _cond_actions(c)}
                            for c in first_block[f]
                        ]
                if "post_threshold" in first_block:
                    proj_star["post_threshold"] = _post_threshold_actions(
                        first_block["post_threshold"])

                # Flatten actions across all blocks. Non-primary block actions
                # carry `timing_override` so card_desc_gen splits them into a
                # separate prefixed section ("라운드 시작: …" / "[지속] …").
                effects: list = []
                primary_timing = first_block["trigger_timing"]
                for block in blocks:
                    block_timing = block["trigger_timing"]
                    is_non_primary = block_timing != primary_timing
                    for key, val in block.items():
                        if key in BLOCK_META_KEYS:
                            continue
                        if (isinstance(val, list) and val and
                                all(isinstance(v, dict) for v in val)):
                            for p in val:
                                p_copy = dict(p)
                                if is_non_primary:
                                    p_copy["timing_override"] = block_timing
                                effects.append({key: p_copy})
                        elif isinstance(val, dict):
                            v_copy = dict(val)
                            if is_non_primary:
                                v_copy["timing_override"] = block_timing
                            effects.append({key: v_copy})
                        else:
                            effects.append({key: val})
                proj_star["effects"] = effects
                projected_stars[star_n] = proj_star
            projected_card["stars"] = projected_stars
            out_cards[card_id] = projected_card
        out[theme] = out_cards
    return out


# ═══════════════════════════════════════════════════════════════════
# Validators (reuse from v1 codegen, fed the projected v1 layout)
# ═══════════════════════════════════════════════════════════════════

## Guard: a theme card (druid/military/predator/steampunk) that uses an
## action outside CARD_DB_ACTIONS MUST declare `impl: theme_system`. Otherwise
## chain_engine dispatches to _execute_actions (card_db path) which cannot
## handle theme actions — silent drop with no runtime error.
## Backlog #4 (Phase 2 이월) resolution.
def validate_impl_theme_system(all_cards: dict) -> list[str]:
    errors: list[str] = []
    theme_themes = {"druid", "military", "predator", "steampunk"}
    for theme, cards in all_cards.items():
        if theme not in theme_themes:
            continue
        for card_id, card in cards.items():
            impl = card.get("impl", "card_db")
            if impl == "theme_system":
                continue
            for star_n, star in card.get("stars", {}).items():
                for block in star.get("effects", []):
                    if not isinstance(block, dict):
                        continue
                    for key in block:
                        if key in BLOCK_META_KEYS:
                            continue
                        if key not in CARD_DB_ACTIONS:
                            errors.append(
                                f"{card_id} ★{star_n}: action '{key}' not in "
                                f"CARD_DB_ACTIONS, but impl='card_db' (default). "
                                f"Add 'impl: theme_system' to the card, or use a "
                                f"built-in action from: {sorted(CARD_DB_ACTIONS)}"
                            )
    return errors


## Guard: scalar-valued actions (e.g. `gold: 3`, `terazin: 2`) in a
## NON-PRIMARY block cannot carry `timing_override`, so their description
## would mis-render under the primary timing. Require dict form in that case.
## Backlog #10 (Phase 2 이월) resolution.
def validate_multiblock_scalar_actions(all_cards: dict) -> list[str]:
    errors: list[str] = []
    for theme, cards in all_cards.items():
        for card_id, card in cards.items():
            for star_n, star in card.get("stars", {}).items():
                blocks = star.get("effects", []) or []
                if len(blocks) < 2:
                    continue
                primary_timing = blocks[0].get("trigger_timing")
                for block in blocks[1:]:
                    block_timing = block.get("trigger_timing")
                    if block_timing == primary_timing:
                        continue  # same timing: scalar desc renders correctly
                    for key, val in block.items():
                        if key in BLOCK_META_KEYS:
                            continue
                        if not isinstance(val, (dict, list)):
                            errors.append(
                                f"{card_id} ★{star_n}: scalar action "
                                f"'{key}: {val}' lives in a non-primary block "
                                f"({block_timing}). Scalar actions cannot carry "
                                f"timing_override — use dict form: "
                                f"'{key}: {{value: {val}}}' or move to the "
                                f"primary block."
                            )
    return errors


## Guard: `impl: theme_system` cards must not set `is_threshold: true`.
## chain_engine flips `card.threshold_fired` around the dispatch arm
## (before the theme_system branch is entered), so the handler has no
## visibility into threshold state. Expressing one-shot threshold-like
## behaviour must be done via theme_state keys inside the handler.
## Backlog #7 (Phase 2 이월) resolution.
def validate_is_threshold_with_theme_system(all_cards: dict) -> list[str]:
    errors: list[str] = []
    for _theme, cards in all_cards.items():
        for cid, card in cards.items():
            if card.get("impl", "card_db") != "theme_system":
                continue
            # card-level is_threshold (v1 compat field)
            if card.get("is_threshold"):
                errors.append(
                    f"{cid}: is_threshold=true with impl=theme_system — "
                    f"chain_engine flips threshold_fired before the "
                    f"theme_system arm; the handler has no visibility. "
                    f"Use theme_state instead."
                )
            # block-level is_threshold (v2 canonical location)
            for star, sd in (card.get("stars") or {}).items():
                for block in sd.get("effects", []) or []:
                    if not isinstance(block, dict):
                        continue
                    if block.get("is_threshold"):
                        errors.append(
                            f"{cid} ★{star}: is_threshold=true in a block "
                            f"with impl=theme_system (same structural "
                            f"issue — handler cannot see threshold_fired)."
                        )
    return errors


## Guard: YAML-level `retrigger` action is blocked until chain_engine
## covers theme_system routing. chain_engine._execute_actions implements
## retrigger by re-reading template["effects"] on the target card; that
## array is empty for impl=theme_system targets, so the retrigger silently
## does nothing. No card currently ships this action; this validator is
## preventive. Walk all blocks + conditional/r_conditional/post_threshold.
## Backlog #3 (Phase 2 이월) resolution.
def validate_no_retrigger(all_cards: dict) -> list[str]:
    errors: list[str] = []

    def walk_block_actions(cid: str, star: int, ctx: str, block: dict) -> None:
        """Walk action keys in a v2 block dict."""
        for key, val in block.items():
            if key in BLOCK_META_KEYS:
                continue
            if key == "retrigger":
                errors.append(
                    f"{cid} ★{star} ({ctx}): 'retrigger' action is not "
                    f"ready for YAML use — chain_engine silently drops "
                    f"retrigger when the target is theme_system-dispatched. "
                    f"Close backlog #3 before re-enabling."
                )
            # dict-valued action may have nested `effects` list (e.g. on_combat_result)
            params_list = val if isinstance(val, list) else [val]
            for p in params_list:
                if isinstance(p, dict) and isinstance(p.get("effects"), list):
                    for nested_block in p["effects"]:
                        if isinstance(nested_block, dict):
                            walk_block_actions(cid, star, f"{ctx}→{key}.effects", nested_block)

    def walk_cond_list(cid: str, star: int, ctx: str, conds: list) -> None:
        """Walk actions inside depth-reduced conditional / r_conditional entries."""
        for entry in conds or []:
            if not isinstance(entry, dict):
                continue
            # Entry shape is {when, ...actions} — extract actions as pseudo-block.
            actions_only = {k: v for k, v in entry.items() if k != "when"}
            walk_block_actions(cid, star, ctx, actions_only)

    def walk_post_threshold(cid: str, star: int, pt: Any) -> None:
        """post_threshold is now a single dict-of-actions."""
        if isinstance(pt, dict):
            walk_block_actions(cid, star, "post_threshold", pt)
        elif isinstance(pt, list):
            # idempotent: old flat-list shape
            for blk in pt:
                if isinstance(blk, dict):
                    walk_block_actions(cid, star, "post_threshold", blk)

    for _theme, cards in all_cards.items():
        for cid, card in cards.items():
            for star, sd in (card.get("stars") or {}).items():
                for block in sd.get("effects", []) or []:
                    if not isinstance(block, dict):
                        continue
                    walk_block_actions(cid, star, "effects", block)
                    walk_cond_list(cid, star, "conditional", block.get("conditional"))
                    walk_cond_list(cid, star, "r_conditional", block.get("r_conditional"))
                    walk_post_threshold(cid, star, block.get("post_threshold"))
    return errors


## Guard: after the conditional-depth migration (2026-04-21), conditional /
## r_conditional entries use {when, ...actions} shape and post_threshold is a
## dict-of-actions. A stray `effects:` key would mean an old v1-shape that
## this codegen expects to have been migrated away. Reject it so stale YAML
## never reaches downstream emission quietly.
def validate_conditional_effects_key_removed(all_cards: dict) -> list[str]:
    errors: list[str] = []
    for _theme, cards in all_cards.items():
        for card_id, card in cards.items():
            for star_n, star in (card.get("stars") or {}).items():
                for block_idx, block in enumerate(star.get("effects", []) or []):
                    if not isinstance(block, dict):
                        continue
                    for f in ("conditional", "r_conditional"):
                        for entry_idx, entry in enumerate(block.get(f, []) or []):
                            if isinstance(entry, dict) and "effects" in entry:
                                errors.append(
                                    f"{card_id} ★{star_n} block[{block_idx}] "
                                    f"{f}[{entry_idx}]: legacy 'effects:' key "
                                    f"found. Migrate to depth-reduced "
                                    f"{{when, ...actions}} shape."
                                )
                    pt = block.get("post_threshold")
                    if isinstance(pt, list):
                        errors.append(
                            f"{card_id} ★{star_n} block[{block_idx}] "
                            f"post_threshold: legacy list form. Migrate to "
                            f"dict-of-actions."
                        )
    return errors


## Guard: non-primary blocks of a multi-block card cannot carry
## conditional / r_conditional / post_threshold. _project_to_desc_gen_input
## only lifts those fields from the primary (first) block, so anything in
## later blocks is silently dropped from the card description.
## Backlog #11 resolution.
def validate_multiblock_nonprimary_conditional(all_cards: dict) -> list[str]:
    errors: list[str] = []
    forbidden = ("conditional", "r_conditional", "post_threshold")
    for _theme, cards in all_cards.items():
        for card_id, card in cards.items():
            for star_n, star in (card.get("stars") or {}).items():
                blocks = star.get("effects", []) or []
                if len(blocks) < 2:
                    continue
                for block_idx, block in enumerate(blocks[1:], start=1):
                    if not isinstance(block, dict):
                        continue
                    for key in forbidden:
                        if key in block:
                            errors.append(
                                f"{card_id} ★{star_n}: non-primary block #{block_idx} "
                                f"(trigger_timing={block.get('trigger_timing')!r}) "
                                f"has '{key}' — desc_gen only projects this from the "
                                f"primary (first) block. Move it to the primary block, "
                                f"or restructure so the block carrying '{key}' is first."
                            )
    return errors


## Guard: a card's representative timing (first block's trigger_timing)
## must be identical across ★1/★2/★3. The flat hoist in _c() copies the
## first block's metadata to template top-level; if that changes between
## stars, legacy readers (sim AI evaluator, UI) see the timing flip on ★↑
## with no visible trigger.
## Backlog #12 resolution.
def validate_multiblock_primary_timing_consistency(all_cards: dict) -> list[str]:
    # Only applies to cards that have a multi-block star — single-block
    # cards are free to change their sole timing across ★ (legitimate
    # star-level timing override, e.g. ne_merchant PCD→PC at ★3).
    errors: list[str] = []
    for _theme, cards in all_cards.items():
        for card_id, card in cards.items():
            stars = card.get("stars") or {}
            is_multiblock = any(
                len(star.get("effects", []) or []) >= 2
                for star in stars.values()
            )
            if not is_multiblock:
                continue
            timing_by_star: dict[int, str] = {}
            for star_n, star in stars.items():
                blocks = star.get("effects", []) or []
                if not blocks:
                    continue
                first_timing = blocks[0].get("trigger_timing")
                if first_timing is not None:
                    timing_by_star[star_n] = first_timing
            distinct = set(timing_by_star.values())
            if len(distinct) > 1:
                stars_list = ", ".join(
                    f"★{s}={timing_by_star[s]}" for s in sorted(timing_by_star)
                )
                errors.append(
                    f"{card_id}: multi-block card's primary (first block) "
                    f"trigger_timing differs across stars — {stars_list}. "
                    f"Keep block ordering consistent so flat-hoist accessors "
                    f"don't flip between ★."
                )
    return errors


def run_validators(all_cards: dict) -> None:
    projected = _project_to_desc_gen_input(all_cards)
    ec_errors = validate_conscript_enhanced_count(projected)
    if ec_errors:
        print("❌ conscript.enhanced_count violations:")
        for e in ec_errors:
            print(f"  - {e}")
        sys.exit(2)
    parity_errors = validate_r_conditional_star_parity(projected)
    if parity_errors:
        print("❌ r_conditional ★ parity violations:")
        for e in parity_errors:
            print(f"  - {e}")
        sys.exit(2)
    impl_errors = validate_impl_theme_system(all_cards)
    if impl_errors:
        print("❌ impl: theme_system flag violations:")
        for e in impl_errors:
            print(f"  - {e}")
        sys.exit(2)
    scalar_errors = validate_multiblock_scalar_actions(all_cards)
    if scalar_errors:
        print("❌ multi-block scalar action violations:")
        for e in scalar_errors:
            print(f"  - {e}")
        sys.exit(2)
    thresh_errors = validate_is_threshold_with_theme_system(all_cards)
    if thresh_errors:
        print("❌ is_threshold + theme_system violations:")
        for e in thresh_errors:
            print(f"  - {e}")
        sys.exit(2)
    rt_errors = validate_no_retrigger(all_cards)
    if rt_errors:
        print("❌ retrigger action not ready for YAML use:")
        for e in rt_errors:
            print(f"  - {e}")
        sys.exit(2)
    legacy_cond_errors = validate_conditional_effects_key_removed(all_cards)
    if legacy_cond_errors:
        print("❌ legacy 'effects:' key in conditional / post_threshold (depth should be reduced):")
        for e in legacy_cond_errors:
            print(f"  - {e}")
        sys.exit(2)
    nonprimary_cond_errors = validate_multiblock_nonprimary_conditional(all_cards)
    if nonprimary_cond_errors:
        print("❌ multi-block non-primary block carries conditional-family:")
        for e in nonprimary_cond_errors:
            print(f"  - {e}")
        sys.exit(2)
    primary_timing_errors = validate_multiblock_primary_timing_consistency(all_cards)
    if primary_timing_errors:
        print("❌ multi-block primary timing flips across ★:")
        for e in primary_timing_errors:
            print(f"  - {e}")
        sys.exit(2)


# ═══════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════

def _check_file(output_path: Path, generated: str, label: str) -> bool:
    """Return True if the current file matches the generated content."""
    if not output_path.exists():
        print(f"ERROR: {output_path} does not exist")
        return False
    current = output_path.read_text()
    if current == generated:
        return True
    import difflib
    print(f"❌ MISMATCH: {label} differs from YAML")
    print(f"   Run: python3 scripts/codegen_card_db.py")
    diff_lines = list(difflib.unified_diff(
        current.splitlines(keepends=True),
        generated.splitlines(keepends=True),
        fromfile=f"{label} (current)", tofile=f"{label} (from YAML)", n=2,
    ))
    MAX = 60
    for line in diff_lines[:MAX]:
        print(line, end="")
    if len(diff_lines) > MAX:
        print(f"\n  ... ({len(diff_lines) - MAX} more diff lines)")
    return False


def main() -> None:
    check_mode = "--check" in sys.argv

    all_cards = load_cards()
    if not all_cards:
        print("ERROR: no YAML files loaded")
        sys.exit(1)

    run_validators(all_cards)

    card_db_src = generate_card_db(all_cards)
    projected = _project_to_desc_gen_input(all_cards)
    descs = generate_all_descs(projected)
    descs_src = generate_descs_gd(projected, descs)

    total = sum(len(c) for c in all_cards.values())

    if check_mode:
        ok_db = _check_file(OUTPUT_DB, card_db_src, "card_db.gd")
        ok_descs = _check_file(OUTPUT_DESCS, descs_src, "card_descs.gd")
        if ok_db and ok_descs:
            print(f"✅ card_db.gd + card_descs.gd match YAML ({total} cards)")
            sys.exit(0)
        sys.exit(1)

    _write_file(OUTPUT_DB, card_db_src)
    _write_file(OUTPUT_DESCS, descs_src)
    print(f"Generated {total} cards (v2 block format)")
    print(f"  → {OUTPUT_DB}")
    print(f"  → {OUTPUT_DESCS}")


if __name__ == "__main__":
    main()
