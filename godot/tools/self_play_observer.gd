extends SceneTree
## Self-play observability runner.
##
## Example:
## godot --headless --path godot/ -s tools/self_play_observer.gd -- \
##   --runs=3 --strategies=adaptive,soft_steampunk --difficulty=1 \
##   --out=/private/tmp/warforge_selfplay.json \
##   --trace-dir=/private/tmp/warforge_selfplay_traces

const DEFAULT_GENOME_PATH := "res://sim/best_genome.json"
const DEFAULT_RUNS := 3
const DEFAULT_SEED := 42
const DEFAULT_DIFFICULTY := 1
const DEFAULT_TRACE_STATS := true
const COMMANDER_IDS := {
	"none": 0,
	"gambler": 1,
	"breeder": 2,
	"smith": 3,
	"strategist": 4,
	"collector": 5,
	"raider": 6,
	"alchemist": 7,
}
const COMMANDER_LABELS := {
	0: "NONE",
	1: "도박꾼",
	2: "양성가",
	3: "단조사",
	4: "전략가",
	5: "수집가",
	6: "약탈자",
	7: "연금술사",
}
const TALISMAN_IDS := {
	"none": 0,
	"burst_sack": 1,
	"war_drum": 2,
	"mercury_drop": 3,
	"glass_eye": 4,
	"two_faced_coin": 5,
	"golden_die": 6,
	"cracked_egg": 7,
	"flint": 8,
	"cracked_skull": 9,
	"rusty_wrench": 10,
	"soul_jar": 11,
	"copper_wire": 12,
}
const TALISMAN_LABELS := {
	0: "NONE",
	1: "터진 자루",
	2: "전쟁 북",
	3: "수은 방울",
	4: "유리 눈",
	5: "양면 동전",
	6: "황금 주사위",
	7: "깨진 알",
	8: "부싯돌",
	9: "금간 해골",
	10: "녹슨 렌치",
	11: "영혼 항아리",
	12: "구리 전선",
}

var _Logic = preload("res://tools/self_play_observer_logic.gd")


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var GenomeClass = load("res://sim/genome.gd")
	var RunnerClass = load("res://sim/headless_runner.gd")
	var AgentClass = load("res://sim/ai_agent.gd")
	var TracerClass = load("res://sim/ai_tracer.gd")

	var args: Dictionary = _parse_args()
	var runs_per_strategy: int = max(1, int(args.get("runs", DEFAULT_RUNS)))
	var base_seed: int = int(args.get("seed", DEFAULT_SEED))
	var difficulty: int = clampi(int(args.get("difficulty", DEFAULT_DIFFICULTY)), 1, 8)
	var commander_type: int = _parse_named_id(args.get("commander", "none"),
		COMMANDER_IDS, "commander")
	var talisman_type: int = _parse_named_id(args.get("talisman", "none"),
		TALISMAN_IDS, "talisman")
	if commander_type < 0 or talisman_type < 0:
		quit(2)
		return
	var genome_path: String = str(args.get("genome", DEFAULT_GENOME_PATH))
	var trace_dir: String = str(args.get("trace-dir", ""))
	var out_path: String = str(args.get("out", ""))
	var include_results: bool = _bool_arg(args, "include-results", false)
	var quiet_progress: bool = _bool_arg(args, "quiet-progress", false)
	var trace_stats: bool = _bool_arg(args, "trace-stats", DEFAULT_TRACE_STATS)

	var logic = _Logic.new()
	var strategies: Array = logic.normalize_strategies(
		str(args.get("strategies", "all")),
		AgentClass.STRATEGY_NAMES
	)
	if strategies.is_empty():
		printerr("ERROR: no valid strategies selected")
		quit(2)
		return

	var genome = GenomeClass.load_file(genome_path)
	if genome == null:
		printerr("ERROR: failed to load genome: %s" % genome_path)
		quit(1)
		return

	if trace_dir != "":
		var err: Error = _ensure_dir(trace_dir)
		if err != OK:
			printerr("ERROR: failed to create trace dir %s: %s" % [trace_dir, error_string(err)])
			quit(1)
			return

	var results: Array = []
	var run_index: int = 0
	for strategy_value in strategies:
		var strategy: String = str(strategy_value)
		for i in range(runs_per_strategy):
			var seed_val: int = base_seed + int(hash(strategy)) + int(i)
			var runner = RunnerClass.new(genome, strategy, seed_val, difficulty)
			if runner.has_method("set_run_identity"):
				runner.set_run_identity(commander_type, talisman_type)
			var tracer = null
			if trace_dir != "" or trace_stats:
				tracer = TracerClass.new()
				tracer.enabled = true
				runner.set_tracer(tracer)

			var result: Dictionary = runner.run()
			if tracer != null and trace_stats:
				result["trace_stats"] = _derive_trace_stats(tracer.events)
			results.append(result)
			run_index += 1

			if tracer != null:
				if trace_dir != "":
					var trace_path: String = _join_path(trace_dir,
						"%s_%d.jsonl" % [strategy, seed_val])
					var trace_err: Error = tracer.flush_to_file(trace_path)
					if trace_err != OK:
						printerr("ERROR: failed to write trace %s: %s" % [
							trace_path, error_string(trace_err)])
						quit(1)
						return
				else:
					tracer.events.clear()

			if not quiet_progress:
				var outcome: String = "WIN" if bool(result.get("won", false)) else "LOSE"
				printerr("[self-play] %d/%d %s seed=%d %s hp=%d rounds=%d" % [
					run_index,
					strategies.size() * runs_per_strategy,
					strategy,
					seed_val,
					outcome,
					int(result.get("final_hp", 0)),
					int(result.get("rounds_played", 0)),
				])

	var metadata: Dictionary = {
		"genome_path": genome_path,
		"runs_per_strategy": runs_per_strategy,
		"base_seed": base_seed,
		"difficulty": difficulty,
		"commander_type": commander_type,
		"commander_name": COMMANDER_LABELS.get(commander_type, str(commander_type)),
		"talisman_type": talisman_type,
		"talisman_name": TALISMAN_LABELS.get(talisman_type, str(talisman_type)),
			"strategies": strategies,
			"total_runs": results.size(),
			"trace_dir": trace_dir,
			"trace_stats": trace_stats,
		}
	var summary: Dictionary = logic.summarize(results, metadata)
	if include_results:
		summary["results"] = results

	if out_path != "":
		var write_err: Error = _write_json(out_path, summary)
		if write_err != OK:
			printerr("ERROR: failed to write summary %s: %s" % [out_path, error_string(write_err)])
			quit(1)
			return

	print(JSON.stringify(summary, "\t"))
	quit(0)


func _parse_args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var parts: PackedStringArray = arg.substr(2).split("=", true, 1)
		var key: String = str(parts[0])
		var raw_value: String = "true" if parts.size() == 1 else str(parts[1])
		if raw_value.is_valid_int():
			result[key] = raw_value.to_int()
		else:
			result[key] = raw_value
	return result


func _derive_trace_stats(events: Array) -> Dictionary:
	var cards_sold := 0
	var sell_reasons := {}
	var sell_zones := {}
	for event_value in events:
		var event: Dictionary = event_value
		if str(event.get("t", "")) != "sell":
			continue
		cards_sold += 1
		_inc_count(sell_reasons, str(event.get("reason", "unknown")))
		_inc_count(sell_zones, str(event.get("zone", "unknown")))
	return {
		"cards_sold": cards_sold,
		"sell_events": cards_sold,
		"sell_reasons": sell_reasons,
		"sell_zones": sell_zones,
		"source": "ai_tracer.sell events",
	}


func _parse_named_id(value: Variant, lookup: Dictionary, label: String) -> int:
	var normalized: String = str(value).strip_edges().to_lower().replace("-", "_")
	if normalized.is_valid_int():
		return normalized.to_int()
	if lookup.has(normalized):
		return int(lookup[normalized])
	printerr("ERROR: unknown %s '%s'" % [label, str(value)])
	return -1


func _bool_arg(args: Dictionary, key: String, default_value: bool) -> bool:
	if not args.has(key):
		return default_value
	var value = args[key]
	if value is bool:
		return value
	var value_text: String = str(value).to_lower()
	return value_text in ["1", "true", "yes", "on"]


func _inc_count(counts: Dictionary, key: String) -> void:
	counts[key] = int(counts.get(key, 0)) + 1


func _write_json(path: String, data: Dictionary) -> Error:
	var dir: String = path.get_base_dir()
	if dir != "":
		var dir_err: Error = _ensure_dir(dir)
		if dir_err != OK:
			return dir_err

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.store_line("")
	file.close()
	return OK


func _ensure_dir(path: String) -> Error:
	if path == "":
		return OK
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


func _join_path(dir: String, filename: String) -> String:
	return dir.trim_suffix("/") + "/" + filename
