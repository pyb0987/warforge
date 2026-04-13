extends SceneTree
## AI Research batch runner. Evaluates with BOTH game balance + AI quality axes.
##
## Usage:
##   godot --headless --path godot/ -s sim/ai_research/ai_batch_runner.gd -- \
##     --genome=res://sim/ai_research/ai_best_genome.json --runs=20 --seed=42
##
## Output: JSON with game balance scores + AI quality scores to stdout.


func _init() -> void:
	process_frame.connect(_run_batch, CONNECT_ONE_SHOT)


func _run_batch() -> void:
	var _GenomeClass = load("res://sim/genome.gd")
	var _RunnerClass = load("res://sim/headless_runner.gd")
	var _AgentClass = load("res://sim/ai_agent.gd")
	var _EvalClass = load("res://sim/evaluator.gd")
	var _AIEvalClass = load("res://sim/ai_evaluator.gd")

	var args := _parse_args()
	var genome_path: String = args.get("genome", "res://sim/ai_research/ai_best_genome.json")
	var runs_per_ai: int = args.get("runs", 20)
	var base_seed: int = args.get("seed", 42)

	var genome = _GenomeClass.load_file(genome_path)
	if genome == null:
		printerr("ERROR: Failed to load genome from %s" % genome_path)
		quit(1)
		return

	var strategies: Array = _AgentClass.STRATEGY_NAMES
	var results: Array = []
	var total: int = strategies.size() * runs_per_ai
	var done := 0

	printerr("=== AI Research Batch Runner ===")
	printerr("Genome: %s" % genome_path)
	printerr("Runs per AI: %d x %d strategies = %d total" % [runs_per_ai, strategies.size(), total])

	for strat in strategies:
		for i in runs_per_ai:
			var seed_val: int = base_seed + hash(strat) + i
			var runner = _RunnerClass.new(genome, strat, seed_val)
			var result: Dictionary = runner.run()
			results.append(result)
			done += 1
			if done % 10 == 0:
				printerr("  Progress: %d/%d (%.0f%%)" % [done, total, float(done) / total * 100])

	# Game balance evaluation (existing 9-axis)
	printerr("Evaluating game balance (%d results)..." % results.size())
	var game_score: Dictionary = _EvalClass.evaluate(results)

	# AI quality evaluation (4-axis)
	printerr("Evaluating AI quality...")
	var ai_score: Dictionary = _AIEvalClass.evaluate(results)

	# Merge into single output
	var score: Dictionary = game_score.duplicate()
	score["ai_quality"] = ai_score

	# Metadata
	score["metadata"] = {
		"genome_path": genome_path,
		"runs_per_ai": runs_per_ai,
		"total_runs": results.size(),
		"base_seed": base_seed,
		"strategies": strategies,
		"evaluator": "game_balance + ai_quality",
	}

	# Per-strategy stats
	var strat_stats: Dictionary = {}
	for r in results:
		var s: String = r.strategy
		if not strat_stats.has(s):
			strat_stats[s] = {"wins": 0, "total": 0, "avg_hp": 0.0}
		strat_stats[s].total += 1
		if r.won:
			strat_stats[s].wins += 1
		strat_stats[s].avg_hp += r.final_hp
	for s in strat_stats:
		strat_stats[s].avg_hp /= strat_stats[s].total
		strat_stats[s]["win_rate"] = float(strat_stats[s].wins) / strat_stats[s].total
	score["strategy_stats"] = strat_stats

	# Axis delta if baseline provided
	var baseline_path: String = args.get("baseline", "")
	if baseline_path != "":
		var baseline_score: Dictionary = _load_baseline(baseline_path)
		if not baseline_score.is_empty():
			var axis_delta: Dictionary = {}
			for key in _EvalClass.WEIGHTS:
				var cur: float = score.get(key, 0.0)
				var base: float = baseline_score.get(key, 0.0)
				axis_delta[key] = cur - base
			axis_delta["weighted_score"] = score.weighted_score - baseline_score.get("weighted_score", 0.0)
			# AI quality deltas
			var base_ai: Dictionary = baseline_score.get("ai_quality", {})
			for key in _AIEvalClass.WEIGHTS:
				axis_delta["ai_" + key] = ai_score.get(key, 0.0) - base_ai.get(key, 0.0)
			axis_delta["ai_quality_score"] = ai_score.get("ai_quality_score", 0.0) - base_ai.get("ai_quality_score", 0.0)
			score["axis_delta"] = axis_delta

	print(JSON.stringify(score, "  "))

	printerr("=== Done ===")
	printerr("Game weighted_score: %.4f | AI quality: %.4f" % [
		score.weighted_score, ai_score.get("ai_quality_score", 0.0)])
	quit(0)


func _load_baseline(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		printerr("WARNING: Baseline file not found: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	return json.data


func _parse_args() -> Dictionary:
	var result := {}
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--genome="):
			result["genome"] = arg.substr(9)
		elif arg.begins_with("--runs="):
			result["runs"] = arg.substr(7).to_int()
		elif arg.begins_with("--seed="):
			result["seed"] = arg.substr(7).to_int()
		elif arg.begins_with("--baseline="):
			result["baseline"] = arg.substr(11)
	return result
