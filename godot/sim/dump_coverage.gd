extends SceneTree
## One-off coverage dump: runs 20 × 7 strategies, saves per-run purchase_log + final_deck.
## Usage: godot --headless --path . -s sim/dump_coverage.gd -- --out=/tmp/coverage.json

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var _Genome = load("res://sim/genome.gd")
	var _Runner = load("res://sim/headless_runner.gd")
	var _Agent = load("res://sim/ai_agent.gd")

	var out_path := "/tmp/coverage.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.substr(6)

	var genome = _Genome.load_file("res://sim/best_genome.json")
	if genome == null:
		printerr("Failed to load best_genome.json")
		quit(1)
		return

	var strategies: Array = _Agent.STRATEGY_NAMES
	var all_runs: Array = []

	for strat in strategies:
		for i in 20:
			var seed_val: int = 42 + hash(strat) + i
			var runner = _Runner.new(genome, strat, seed_val)
			var result: Dictionary = runner.run()
			all_runs.append({
				"strategy": strat,
				"seed": seed_val,
				"won": result["won"],
				"rounds_played": result["rounds_played"],
				"purchase_log": result["purchase_log"],
				"final_deck": result["final_deck"],
			})
		printerr("Done %s (20 runs)" % strat)

	var f = FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"runs": all_runs}, "  "))
	f.close()
	print("Saved %d runs to %s" % [all_runs.size(), out_path])
	quit(0)
