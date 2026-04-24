extends SceneTree
## Lightweight runner for calibrate_target_cp.py.
##
## Runs HeadlessRunner N times per strategy, aggregates per-round WR, outputs JSON.
## Does NOT call Evaluator (calibration doesn't need full fitness score — only
## per-round WR to compare with target_wr_curve). Much cheaper than batch_runner.gd.
##
## Output JSON:
##   {
##     "per_round_wr": [15 floats],         # R1..R15 clear rate
##     "per_round_totals": [15 ints],       # runs that reached round r
##     "per_round_wins": [15 ints],
##     "total_runs": int,
##     "overall_clear_rate": float,
##     "avg_rounds_played": float
##   }
##
## Usage:
##   godot --headless --path godot/ -s sim/calibration_runner.gd -- \
##     --genome=res://sim/best_genome.json --runs=20 --seed=42


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var _GenomeClass = load("res://sim/genome.gd")
	var _RunnerClass = load("res://sim/headless_runner.gd")
	var _AgentClass = load("res://sim/ai_agent.gd")

	var args := _parse_args()
	var genome_path: String = args.get("genome", "res://sim/default_genome.json")
	var runs_per_ai: int = args.get("runs", 20)
	var base_seed: int = args.get("seed", 42)

	var genome = _GenomeClass.load_file(genome_path)
	if genome == null:
		printerr("ERROR: Failed to load genome from %s" % genome_path)
		quit(1)
		return

	var strategies: Array = _AgentClass.STRATEGY_NAMES

	var per_round_wins: Array = []
	var per_round_totals: Array = []
	per_round_wins.resize(15)
	per_round_totals.resize(15)
	for i in 15:
		per_round_wins[i] = 0
		per_round_totals[i] = 0

	var total_games := 0
	var total_wins := 0
	var total_rounds_played := 0

	printerr("=== Calibration Runner ===")
	printerr("Genome: %s" % genome_path)
	printerr("Runs: %d × %d = %d" % [runs_per_ai, strategies.size(), runs_per_ai * strategies.size()])

	for strat in strategies:
		for i in runs_per_ai:
			var seed_val: int = base_seed + hash(strat) + i
			var runner = _RunnerClass.new(genome, strat, seed_val)
			var result: Dictionary = runner.run()
			total_games += 1
			total_rounds_played += int(result.get("rounds_played", 0))
			if result.get("won", false):
				total_wins += 1
			for rd in result.get("round_data", []):
				var rn: int = int(rd.get("round_num", 0)) - 1
				if rn >= 0 and rn < 15:
					per_round_totals[rn] += 1
					if rd.get("battle_won", false):
						per_round_wins[rn] += 1

	var per_round_wr: Array = []
	for r in 15:
		var t: int = per_round_totals[r]
		var w: int = per_round_wins[r]
		per_round_wr.append(float(w) / t if t > 0 else 0.0)

	var out := {
		"per_round_wr": per_round_wr,
		"per_round_totals": per_round_totals,
		"per_round_wins": per_round_wins,
		"total_runs": total_games,
		"overall_clear_rate": float(total_wins) / total_games if total_games > 0 else 0.0,
		"avg_rounds_played": float(total_rounds_played) / total_games if total_games > 0 else 0.0,
	}

	print(JSON.stringify(out, "  "))
	printerr("Overall clear: %d/%d = %.1f%%" % [total_wins, total_games, float(total_wins) / total_games * 100.0])
	quit(0)


func _parse_args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--genome="):
			result["genome"] = arg.substr(9)
		elif arg.begins_with("--runs="):
			result["runs"] = arg.substr(7).to_int()
		elif arg.begins_with("--seed="):
			result["seed"] = arg.substr(7).to_int()
	return result
