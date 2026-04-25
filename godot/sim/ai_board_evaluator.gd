class_name AIBoardEvaluator
extends RefCounted
## Timing-aware card value differentiation and bench→board promotion.
## Stateless — all methods use only their arguments.

const MAX_ROUND := 15


# ================================================================
# Timing modifier — RS compounds, BS is flat
# ================================================================

## Additive modifier based on trigger timing and remaining rounds.
func timing_modifier(timing: int, round_num: int) -> float:
	var remaining := maxi(MAX_ROUND - round_num, 1)
	match timing:
		Enums.TriggerTiming.ROUND_START:
			# RS fires every round → compounding. +2 per remaining round.
			return 2.0 * remaining
		Enums.TriggerTiming.ON_EVENT:
			# OE chains off RS sources. Value scales with time.
			return 1.5 * remaining
		Enums.TriggerTiming.BATTLE_START:
			# BS fires once/round for combat. Moderate flat value.
			return 6.0
		Enums.TriggerTiming.PERSISTENT:
			# Always active — high value.
			return 8.0 + remaining * 0.5
		Enums.TriggerTiming.POST_COMBAT:
			return 4.0
		Enums.TriggerTiming.POST_COMBAT_VICTORY:
			return 3.0
		Enums.TriggerTiming.POST_COMBAT_DEFEAT:
			return 1.0
		Enums.TriggerTiming.ON_REROLL:
			return 3.0
		Enums.TriggerTiming.ON_SELL:
			return 2.0
		Enums.TriggerTiming.ON_MERGE:
			return 2.0
	return 0.0


# ================================================================
# Effect modifier — action type differentiation
# ================================================================

## Additive modifier based on effect actions.
## v2 block format: `effects` is a list of timing blocks. Iterate block.actions
## across all blocks (multi-block cards contribute actions from every block).
func effect_modifier(effects: Array, round_num: int) -> float:
	var mod := 0.0
	var remaining := maxi(MAX_ROUND - round_num, 1)

	var actions: Array = []
	for block in effects:
		actions.append_array(block.get("actions", []))

	for eff in actions:
		var action: String = eff.get("action", "")
		var target: String = eff.get("target", "self")

		match action:
			"spawn":
				mod += 3.0
				# Adjacency spawns enable chains on neighbors
				if target in ["right_adj", "both_adj"]:
					mod += 5.0
			"enhance_pct":
				# Compound value — earlier = more rounds to stack
				var atk_pct: float = eff.get("enhance_atk_pct", 0.0)
				mod += atk_pct * 100.0 * remaining * 0.3
			"shield_pct":
				# Defense value increases in late game (enemies hit harder)
				var shield: float = eff.get("shield_hp_pct", 0.0)
				mod += shield * 20.0 * (1.0 + round_num * 0.1)
			"grant_gold":
				mod += eff.get("gold_amount", 0) * (1.5 if round_num <= 6 else 0.5)
			"grant_terazin":
				mod += eff.get("terazin_amount", 0) * 2.0
			"retrigger":
				mod += 4.0
			"buff_pct":
				mod += 3.0

	return mod


# ================================================================
# Card board value (enhanced)
# ================================================================

## Enhanced card value for board/bench comparison.
func card_board_value(card: CardInstance, strategy: String,
		round_num: int) -> float:
	var tmpl: Dictionary = card.template
	var tier: int = tmpl.get("tier", 1)
	var star: int = card.star_level
	var timing: int = tmpl.get("trigger_timing", -1)

	# Base: AI heuristic feature (atk+hp), NOT the SSoT CP formula. Tuned for
	# log-scaled card-value comparison; migrating to get_total_cp() shifts the
	# magnitude (~100-2000 vs ~10-200) and would re-tune AI behavior.
	var heuristic_size: float = card.get_total_atk() + card.get_total_hp()
	var val: float = log(maxf(heuristic_size, 1.0)) * 5.0

	# Star and tier
	val += star * 8.0
	val += tier * 2.0

	# Timing modifier
	if timing >= 0:
		val += timing_modifier(timing, round_num)

	# Effect modifier
	var effects: Array = tmpl.get("effects", [])
	if not effects.is_empty():
		val += effect_modifier(effects, round_num)

	# Theme match bonus
	var preferred: int = _theme_for(strategy, round_num)
	var card_theme: int = tmpl.get("theme", 0)
	if preferred >= 0:
		if card_theme == preferred:
			val += 8.0
		elif card_theme != Enums.CardTheme.NEUTRAL:
			val -= 5.0

	# Theme-system cards handled by theme logic → timing-based value boost.
	# v2: all cards have non-empty blocks; use impl flag instead of is_empty.
	var impl: String = tmpl.get("impl", "card_db")
	if impl == "theme_system" and card_theme != Enums.CardTheme.NEUTRAL:
		if timing == Enums.TriggerTiming.ROUND_START:
			val += 6.0  # Theme RS cards are growth engines

	return val


# ================================================================
# Bench→board promotion
# ================================================================

## Find promotion actions: place into empty slots or swap weak board cards.
## Returns Array of {action: "place"|"swap", bench_idx, board_idx}.
func find_promotions(board: Array, bench: Array, field_slots: int,
		strategy: String, round_num: int) -> Array:
	var actions: Array = []

	# Phase 1: fill empty slots
	for bi in bench.size():
		if bench[bi] == null:
			continue
		for fi in field_slots:
			if fi >= board.size():
				break
			if board[fi] == null:
				actions.append({"action": "place", "bench_idx": bi, "board_idx": fi})
				break

	# Phase 2: swap weak board cards for stronger bench cards
	# Dynamic threshold: lower in late game (more urgent to optimize)
	var threshold: float = maxf(3.0, 8.0 - round_num * 0.5)

	# Count copies for merge protection
	var copy_counts: Dictionary = {}
	for card in board:
		if card != null:
			var cid: String = (card as CardInstance).get_base_id()
			copy_counts[cid] = copy_counts.get(cid, 0) + 1
	for card in bench:
		if card != null:
			var cid: String = (card as CardInstance).get_base_id()
			copy_counts[cid] = copy_counts.get(cid, 0) + 1

	for bi in bench.size():
		if bench[bi] == null:
			continue
		# Skip if already placed in phase 1
		var already_placed := false
		for a in actions:
			if a["bench_idx"] == bi:
				already_placed = true
				break
		if already_placed:
			continue

		var bench_card: CardInstance = bench[bi]
		var bench_val: float = card_board_value(bench_card, strategy, round_num)

		var worst_fi := -1
		var worst_val := 999.0
		for fi in field_slots:
			if fi >= board.size():
				break
			if board[fi] == null:
				continue
			var board_card: CardInstance = board[fi]
			# Protect merge candidates
			var bcid: String = board_card.get_base_id()
			if copy_counts.get(bcid, 0) >= 2:
				continue
			var val: float = card_board_value(board_card, strategy, round_num)
			if val < worst_val:
				worst_val = val
				worst_fi = fi

		if worst_fi >= 0 and bench_val > worst_val + threshold:
			actions.append({
				"action": "swap", "bench_idx": bi, "board_idx": worst_fi,
			})

	return actions


# ================================================================
# Helpers
# ================================================================

static func _theme_for(strategy: String, round_num: int = 99) -> int:
	# Soft-commit strategies: no theme preference before R4
	if round_num < 4 and strategy.begins_with("soft_"):
		return -1
	match strategy:
		"soft_steampunk": return Enums.CardTheme.STEAMPUNK
		"soft_druid": return Enums.CardTheme.DRUID
		"soft_predator": return Enums.CardTheme.PREDATOR
		"soft_military": return Enums.CardTheme.MILITARY
	return -1
