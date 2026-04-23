extends SceneTree
## Preset parity diagnostic (2026-04-23).
##
## Question: Given equal target_cp, do the 4 presets (swarm/heavy/sniper/balanced)
##           produce balanced armies, or is CP formula (atk/as × hp) a poor proxy
##           for actual combat power?
##
## Method: For each preset pair (A, B), run combat A vs B N times. Diagonal A vs A
##         should give ~50% (self-play baseline). Off-diagonal reveals tactical
##         advantage/disadvantage that CP doesn't capture.
##
## Output JSON:
##   {
##     "target_cp": [...],
##     "stat_mult": [...],
##     "results": [
##       {
##         "target_cp": float,
##         "stat_mult": float,
##         "matrix": {  # preset_A → {preset_B: {wins, total, wr, avg_ticks}}
##           "swarm":    {"swarm": {...}, "heavy": {...}, ...},
##           "heavy":    {...},
##           ...
##         }
##       },
##       ...
##     ]
##   }
##
## Usage:
##   godot --headless --path godot/ -s sim/preset_parity_runner.gd -- \
##     --runs=20 --cps=7262,36934,126577 --mults=1.5,3.5,6.0 --seed=42

const PresetGen = preload("res://sim/preset_generator.gd")
const PRESETS := ["swarm", "heavy", "sniper", "balanced"]


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

	printerr("=== Preset Parity Runner ===")
	printerr("Genome: %s" % genome_path)
	printerr("Runs per pair: %d" % runs)
	printerr("CP tiers: %s" % str(cps))

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
					var army_a := _build_army(preset_a, target_cp, stat_mult, genome, rng_a)
					var army_b := _build_army(preset_b, target_cp, stat_mult, genome, rng_b)

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


## Build one preset army as unit dict array (same shape as EnemyDB.generate output).
func _build_army(preset_name: String, target_cp: float, stat_mult: float,
		genome, rng: RandomNumberGenerator) -> Array:
	var counts: Dictionary = PresetGen.derive_comp(preset_name, target_cp, genome.enemy_stats, stat_mult)
	var units: Array = []

	# BASE geometry (mirror of EnemyDB.BASE — range/ms are not genome-controlled)
	var BASE := {
		"swarm_range": 0, "swarm_ms": 3,
		"melee_range": 0, "melee_ms": 2,
		"ranged_range": 4, "ranged_ms": 1,
		"heavy_range": 0, "heavy_ms": 1,
		"sniper_range": 6, "sniper_ms": 1,
	}

	for type_name in counts:
		var count: int = int(counts[type_name])
		var stat: Dictionary = genome.get_enemy_stat(type_name)
		var base_atk: float = stat.get("atk", 3.0)
		var base_hp: float = stat.get("hp", 20.0)
		var base_as: float = stat.get("as", 1.0)

		var sub_mult: float = PresetGen.sub_mult(preset_name, type_name)
		var scaled_atk: float = base_atk * stat_mult * sub_mult
		var scaled_hp: float = base_hp * stat_mult * sub_mult

		var range_val: int = BASE.get(type_name + "_range", 0)
		var ms_val: int = BASE.get(type_name + "_ms", 2)

		for _i in count:
			units.append({
				"atk": scaled_atk,
				"hp": scaled_hp,
				"attack_speed": base_as,
				"range": range_val,
				"move_speed": ms_val,
				"radius": 6.0,
			})
	# rng 사용은 현재 없음 (EnemyDB.generate는 preset 선택에만 rng 사용). 장래 확장용 보유.
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
