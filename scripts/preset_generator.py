"""Preset generator — target_cp → preset composition.

Given a target CP and preset name, derives unit counts per role using
fixed preset recipes. Ensures all 4 presets produce similar total CP at
each round, eliminating preset variance.

Mirrors godot/sim/preset_generator.gd — keep in sync.
"""

# Role weights per preset (tactical identity).
# Sum per preset must equal 1.0.
PRESET_RECIPES = {
    "swarm":    {"swarm": 0.80, "ranged": 0.20},
    "heavy":    {"heavy": 0.35, "melee": 0.55, "ranged": 0.10},
    "sniper":   {"sniper": 0.30, "melee": 0.50, "ranged": 0.20},
    "balanced": {"melee": 0.30, "ranged": 0.25, "swarm": 0.25, "heavy": 0.10, "sniper": 0.10},
}

# Preset sub-multiplier (mirrors enemy_db.gd._sub_mult).
# Applied to atk and hp for "off-role" units in a preset.
_SUB_MULT = {
    ("swarm", "ranged"): 0.8,
    ("heavy", "melee"): 0.9,
    ("heavy", "ranged"): 0.7,
    ("sniper", "melee"): 0.8,
    ("balanced", "swarm"): 0.9,
}


def sub_mult(preset_name: str, role: str) -> float:
    return _SUB_MULT.get((preset_name, role), 1.0)


def derive_comp(preset_name: str, target_cp: float, stats: dict, stat_mult: float = 1.0) -> dict:
    """Derive unit counts per role to match target_cp at given stat scale.

    stats: {role: {"atk": float, "hp": float, "as": float}}
    stat_mult: per-round enemy stat multiplier (atk × stat_mult, hp × stat_mult).
               Per-unit CP scales by stat_mult² (atk×hp both scaled).
    Returns: {role: int count}
    """
    if preset_name not in PRESET_RECIPES:
        return {}
    weights = PRESET_RECIPES[preset_name]

    # Average CP per unit (weighted), with sub_mult and stat_mult² applied.
    stat_sq = stat_mult * stat_mult
    avg_cp_per_unit = 0.0
    for role, w in weights.items():
        s = stats.get(role)
        if s is None:
            continue
        sm = sub_mult(preset_name, role)
        atk = s["atk"] * sm
        hp = s["hp"] * sm
        as_val = max(s.get("as", 1.0), 0.01)
        cp_unit = (atk / as_val) * hp * stat_sq
        avg_cp_per_unit += w * cp_unit

    if avg_cp_per_unit <= 0:
        return {role: 1 for role in weights}

    total_units = target_cp / avg_cp_per_unit
    counts = {}
    for role, w in weights.items():
        counts[role] = max(1, round(total_units * w))
    return counts


def preset_cp_estimate(preset_name: str, target_cp: float, stats: dict, stat_mult: float = 1.0) -> float:
    """Given derived comp, compute actual total CP. Should ≈ target_cp."""
    counts = derive_comp(preset_name, target_cp, stats, stat_mult)
    stat_sq = stat_mult * stat_mult
    total = 0.0
    for role, count in counts.items():
        s = stats.get(role, {})
        if not s:
            continue
        sm = sub_mult(preset_name, role)
        atk = s["atk"] * sm
        hp = s["hp"] * sm
        as_val = max(s.get("as", 1.0), 0.01)
        total += (atk / as_val) * hp * count * stat_sq
    return total
