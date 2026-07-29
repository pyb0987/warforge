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


## Pure, non-rolled pressure preview for BUILD UI.
## This intentionally does not choose a preset or call generate(), so it cannot
## advance battle RNG or promise an exact scouted army.
static func pressure_profile(round_num: int, genome: Genome = null,
		difficulty: int = 1) -> Dictionary:
	var g: Genome = genome if genome != null else Genome.create_default()
	var difficulty_value: int = Difficulty.clamp_difficulty(difficulty)
	var stat_mult := _round_stat_mult(g, round_num)
	var target_cp := _round_target_cp(g, round_num)
	var summaries: Array[Dictionary] = []
	for preset_name in PRESET_NAMES:
		var counts: Dictionary = PresetGen.derive_comp(
			preset_name, target_cp, stat_mult)
		var summary := _summarize_counts_for_preview(
			preset_name, counts, stat_mult, difficulty_value)
		if not summary.is_empty():
			summaries.append(summary)
	if summaries.is_empty():
		return {}

	var profile := {
		"round": round_num,
		"difficulty": difficulty_value,
		"boss": _is_boss_round(round_num),
		"exact": false,
		"preset_count": PRESET_NAMES.size(),
		"profiles": summaries,
		"boss_upgrade_count": Difficulty.get_boss_upgrade_rarities(
			round_num, difficulty_value).size(),
	}
	_add_preview_range(profile, summaries, "enemy_count")
	_add_preview_range(profile, summaries, "total_atk")
	_add_preview_range(profile, summaries, "total_hp")
	return profile


## Generate enemy army for a given round.
## genome=null falls back to Genome.create_default().
## Returns: Array of unit dicts {atk, hp, attack_speed, range, move_speed, radius}.
static func generate(round_num: int, rng: RandomNumberGenerator,
		genome: Genome = null, difficulty: int = 1) -> Array:
	var g: Genome = genome if genome != null else Genome.create_default()
	var difficulty_value: int = Difficulty.clamp_difficulty(difficulty)

	var is_boss := _is_boss_round(round_num)
	var preset_idx: int = rng.randi_range(0, PRESET_NAMES.size() - 1)
	var preset_name: String = PRESET_NAMES[preset_idx]

	# Per-round stat multiplier (atk × stat_mult, hp × stat_mult).
	var stat_mult: float = _round_stat_mult(g, round_num)

	# Target army CP (×cp_mult on boss rounds — adds proportionally more units).
	var target_cp: float = _round_target_cp(g, round_num)

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
				"mechanics": [],
			})

	Difficulty.apply_enemy_count_modifier(units, difficulty_value, rng)
	return Difficulty.apply_enemy_modifiers(units, round_num, rng, difficulty_value)


static func _is_boss_round(round_num: int) -> bool:
	return round_num in [4, 8, 12, 15]


static func _round_stat_mult(g: Genome, round_num: int) -> float:
	if round_num >= 1 and round_num <= 15:
		return float(g.enemy_cp_curve[round_num - 1])
	return 1.0


static func _round_target_cp(g: Genome, round_num: int) -> float:
	var target_cp: float = g.target_cp_per_round[round_num - 1] \
		if round_num >= 1 and round_num <= 15 else 100.0
	if _is_boss_round(round_num):
		var bm: Dictionary = g.get_boss_mult()
		target_cp *= float(bm.get("cp_mult", 1.3))
	return target_cp


static func _summarize_counts_for_preview(preset_name: String,
		counts: Dictionary, stat_mult: float, difficulty: int) -> Dictionary:
	var enemy_count := 0
	var total_atk := 0.0
	var total_hp := 0.0
	var atk_mult := Difficulty.get_enemy_atk_mult(difficulty)
	var hp_mult := Difficulty.get_enemy_hp_mult(difficulty)
	for unit_id in counts:
		var count := int(counts[unit_id])
		if count <= 0:
			continue
		var unit_data: Dictionary = UnitDB.get_unit(unit_id)
		if unit_data.is_empty():
			continue
		enemy_count += count
		total_atk += float(unit_data.get("atk", 3)) * stat_mult * atk_mult * count
		total_hp += float(unit_data.get("hp", 20)) * stat_mult * hp_mult * count
	if enemy_count <= 0:
		return {}

	var count_mult := Difficulty.get_enemy_count_mult(difficulty)
	if count_mult > 1.0:
		var adjusted_count := enemy_count + int(floor(
			float(enemy_count) * (count_mult - 1.0)))
		var count_scale := float(adjusted_count) / float(enemy_count)
		total_atk *= count_scale
		total_hp *= count_scale
		enemy_count = adjusted_count

	return {
		"preset_name": preset_name,
		"enemy_count": enemy_count,
		"total_atk": total_atk,
		"total_hp": total_hp,
	}


static func _add_preview_range(profile: Dictionary,
		summaries: Array[Dictionary], key: String) -> void:
	var min_value := 1000000000.0
	var max_value := -1000000000.0
	var total_value := 0.0
	for summary in summaries:
		var value := float(summary.get(key, 0.0))
		min_value = minf(min_value, value)
		max_value = maxf(max_value, value)
		total_value += value
	profile["%s_min" % key] = min_value
	profile["%s_max" % key] = max_value
	profile["%s_avg" % key] = total_value / float(summaries.size())
