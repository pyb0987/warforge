extends SceneTree
## Unit pairwise tournament (2026-04-24, Option C prep).
##
## For each pair of enemy-themed units (40 total), run N×N combat at equal count.
## Output: JSON with per-unit avg WR vs field + raw pairwise matrix.
## Used as empirical target for symbolic regression of CP formula.
##
## Usage:
##   godot --headless --path godot/ -s sim/unit_tournament.gd -- \
##     --count=20 --runs=20 --stat_mult=3.5 --seed=42

const PresetGen = preload("res://sim/preset_generator.gd")
const UnitDBScript = preload("res://core/data/unit_db.gd")

# Enemy-only units (40: predator/druid/military/steampunk × 10)
const ENEMY_UNITS := [
	"sp_spider", "sp_rat", "sp_sawblade", "sp_scorpion", "sp_crab",
	"sp_titan", "sp_cannon", "sp_drone", "sp_turret", "sp_scout",
	"dr_wolf", "dr_boar", "dr_treant_y", "dr_spirit", "dr_turtle",
	"dr_treant_a", "dr_rootguard", "dr_vine", "dr_toad", "dr_spore",
	"pr_larva", "pr_worker", "pr_spider", "pr_warrior", "pr_charger",
	"pr_sniper", "pr_flyer", "pr_queen", "pr_guardian", "pr_apex",
	"ml_recruit", "ml_infantry", "ml_shield", "ml_drone", "ml_biker",
	"ml_plasma", "ml_sniper", "ml_artillery", "ml_commander", "ml_walker",
]

var _unit_db


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var args := _parse_args()
	var count: int = args.get("count", 20)
	var runs: int = args.get("runs", 20)
	var stat_mult: float = args.get("stat_mult", 3.5)
	var base_seed: int = args.get("seed", 42)

	_unit_db = UnitDBScript.new()
	_unit_db._register_all()

	printerr("=== Unit 1v1 Tournament ===")
	printerr("Units: %d (enemy-themed)" % ENEMY_UNITS.size())
	printerr("Per matchup: %d units × %d runs = %d fights" % [count, runs, count * runs])
	printerr("Total: %d matchups" % (ENEMY_UNITS.size() * ENEMY_UNITS.size()))

	var matrix := {}  # {u1: {u2: {wr, ties, avg_ticks}}}
	var total_matches := ENEMY_UNITS.size() * ENEMY_UNITS.size()
	var done := 0

	for i in ENEMY_UNITS.size():
		var u1 = ENEMY_UNITS[i]
		matrix[u1] = {}
		for j in ENEMY_UNITS.size():
			var u2 = ENEMY_UNITS[j]
			var wins1 := 0
			var ties := 0
			var ticks_sum := 0
			for r in runs:
				var seed_val: int = base_seed + i * 10000 + j * 100 + r
				var army1 := _build_army_single(u1, count, stat_mult)
				var army2 := _build_army_single(u2, count, stat_mult)

				var engine := CombatEngine.new()
				engine.headless = true
				engine.setup(army1, army2)  # team 1 = u1, team 0 = u2
				while engine.tick():
					pass

				var alive1 := _count_alive(engine, 1)
				var alive2 := _count_alive(engine, 0)
				if alive1 > 0 and alive2 == 0:
					wins1 += 1
				elif alive1 == 0 and alive2 == 0:
					ties += 1
				ticks_sum += engine.get_tick()

			matrix[u1][u2] = {
				"wr": float(wins1) / runs,
				"ties": ties,
				"avg_ticks": float(ticks_sum) / runs,
			}
			done += 1
			if done % 100 == 0:
				printerr("  progress: %d / %d" % [done, total_matches])

	# Per-unit aggregate: avg WR vs field (exclude self)
	var aggregates := {}
	for u1 in ENEMY_UNITS:
		var sum_wr := 0.0
		var n := 0
		for u2 in ENEMY_UNITS:
			if u1 == u2:
				continue
			sum_wr += matrix[u1][u2]["wr"]
			n += 1
		aggregates[u1] = {
			"avg_wr_vs_field": sum_wr / n,
			"stats": _unit_db.get_unit(u1),
		}

	var out := {
		"meta": {
			"count": count,
			"runs": runs,
			"stat_mult": stat_mult,
			"seed": base_seed,
			"units": ENEMY_UNITS,
		},
		"aggregates": aggregates,
		"matrix": matrix,
	}
	print(JSON.stringify(out, "  "))
	printerr("=== Done ===")
	quit(0)


func _build_army_single(unit_id: String, count: int, stat_mult: float) -> Array:
	var unit_data: Dictionary = _unit_db.get_unit(unit_id)
	if unit_data.is_empty():
		printerr("ERROR: unknown unit %s" % unit_id)
		return []
	var base_atk: float = float(unit_data.get("atk", 3))
	var base_hp: float = float(unit_data.get("hp", 20))
	var base_as: float = float(unit_data.get("attack_speed", 1.0))
	var range_val: int = int(unit_data.get("range", 0))
	var ms_val: int = int(unit_data.get("move_speed", 2))
	var scaled_atk: float = base_atk * stat_mult
	var scaled_hp: float = base_hp * stat_mult
	var units: Array = []
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


func _count_alive(engine: CombatEngine, team_id: int) -> int:
	var count := 0
	for i in engine.count:
		if engine.alive[i] == 1 and engine.team[i] == team_id:
			count += 1
	return count


func _parse_args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--count="):
			result["count"] = arg.substr(8).to_int()
		elif arg.begins_with("--runs="):
			result["runs"] = arg.substr(7).to_int()
		elif arg.begins_with("--stat_mult="):
			result["stat_mult"] = float(arg.substr(12))
		elif arg.begins_with("--seed="):
			result["seed"] = arg.substr(7).to_int()
	return result
