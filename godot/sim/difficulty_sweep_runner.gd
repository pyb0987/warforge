extends SceneTree
## Runs a D1-D8 headless calibration sweep and outputs aggregate JSON.
##
## Usage:
##   godot --headless --path godot/ -s sim/difficulty_sweep_runner.gd -- \
##     --genome=res://sim/best_genome.json --runs=5 --seed=42

const MAX_ROUNDS := 15


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var _GenomeClass = load("res://sim/genome.gd")
	var _RunnerClass = load("res://sim/headless_runner.gd")
	var _AgentClass = load("res://sim/ai_agent.gd")

	var args := _parse_args()
	var genome_path: String = args.get("genome", "res://sim/default_genome.json")
	var runs_per_ai: int = args.get("runs", 5)
	var base_seed: int = args.get("seed", 42)
	var min_difficulty: int = _clamp_difficulty(args.get("min_difficulty", 1))
	var max_difficulty: int = _clamp_difficulty(args.get("max_difficulty", 8))
	if max_difficulty < min_difficulty:
		var tmp := min_difficulty
		min_difficulty = max_difficulty
		max_difficulty = tmp

	var genome = _GenomeClass.load_file(genome_path)
	if genome == null:
		printerr("ERROR: Failed to load genome from %s" % genome_path)
		quit(1)
		return

	var strategies: Array = _AgentClass.STRATEGY_NAMES
	var results: Array = []

	printerr("=== Difficulty Sweep Runner ===")
	printerr("Genome: %s" % genome_path)
	printerr("Difficulties: D%d-D%d" % [min_difficulty, max_difficulty])
	printerr("Runs: %d × %d strategies × %d difficulties = %d total" % [
		runs_per_ai,
		strategies.size(),
		max_difficulty - min_difficulty + 1,
		runs_per_ai * strategies.size() * (max_difficulty - min_difficulty + 1),
	])

	for difficulty in range(min_difficulty, max_difficulty + 1):
		results.append(_run_difficulty(
			difficulty, genome, strategies, runs_per_ai, base_seed, _RunnerClass))

	var out := {
		"genome_path": genome_path,
		"runs_per_ai": runs_per_ai,
		"base_seed": base_seed,
		"strategies": strategies,
		"results": results,
	}
	print(JSON.stringify(out, "  "))
	quit(0)


func _run_difficulty(difficulty: int, genome, strategies: Array,
		runs_per_ai: int, base_seed: int, runner_class) -> Dictionary:
	var per_round_wins: Array = []
	var per_round_totals: Array = []
	per_round_wins.resize(MAX_ROUNDS)
	per_round_totals.resize(MAX_ROUNDS)
	for i in MAX_ROUNDS:
		per_round_wins[i] = 0
		per_round_totals[i] = 0

	var total_games := 0
	var total_wins := 0
	var total_rounds_played := 0
	var total_final_hp := 0
	var strategy_stats: Dictionary = {}

	for strat in strategies:
		strategy_stats[strat] = {"wins": 0, "total": 0, "avg_rounds": 0.0, "avg_hp": 0.0}
		for i in runs_per_ai:
			var seed_val: int = base_seed + hash(strat) + i
			var runner = runner_class.new(genome, strat, seed_val, difficulty)
			var result: Dictionary = runner.run()
			total_games += 1
			total_rounds_played += int(result.get("rounds_played", 0))
			total_final_hp += int(result.get("final_hp", 0))

			strategy_stats[strat].total += 1
			strategy_stats[strat].avg_rounds += int(result.get("rounds_played", 0))
			strategy_stats[strat].avg_hp += int(result.get("final_hp", 0))
			if result.get("won", false):
				total_wins += 1
				strategy_stats[strat].wins += 1

			for rd in result.get("round_data", []):
				var rn: int = int(rd.get("round_num", 0)) - 1
				if rn >= 0 and rn < MAX_ROUNDS:
					per_round_totals[rn] += 1
					if rd.get("battle_won", false):
						per_round_wins[rn] += 1

	for strat in strategy_stats:
		var total: int = strategy_stats[strat].total
		if total > 0:
			strategy_stats[strat].avg_rounds /= total
			strategy_stats[strat].avg_hp /= total
			strategy_stats[strat]["win_rate"] = float(strategy_stats[strat].wins) / total
		else:
			strategy_stats[strat]["win_rate"] = 0.0

	var per_round_wr: Array = []
	for r in MAX_ROUNDS:
		var round_total: int = per_round_totals[r]
		var round_wins: int = per_round_wins[r]
		per_round_wr.append(float(round_wins) / round_total if round_total > 0 else 0.0)

	var avg_rounds := float(total_rounds_played) / total_games if total_games > 0 else 0.0
	var avg_hp := float(total_final_hp) / total_games if total_games > 0 else 0.0
	var clear_rate := float(total_wins) / total_games if total_games > 0 else 0.0
	printerr("D%d clear %.1f%%, avg rounds %.2f, avg hp %.1f" % [
		difficulty, clear_rate * 100.0, avg_rounds, avg_hp])

	return {
		"difficulty": difficulty,
		"total_runs": total_games,
		"clear_rate": clear_rate,
		"avg_rounds_played": avg_rounds,
		"avg_final_hp": avg_hp,
		"per_round_wr": per_round_wr,
		"per_round_totals": per_round_totals,
		"per_round_wins": per_round_wins,
		"strategy_stats": strategy_stats,
	}


func _parse_args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--genome="):
			result["genome"] = arg.substr(9)
		elif arg.begins_with("--runs="):
			result["runs"] = arg.substr(7).to_int()
		elif arg.begins_with("--seed="):
			result["seed"] = arg.substr(7).to_int()
		elif arg.begins_with("--min-difficulty="):
			result["min_difficulty"] = arg.substr(17).to_int()
		elif arg.begins_with("--max-difficulty="):
			result["max_difficulty"] = arg.substr(17).to_int()
	return result


func _clamp_difficulty(value: int) -> int:
	return clampi(value, 1, 8)
