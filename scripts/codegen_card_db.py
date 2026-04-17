#!/usr/bin/env python3
"""
codegen_card_db.py — Generate card_db.gd from YAML card definitions.

Usage:
    python3 scripts/codegen_card_db.py          # Generate card_db.gd
    python3 scripts/codegen_card_db.py --check   # Verify generated == current
"""

from __future__ import annotations

import sys
import yaml
from pathlib import Path
from typing import Any, Optional

ROOT = Path(__file__).resolve().parent.parent
CARDS_DIR = ROOT / "data" / "cards"
OUTPUT = ROOT / "godot" / "core" / "data" / "card_db.gd"
OUTPUT_DESCS = ROOT / "godot" / "core" / "data" / "card_descs.gd"

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


def gen_effect(effect: dict) -> str:
    """Convert a single YAML effect to a GDScript expression string."""
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
        # Theme-specific effect (tree_add, hatch, etc.)
        # Phase 2: these will be stored in effects array for theme_system
        # Phase 1: theme_system cards have impl: theme_system, effects ignored
        return _gen_raw_dict({"action": action, **params})


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


# ═══════════════════════════════════════════════════════════════════
# Conditional / post-threshold generation
# ═══════════════════════════════════════════════════════════════════

def gen_conditional(cond_list: list) -> str:
    """Generate conditional_effects array."""
    items = []
    for cond in cond_list:
        when = cond["when"]
        cond_type = next(iter(when))
        threshold = when[cond_type]
        effects_code = [gen_effect(e) for e in cond["effects"]]
        items.append(
            f'{{"condition": "{cond_type}", "threshold": {threshold},\n'
            f'\t\t\t\t\t "effects": [{", ".join(effects_code)}]}}'
        )
    return "[\n\t\t\t\t\t" + ",\n\t\t\t\t\t".join(items) + ",\n\t\t\t\t]"


def gen_post_threshold(effects: list) -> str:
    """Generate post_threshold_effects array."""
    parts = [gen_effect(e) for e in effects]
    return f'[{", ".join(parts)}]'


# ═══════════════════════════════════════════════════════════════════
# Effects array generation
# ═══════════════════════════════════════════════════════════════════

THEME_EFFECTS = {
    "tree_add", "tree_absorb", "tree_breed", "tree_enhance", "tree_shield",
    "tree_distribute", "multiply_stats", "debuff_store",
    "hatch", "meta_consume", "hatch_scaled", "on_combat_result",
    "train", "conscript", "rank_threshold", "rank_buff", "swarm_buff",
    "counter_produce", "range_bonus", "economy",
    # Additional theme effect types used by sub-agents
    "tree_gold", "druid_unit_enhance", "tree_temp_buff", "epic_shop_unlock",
    "persistent", "revive", "rare_counter", "epic_counter", "total_counter", "on_merge",
    "upgrade_discount", "hatch_enhance", "battle_buff", "free_reroll", "revive_override",
    # Military R4/R10 재설계 (2026-04-16, trace 012)
    "enhance_convert_card", "enhance_convert_target", "spawn_enhanced_random",
    "spawn_unit", "crit_buff", "crit_splash", "rank_buff_hp",
    "upgrade_shop_bonus", "conscript_pool_tier", "lifesteal",
    "high_rank_mult", "grant_gold", "grant_terazin", "revive_scope_override",
    "buff",  # 일반 버프 (as_bonus 등)
}


def _convert_nested_effects(params: dict) -> dict:
    """Recursively convert nested YAML effect structures to clean dicts.
    Handles 'effects' sub-arrays (e.g., on_combat_result.effects)."""
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


def gen_theme_effect_gd(effect: dict) -> str:
    """Convert a single YAML theme effect to GDScript dict literal."""
    action = next(iter(effect))
    params = effect[action]
    if isinstance(params, dict):
        d = {"action": action, **_convert_nested_effects(params)}
    else:
        # Simple value (e.g., gold: 3)
        d = {"action": action, "value": params}
    return _gen_raw_dict(d)


def gen_theme_effects_block(card_id: str, card: dict, indent: str = "\t") -> list[str]:
    """Generate _theme_effects[card_id] = {1: [...], 2: [...], 3: [...]} block."""
    lines = [f'{indent}_theme_effects["{card_id}"] = {{']
    for star in [1, 2, 3]:
        star_data = card["stars"][star]
        effects = star_data.get("effects", [])
        # Include ALL effects (theme + any conditionals)
        effect_parts = [gen_theme_effect_gd(e) for e in effects]

        # Add conditional effects if present
        for cond in star_data.get("conditional", []):
            when = cond["when"]
            cond_type = next(iter(when))
            threshold = when[cond_type]
            cond_effects = [gen_theme_effect_gd(e) for e in cond["effects"]]
            cond_dict = (f'{{"action": "conditional", "condition": "{cond_type}", '
                         f'"threshold": {threshold}, '
                         f'"effects": [{", ".join(cond_effects)}]}}')
            effect_parts.append(cond_dict)

        # Rank-milestone conditional effects (R4/R10, Military 재설계 trace 012).
        # 런타임 차이: `conditional`은 매 실행마다 조건 체크, `r_conditional`은
        # rank가 milestone(4 or 10)에 처음 도달할 때 one-shot 발동.
        for cond in star_data.get("r_conditional", []):
            when = cond["when"]
            cond_type = next(iter(when))
            threshold = when[cond_type]
            cond_effects = [gen_theme_effect_gd(e) for e in cond["effects"]]
            cond_dict = (f'{{"action": "r_conditional", "condition": "{cond_type}", '
                         f'"threshold": {threshold}, '
                         f'"effects": [{", ".join(cond_effects)}]}}')
            effect_parts.append(cond_dict)

        if not effect_parts:
            lines.append(f'{indent}\t{star}: [],')
        elif len(effect_parts) == 1 and len(effect_parts[0]) < 70:
            lines.append(f'{indent}\t{star}: [{effect_parts[0]}],')
        else:
            lines.append(f'{indent}\t{star}: [')
            for i, ep in enumerate(effect_parts):
                comma = "," if i < len(effect_parts) - 1 else ","
                lines.append(f'{indent}\t\t{ep}{comma}')
            lines.append(f'{indent}\t],')
    lines.append(f'{indent}}}')
    return lines


def is_theme_effect(effect: dict) -> bool:
    """Check if effect uses theme DSL (not directly expressible in card_db)."""
    action = next(iter(effect))
    return action in THEME_EFFECTS


def gen_effects_array(effects: list, indent: str = "\t\t") -> str:
    """Generate GDScript effects array. Filters out theme effects for now."""
    # Phase 1: theme effects become [] in card_db.gd
    card_db_effects = [e for e in effects if not is_theme_effect(e)]
    if not card_db_effects:
        return "[]"
    parts = [gen_effect(e) for e in card_db_effects]
    if len(parts) == 1 and len(parts[0]) < 80:
        return f"[{parts[0]}]"
    sep = f",\n{indent}\t "
    return f"[{parts[0]}{sep}{sep.join(parts[1:])}]" if len(parts) > 1 else f"[{parts[0]}]"


# ═══════════════════════════════════════════════════════════════════
# Star override detection and generation
# ═══════════════════════════════════════════════════════════════════

def star_data_differs(star1: dict, star_n: dict, impl: str) -> bool:
    """Check if ★N functionally differs from ★1."""
    if star1.get("max_act") != star_n.get("max_act"):
        return True
    if star_n.get("timing") is not None:
        return True
    if star_n.get("conditional") and not star1.get("conditional"):
        return True
    if star_n.get("post_threshold") and not star1.get("post_threshold"):
        return True
    if star_n.get("require_tenure") != star1.get("require_tenure"):
        return True
    if star_n.get("is_threshold") != star1.get("is_threshold"):
        return True

    # Compare effects (serialize for comparison)
    e1 = star1.get("effects", [])
    en = star_n.get("effects", [])
    if impl == "theme_system":
        # For theme_system, card_db effects are always [] — only non-effect fields matter
        # Effect differences are handled by theme_system.gd, not card_db.gd
        return False
    return str(e1) != str(en)


def gen_star_override(card: dict, star_n: dict, star_level: int, indent: str) -> str:
    """Generate a star override entry (using _star() or inline dict)."""
    name = f'{card["name"]} ★{star_level}'
    impl = card.get("impl", "card_db")
    timing_gd = TIMING_MAP[star_n.get("timing", card["timing"])]
    max_act = star_n["max_act"]
    tags_var = f'{card["_var_prefix"]}_tags'
    comp_var = f'{card["_var_prefix"]}_comp'

    # Determine effects
    effects = star_n.get("effects", [])
    if impl == "theme_system":
        effects_code = "[]"
    else:
        effects_code = gen_effects_array(effects, indent + "\t")

    # Listen layers
    listen = card.get("listen", {})
    l1_gd = gen_layer(listen.get("l1"), LAYER1_MAP)
    l2_gd = gen_layer(listen.get("l2"), LAYER2_MAP)

    # Flags from star or card level
    req_other = star_n.get("require_other", card.get("require_other", False))
    req_tenure = star_n.get("require_tenure", card.get("require_tenure", 0))
    is_thresh = star_n.get("is_threshold", card.get("is_threshold", False))

    has_conditional = bool(star_n.get("conditional")) and impl != "theme_system"
    has_post_threshold = bool(star_n.get("post_threshold")) and impl != "theme_system"

    if has_conditional or has_post_threshold:
        # Must use inline dict (not _star)
        lines = [f'{indent}{star_level}: {{']
        lines.append(f'{indent}\t"name": "{name}",')
        lines.append(f'{indent}\t"composition": {comp_var},')
        lines.append(f'{indent}\t"trigger_timing": {timing_gd}, "max_activations": {max_act},')
        lines.append(f'{indent}\t"effects": {effects_code},')
        lines.append(f'{indent}\t"card_tags": {tags_var},')
        lines.append(f'{indent}\t"trigger_layer1": {l1_gd}, "trigger_layer2": {l2_gd},')
        lines.append(f'{indent}\t"require_other_card": {"true" if req_other else "false"}, '
                      f'"require_tenure": {req_tenure},')
        lines.append(f'{indent}\t"is_threshold": {"true" if is_thresh else "false"},')
        if has_conditional:
            cond_code = gen_conditional(star_n["conditional"])
            lines.append(f'{indent}\t"conditional_effects": {cond_code},')
        if has_post_threshold:
            pt_code = gen_post_threshold(star_n["post_threshold"])
            lines.append(f'{indent}\t"post_threshold_effects": {pt_code},')
        lines.append(f'{indent}}},')
        return "\n".join(lines)
    else:
        # Use _star() helper
        args = [f'"{name}"', comp_var, timing_gd, str(max_act)]
        args.append(effects_code)
        args.append(tags_var)

        # Optional args: only include if non-default
        has_optional = (l1_gd != "-1" or l2_gd != "-1" or req_other
                        or req_tenure != 0 or is_thresh)
        if has_optional:
            args.append(l1_gd)
            args.append(l2_gd)
            if req_other or req_tenure != 0 or is_thresh:
                args.append("true" if req_other else "false")
                if req_tenure != 0 or is_thresh:
                    args.append(str(req_tenure))
                    if is_thresh:
                        args.append("true")

        call = f'_star({", ".join(args)})'
        return f'{indent}{star_level}: {call},'


# ═══════════════════════════════════════════════════════════════════
# Card registration generation
# ═══════════════════════════════════════════════════════════════════

def make_var_prefix(card_id: str) -> str:
    """Generate a short variable prefix from card_id."""
    # sp_assembly → asm, ne_earth_echo → ee, etc.
    # Use last part's first 2-3 chars for uniqueness
    parts = card_id.split("_")
    if len(parts) <= 2:
        return parts[-1][:3]
    return "".join(p[0] for p in parts[1:])


def gen_card_registration(card_id: str, card: dict) -> list[str]:
    """Generate _c() call and supporting variable declarations for one card."""
    lines = []
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

    # Timing
    timing_gd = TIMING_MAP[card["timing"]]

    # ★1 data
    star1 = card["stars"][1]
    max_act = star1["max_act"]

    # Effects
    effects = star1.get("effects", [])
    if impl == "theme_system":
        effects_code = "[]"
    else:
        effects_code = gen_effects_array(effects, "\t\t")

    # Listen layers
    listen = card.get("listen", {})
    l1_gd = gen_layer(listen.get("l1"), LAYER1_MAP)
    l2_gd = gen_layer(listen.get("l2"), LAYER2_MAP)

    # Flags
    req_other = card.get("require_other", False)
    req_tenure = card.get("require_tenure", 0)
    is_thresh = card.get("is_threshold", False)

    # Star overrides — always generate (name always differs: "X ★2", "X ★3")
    has_overrides = True
    override_lines = []
    for star in [2, 3]:
        star_n = card["stars"][star]
        override_lines.append(gen_star_override(card, star_n, star, "\t\t\t"))

    # Build _c() call
    c_args = [f'"{card_id}"', f'"{card["name"]}"', str(card["tier"]),
              "T"]  # T is the local theme variable
    c_args_line2 = [f"{prefix}_comp", timing_gd, str(max_act)]
    c_args_line3 = [effects_code]
    c_args_line4 = [f"{prefix}_tags"]

    # Optional positional args
    has_optional = (l1_gd != "-1" or l2_gd != "-1" or req_other
                    or req_tenure != 0 or is_thresh or has_overrides)
    if has_optional:
        c_args_line4.append(l1_gd)
        c_args_line4.append(l2_gd)
        if req_other or req_tenure != 0 or is_thresh or has_overrides:
            c_args_line4.append("true" if req_other else "false")
            c_args_line4.append(str(req_tenure))
            c_args_line4.append("true" if is_thresh else "false")

    if has_overrides:
        c_args_line4.append("{")

    lines.append(f'\t_c({", ".join(c_args)},')
    lines.append(f'\t\t{", ".join(c_args_line2)},')
    lines.append(f'\t\t{", ".join(c_args_line3)},')

    if has_overrides:
        lines.append(f'\t\t{", ".join(c_args_line4)}')
        for ol in override_lines:
            lines.append(ol)
        lines.append("\t\t})")
    else:
        last = ", ".join(c_args_line4)
        lines.append(f'\t\t{last})')

    # Theme effects block for theme_system cards
    if impl == "theme_system":
        lines.extend(gen_theme_effects_block(card_id, card))

    return lines


def gen_register_function(theme: str, cards: dict) -> list[str]:
    """Generate _register_{theme}() function."""
    lines = []
    func_name = f"_register_{theme}"

    # Comment header
    lines.append("")
    lines.append("")
    lines.append(f"# {'═' * 67}")
    lines.append(f"# {theme.upper()} ({len(cards)} cards)")
    lines.append(f"# {'═' * 67}")
    lines.append(f"func {func_name}() -> void:")
    lines.append(f"\tvar T := {THEME_MAP[theme]}")

    # Collect used enums across all cards in this theme
    used_timings: set[str] = set()
    used_l1: set[str] = set()
    used_l2: set[str] = set()
    for card in cards.values():
        used_timings.add(card["timing"])
        listen = card.get("listen", {})
        if listen.get("l1"):
            used_l1.add(listen["l1"])
        if listen.get("l2"):
            used_l2.add(listen["l2"])
        # Also scan effects for output layers
        for star_data in card.get("stars", {}).values():
            for eff in star_data.get("effects", []):
                action = next(iter(eff))
                p = eff[action]
                if isinstance(p, dict):
                    if p.get("ol1") and p["ol1"] != "null":
                        used_l1.add(p["ol1"])
                    if p.get("ol2") and p["ol2"] != "null":
                        used_l2.add(p["ol2"])

    # Declare local timing/layer variables (matching current code style)
    _TIMING_SHORT = {
        "RS": "ROUND_START", "OE": "ON_EVENT", "BS": "BATTLE_START",
        "CA": "ON_COMBAT_ATTACK", "PC": "POST_COMBAT",
        "PCD": "POST_COMBAT_DEFEAT", "PCV": "POST_COMBAT_VICTORY",
        "REROLL": "ON_REROLL", "MERGE": "ON_MERGE", "SELL": "ON_SELL",
        "DEATH": "ON_COMBAT_DEATH", "PERSISTENT": "PERSISTENT",
    }
    _L1_SHORT = {"UA": "UNIT_ADDED", "EN": "ENHANCED"}
    _L2_SHORT = {
        "MF": "MANUFACTURE", "UP": "UPGRADE", "TG": "TREE_GROW",
        "BR": "BREED", "HA": "HATCH", "MT": "METAMORPHOSIS",
        "TR": "TRAIN", "CO": "CONSCRIPT",
    }

    local_vars: dict[str, str] = {}  # full_enum_path → short_name
    for short in sorted(used_timings):
        if short in _TIMING_SHORT:
            full = f"Enums.TriggerTiming.{_TIMING_SHORT[short]}"
            lines.append(f"\tvar {short} := {full}")
            local_vars[full] = short
    for short in sorted(used_l1):
        if short in _L1_SHORT:
            full = f"Enums.Layer1.{_L1_SHORT[short]}"
            lines.append(f"\tvar {short} := {full}")
            local_vars[full] = short
    for short in sorted(used_l2):
        if short in _L2_SHORT:
            full = f"Enums.Layer2.{_L2_SHORT[short]}"
            lines.append(f"\tvar {short} := {full}")
            local_vars[full] = short

    # Assign var prefixes and check for collisions
    prefixes_used: dict[str, str] = {}
    for card_id, card in cards.items():
        prefix = make_var_prefix(card_id)
        # Handle collisions by appending chars
        base = prefix
        i = 2
        while prefix in prefixes_used and prefixes_used[prefix] != card_id:
            prefix = base + str(i)
            i += 1
        prefixes_used[prefix] = card_id
        card["_var_prefix"] = prefix

    # Generate each card (raw, with full enum paths)
    all_card_lines: list[str] = []
    first = True
    for card_id, card in cards.items():
        if not first:
            all_card_lines.append("")
        first = False
        all_card_lines.extend(gen_card_registration(card_id, card))

    # 2nd pass: scan generated lines for any remaining Enums.* references
    # and declare local vars for them
    _ALL_ENUMS = {}
    for short, full in TIMING_MAP.items():
        _ALL_ENUMS[full] = short
    for short, full in LAYER1_MAP.items():
        _ALL_ENUMS[full] = short
    for short, full in LAYER2_MAP.items():
        _ALL_ENUMS[full] = short

    joined = "\n".join(all_card_lines)
    extra_vars: list[str] = []
    for full_path, short_name in _ALL_ENUMS.items():
        if full_path in joined and full_path not in local_vars:
            local_vars[full_path] = short_name
            extra_vars.append(f"\tvar {short_name} := {full_path}")
    if extra_vars:
        # Insert extra var declarations after existing ones
        # Find insertion point (after last var T/timing/layer line)
        insert_idx = len(lines)
        for i in range(len(lines) - 1, -1, -1):
            if lines[i].startswith("\tvar "):
                insert_idx = i + 1
                break
        for ev in sorted(extra_vars):
            lines.insert(insert_idx, ev)
            insert_idx += 1

    # Replace full enum paths with local variable names
    for i, line in enumerate(all_card_lines):
        for full_path, short_name in local_vars.items():
            line = line.replace(full_path, short_name)
        all_card_lines[i] = line

    lines.extend(all_card_lines)

    return lines


# ═══════════════════════════════════════════════════════════════════
# Static file sections
# ═══════════════════════════════════════════════════════════════════

HEADER = '''\
# AUTO-GENERATED from data/cards/*.yaml — DO NOT EDIT
# Run: python3 scripts/codegen_card_db.py
extends Node
## Card database. Autoloaded as "CardDB".

var _templates: Dictionary = {}
var _theme_effects: Dictionary = {}  # card_id → {star_level → Array of effect dicts}
var _tier_cost := {1: 2, 2: 3, 3: 4, 4: 5, 5: 6}
'''

def gen_ready(themes: list[str]) -> str:
    calls = "\n".join(f"\t_register_{t}()" for t in themes)
    return f'''
func _ready() -> void:
{calls}
\tprint("[CardDB] Registered %d cards." % _templates.size())
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


## Theme system cards: per-star effect parameters from YAML DSL.
## Returns Array of dicts, each with "action" key + parameters.
func get_theme_effects(card_id: String, star_level: int) -> Array:
\tvar card_data: Dictionary = _theme_effects.get(card_id, {})
\treturn card_data.get(star_level, [])
'''

HELPER_FUNCTIONS = '''
## Compact card registration.
## effects: Array of Dicts, each with {action, target, ...params}
func _c(id: String, nm: String, tier: int, theme: int,
\t\tcomp: Array, timing: int, max_act: int,
\t\teffects: Array, tags: PackedStringArray,
\t\tl1: int = -1, l2: int = -1,
\t\trequire_other: bool = false, require_tenure: int = 0,
\t\tis_threshold: bool = false,
\t\tstar_overrides: Dictionary = {}) -> void:
\t_templates[id] = {
\t\t"id": id, "name": nm, "tier": tier, "theme": theme,
\t\t"composition": comp,
\t\t"trigger_timing": timing,
\t\t"trigger_layer1": l1, "trigger_layer2": l2,
\t\t"require_other_card": require_other,
\t\t"require_tenure": require_tenure,
\t\t"is_threshold": is_threshold,
\t\t"max_activations": max_act,
\t\t"effects": effects,
\t\t"cost": _tier_cost.get(tier, 3),
\t\t"card_tags": tags,
\t\t"star_overrides": star_overrides,
\t}


## Star override dict builder.
func _star(nm: String, comp: Array, timing: int, max_act: int,
\t\teffects: Array, tags: PackedStringArray,
\t\tl1: int = -1, l2: int = -1,
\t\trequire_other: bool = false, require_tenure: int = 0,
\t\tis_threshold: bool = false) -> Dictionary:
\treturn {
\t\t"name": nm, "composition": comp,
\t\t"trigger_timing": timing, "max_activations": max_act,
\t\t"effects": effects, "card_tags": tags,
\t\t"trigger_layer1": l1, "trigger_layer2": l2,
\t\t"require_other_card": require_other,
\t\t"require_tenure": require_tenure,
\t\t"is_threshold": is_threshold,
\t}


# --- Effect helpers ---
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


# ═══════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════

def load_all_cards() -> dict[str, dict]:
    """Load all YAML card files, return {theme: {card_id: card_data}}."""
    all_cards = {}
    for theme in THEME_ORDER:
        path = CARDS_DIR / f"{theme}.yaml"
        if not path.exists():
            print(f"WARNING: {path} not found, skipping {theme}")
            continue
        with open(path) as f:
            data = yaml.safe_load(f)
        if data and "cards" in data:
            # Convert star keys from int to int (YAML may parse as int already)
            cards = data["cards"]
            for card_id, card in cards.items():
                if "stars" in card:
                    card["stars"] = {int(k): v for k, v in card["stars"].items()}
            all_cards[theme] = cards
    return all_cards


def generate(all_cards: dict[str, dict]) -> str:
    """Generate the full card_db.gd content."""
    present_themes = [t for t in THEME_ORDER if t in all_cards]

    parts = [HEADER]
    parts.append(gen_ready(present_themes))
    parts.append(API_FUNCTIONS)
    parts.append(HELPER_FUNCTIONS)

    for theme in present_themes:
        register_lines = gen_register_function(theme, all_cards[theme])
        parts.append("\n".join(register_lines))

    parts.append("")  # Trailing newline
    return "\n".join(parts)


def _check_file(output_path: Path, generated: str, label: str) -> bool:
    """Check if generated content matches current file. Returns True if OK."""
    if not output_path.exists():
        print(f"ERROR: {output_path} does not exist")
        return False
    current = output_path.read_text()
    if current == generated:
        return True
    import difflib
    print(f"❌ MISMATCH: {label} differs from YAML")
    print(f"   {label} is a generated file — edit YAML, then run:")
    print(f"   python3 scripts/codegen_card_db.py")
    print()
    cur_lines = current.splitlines(keepends=True)
    gen_lines = generated.splitlines(keepends=True)
    diff = difflib.unified_diff(
        cur_lines, gen_lines,
        fromfile=f"{label} (current)",
        tofile=f"{label} (from YAML)",
        n=2,
    )
    diff_lines = list(diff)
    MAX_DIFF_LINES = 60
    for line in diff_lines[:MAX_DIFF_LINES]:
        print(line, end="")
    if len(diff_lines) > MAX_DIFF_LINES:
        print(f"\n  ... ({len(diff_lines) - MAX_DIFF_LINES} more diff lines)")
    return False


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
                    text = d[star].replace('"', '\\"')
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


def main():
    check_mode = "--check" in sys.argv

    all_cards = load_all_cards()
    if not all_cards:
        print("ERROR: No YAML files found in", CARDS_DIR)
        sys.exit(1)

    # Structural validation — fail hard in both generate and --check modes.
    # Prevents ★1/★2/★3 r_conditional drift before codegen produces output.
    parity_errors = validate_r_conditional_star_parity(all_cards)
    if parity_errors:
        print("❌ r_conditional ★ parity violations:")
        for err in parity_errors:
            print(f"  - {err}")
        print()
        print(
            "r_conditional must be structurally identical across ★1/★2/★3 "
            "within a card.\n"
            "See evidence: 훈련소/보급부대/군수공장 drift fixes (2026-04-16)."
        )
        sys.exit(2)

    total = sum(len(c) for c in all_cards.values())
    generated_db = generate(all_cards)

    # Generate card descriptions
    from card_desc_gen import generate_all_descs
    descs = generate_all_descs(all_cards)
    generated_descs = generate_descs_gd(all_cards, descs)

    if check_mode:
        ok_db = _check_file(OUTPUT, generated_db, "card_db.gd")
        ok_descs = _check_file(OUTPUT_DESCS, generated_descs, "card_descs.gd")
        if ok_db and ok_descs:
            print(f"✅ card_db.gd + card_descs.gd match YAML ({total} cards)")
            sys.exit(0)
        else:
            sys.exit(1)
    else:
        _write_file(OUTPUT, generated_db)
        _write_file(OUTPUT_DESCS, generated_descs)
        print(f"Generated {OUTPUT} ({total} cards)")
        print(f"Generated {OUTPUT_DESCS} ({total} cards, "
              f"{sum(len(d) for d in descs.values())} descs)")


if __name__ == "__main__":
    main()
