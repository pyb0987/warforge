#!/usr/bin/env python3
"""
codegen_v2.py — Generate card_db.gd directly from v2 YAML (timing-block format).

B-direct migration (Phase 2): effects are stored as a list of timing blocks in
a unified `_templates[id].effects`. No `_theme_effects` dict. Theme systems
access per-star effects via `get_star_template().effects` and search actions
inside the matching block.

Output: /tmp/card_db_v2.gd and /tmp/card_descs_v2.gd. Promotion to the official
paths happens in C6.
"""

from __future__ import annotations

import sys
from collections import OrderedDict
from pathlib import Path
from typing import Any, Optional

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
# Reuse enum maps, action-level generators, validators.
import codegen_card_db as v1cg  # noqa: E402
from card_desc_gen import generate_all_descs  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
CARDS_V2_DIR = ROOT / "data" / "cards_v2"
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

def load_v2_cards() -> "dict[str, dict[str, dict]]":
    """Load all v2 YAMLs. Returns {theme: {card_id: card_v2}}."""
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
            return v1cg._gen_raw_dict({
                "action": "grant_terazin", "target": "self",
                "terazin_amount": params,
            })
        return v1cg._gen_raw_dict({"action": action, "value": params})

    if impl == "card_db" and action in v1cg.CARD_DB_ACTIONS:
        return v1cg.gen_effect({action: params})

    # Theme-system path — emit raw dict with nested `effects` flattening.
    d = {"action": action, **v1cg._convert_nested_effects(params)}
    return v1cg._gen_raw_dict(d)


def gen_conditional_entry(cond: dict, indent: str, impl: str) -> str:
    """Generate one conditional/r_conditional entry as a GDScript dict."""
    when = cond["when"]
    cond_type = next(iter(when))
    threshold = when[cond_type]
    inner_actions = []
    for e in cond.get("effects", []):
        # Inner effects are v1-style {action: params} dicts
        action = next(iter(e))
        params = e[action]
        inner_actions.append(gen_action_dict(action, params, impl))
    actions_src = ", ".join(inner_actions)
    return (
        f'{{"condition": "{cond_type}", "threshold": {threshold}, '
        f'"effects": [{actions_src}]}}'
    )


def gen_post_threshold_list(effects: list, impl: str) -> str:
    """Post-threshold is a flat list of action dicts."""
    parts = []
    for e in effects:
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
    timing_gd = v1cg.TIMING_MAP[timing_short]
    max_act: int = meta["max_act"]

    listen = meta.get("listen") or {}
    l1_gd = v1cg.gen_layer(listen.get("l1"), v1cg.LAYER1_MAP)
    l2_gd = v1cg.gen_layer(listen.get("l2"), v1cg.LAYER2_MAP)

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
    lines.append(f"\tvar T := {v1cg.THEME_MAP[theme]}")

    # Local enum declarations for readability
    used_timings, used_l1, used_l2 = collect_used_enums(cards)
    for short in sorted(used_timings):
        full = v1cg.TIMING_MAP[short]
        lines.append(f"\tvar {short} := {full}")
    for short in sorted(used_l1):
        full = v1cg.LAYER1_MAP[short]
        lines.append(f"\tvar {short} := {full}")
    for short in sorted(used_l2):
        full = v1cg.LAYER2_MAP[short]
        lines.append(f"\tvar {short} := {full}")

    # Var prefix assignment + collision handling
    prefixes_used: dict[str, str] = {}
    for card_id, card in cards.items():
        prefix = v1cg.make_var_prefix(card_id)
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
        local_vars[v1cg.TIMING_MAP[t]] = t
    for x in used_l1:
        local_vars[v1cg.LAYER1_MAP[x]] = x
    for x in used_l2:
        local_vars[v1cg.LAYER2_MAP[x]] = x

    # Second pass: catch enums that slipped through (e.g., inside gen_action_dict
    # output where local vars weren't substituted)
    _ALL_ENUMS: dict[str, str] = {}
    for short, full in v1cg.TIMING_MAP.items():
        _ALL_ENUMS[full] = short
    for short, full in v1cg.LAYER1_MAP.items():
        _ALL_ENUMS[full] = short
    for short, full in v1cg.LAYER2_MAP.items():
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
# AUTO-GENERATED from data/cards_v2/*.yaml — DO NOT EDIT
# Run: python3 scripts/codegen_v2.py
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


## Legacy adapter for theme_systems still using the flat-effects API.
## Returns the first block's actions AND reconstructs r_conditional /
## conditional entries as pseudo-actions (matching v1 codegen emission),
## because theme_systems search for these via _find_eff in the same list.
## Multi-block cards (introduced in C5) must use get_block_for_timing() directly.
func get_theme_effects(card_id: String, star_level: int) -> Array:
\tvar blocks := get_effect_blocks(card_id, star_level)
\tif blocks.is_empty():
\t\treturn []
\tvar block: Dictionary = blocks[0]
\tvar result: Array = block.get("actions", []).duplicate()
\tfor rc in block.get("r_conditional_effects", []):
\t\tresult.append({
\t\t\t"action": "r_conditional",
\t\t\t"condition": rc.get("condition", ""),
\t\t\t"threshold": rc.get("threshold", 0),
\t\t\t"effects": rc.get("effects", []),
\t\t})
\tfor c in block.get("conditional_effects", []):
\t\tresult.append({
\t\t\t"action": "conditional",
\t\t\t"condition": c.get("condition", ""),
\t\t\t"threshold": c.get("threshold", 0),
\t\t\t"effects": c.get("effects", []),
\t\t})
\treturn result
'''

HELPER_FUNCTIONS = '''
## Compact card registration (v2 block format).
## Backward-compat: the first block's meta fields are also hoisted to the
## template top level so legacy read sites (tests, UI code) keep working while
## Phase 2 runtime migrates to full block-awareness.
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
    present_themes = [t for t in v1cg.THEME_ORDER if t in all_cards]
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

def _project_v2_to_desc_gen_input(all_cards: dict) -> dict:
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
                # For desc gen, only use the ★1-timing block to mimic v1 behavior.
                # Multi-block cards (future sp_warmachine) need desc_gen updates —
                # out of scope for C1.
                block = star_data["effects"][0]
                proj_star["max_act"] = block["max_act"]
                if block["trigger_timing"] != base_timing:
                    proj_star["timing"] = block["trigger_timing"]
                for f in ("conditional", "r_conditional", "post_threshold"):
                    if f in block:
                        proj_star[f] = block[f]
                # Flatten actions back to v1 effects list
                effects: list = []
                for key, val in block.items():
                    if key in BLOCK_META_KEYS:
                        continue
                    if isinstance(val, list) and val and all(isinstance(v, dict) for v in val):
                        for p in val:
                            effects.append({key: p})
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

def run_validators(all_cards_v2: dict) -> None:
    projected = _project_v2_to_desc_gen_input(all_cards_v2)
    ec_errors = v1cg.validate_conscript_enhanced_count(projected)
    if ec_errors:
        print("❌ conscript.enhanced_count violations:")
        for e in ec_errors:
            print(f"  - {e}")
        sys.exit(2)
    parity_errors = v1cg.validate_r_conditional_star_parity(projected)
    if parity_errors:
        print("❌ r_conditional ★ parity violations:")
        for e in parity_errors:
            print(f"  - {e}")
        sys.exit(2)


# ═══════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════

def main() -> None:
    all_cards = load_v2_cards()
    if not all_cards:
        print("ERROR: no v2 YAML files loaded")
        sys.exit(1)

    run_validators(all_cards)

    card_db_src = generate_card_db(all_cards)

    # Descriptions — reuse v1 desc gen with a projection.
    projected = _project_v2_to_desc_gen_input(all_cards)
    descs = generate_all_descs(projected)
    descs_src = v1cg.generate_descs_gd(projected, descs)

    v1cg._write_file(OUTPUT_DB, card_db_src)
    v1cg._write_file(OUTPUT_DESCS, descs_src)

    total = sum(len(c) for c in all_cards.values())
    print(f"v2 codegen: {total} cards (block format)")
    print(f"  → {OUTPUT_DB}")
    print(f"  → {OUTPUT_DESCS}")


if __name__ == "__main__":
    main()
