extends GutTest

const ObserverLogic = preload("res://tools/self_play_observer_logic.gd")
const MetaProgressScript = preload("res://core/meta_progress.gd")

var _logic


func before_each() -> void:
	_logic = ObserverLogic.new()


func test_normalize_strategies_all_preserves_known_order() -> void:
	var result: Array = _logic.normalize_strategies("all", ["adaptive", "economy", "aggressive"])

	assert_eq(result, ["adaptive", "economy", "aggressive"])


func test_normalize_strategies_removes_duplicates() -> void:
	var result: Array = _logic.normalize_strategies(
		"adaptive, economy, adaptive",
		["adaptive", "economy", "aggressive"]
	)

	assert_eq(result, ["adaptive", "economy"])


func test_summarize_aggregates_runs_strategies_and_rounds() -> void:
	var results := [
		{
			"strategy": "adaptive",
			"won": true,
			"rounds_played": 15,
			"final_hp": 9,
			"purchase_log": ["spark_drone", "spark_drone", "iron_guard"],
			"merge_events": [{"card_id": "spark_drone", "new_star": 2}],
			"upgrades_purchased": [{"upgrade_id": "reinforced_core"}],
			"boss_rewards_applied": [{"reward_id": "r4_trophy"}],
			"final_deck": [
				{"card_id": "spark_drone", "star_level": 2},
				{"card_id": "iron_guard", "star_level": 1},
			],
			"round_data": [
				{
					"round_num": 1,
					"battle_won": true,
					"total_player_units": 8,
					"total_enemy_units": 4,
					"board_size": 2,
					"chain_events": 3,
					"gold": 2,
				},
			],
		},
		{
			"strategy": "adaptive",
			"won": false,
			"rounds_played": 7,
			"final_hp": 0,
			"purchase_log": ["spark_drone"],
			"merge_events": [],
			"upgrades_purchased": [],
			"boss_rewards_applied": [],
			"final_deck": [{"card_id": "spark_drone", "star_level": 1}],
			"round_data": [
				{
					"round_num": 1,
					"battle_won": false,
					"total_player_units": 3,
					"total_enemy_units": 5,
					"board_size": 1,
					"chain_events": 1,
					"gold": 4,
				},
			],
		},
	]

	var summary: Dictionary = _logic.summarize(results, {"difficulty": 1})
	var overall: Dictionary = summary["overall"]
	var adaptive: Dictionary = summary["per_strategy"]["adaptive"]
	var round_1: Dictionary = summary["per_round"][0]

	assert_eq(summary["schema"], "warforge-self-play-observer/v1")
	assert_eq(overall["total_runs"], 2)
	assert_eq(overall["wins"], 1)
	assert_eq(overall["clear_rate"], 0.5)
	assert_eq(adaptive["avg_rounds_played"], 11.0)
	assert_eq(adaptive["top_purchases"][0], {"id": "spark_drone", "count": 3})
	assert_eq(adaptive["top_merges"][0], {"id": "spark_drone★2", "count": 1})
	assert_eq(round_1["samples"], 2)
	assert_eq(round_1["win_rate"], 0.5)
	assert_eq(round_1["avg_player_units"], 5.5)
	assert_eq(round_1["avg_chain_events"], 2.0)


func test_summarize_formats_low_clear_alert() -> void:
	var results := []
	for i in 5:
		results.append({
			"strategy": "soft_druid",
			"won": false,
			"rounds_played": 9,
			"final_hp": -5,
			"purchase_log": [],
			"merge_events": [],
			"upgrades_purchased": [],
			"boss_rewards_applied": [],
			"final_deck": [],
			"round_data": [],
		})

	var summary: Dictionary = _logic.summarize(results)
	var messages: Array = []
	for alert in summary["alerts"]:
		messages.append(str(alert.get("message", "")))

	assert_has(messages, "Overall clear rate is below 20% across 5 observed runs.")
	assert_has(messages, "soft_druid cleared 0/5 observed runs.")


func test_summarize_reports_completion_milestones_and_loss_rounds() -> void:
	var results := [
		{
			"strategy": "adaptive",
			"won": true,
			"rounds_played": 15,
			"final_hp": 8,
			"purchase_log": [],
			"merge_events": [],
			"merge_upgrades": [],
			"upgrades_purchased": [],
			"boss_rewards_applied": [
				{"round": 4, "reward_id": "r4_2"},
				{"round": 8, "reward_id": "r8_2"},
				{"round": 12, "reward_id": "r12_2"},
			],
			"final_deck": [],
			"round_data": _rounds(15, 12, 20),
		},
		{
			"strategy": "adaptive",
			"won": false,
			"rounds_played": 8,
			"final_hp": -3,
			"purchase_log": [],
			"merge_events": [],
			"merge_upgrades": [],
			"upgrades_purchased": [],
			"boss_rewards_applied": [{"round": 4, "reward_id": "r4_4"}],
			"final_deck": [],
			"round_data": _rounds(8, 10, 20),
		},
		{
			"strategy": "adaptive",
			"won": false,
			"rounds_played": 3,
			"final_hp": -2,
			"purchase_log": [],
			"merge_events": [],
			"merge_upgrades": [],
			"upgrades_purchased": [],
			"boss_rewards_applied": [],
			"final_deck": [],
			"round_data": _rounds(3, 8, 20),
		},
	]

	var completion: Dictionary = _logic.summarize(results)["completion"]
	var r4: Dictionary = _milestone(completion, 4)
	var r8: Dictionary = _milestone(completion, 8)
	var r12: Dictionary = _milestone(completion, 12)

	assert_eq(completion["full_clears"], 1)
	assert_eq(completion["losses"], 2)
	assert_eq(completion["top_loss_rounds"][0], {"id": "R3", "count": 1})
	assert_eq(r4["reached_runs"], 2)
	assert_eq(r4["eligible_runs"], 2)
	assert_eq(r4["reward_runs"], 2)
	assert_eq(r8["reached_runs"], 2)
	assert_eq(r8["eligible_runs"], 2)
	assert_eq(r8["reward_runs"], 1)
	assert_eq(r8["missed_after_reach"], 1)
	assert_eq(r8["missed_after_eligible"], 1)
	assert_eq(r12["reached_runs"], 1)
	assert_eq(r12["eligible_runs"], 1)
	assert_eq(r12["reward_runs"], 1)


func test_summarize_projects_unlock_pressure_from_available_stats() -> void:
	var result := {
		"strategy": "adaptive",
		"won": true,
		"rounds_played": 15,
		"final_hp": 12,
		"purchase_log": [],
		"merge_events": [],
		"merge_upgrades": _dummy_rows(6),
		"upgrades_purchased": _dummy_rows(10),
		"boss_rewards_applied": [],
		"final_deck": [
			{"card_id": "a", "star_level": 2},
			{"card_id": "b", "star_level": 2},
			{"card_id": "c", "star_level": 2},
			{"card_id": "d", "star_level": 2},
			{"card_id": "e", "star_level": 2},
			{"card_id": "f", "star_level": 1},
			{"card_id": "g", "star_level": 1},
		],
		"round_data": _rounds(8, 130, 40, 15),
	}

	var projection: Dictionary = _logic.summarize([result], {"difficulty": 2})[
		"unlock_projection"]
	var run_projection: Dictionary = projection["runs"][0]
	var clear_metric: Dictionary = _metric(projection, "clear")
	var field_metric: Dictionary = _metric(projection, "field_units_120")
	var cards_sold_metric: Dictionary = _metric(projection, "cards_sold_20")

	assert_eq(projection["status"], "partial")
	assert_eq(projection["runs_with_projected_unlocks"], 1)
	assert_gte(int(projection["largest_projected_unlock_count"]), 7)
	assert_eq(projection["pacing_model"]["status"], "ui_reveal")
	assert_eq(projection["pacing_model"]["reveal_cap_per_run"], 3)
	assert_eq(run_projection["projected_revealed_unlock_count"], 3)
	assert_gt(int(run_projection["projected_deferred_unlock_count"]), 0)
	assert_eq(
		run_projection["raw_projected_unlock_count"],
		run_projection["projected_unlock_count"]
	)
	assert_has(run_projection["projected_unlocks"], "difficulty: D3")
	assert_has(run_projection["projected_unlocks"], "talisman: glass_eye")
	assert_has(run_projection["projected_unlocks"], "commander: strategist")
	assert_has(run_projection["projected_unlocks"], "commander: smith")
	assert_has(run_projection["projected_unlocks"], "commander: raider")
	assert_has(run_projection["projected_unlocks"], "talisman: cracked_egg")
	assert_has(run_projection["projected_unlocks"], "talisman: war_drum")
	assert_eq(clear_metric["runs_at_threshold"], 1)
	assert_eq(field_metric["best_value"], 130.0)
	assert_false(bool(cards_sold_metric["observable"]))


func test_trace_stats_make_card_sale_unlock_projection_observable() -> void:
	var result := _minimal_result()
	result["trace_stats"] = {
		"cards_sold": 20,
		"sell_events": 20,
		"source": "ai_tracer.sell events",
	}

	var projection: Dictionary = _logic.summarize([result], {"difficulty": 1})[
		"unlock_projection"]
	var cards_sold_20: Dictionary = _metric(projection, "cards_sold_20")
	var cards_sold_12: Dictionary = _metric(projection, "cards_sold_12")
	var run_projection: Dictionary = projection["runs"][0]

	assert_eq(projection["status"], "complete")
	assert_true(bool(cards_sold_20["observable"]))
	assert_eq(cards_sold_20["best_value"], 20.0)
	assert_eq(cards_sold_20["confidence"], "trace_event_count")
	assert_eq(cards_sold_12["runs_at_threshold"], 1)
	assert_has(run_projection["projected_unlocks"], "commander: alchemist")
	assert_has(run_projection["projected_unlocks"], "talisman: soul_jar")


func test_completion_readiness_ranks_weak_strategy_floor() -> void:
	var results := []
	for i in 5:
		results.append({
			"strategy": "soft_druid",
			"won": false,
			"rounds_played": 7,
			"final_hp": -4,
			"purchase_log": [],
			"merge_events": [],
			"merge_upgrades": [],
			"upgrades_purchased": [],
			"boss_rewards_applied": [{"round": 4, "reward_id": "r4_2"}],
			"final_deck": [],
			"round_data": _rounds(7, 9, 18),
		})
	for i in 5:
		results.append({
			"strategy": "adaptive",
			"won": true,
			"rounds_played": 15,
			"final_hp": 10,
			"purchase_log": [],
			"merge_events": [],
			"merge_upgrades": [],
			"upgrades_purchased": [],
			"boss_rewards_applied": [
				{"round": 4, "reward_id": "r4_2"},
				{"round": 8, "reward_id": "r8_2"},
				{"round": 12, "reward_id": "r12_2"},
			],
			"final_deck": [],
			"round_data": _rounds(15, 16, 14),
		})

	var readiness: Dictionary = _logic.summarize(results, {
		"difficulty": 1,
		"strategies": ["soft_druid", "adaptive"],
	})["completion_readiness"]
	var top_risk: Dictionary = readiness["top_risks"][0]

	assert_eq(readiness["status"], "needs_attention")
	assert_eq(readiness["sample"]["total_runs"], 10)
	assert_eq(readiness["sample"]["min_runs_per_strategy"], 5)
	assert_eq(top_risk["rank"], 1)
	assert_eq(top_risk["code"], "weak_strategy_floor")
	assert_eq(top_risk["severity"], "high")
	assert_string_contains(top_risk["evidence"], "soft_druid 0/5 clears")
	assert_string_contains(readiness["recommended_next_slice"], "worst strategy lane")


func test_completion_readiness_flags_low_nonzero_strategy_floor() -> void:
	var results := []
	for i in 3:
		results.append(_readiness_result("soft_druid", true, 15, 4))
	for i in 17:
		results.append(_readiness_result("soft_druid", false, 11, -6))
	for i in 20:
		results.append(_readiness_result("adaptive", true, 15, 12))

	var readiness: Dictionary = _logic.summarize(results, {
		"difficulty": 1,
		"strategies": ["soft_druid", "adaptive"],
	})["completion_readiness"]
	var top_risk: Dictionary = readiness["top_risks"][0]

	assert_eq(readiness["status"], "needs_attention")
	assert_eq(readiness["sample"]["total_runs"], 40)
	assert_eq(readiness["sample"]["min_runs_per_strategy"], 20)
	assert_eq(top_risk["code"], "weak_strategy_floor")
	assert_eq(top_risk["severity"], "high")
	assert_string_contains(top_risk["evidence"], "soft_druid 3/20 clears")
	assert_string_contains(top_risk["evidence"], "15.0%")


func test_completion_readiness_does_not_high_flag_strategy_at_low_floor_boundary() -> void:
	var results := []
	for i in 4:
		results.append(_readiness_result("soft_druid", true, 15, 4))
	for i in 16:
		results.append(_readiness_result("soft_druid", false, 11, -6))
	for i in 20:
		results.append(_readiness_result("adaptive", true, 15, 12))

	var readiness: Dictionary = _logic.summarize(results, {
		"difficulty": 1,
		"strategies": ["soft_druid", "adaptive"],
	})["completion_readiness"]
	var risk_codes: Array[String] = []
	for risk in readiness["top_risks"]:
		risk_codes.append(str(risk.get("code", "")))

	assert_eq(readiness["status"], "watch")
	assert_false(risk_codes.has("weak_strategy_floor"))


func test_unlock_projection_thresholds_match_meta_progress_design() -> void:
	var projection: Dictionary = _logic.summarize([_minimal_result()],
		{"difficulty": 1})["unlock_projection"]

	assert_eq(_metric(projection, "field_units_120")["threshold"],
		MetaProgressScript.FIELD_UNITS_THRESHOLD)
	assert_eq(_metric(projection, "attached_upgrades_16")["threshold"],
		MetaProgressScript.ATTACHED_UPGRADES_COMMANDER_THRESHOLD)
	assert_eq(_metric(projection, "attached_upgrades_12")["threshold"],
		MetaProgressScript.ATTACHED_UPGRADES_TALISMAN_THRESHOLD)
	assert_eq(_metric(projection, "unique_field_cards_7")["threshold"],
		MetaProgressScript.UNIQUE_FIELD_CARDS_THRESHOLD)
	assert_eq(_metric(projection, "win_streak_8")["threshold"],
		MetaProgressScript.WIN_STREAK_THRESHOLD)
	assert_eq(_metric(projection, "cards_sold_20")["threshold"],
		MetaProgressScript.CARDS_SOLD_COMMANDER_THRESHOLD)
	assert_eq(_metric(projection, "cards_sold_12")["threshold"],
		MetaProgressScript.CARDS_SOLD_TALISMAN_THRESHOLD)
	assert_eq(_metric(projection, "growth_events_120")["threshold"],
		MetaProgressScript.GROWTH_EVENTS_THRESHOLD)
	assert_eq(_metric(projection, "star2_cards_5")["threshold"],
		MetaProgressScript.STAR2_CARDS_THRESHOLD)
	assert_eq(_metric(projection, "unit_advantage_wins_5")["threshold"],
		MetaProgressScript.UNIT_ADVANTAGE_WINS_THRESHOLD)


func _rounds(count: int, player_units: int, enemy_units: int,
		chain_events: int = 1) -> Array:
	var rows: Array = []
	for i in count:
		rows.append({
			"round_num": i + 1,
			"battle_won": true,
			"total_player_units": player_units,
			"total_enemy_units": enemy_units,
			"board_size": 5,
			"chain_events": chain_events,
			"gold": 10,
		})
	return rows


func _dummy_rows(count: int) -> Array:
	var rows: Array = []
	for i in count:
		rows.append({"idx": i})
	return rows


func _readiness_result(strategy: String, won: bool, rounds_played: int,
		final_hp: int) -> Dictionary:
	var rewards := []
	if rounds_played >= 4:
		rewards.append({"round": 4, "reward_id": "r4_2"})
	if rounds_played >= 8:
		rewards.append({"round": 8, "reward_id": "r8_2"})
	if rounds_played >= 12:
		rewards.append({"round": 12, "reward_id": "r12_2"})
	return {
		"strategy": strategy,
		"won": won,
		"rounds_played": rounds_played,
		"final_hp": final_hp,
		"purchase_log": [],
		"merge_events": [],
		"merge_upgrades": [],
		"upgrades_purchased": [],
		"boss_rewards_applied": rewards,
		"final_deck": [],
		"round_data": _rounds(rounds_played, 12, 10),
	}


func _minimal_result() -> Dictionary:
	return {
		"strategy": "adaptive",
		"won": false,
		"rounds_played": 1,
		"final_hp": 1,
		"purchase_log": [],
		"merge_events": [],
		"merge_upgrades": [],
		"upgrades_purchased": [],
		"boss_rewards_applied": [],
		"final_deck": [],
		"round_data": [],
	}


func _milestone(completion: Dictionary, round_num: int) -> Dictionary:
	for row in completion["boss_milestones"]:
		if int(row.get("round", 0)) == round_num:
			return row
	return {}


func _metric(projection: Dictionary, metric_id: String) -> Dictionary:
	for row in projection["metrics"]:
		if str(row.get("id", "")) == metric_id:
			return row
	return {}
