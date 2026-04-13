class_name AIEvaluator
extends RefCounted
## AI decision quality evaluator for autoresearch Phase 2.
## Separate from Evaluator (game balance) — measures how well the AI plays.
## Used alongside Evaluator when tuning ai_params.

## Axis weights for AI quality scoring.
const WEIGHTS := {
	"economy_efficiency": 0.25,
	"merge_rate": 0.25,
	"board_strength_curve": 0.25,
	"card_diversity": 0.25,
}


## Evaluate AI quality from simulation results. Returns score dictionary.
static func evaluate(results: Array) -> Dictionary:
	var scores := {}
	scores["economy_efficiency"] = _eval_economy_efficiency(results)
	scores["merge_rate"] = _eval_merge_rate(results)
	scores["board_strength_curve"] = _eval_board_strength_curve(results)
	scores["card_diversity"] = _eval_card_diversity(results)

	var ws := 0.0
	for key in WEIGHTS:
		ws += scores[key] * WEIGHTS[key]
	scores["ai_quality_score"] = ws

	return scores


# ================================================================
# Axis 1: economy_efficiency — how well gold is utilized
# ================================================================

## Measures: average gold utilization per round.
## High gold leftover = wasted potential. Zero gold = over-spending.
## Ideal: spend most gold but keep interest-level reserves.
static func _eval_economy_efficiency(results: Array) -> float:
	var total_score := 0.0
	var count := 0
	for r in results:
		var total_income := 0.0
		var total_waste := 0.0
		for rd in r.round_data:
			var gold: int = rd.get("gold", 0)
			# Gold at end of round: high is wasteful if not banking for interest
			var round_num: int = rd.get("round_num", 1)
			# Ideal: keep 5-10g in mid-game (R4-R9), spend all late (R10+)
			var ideal_reserve: float
			if round_num < 4:
				ideal_reserve = 3.0
			elif round_num < 10:
				ideal_reserve = 7.0  # Interest banking
			else:
				ideal_reserve = 2.0  # Spend aggressively
			# Score: gaussian around ideal, σ=5
			var diff: float = absf(float(gold) - ideal_reserve)
			total_score += exp(-diff * diff / 50.0)
			count += 1
	if count == 0:
		return 0.5
	return clampf(total_score / count, 0.0, 1.0)


# ================================================================
# Axis 2: merge_rate — ★2+ merge completion
# ================================================================

## Measures: proportion of ★2+ cards in final deck.
## Higher star cards = better buy/reroll decisions.
static func _eval_merge_rate(results: Array) -> float:
	var total_score := 0.0
	var count := 0
	for r in results:
		var final_deck: Array = r.get("final_deck", [])
		if final_deck.is_empty():
			continue
		var star_sum := 0
		for card in final_deck:
			star_sum += card.get("star_level", 1)
		# Average star level: 1.0 = no merges, 2.0 = all ★2, 3.0 = all ★3
		var avg_star: float = float(star_sum) / final_deck.size()
		# Normalize: 1.0 → 0.0, 2.0 → 0.5, 3.0 → 1.0
		total_score += clampf((avg_star - 1.0) / 2.0, 0.0, 1.0)
		count += 1
	if count == 0:
		return 0.5
	return total_score / count


# ================================================================
# Axis 3: board_strength_curve — CP growth monotonicity
# ================================================================

## Measures: how consistently board CP grows round over round.
## Dips indicate poor sell/buy timing.
static func _eval_board_strength_curve(results: Array) -> float:
	var total_score := 0.0
	var count := 0
	for r in results:
		var rd_arr: Array = r.get("round_data", [])
		if rd_arr.size() < 3:
			continue
		var growth_count := 0
		var total_transitions := 0
		var prev_total_cp := 0.0
		for rd in rd_arr:
			var cps: Array = rd.get("card_cps", [])
			var total_cp := 0.0
			for cp in cps:
				total_cp += cp
			if prev_total_cp > 0.0:
				total_transitions += 1
				if total_cp >= prev_total_cp * 0.95:  # Allow 5% dip tolerance
					growth_count += 1
			prev_total_cp = total_cp
		if total_transitions > 0:
			total_score += float(growth_count) / total_transitions
		count += 1
	if count == 0:
		return 0.5
	return total_score / count


# ================================================================
# Axis 4: card_diversity — use of different card types
# ================================================================

## Measures: how many distinct cards appear in final decks across runs.
## Low diversity = AI always picks the same cards regardless of shop offers.
static func _eval_card_diversity(results: Array) -> float:
	var card_counts := {}
	var total_runs := 0
	for r in results:
		total_runs += 1
		var final_deck: Array = r.get("final_deck", [])
		var seen := {}
		for card in final_deck:
			var cid: String = card.get("card_id", "")
			if cid != "" and not seen.has(cid):
				seen[cid] = true
				card_counts[cid] = card_counts.get(cid, 0) + 1
	if total_runs == 0:
		return 0.5
	# Count cards appearing in at least 5% of runs
	var threshold: float = total_runs * 0.05
	var diverse_count := 0
	for cid in card_counts:
		if card_counts[cid] >= threshold:
			diverse_count += 1
	# Normalize: 55 total cards, 20+ used = good diversity
	return clampf(float(diverse_count) / 25.0, 0.0, 1.0)
