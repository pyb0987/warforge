class_name SelfPlayObserverLogic
extends RefCounted

const MAX_ROUNDS := 15
const TOP_LIMIT := 10
const SCHEMA := "warforge-self-play-observer/v1"
const BOSS_MILESTONE_ROUNDS := [4, 8, 12]
const PROJECTED_UNLOCK_REVEAL_CAP := 3
# Mirrors MetaProgress/replay unlock thresholds without preloading MetaProgress.
# MetaProgress depends on run-start UI data helpers that are noisy in -s tools.
const FIELD_UNITS_THRESHOLD := 120
const ATTACHED_UPGRADES_COMMANDER_THRESHOLD := 16
const ATTACHED_UPGRADES_TALISMAN_THRESHOLD := 12
const UNIQUE_FIELD_CARDS_THRESHOLD := 7
const WIN_STREAK_THRESHOLD := 8
const CARDS_SOLD_COMMANDER_THRESHOLD := 20
const CARDS_SOLD_TALISMAN_THRESHOLD := 12
const GROWTH_EVENTS_THRESHOLD := 120
const STAR2_CARDS_THRESHOLD := 5
const UNIT_ADVANTAGE_WINS_THRESHOLD := 5


func normalize_strategies(raw: String, all_strategies: Array) -> Array:
	var trimmed := raw.strip_edges()
	if trimmed == "" or trimmed == "all":
		return all_strategies.duplicate()

	var normalized: Array = []
	for part in trimmed.split(",", false):
		var strategy := part.strip_edges()
		if strategy == "":
			continue
		if not all_strategies.has(strategy):
			push_error("Unknown self-play strategy: %s" % strategy)
			return []
		if not normalized.has(strategy):
			normalized.append(strategy)
	return normalized


func summarize(results: Array, metadata: Dictionary = {}) -> Dictionary:
	var total_acc := _new_strategy_acc()
	var strategy_accs := {}
	var round_accs := _new_round_accs()

	for result in results:
		var strategy := str(result.get("strategy", "unknown"))
		if not strategy_accs.has(strategy):
			strategy_accs[strategy] = _new_strategy_acc()

		_accumulate_strategy(total_acc, result)
		_accumulate_strategy(strategy_accs[strategy], result)
		_accumulate_rounds(round_accs, result.get("round_data", []))

	var per_strategy := {}
	var strategy_names := strategy_accs.keys()
	strategy_names.sort()
	for strategy in strategy_names:
		per_strategy[strategy] = _finish_strategy(strategy_accs[strategy])

	var summary := {
		"schema": SCHEMA,
		"metadata": metadata.duplicate(true),
		"overall": _finish_strategy(total_acc),
		"per_strategy": per_strategy,
		"per_round": _finish_rounds(round_accs),
	}
	summary["completion"] = _make_completion_summary(results)
	summary["unlock_projection"] = _make_unlock_projection(results, metadata)
	summary["completion_readiness"] = _make_completion_readiness(summary)
	summary["alerts"] = _make_alerts(summary)
	return summary


func _new_strategy_acc() -> Dictionary:
	return {
		"total_runs": 0,
		"wins": 0,
		"rounds_played_sum": 0,
		"final_hp_sum": 0,
		"purchases_sum": 0,
		"merges_sum": 0,
		"upgrade_purchases_sum": 0,
		"boss_rewards_sum": 0,
		"purchases": {},
		"final_cards": {},
		"merges": {},
		"boss_rewards": {},
	}


func _accumulate_strategy(acc: Dictionary, result: Dictionary) -> void:
	acc["total_runs"] += 1
	acc["wins"] += 1 if bool(result.get("won", false)) else 0
	acc["rounds_played_sum"] += int(result.get("rounds_played", 0))
	acc["final_hp_sum"] += int(result.get("final_hp", 0))

	var purchase_log: Array = result.get("purchase_log", [])
	acc["purchases_sum"] += purchase_log.size()
	for card_id in purchase_log:
		_inc(acc["purchases"], str(card_id))

	var merge_events: Array = result.get("merge_events", [])
	acc["merges_sum"] += merge_events.size()
	for merge_event in merge_events:
		var card_id := str(merge_event.get("card_id", "?"))
		var new_star := int(merge_event.get("new_star", 0))
		_inc(acc["merges"], "%s★%d" % [card_id, new_star])

	var upgrade_purchases: Array = result.get("upgrades_purchased", [])
	acc["upgrade_purchases_sum"] += upgrade_purchases.size()

	var boss_rewards: Array = result.get("boss_rewards_applied", [])
	acc["boss_rewards_sum"] += boss_rewards.size()
	for reward in boss_rewards:
		_inc(acc["boss_rewards"], str(reward.get("reward_id", reward.get("id", "?"))))

	var final_deck: Array = result.get("final_deck", [])
	for card in final_deck:
		var card_id := str(card.get("card_id", "?"))
		var star_level := int(card.get("star_level", 1))
		_inc(acc["final_cards"], "%s★%d" % [card_id, star_level])


func _finish_strategy(acc: Dictionary) -> Dictionary:
	var total := int(acc["total_runs"])
	return {
		"total_runs": total,
		"wins": int(acc["wins"]),
		"clear_rate": _ratio(acc["wins"], total),
		"avg_rounds_played": _average(acc["rounds_played_sum"], total),
		"avg_final_hp": _average(acc["final_hp_sum"], total),
		"avg_purchases": _average(acc["purchases_sum"], total),
		"avg_merges": _average(acc["merges_sum"], total),
		"avg_upgrade_purchases": _average(acc["upgrade_purchases_sum"], total),
		"avg_boss_rewards": _average(acc["boss_rewards_sum"], total),
		"top_purchases": _top_counts(acc["purchases"], TOP_LIMIT),
		"top_final_cards": _top_counts(acc["final_cards"], TOP_LIMIT),
		"top_merges": _top_counts(acc["merges"], TOP_LIMIT),
		"boss_rewards": _top_counts(acc["boss_rewards"], TOP_LIMIT),
	}


func _new_round_accs() -> Array:
	var accs: Array = []
	for round_index in MAX_ROUNDS:
		accs.append({
			"round": round_index + 1,
			"samples": 0,
			"wins": 0,
			"player_units_sum": 0,
			"enemy_units_sum": 0,
			"board_size_sum": 0,
			"chain_events_sum": 0,
			"gold_sum": 0,
		})
	return accs


func _accumulate_rounds(round_accs: Array, round_data: Array) -> void:
	for round_result in round_data:
		var round_num := int(round_result.get("round_num", 0))
		if round_num < 1 or round_num > round_accs.size():
			continue
		var acc: Dictionary = round_accs[round_num - 1]
		acc["samples"] += 1
		acc["wins"] += 1 if bool(round_result.get("battle_won", false)) else 0
		acc["player_units_sum"] += int(round_result.get("total_player_units", 0))
		acc["enemy_units_sum"] += int(round_result.get("total_enemy_units", 0))
		acc["board_size_sum"] += int(round_result.get("board_size", 0))
		acc["chain_events_sum"] += int(round_result.get("chain_events", 0))
		acc["gold_sum"] += int(round_result.get("gold", 0))


func _finish_rounds(round_accs: Array) -> Array:
	var rows: Array = []
	for acc in round_accs:
		var samples := int(acc["samples"])
		if samples <= 0:
			continue
		rows.append({
			"round": int(acc["round"]),
			"samples": samples,
			"win_rate": _ratio(acc["wins"], samples),
			"avg_player_units": _average(acc["player_units_sum"], samples),
			"avg_enemy_units": _average(acc["enemy_units_sum"], samples),
			"avg_board_size": _average(acc["board_size_sum"], samples),
			"avg_chain_events": _average(acc["chain_events_sum"], samples),
			"avg_gold": _average(acc["gold_sum"], samples),
		})
	return rows


func _make_alerts(summary: Dictionary) -> Array:
	var alerts: Array = []
	var overall: Dictionary = summary.get("overall", {})
	var total_runs := int(overall.get("total_runs", 0))
	if total_runs >= 5 and float(overall.get("clear_rate", 0.0)) < 0.2:
		alerts.append({
			"level": "warning",
			"code": "low_overall_clear_rate",
			"message": "Overall clear rate is below 20%% across %d observed runs." % total_runs,
		})

	var per_strategy: Dictionary = summary.get("per_strategy", {})
	for strategy in per_strategy.keys():
		var stats: Dictionary = per_strategy[strategy]
		var strategy_runs := int(stats.get("total_runs", 0))
		if strategy_runs >= 3 and float(stats.get("clear_rate", 0.0)) == 0.0:
			alerts.append({
				"level": "warning",
				"code": "strategy_zero_clear_rate",
				"strategy": strategy,
				"message": "%s cleared 0/%d observed runs." % [strategy, strategy_runs],
			})
		if strategy_runs >= 3 and float(stats.get("avg_rounds_played", 0.0)) < 8.0:
			alerts.append({
				"level": "warning",
				"code": "strategy_early_deaths",
				"strategy": strategy,
				"message": "%s averaged fewer than 8 rounds reached." % strategy,
			})

	var completion: Dictionary = summary.get("completion", {})
	var top_loss_rounds: Array = completion.get("top_loss_rounds", [])
	if total_runs >= 5 and not top_loss_rounds.is_empty():
		var first_loss: Dictionary = top_loss_rounds[0]
		if int(first_loss.get("count", 0)) >= ceili(float(total_runs) * 0.4):
			alerts.append({
				"level": "info",
				"code": "clustered_loss_round",
				"round": str(first_loss.get("id", "")),
				"message": "Observed losses cluster around %s." % first_loss.get("id", "?"),
			})

	var unlock_projection: Dictionary = summary.get("unlock_projection", {})
	if int(unlock_projection.get("largest_projected_unlock_count", 0)) >= 5:
		alerts.append({
			"level": "warning",
			"code": "possible_unlock_burst",
			"message": "At least one observed run projects 5+ unlocks from available metrics.",
		})
	if not unlock_projection.get("unobservable_metrics", []).is_empty():
		alerts.append({
			"level": "info",
			"code": "partial_unlock_projection",
			"message": "Unlock projection is partial because some meta stats are not present in headless results.",
		})
	return alerts


func _make_completion_readiness(summary: Dictionary) -> Dictionary:
	var overall: Dictionary = summary.get("overall", {})
	var per_strategy: Dictionary = summary.get("per_strategy", {})
	var completion: Dictionary = summary.get("completion", {})
	var unlock_projection: Dictionary = summary.get("unlock_projection", {})
	var metadata: Dictionary = summary.get("metadata", {})
	var total_runs := int(overall.get("total_runs", 0))
	var min_runs_per_strategy := _min_runs_per_strategy(per_strategy)
	var risks: Array = []

	if total_runs < 10 or min_runs_per_strategy < 3:
		_add_completion_risk(
			risks,
			"sample_too_small",
			"high",
			"Completion sample is too small",
			"%d total runs; smallest strategy sample %d." % [
				total_runs, min_runs_per_strategy],
			"Rerun self-play with every core strategy and at least 3 runs each."
		)

	var clear_rate := float(overall.get("clear_rate", 0.0))
	if total_runs >= 5 and clear_rate < 0.2:
		_add_completion_risk(
			risks,
			"low_overall_clear_rate",
			"high",
			"Overall clear rate is below the prototype floor",
			"%d/%d clears (%.1f%%)." % [
				int(overall.get("wins", 0)), total_runs, clear_rate * 100.0],
			"Inspect the main survival curve before adding more UI polish."
		)
	elif total_runs >= 5 and clear_rate < 0.35:
		_add_completion_risk(
			risks,
			"thin_overall_clear_rate",
			"medium",
			"Overall clear rate is thin",
			"%d/%d clears (%.1f%%)." % [
				int(overall.get("wins", 0)), total_runs, clear_rate * 100.0],
			"Use death-round and strategy-floor evidence to choose the next repair."
		)

	var weak_strategies := _weak_strategy_rows(per_strategy)
	if not weak_strategies.is_empty():
		_add_completion_risk(
			risks,
			"weak_strategy_floor",
			"high",
			"One or more strategies have an unsafe floor",
			_join_strategy_evidence(weak_strategies),
			"Repair the worst strategy lane only after inspecting trace buckets."
		)

	var milestone_risk := _boss_milestone_risk(completion, total_runs)
	if not milestone_risk.is_empty():
		_add_completion_risk(
			risks,
			str(milestone_risk.get("code", "boss_milestone_bottleneck")),
			str(milestone_risk.get("severity", "medium")),
			str(milestone_risk.get("title", "Boss milestone bottleneck")),
			str(milestone_risk.get("evidence", "")),
			str(milestone_risk.get("recommended_next_slice", "Inspect boss milestone flow."))
		)

	var largest_unlocks := int(unlock_projection.get(
		"largest_raw_projected_unlock_count",
		unlock_projection.get("largest_projected_unlock_count", 0)))
	var largest_deferred := int(unlock_projection.get(
		"largest_projected_deferred_unlock_count", 0))
	if largest_unlocks >= 5:
		_add_completion_risk(
			risks,
			"unlock_burst_pressure",
			"medium",
			"Projected unlock pressure is still bursty",
			"Largest run projects %d raw unlocks; up to %d deferred by UI reveal cap." % [
				largest_unlocks, largest_deferred],
			"Revisit unlock pacing only if fresh playtests find the recap overwhelming."
		)

	if str(unlock_projection.get("status", "")) != "complete":
		_add_completion_risk(
			risks,
			"partial_unlock_projection",
			"low",
			"Unlock projection is partial",
			"Some unlock metrics are not observable in this report.",
			"Enable trace stats or add missing observer fields before changing progression."
		)

	_rank_risks(risks)
	var status := "ready_for_next_slice"
	if not risks.is_empty():
		status = "needs_attention" if _has_high_risk(risks) else "watch"
	var recommended_next := _recommended_next_slice(risks)

	return {
		"status": status,
		"recommended_next_slice": recommended_next,
		"sample": {
			"total_runs": total_runs,
			"min_runs_per_strategy": min_runs_per_strategy,
			"difficulty": int(metadata.get("difficulty", 1)),
			"strategies": metadata.get("strategies", []),
		},
		"top_risks": risks,
	}


func _min_runs_per_strategy(per_strategy: Dictionary) -> int:
	if per_strategy.is_empty():
		return 0
	var min_runs := 999999
	for strategy in per_strategy.keys():
		var stats: Dictionary = per_strategy[strategy]
		min_runs = mini(min_runs, int(stats.get("total_runs", 0)))
	return min_runs


func _add_completion_risk(risks: Array, code: String, severity: String,
		title: String, evidence: String, recommended_next_slice: String) -> void:
	risks.append({
		"rank": risks.size() + 1,
		"code": code,
		"severity": severity,
		"title": title,
		"evidence": evidence,
		"recommended_next_slice": recommended_next_slice,
	})


func _weak_strategy_rows(per_strategy: Dictionary) -> Array:
	var rows: Array = []
	for strategy in per_strategy.keys():
		var stats: Dictionary = per_strategy[strategy]
		var runs := int(stats.get("total_runs", 0))
		if runs < 3:
			continue
		var clear_rate := float(stats.get("clear_rate", 0.0))
		var avg_rounds := float(stats.get("avg_rounds_played", 0.0))
		if clear_rate == 0.0 or avg_rounds < 8.0:
			rows.append({
				"strategy": str(strategy),
				"runs": runs,
				"wins": int(stats.get("wins", 0)),
				"clear_rate": clear_rate,
				"avg_rounds_played": avg_rounds,
			})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["clear_rate"]) == float(b["clear_rate"]):
			return float(a["avg_rounds_played"]) < float(b["avg_rounds_played"])
		return float(a["clear_rate"]) < float(b["clear_rate"])
	)
	if rows.size() > 3:
		rows.resize(3)
	return rows


func _join_strategy_evidence(rows: Array) -> String:
	var parts: Array[String] = []
	for row in rows:
		parts.append("%s %d/%d clears, avg R%.1f" % [
			str(row.get("strategy", "?")),
			int(row.get("wins", 0)),
			int(row.get("runs", 0)),
			float(row.get("avg_rounds_played", 0.0)),
		])
	return "; ".join(parts)


func _boss_milestone_risk(completion: Dictionary, total_runs: int) -> Dictionary:
	if total_runs < 5:
		return {}
	for row in completion.get("boss_milestones", []):
		var milestone: Dictionary = row
		var round_num := int(milestone.get("round", 0))
		var reached_runs := int(milestone.get("reached_runs", 0))
		var eligible_runs := int(milestone.get("eligible_runs", reached_runs))
		var reward_runs := int(milestone.get("reward_runs", 0))
		var reached_rate := float(milestone.get("reached_rate", 0.0))
		var reward_rate_of_eligible := float(milestone.get(
			"reward_rate_of_eligible",
			milestone.get("reward_rate_of_reached", 0.0)))
		if eligible_runs > 0 and reward_rate_of_eligible < 1.0:
			return {
				"code": "boss_reward_application_gap",
				"severity": "high",
				"title": "Boss rewards are not reliably applied after milestone reach",
				"evidence": "R%d reward-eligible %d runs but reward applied %d times." % [
					round_num, eligible_runs, reward_runs],
				"recommended_next_slice": "Fix boss reward application/parity before tuning.",
			}
		if round_num == 4 and reached_rate < 0.5:
			return {
				"code": "early_survival_wall",
				"severity": "high",
				"title": "Runs often fail before the first boss reward",
				"evidence": "Only %d/%d runs reached R4." % [reached_runs, total_runs],
				"recommended_next_slice": "Inspect early survival and build economy before adding long-run UI.",
			}
		if round_num == 8 and reached_rate < 0.35:
			return {
				"code": "midrun_survival_wall",
				"severity": "medium",
				"title": "Few runs reach the second boss reward",
				"evidence": "Only %d/%d runs reached R8." % [reached_runs, total_runs],
				"recommended_next_slice": "Inspect midrun conversion after first reward.",
			}
		if round_num == 12 and reached_rate < 0.2:
			return {
				"code": "late_run_reach_gap",
				"severity": "medium",
				"title": "Few runs reach the final reward tier",
				"evidence": "Only %d/%d runs reached R12." % [reached_runs, total_runs],
				"recommended_next_slice": "Consider a roadmap/progression rail only after survival gaps are understood.",
			}
	return {}


func _rank_risks(risks: Array) -> void:
	risks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var severity_a := _severity_weight(str(a.get("severity", "")))
		var severity_b := _severity_weight(str(b.get("severity", "")))
		if severity_a == severity_b:
			return str(a.get("code", "")) < str(b.get("code", ""))
		return severity_a > severity_b
	)
	for i in risks.size():
		var row: Dictionary = risks[i]
		row["rank"] = i + 1


func _severity_weight(severity: String) -> int:
	match severity:
		"high":
			return 3
		"medium":
			return 2
		"low":
			return 1
	return 0


func _has_high_risk(risks: Array) -> bool:
	for row in risks:
		if str(row.get("severity", "")) == "high":
			return true
	return false


func _recommended_next_slice(risks: Array) -> String:
	if risks.is_empty():
		return "Run manual full-run playtest or build the next whole-run orientation feature."
	var top: Dictionary = risks[0]
	return str(top.get("recommended_next_slice", "Inspect top completion risk."))


func _make_completion_summary(results: Array) -> Dictionary:
	var total_runs := results.size()
	var wins := 0
	var losses := 0
	var final_round_counts := {}
	var loss_round_counts := {}
	var milestone_accs := {}
	for boss_round in BOSS_MILESTONE_ROUNDS:
		milestone_accs[boss_round] = {
			"round": boss_round,
			"reached_runs": 0,
			"eligible_runs": 0,
			"reward_runs": 0,
			"missed_after_reach": 0,
			"missed_after_eligible": 0,
		}

	for result in results:
		var won := bool(result.get("won", false))
		var final_round := int(result.get("rounds_played", 0))
		_inc(final_round_counts, "R%d" % final_round)
		if won:
			wins += 1
		else:
			losses += 1
			_inc(loss_round_counts, "R%d" % final_round)

		var boss_reward_rounds := _boss_reward_rounds(result)
		for boss_round in BOSS_MILESTONE_ROUNDS:
			var milestone: Dictionary = milestone_accs[boss_round]
			var reached := final_round >= int(boss_round)
			var eligible := _boss_round_won(result, int(boss_round))
			var rewarded := boss_reward_rounds.has(int(boss_round))
			if reached:
				milestone["reached_runs"] = int(milestone["reached_runs"]) + 1
			if eligible:
				milestone["eligible_runs"] = int(milestone["eligible_runs"]) + 1
			if rewarded:
				milestone["reward_runs"] = int(milestone["reward_runs"]) + 1
			if eligible and not rewarded:
				milestone["missed_after_reach"] = int(milestone["missed_after_reach"]) + 1
				milestone["missed_after_eligible"] = \
					int(milestone["missed_after_eligible"]) + 1

	var boss_milestones: Array = []
	for boss_round in BOSS_MILESTONE_ROUNDS:
		var milestone: Dictionary = milestone_accs[boss_round]
		var reached_runs := int(milestone["reached_runs"])
		var eligible_runs := int(milestone["eligible_runs"])
		var reward_runs := int(milestone["reward_runs"])
		milestone["reached_rate"] = _ratio(reached_runs, total_runs)
		milestone["eligible_rate"] = _ratio(eligible_runs, total_runs)
		milestone["reward_rate"] = _ratio(reward_runs, total_runs)
		milestone["reward_rate_of_reached"] = _ratio(reward_runs, reached_runs)
		milestone["reward_rate_of_eligible"] = _ratio(reward_runs, eligible_runs)
		boss_milestones.append(milestone)

	return {
		"total_runs": total_runs,
		"wins": wins,
		"losses": losses,
		"full_clears": wins,
		"clear_rate": _ratio(wins, total_runs),
		"top_final_rounds": _top_counts(final_round_counts, TOP_LIMIT),
		"top_loss_rounds": _top_counts(loss_round_counts, TOP_LIMIT),
		"boss_milestones": boss_milestones,
	}


func _boss_reward_rounds(result: Dictionary) -> Array:
	var rounds: Array = []
	for reward in result.get("boss_rewards_applied", []):
		var round_num := int(reward.get("round", 0))
		if round_num > 0 and not rounds.has(round_num):
			rounds.append(round_num)
	return rounds


func _boss_round_won(result: Dictionary, round_num: int) -> bool:
	for round_result in result.get("round_data", []):
		if int(round_result.get("round_num", 0)) == round_num:
			return bool(round_result.get("battle_won", false))
	return false


func _make_unlock_projection(results: Array, metadata: Dictionary) -> Dictionary:
	var specs := _unlock_metric_specs(metadata)
	_apply_trace_stat_observability(specs, results)
	var metric_rows: Array = []
	var metric_accs := {}
	var unobservable: Array = []
	for spec in specs:
		var metric_id := str(spec.get("id", ""))
		metric_accs[metric_id] = {
			"id": metric_id,
			"label": str(spec.get("label", metric_id)),
			"stat": str(spec.get("stat", metric_id)),
			"threshold": spec.get("threshold", 0),
			"unlocks": spec.get("unlocks", []),
			"source": str(spec.get("source", "")),
			"confidence": str(spec.get("confidence", "observed")),
			"observable": bool(spec.get("observable", true)),
			"best_value": null,
			"runs_at_threshold": 0,
			"hit_rate": 0.0,
		}
		if not bool(spec.get("observable", true)):
			unobservable.append(metric_accs[metric_id].duplicate(true))

	var projected_runs: Array = []
	var runs_with_projected_unlocks := 0
	var runs_with_projected_deferred_unlocks := 0
	var largest_projected_unlock_count := 0
	var largest_projected_revealed_unlock_count := 0
	var largest_projected_deferred_unlock_count := 0
	for i in results.size():
		var result: Dictionary = results[i]
		var stats := _extract_unlock_stats(result)
		var run_unlocks: Array[String] = []
		for spec in specs:
			if not bool(spec.get("observable", true)):
				continue
			var stat_name := str(spec.get("stat", spec.get("id", "")))
			var value = stats.get(stat_name)
			if value == null:
				continue
			var metric: Dictionary = metric_accs[str(spec.get("id", ""))]
			var numeric_value := _metric_numeric_value(value)
			if metric["best_value"] == null or numeric_value > float(metric["best_value"]):
				metric["best_value"] = numeric_value
			if _metric_hits_threshold(spec, value):
				metric["runs_at_threshold"] = int(metric["runs_at_threshold"]) + 1
				for unlock in spec.get("unlocks", []):
					if not run_unlocks.has(str(unlock)):
						run_unlocks.append(str(unlock))

		if not run_unlocks.is_empty():
			runs_with_projected_unlocks += 1
		var revealed_unlocks := run_unlocks.slice(0,
			mini(PROJECTED_UNLOCK_REVEAL_CAP, run_unlocks.size()))
		var deferred_unlocks := run_unlocks.slice(revealed_unlocks.size())
		if not deferred_unlocks.is_empty():
			runs_with_projected_deferred_unlocks += 1
		largest_projected_unlock_count = maxi(
			largest_projected_unlock_count, run_unlocks.size())
		largest_projected_revealed_unlock_count = maxi(
			largest_projected_revealed_unlock_count, revealed_unlocks.size())
		largest_projected_deferred_unlock_count = maxi(
			largest_projected_deferred_unlock_count, deferred_unlocks.size())
		projected_runs.append({
			"idx": i,
			"strategy": str(result.get("strategy", "unknown")),
			"won": bool(result.get("won", false)),
			"rounds_played": int(result.get("rounds_played", 0)),
			"stats": stats,
			"raw_projected_unlocks": run_unlocks,
			"raw_projected_unlock_count": run_unlocks.size(),
			"projected_unlocks": run_unlocks,
			"projected_unlock_count": run_unlocks.size(),
			"projected_revealed_unlocks": revealed_unlocks,
			"projected_revealed_unlock_count": revealed_unlocks.size(),
			"projected_deferred_unlocks": deferred_unlocks,
			"projected_deferred_unlock_count": deferred_unlocks.size(),
		})

	for spec in specs:
		var metric: Dictionary = metric_accs[str(spec.get("id", ""))]
		metric["hit_rate"] = _ratio(metric.get("runs_at_threshold", 0), results.size())
		metric_rows.append(metric)

	return {
		"status": "partial" if not unobservable.is_empty() else "complete",
		"runs": projected_runs,
		"metrics": metric_rows,
		"unobservable_metrics": unobservable,
		"runs_with_projected_unlocks": runs_with_projected_unlocks,
		"runs_with_projected_deferred_unlocks": runs_with_projected_deferred_unlocks,
		"largest_projected_unlock_count": largest_projected_unlock_count,
		"largest_raw_projected_unlock_count": largest_projected_unlock_count,
		"largest_projected_revealed_unlock_count": largest_projected_revealed_unlock_count,
		"largest_projected_deferred_unlock_count": largest_projected_deferred_unlock_count,
		"pacing_model": {
			"status": "ui_reveal",
			"reveal_cap_per_run": PROJECTED_UNLOCK_REVEAL_CAP,
			"source": "matches UI reveal cap; live unlock availability is not capped",
		},
	}


func _apply_trace_stat_observability(specs: Array, results: Array) -> void:
	if not _all_results_have_trace_cards_sold(results):
		return
	for spec in specs:
		if str(spec.get("stat", "")) != "cards_sold":
			continue
		spec["observable"] = true
		spec["source"] = "result.trace_stats.cards_sold"
		spec["confidence"] = "trace_event_count"


func _all_results_have_trace_cards_sold(results: Array) -> bool:
	if results.is_empty():
		return false
	for result in results:
		var trace_stats: Dictionary = result.get("trace_stats", {})
		if not trace_stats.has("cards_sold"):
			return false
	return true


func _unlock_metric_specs(metadata: Dictionary) -> Array:
	var difficulty := int(metadata.get("difficulty", 1))
	var clear_unlocks: Array[String] = ["difficulty: D%d" % mini(difficulty + 1, 8)]
	match difficulty:
		2:
			clear_unlocks.append("talisman: glass_eye")
		3:
			clear_unlocks.append("talisman: copper_wire")
		5:
			clear_unlocks.append("talisman: golden_die")
		7:
			clear_unlocks.append("talisman: war_drum")

	return [
		{
			"id": "clear",
			"label": "Clear run",
			"stat": "won",
			"threshold": true,
			"unlocks": clear_unlocks,
			"source": "result.won",
			"confidence": "exact",
		},
		{
			"id": "field_units_120",
			"label": "Field units",
			"stat": "max_field_units",
			"threshold": FIELD_UNITS_THRESHOLD,
			"unlocks": ["commander: strategist"],
			"source": "max round_data.total_player_units",
			"confidence": "round_data_peak",
		},
		{
			"id": "attached_upgrades_16",
			"label": "Attached upgrades",
			"stat": "max_attached_upgrades",
			"threshold": ATTACHED_UPGRADES_COMMANDER_THRESHOLD,
			"unlocks": ["commander: smith"],
			"source": "upgrades_purchased + merge_upgrades events",
			"confidence": "event_count_proxy",
		},
		{
			"id": "unique_field_cards_7",
			"label": "Unique field cards",
			"stat": "max_unique_field_cards",
			"threshold": UNIQUE_FIELD_CARDS_THRESHOLD,
			"unlocks": ["commander: collector"],
			"source": "final_deck unique card ids",
			"confidence": "final_snapshot_lower_bound",
		},
		{
			"id": "win_streak_8",
			"label": "Win streak",
			"stat": "best_win_streak",
			"threshold": WIN_STREAK_THRESHOLD,
			"unlocks": ["commander: raider"],
			"source": "round_data.battle_won streak",
			"confidence": "exact",
		},
		{
			"id": "cards_sold_20",
			"label": "Cards sold",
			"stat": "cards_sold",
			"threshold": CARDS_SOLD_COMMANDER_THRESHOLD,
			"unlocks": ["commander: alchemist"],
			"source": "not exported by headless result",
			"confidence": "unobservable",
			"observable": false,
		},
		{
			"id": "growth_events_120",
			"label": "Growth events",
			"stat": "growth_events",
				"threshold": GROWTH_EVENTS_THRESHOLD,
				"unlocks": ["talisman: mercury_drop"],
				"source": "sum round_data.chain_events; live uses chain_result.chain_count",
				"confidence": "chain_event_count_proxy",
			},
		{
			"id": "star2_cards_5",
			"label": "Star 2+ cards",
			"stat": "max_star2_cards",
			"threshold": STAR2_CARDS_THRESHOLD,
			"unlocks": ["talisman: cracked_egg"],
			"source": "final_deck star_level >= 2",
			"confidence": "final_snapshot_lower_bound",
		},
		{
			"id": "unit_advantage_wins_5",
			"label": "Unit advantage wins",
			"stat": "unit_advantage_wins",
			"threshold": UNIT_ADVANTAGE_WINS_THRESHOLD,
			"unlocks": ["talisman: war_drum"],
			"source": "winning rounds with player units > enemy units",
			"confidence": "round_data_exact",
		},
		{
			"id": "attached_upgrades_12",
			"label": "Attached upgrades",
			"stat": "max_attached_upgrades",
			"threshold": ATTACHED_UPGRADES_TALISMAN_THRESHOLD,
			"unlocks": ["talisman: rusty_wrench", "talisman: burst_sack"],
			"source": "upgrades_purchased + merge_upgrades events",
			"confidence": "event_count_proxy",
		},
		{
			"id": "cards_sold_12",
			"label": "Cards sold",
			"stat": "cards_sold",
			"threshold": CARDS_SOLD_TALISMAN_THRESHOLD,
			"unlocks": ["talisman: soul_jar"],
			"source": "not exported by headless result",
			"confidence": "unobservable",
			"observable": false,
		},
	]


func _extract_unlock_stats(result: Dictionary) -> Dictionary:
	var round_data: Array = result.get("round_data", [])
	var max_field_units := 0
	var best_win_streak := 0
	var current_win_streak := 0
	var growth_events := 0
	var unit_advantage_wins := 0
	for round_result in round_data:
		var player_units := int(round_result.get("total_player_units", 0))
		var enemy_units := int(round_result.get("total_enemy_units", 0))
		var won := bool(round_result.get("battle_won", false))
		max_field_units = maxi(max_field_units, player_units)
		growth_events += int(round_result.get("chain_events", 0))
		if won:
			current_win_streak += 1
			best_win_streak = maxi(best_win_streak, current_win_streak)
			if player_units > enemy_units:
				unit_advantage_wins += 1
		else:
			current_win_streak = 0

	var unique_cards := {}
	var star2_cards := 0
	for card in result.get("final_deck", []):
		var card_id := str(card.get("card_id", ""))
		if card_id != "":
			unique_cards[card_id] = true
		if int(card.get("star_level", 1)) >= 2:
			star2_cards += 1
	var cards_sold = null
	var trace_stats: Dictionary = result.get("trace_stats", {})
	if trace_stats.has("cards_sold"):
		cards_sold = int(trace_stats.get("cards_sold", 0))

	return {
		"won": bool(result.get("won", false)),
		"max_field_units": max_field_units,
		"max_attached_upgrades": result.get("upgrades_purchased", []).size() \
			+ result.get("merge_upgrades", []).size(),
		"max_unique_field_cards": unique_cards.size(),
		"best_win_streak": best_win_streak,
		"cards_sold": cards_sold,
		"growth_events": growth_events,
		"max_star2_cards": star2_cards,
		"unit_advantage_wins": unit_advantage_wins,
	}


func _metric_hits_threshold(spec: Dictionary, value: Variant) -> bool:
	var threshold = spec.get("threshold", 0)
	if threshold is bool:
		return bool(value) == bool(threshold)
	return _metric_numeric_value(value) >= float(threshold)


func _metric_numeric_value(value: Variant) -> float:
	if value is bool:
		return 1.0 if bool(value) else 0.0
	return float(value)


func _inc(counts: Dictionary, key: String) -> void:
	counts[key] = int(counts.get(key, 0)) + 1


func _top_counts(counts: Dictionary, limit: int) -> Array:
	var rows: Array = []
	for key in counts.keys():
		rows.append({"id": key, "count": int(counts[key])})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["count"]) == int(b["count"]):
			return str(a["id"]) < str(b["id"])
		return int(a["count"]) > int(b["count"])
	)
	if rows.size() > limit:
		rows.resize(limit)
	return rows


func _ratio(numerator: Variant, denominator: int) -> float:
	if denominator <= 0:
		return 0.0
	return float(numerator) / float(denominator)


func _average(total: Variant, count: int) -> float:
	if count <= 0:
		return 0.0
	return float(total) / float(count)
