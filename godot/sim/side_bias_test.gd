extends SceneTree
## Side bias diagnostic: swarm vs swarm with roles swapped.
##
## If original (A=ally, B=enemy) produces different WR than swapped
## (B=ally, A=enemy), the asymmetry is side-bound, not preset-bound.

const PresetGen = preload("res://sim/preset_generator.gd")


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var _GenomeClass = load("res://sim/genome.gd")
	var genome = _GenomeClass.load_file("res://sim/best_genome.json")

	var target_cp := 36934.0
	var stat_mult := 3.5
	var runs := 20
	var base_seed := 42

	print("=== Side Bias Test (swarm vs swarm) ===")

	var a_wins_orig := 0
	var a_wins_swap := 0
	for i in runs:
		var army_a := _build_army("swarm", target_cp, stat_mult, genome)
		var army_b := _build_army("swarm", target_cp, stat_mult, genome)

		# Original: A as ally (team 1), B as enemy (team 0)
		var engine1 := CombatEngine.new()
		engine1.headless = true
		engine1.setup(army_a, army_b)
		while engine1.tick(): pass
		if _count_alive(engine1, 1) > 0 and _count_alive(engine1, 0) == 0:
			a_wins_orig += 1

		# Swapped: A as enemy, B as ally
		var engine2 := CombatEngine.new()
		engine2.headless = true
		engine2.setup(army_b, army_a)  # B as ally now, A as enemy
		while engine2.tick(): pass
		# Count A's wins: A is now team 0 (enemy), so A wins if team 0 alive and team 1 dead
		if _count_alive(engine2, 0) > 0 and _count_alive(engine2, 1) == 0:
			a_wins_swap += 1

	print("Original (A=ally): %d/%d" % [a_wins_orig, runs])
	print("Swapped (A=enemy): %d/%d" % [a_wins_swap, runs])
	print()
	if a_wins_orig != a_wins_swap:
		print("SIDE BIAS CONFIRMED — ally/enemy role produces different outcomes for identical armies.")
	else:
		print("Result invariant to side — bias is not positional.")
	quit(0)


func _build_army(preset_name: String, target_cp: float, stat_mult: float, genome) -> Array:
	var counts: Dictionary = PresetGen.derive_comp(preset_name, target_cp, genome.enemy_stats, stat_mult)
	var units: Array = []
	var BASE := {"swarm_range": 0, "swarm_ms": 3, "melee_range": 0, "melee_ms": 2,
		"ranged_range": 4, "ranged_ms": 1, "heavy_range": 0, "heavy_ms": 1,
		"sniper_range": 6, "sniper_ms": 1}
	for type_name in counts:
		var count: int = int(counts[type_name])
		var stat: Dictionary = genome.get_enemy_stat(type_name)
		var sub_mult: float = PresetGen.sub_mult(preset_name, type_name)
		for _i in count:
			units.append({
				"atk": stat.get("atk", 3.0) * stat_mult * sub_mult,
				"hp": stat.get("hp", 20.0) * stat_mult * sub_mult,
				"attack_speed": stat.get("as", 1.0),
				"range": BASE.get(type_name + "_range", 0),
				"move_speed": BASE.get(type_name + "_ms", 2),
				"radius": 6.0,
			})
	return units


func _count_alive(engine: CombatEngine, team_id: int) -> int:
	var count := 0
	for i in engine.count:
		if engine.alive[i] == 1 and engine.team[i] == team_id:
			count += 1
	return count
