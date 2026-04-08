extends SceneTree
## Debug single game — outputs per-round board state for analysis.

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var _GenomeClass = load("res://sim/genome.gd")
	var _RunnerClass = load("res://sim/headless_runner.gd")

	var args := _parse_args()
	var strat: String = args.get("strategy", "druid_focused")
	var seed_val: int = args.get("seed", 42)
	var genome_path: String = args.get("genome", "res://sim/best_genome.json")

	var genome = _GenomeClass.load_file(genome_path)
	if genome == null:
		printerr("ERROR: genome load fail")
		quit(1)
		return

	var runner = _RunnerClass.new(genome, strat, seed_val)
	var result: Dictionary = runner.run()

	print("=== %s | seed=%d | %s | HP=%d ===" % [
		strat, seed_val,
		"WIN" if result["won"] else "LOSE",
		result["final_hp"]])

	# Purchase log
	var _cdb = Engine.get_singleton("CardDB") if Engine.has_singleton("CardDB") else null
	print("\n--- PURCHASES ---")
	for cid in result["purchase_log"]:
		if _cdb:
			var tmpl: Dictionary = _cdb.get_template(cid)
			var theme: int = tmpl.get("theme", 0)
			var tier: int = tmpl.get("tier", 1)
			var theme_name: String = ["NE", "SP", "DR", "PR", "ML"][theme]
			print("  T%d %s %s" % [tier, theme_name, cid])
		else:
			print("  %s" % cid)

	# Per-round summary
	print("\n--- ROUNDS ---")
	for rd in result["round_data"]:
		var r: int = rd["round_num"]
		var won_str: String = "W" if rd["battle_won"] else "L"
		print("R%02d %s | units=%d vs %d | board=%d | chain=%d | gold=%d" % [
			r, won_str,
			rd["total_player_units"], rd["total_enemy_units"],
			rd["board_size"], rd["chain_events"], rd["gold"]])

	# Final deck
	print("\n--- FINAL DECK ---")
	for card in result["final_deck"]:
		var cid: String = card["card_id"]
		var star: int = card["star_level"]
		var theme: int = card["theme"]
		var theme_name: String = ["NE", "SP", "DR", "PR", "ML"][theme]
		print("  ★%d %s %s (pos=%d)" % [star, theme_name, cid, card["position"]])

	# Merge events
	if not result["merge_events"].is_empty():
		print("\n--- MERGES ---")
		for m in result["merge_events"]:
			print("  R%d %s → ★%d" % [m["round"], m["card_id"], m["new_star"]])

	quit(0)


func _parse_args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var parts := arg.substr(2).split("=", true, 1)
			if parts.size() == 2:
				var key: String = parts[0]
				var val: String = parts[1]
				if val.is_valid_int():
					result[key] = val.to_int()
				else:
					result[key] = val
	return result
