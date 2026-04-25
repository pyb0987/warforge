class_name EnemyDB
extends RefCounted
## Enemy generation: theme-based army composition, round-scaled difficulty.
## Single source of truth for both play (game_manager) and sim (headless_runner).
##
## 2026-04-24 refactor: 4 enemy presets = 4 game themes (predator/druid/military/steampunk).
## Each preset draws units from its theme's UnitDB pool (10 units per theme).
## Neutral + mil_enhanced excluded from enemy armies.
##
## Stat scaling per round:
##   atk × stat_mult, hp × stat_mult  (enemy_cp_curve[round-1])
##   target_cp_per_round[round-1] drives total army CP
##   boss rounds (4/8/12/15): target_cp × boss_scaling.cp_mult

## Preset types = 4 game themes.
enum Preset { PREDATOR, DRUID, MILITARY, STEAMPUNK }

const PRESET_NAMES := ["predator", "druid", "military", "steampunk"]

## PresetGenerator loads UNIT_INTRINSIC_CP + THEME_RECIPES.
const PresetGen = preload("res://sim/preset_generator.gd")


## Mirror of default cp curve formula. Kept for tests and as sanity reference.
static func _round_mult(r: int) -> float:
	return 1.0 + (r - 1) * 0.2 + maxf(0.0, (r - 8)) * 0.1


## Generate enemy army for a given round.
## genome=null falls back to Genome.create_default().
## Returns: Array of unit dicts {atk, hp, attack_speed, range, move_speed, radius}.
static func generate(round_num: int, rng: RandomNumberGenerator, genome: Genome = null) -> Array:
	var g: Genome = genome if genome != null else Genome.create_default()

	var is_boss := round_num in [4, 8, 12, 15]
	var preset_idx: int = rng.randi_range(0, PRESET_NAMES.size() - 1)
	var preset_name: String = PRESET_NAMES[preset_idx]

	# Per-round stat multiplier (atk × stat_mult, hp × stat_mult).
	var stat_mult: float = g.enemy_cp_curve[round_num - 1] if round_num >= 1 and round_num <= 15 else 1.0

	# Target army CP (×cp_mult on boss rounds — adds proportionally more units).
	var target_cp: float = g.target_cp_per_round[round_num - 1] if round_num >= 1 and round_num <= 15 else 100.0
	if is_boss:
		var bm: Dictionary = g.get_boss_mult()
		target_cp *= float(bm.get("cp_mult", 1.3))

	# Theme-based composition: {unit_id: count}
	var counts: Dictionary = PresetGen.derive_comp(preset_name, target_cp, stat_mult)

	var units: Array = []
	for unit_id in counts:
		var count: int = int(counts[unit_id])
		var unit_data: Dictionary = UnitDB.get_unit(unit_id)
		if unit_data.is_empty():
			push_warning("EnemyDB: unknown unit_id %s (preset %s)" % [unit_id, preset_name])
			continue

		var base_atk: float = float(unit_data.get("atk", 3))
		var base_hp: float = float(unit_data.get("hp", 20))
		var base_as: float = float(unit_data.get("attack_speed", 1.0))
		var range_val: int = int(unit_data.get("range", 0))
		var ms_val: int = int(unit_data.get("move_speed", 2))

		# Per-round stat scaling (atk × stat_mult, hp × stat_mult).
		# No sub_mult: each theme unit is "on-theme" by construction.
		var scaled_atk: float = base_atk * stat_mult
		var scaled_hp: float = base_hp * stat_mult

		for _i in count:
			units.append({
				"atk": scaled_atk,
				"hp": scaled_hp,
				"attack_speed": base_as,
				"range": range_val,
				"move_speed": ms_val,
				"radius": 6.0,
			})

	return units
