extends SceneTree
## Preset parity diagnostic (2026-04-23, updated 2026-04-24 for theme system).
##
## Question: Given equal target_cp across 4 themed presets, do they produce
##           balanced armies? Off-diagonal reveals preset dominance asymmetry.
##
## Method: For each preset pair (A, B), run combat A vs B N times.
##         Presets: predator/druid/military/steampunk (each = 1 game theme).
##
## Output JSON: see original header.
##
## Usage:
##   godot --headless --path godot/ -s sim/preset_parity_runner.gd -- \
##     --runs=20 --cps=7262,36934,126577 --mults=1.5,3.5,6.0 --seed=42

const PresetGen = preload("res://sim/preset_generator.gd")
const UnitDBScript = preload("res://core/data/unit_db.gd")
const PRESETS := ["predator", "druid", "military", "steampunk"]

var _unit_db  # Node-like, instantiated at _run


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var _GenomeClass = load("res://sim/genome.gd")

	var args := _parse_args()
	var runs: int = args.get("runs", 20)
	var cps: Array = args.get("cps", [7262.0, 36934.0, 126577.0])
	var mults: Array = args.get("mults", [1.5, 3.5, 6.0])
	var base_seed: int = args.get("seed", 42)
	var genome_path: String = args.get("genome", "res://sim/best_genome.json")

	if cps.size() != mults.size():
		printerr("ERROR: cps and mults must have same length")
		quit(1)
		return

	var genome = _GenomeClass.load_file(genome_path)
	if genome == null:
		printerr("ERROR: Failed to load genome from %s" % genome_path)
		quit(1)
		return

	# Instantiate UnitDB locally (SceneTree scripts lack autoload compile-time access).
	_unit_db = UnitDBScript.new()
	_unit_db._register_all()

	printerr("=== Preset Parity Runner (themed, 2026-04-24) ===")
	printerr("Genome: %s" % genome_path)
	printerr("Runs per pair: %d" % runs)
	printerr("CP tiers: %s" % str(cps))
	printerr("Presets: %s" % str(PRESETS))

	var all_results: Array = []
	for tier_idx in cps.size():
		var target_cp: float = cps[tier_idx]
		var stat_mult: float = mults[tier_idx]
		printerr("\n--- Tier %d: target_cp=%.0f, stat_mult=%.2f ---" % [tier_idx, target_cp, stat_mult])

		var matrix: Dictionary = {}
		for preset_a in PRESETS:
			matrix[preset_a] = {}
			for preset_b in PRESETS:
				var wins_a := 0
				var ties := 0
				var ticks_sum := 0
				for i in runs:
					var seed_val: int = base_seed + tier_idx * 1000 + PRESETS.find(preset_a) * 100 + PRESETS.find(preset_b) * 10 + i
					var rng_a := RandomNumberGenerator.new()
					rng_a.seed = seed_val
					var rng_b := RandomNumberGenerator.new()
					rng_b.seed = seed_val + 500000
					var army_a := _build_army(preset_a, target_cp, stat_mult, rng_a)
					var army_b := _build_army(preset_b, target_cp, stat_mult, rng_b)

					var engine := CombatEngine.new()
					engine.headless = true
					engine.setup(army_a, army_b)  # A as team 1, B as team 0
					while engine.tick():
						pass

					var alive_a := _count_alive(engine, 1)
					var alive_b := _count_alive(engine, 0)
					if alive_a > 0 and alive_b == 0:
						wins_a += 1
					elif alive_a == 0 and alive_b == 0:
						ties += 1
					ticks_sum += engine.get_tick()

				var wr: float = float(wins_a) / runs
				matrix[preset_a][preset_b] = {
					"wins_a": wins_a,
					"ties": ties,
					"total": runs,
					"wr_a": wr,
					"avg_ticks": float(ticks_sum) / runs,
				}
				printerr("  %s vs %s: %d/%d = %.0f%% (ties %d, avg_ticks %.0f)" % [
					preset_a, preset_b, wins_a, runs, wr * 100.0, ties, float(ticks_sum) / runs])
		all_results.append({
			"target_cp": target_cp,
			"stat_mult": stat_mult,
			"matrix": matrix,
		})

	var out := {
		"meta": {
			"runs_per_pair": runs,
			"base_seed": base_seed,
			"genome": genome_path,
			"presets": PRESETS,
		},
		"results": all_results,
	}
	print(JSON.stringify(out, "  "))
	printerr("\n=== Done ===")
	quit(0)


## Build themed army via PresetGen.derive_comp + UnitDB lookup.
func _build_army(preset_name: String, target_cp: float, stat_mult: float,
		rng: RandomNumberGenerator) -> Array:
	var counts: Dictionary = PresetGen.derive_comp(preset_name, target_cp, stat_mult)
	var units: Array = []

	for unit_id in counts:
		var count: int = int(counts[unit_id])
		var unit_data: Dictionary = _unit_db.get_unit(unit_id)
		if unit_data.is_empty():
			printerr("WARN: unknown unit_id %s in preset %s" % [unit_id, preset_name])
			continue

		var base_atk: float = float(unit_data.get("atk", 3))
		var base_hp: float = float(unit_data.get("hp", 20))
		var base_as: float = float(unit_data.get("attack_speed", 1.0))
		var range_val: int = int(unit_data.get("range", 0))
		var ms_val: int = int(unit_data.get("move_speed", 2))

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
	var _unused := rng
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
		if arg.begins_with("--runs="):
			result["runs"] = arg.substr(7).to_int()
		elif arg.begins_with("--seed="):
			result["seed"] = arg.substr(7).to_int()
		elif arg.begins_with("--genome="):
			result["genome"] = arg.substr(9)
		elif arg.begins_with("--cps="):
			var parts: Array = Array(arg.substr(6).split(","))
			var cps: Array = []
			for p in parts:
				cps.append(float(p))
			result["cps"] = cps
		elif arg.begins_with("--mults="):
			var parts: Array = Array(arg.substr(8).split(","))
			var mults: Array = []
			for p in parts:
				mults.append(float(p))
			result["mults"] = mults
	return result
