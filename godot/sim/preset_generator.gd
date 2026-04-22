class_name PresetGenerator
extends RefCounted
## Preset generator — target_cp → preset composition.
##
## Given a target CP value and preset name, derives unit counts per role
## using fixed preset recipes. Ensures all 4 presets produce similar total
## CP at each round, eliminating preset variance.
##
## Mirrors scripts/preset_generator.py — keep in sync.


## Role weights per preset (tactical identity). Sum per preset = 1.0.
const PRESET_RECIPES := {
	"swarm":    {"swarm": 0.80, "ranged": 0.20},
	"heavy":    {"heavy": 0.35, "melee": 0.55, "ranged": 0.10},
	"sniper":   {"sniper": 0.30, "melee": 0.50, "ranged": 0.20},
	"balanced": {"melee": 0.30, "ranged": 0.25, "swarm": 0.25, "heavy": 0.10, "sniper": 0.10},
}


static func sub_mult(preset_name: String, role: String) -> float:
	if preset_name == "swarm" and role == "ranged":
		return 0.8
	if preset_name == "heavy":
		if role == "melee":
			return 0.9
		if role == "ranged":
			return 0.7
	if preset_name == "sniper" and role == "melee":
		return 0.8
	if preset_name == "balanced" and role == "swarm":
		return 0.9
	return 1.0


## Derive unit counts per role to match target_cp.
## stats: {role: {"atk": float, "hp": float, "as": float}}
## Returns: {role: int count}
static func derive_comp(preset_name: String, target_cp: float, stats: Dictionary) -> Dictionary:
	var weights: Dictionary = PRESET_RECIPES.get(preset_name, {})
	if weights.is_empty():
		return {}

	var avg_cp_per_unit := 0.0
	for role in weights:
		var s: Dictionary = stats.get(role, {})
		if s.is_empty():
			continue
		var sm: float = sub_mult(preset_name, role)
		var atk: float = float(s.get("atk", 0.0)) * sm
		var hp: float = float(s.get("hp", 0.0)) * sm
		var as_val: float = maxf(float(s.get("as", 1.0)), 0.01)
		var cp_unit: float = (atk / as_val) * hp
		avg_cp_per_unit += float(weights[role]) * cp_unit

	if avg_cp_per_unit <= 0.0:
		var default_counts: Dictionary = {}
		for role in weights:
			default_counts[role] = 1
		return default_counts

	var total_units: float = target_cp / avg_cp_per_unit
	var counts: Dictionary = {}
	for role in weights:
		counts[role] = maxi(1, roundi(total_units * float(weights[role])))
	return counts
