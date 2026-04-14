class_name AIAgent
extends RefCounted
## AI strategy agent for headless simulation.
## Build-phase decisions: buy, sell, reroll, levelup, arrange.

const STRATEGY_NAMES: Array[String] = [
	"steampunk_focused",
	"druid_focused",
	"predator_focused",
	"military_focused",
	"hybrid",
	"economy",
	"aggressive",
]

const _THEME_MAP := {
	"steampunk_focused": Enums.CardTheme.STEAMPUNK,
	"druid_focused": Enums.CardTheme.DRUID,
	"predator_focused": Enums.CardTheme.PREDATOR,
	"military_focused": Enums.CardTheme.MILITARY,
}

## Per-strategy config — extracted to ai_synergy_data.gd for file size.
var _STRATEGY_CONFIG: Dictionary:
	get: return _Syn.STRATEGY_CONFIG

var strategy: String
var _rng: RandomNumberGenerator
var _genome: Genome
var _recent_wins: int = 0
const _AIBuildScript = preload("res://sim/ai_build_path.gd")
var _build_path = _AIBuildScript.new()
const _AIBoardEvalScript = preload("res://sim/ai_board_evaluator.gd")
var _board_eval = _AIBoardEvalScript.new()
const _AIPositionScript = preload("res://sim/ai_position_solver.gd")
var _position_solver = _AIPositionScript.new()

const MAX_ACTIONS := 30

# Synergy data extracted to ai_synergy_data.gd for file size management.
const _Syn = preload("res://sim/ai_synergy_data.gd")
# Theme-state-aware scoring (trees, rank, counters, unit caps).
const _ThemeScorerScript = preload("res://sim/ai_theme_scorer.gd")
var _theme_scorer = _ThemeScorerScript.new()
# Helper utilities (state queries, extracted for file size).
const _H = preload("res://sim/ai_helpers.gd")
var _CHAIN_PAIRS: Dictionary:
	get: return _Syn.CHAIN_PAIRS
var _THEME_SYNERGY: Dictionary:
	get: return _Syn.THEME_SYNERGY
var _THEME_CRITICAL: Dictionary:
	get: return _Syn.THEME_CRITICAL


func _init(strat: String = "hybrid", rng: RandomNumberGenerator = null, genome: Genome = null) -> void:
	strategy = strat
	_rng = rng if rng != null else RandomNumberGenerator.new()
	_genome = genome


func _get_reroll_cost() -> int:
	return _genome.get_reroll_cost() if _genome else 1


func _try_levelup(state: GameState) -> bool:
	if not state.try_levelup():
		return false
	if _genome:
		var next_lv := state.shop_level + 1
		state.levelup_current_cost = _genome.get_levelup_cost(next_lv)
	return true


## Record battle result for adaptive scoring.
func record_battle_result(won: bool) -> void:
	if won:
		_recent_wins = mini(_recent_wins + 1, 5)
	else:
		_recent_wins = maxi(_recent_wins - 1, 0)


func play_build_phase(state: GameState, shop: RefCounted) -> void:
	if state.hp <= 10 and strategy == "economy":
		_play_aggressive(state, shop)
	else:
		match strategy:
			"economy":
				_play_economy(state, shop)
			"aggressive":
				_play_aggressive(state, shop)
			"steampunk_focused", "druid_focused", "predator_focused", "military_focused":
				_play_theme_focused(state, shop)
			"hybrid":
				_play_hybrid(state, shop)
			_:
				_play_hybrid(state, shop)

	# M6: Arsenal fuel sell (before cleanup, so absorbed units arrive)
	_try_arsenal_fuel_sell(state)

	_cleanup_bench(state)
	_promote_bench(state)

	if state.round_num >= 7:
		_transition_board(state)

	_arrange_board(state)


# --- Genome signal: enemy pressure → adaptive spending ---

## Returns enemy pressure multiplier [0.5, 2.0] based on genome CP curve.
## Higher = enemies are harder this round → spend more aggressively.
func _get_enemy_pressure(round_num: int) -> float:
	if not _genome or _genome.enemy_cp_curve.is_empty():
		return 1.0
	if round_num < 1 or round_num > 15:
		return 1.0
	var cp: float = _genome.enemy_cp_curve[round_num - 1]
	# Compare to default curve baseline
	var default_cp: float = Genome._original_round_mult(round_num)
	if default_cp <= 0.0:
		return 1.0
	var ratio: float = cp / default_cp
	return clampf(ratio, 0.5, 2.0)


## Returns genome-aware gold floor for interest.
func _get_interest_floor() -> int:
	if not _genome:
		return 5
	var per_5: int = _genome.economy.get("interest_per_5g", 1)
	var max_i: int = _genome.economy.get("max_interest", 2)
	# Floor = gold needed for max interest
	return max_i / maxi(per_5, 1) * 5


## M1: Interest-aware gold floor for ALL strategies (not just economy).
## Returns 0 if round is before banking start or after aggro transition.
func _get_universal_interest_floor(round_num: int) -> int:
	var start_r: int = int(_p("interest_all_start", 4))
	var aggro_r: int = int(_p("aggro_transition_round", 10))
	if round_num < start_r or round_num >= aggro_r:
		return 0
	return _get_interest_floor()


## M2: Pool-aware slow-roll — delay levelup when winning/strong AND
## an achievable merge exists (★1 copies with pool remaining).
func _should_delay_levelup(state: GameState) -> bool:
	var min_r: int = int(_p("slow_roll_min_round", 5))
	if state.round_num < min_r:
		return false
	# Must have an achievable merge with reasonable find probability
	if not _H.has_achievable_merge(state):
		return false
	var p_merge := _H.merge_find_probability(state, _genome)
	if p_merge < 0.05:
		return false  # merge target too diluted at current shop level
	# Primary: recent wins indicate we're strong enough to slow-roll
	if _recent_wins >= 2:
		return true
	# Fallback: CP-based check for early game before battle data
	var total_cp := 0.0
	var card_count := 0
	for card in state.board:
		if card == null:
			continue
		var c := card as CardInstance
		total_cp += c.get_total_atk() + c.get_total_hp()
		card_count += 1
	if card_count == 0:
		return false
	var avg_cp: float = total_cp / card_count
	var enemy_cp: float = Genome._original_round_mult(state.round_num)
	if _genome and not _genome.enemy_cp_curve.is_empty():
		enemy_cp = _genome.enemy_cp_curve[state.round_num - 1]
	var enemy_proxy: float = enemy_cp * 100.0
	var ratio: float = _p("slow_roll_board_cp_ratio", 1.5)
	return avg_cp > enemy_proxy * ratio


## M6: ON_SELL heuristic — when sp_arsenal on board, sell SP bench
## cards as fuel (they get absorbed).
func _try_arsenal_fuel_sell(state: GameState) -> void:
	var has_arsenal := false
	for card in state.board:
		if card != null and (card as CardInstance).get_base_id() == "sp_arsenal":
			has_arsenal = true
			break
	if not has_arsenal:
		return
	var fuel_bonus: float = _p("arsenal_fuel_bonus", 15.0)
	for i in state.bench.size():
		if state.bench[i] == null:
			continue
		var c := state.bench[i] as CardInstance
		if c.template.get("theme", -1) != Enums.CardTheme.STEAMPUNK:
			continue
		if c.upgrades.is_empty():
			continue
		var val := _card_value(c, state)
		if val < fuel_bonus:
			state.sell_card("bench", i)
			return  # One fuel sell per round


## Genome ai_params accessor shorthand.
func _p(key: String, fallback: float = 0.0) -> float:
	if _genome:
		return _genome.get_ai_param(key)
	return Genome.DEFAULT_AI_PARAMS.get(key, fallback)


## Pool remaining copies for a card (99 if no pool tracking).
func _pool_remaining(state: GameState, card_id: String) -> int:
	if state.card_pool == null:
		return 99
	return state.card_pool.get_remaining(card_id)


## Tier appearance probability [0.0, 1.0] at current shop level.
func _tier_weight_fraction(tier: int, shop_level: int) -> float:
	var key := str(shop_level)
	var weights: Array
	if _genome and _genome.shop_tier_weights.has(key):
		weights = _genome.shop_tier_weights[key]
	else:
		weights = Genome.DEFAULT_SHOP_TIER_WEIGHTS.get(key, [100, 0, 0, 0, 0])
	if tier < 1 or tier > weights.size():
		return 0.0
	var total := 0.0
	for w in weights:
		total += float(w)
	if total <= 0.0:
		return 0.0
	return float(weights[tier - 1]) / total


# --- Strategy implementations ---

## Cheap levelup: level up first when cost is trivially low.
func _try_cheap_levelup(state: GameState) -> void:
	while state.levelup_current_cost <= 2 and state.levelup_current_cost > 0:
		if not _try_levelup(state):
			break


## Economy: buy cards first, bank gold for interest, levelup when affordable.
func _play_economy(state: GameState, shop: RefCounted) -> void:
	_try_cheap_levelup(state)

	var interest_floor: int = _get_interest_floor()
	var pressure: float = _get_enemy_pressure(state.round_num)

	# Minimum board size: buy until we have at least 4 cards
	# But respect gold floor (at least keep 2g for R1 flexibility)
	var board_count := state.board_count()
	var min_gold := 2 if state.round_num <= 2 else 0
	var actions := 0
	while actions < MAX_ACTIONS and board_count < 4:
		actions += 1
		if state.gold <= min_gold:
			break
		var bought := _try_buy_best(state, shop, -1)
		if not bought:
			break
		board_count = state.board_count()

	# After minimum board, buy only if we'd still keep interest floor
	var pressure_excess: float = maxf(pressure - 1.0, 0.0)
	var buy_threshold: int = interest_floor + maxi(2 - int(pressure_excess * 3.0), 0)
	while actions < MAX_ACTIONS:
		actions += 1
		if state.gold < buy_threshold:
			break
		var bought := _try_buy_best(state, shop, -1)
		if not bought:
			break

	# Levelup only if we'd still have interest floor after
	if state.gold >= state.levelup_current_cost + interest_floor:
		_try_levelup(state)


## Aggressive: buy everything, reroll frequently.
func _play_aggressive(state: GameState, shop: RefCounted) -> void:
	_try_cheap_levelup(state)

	# Aggressive levelup: reach ShopLv3 by R5 for T3 access
	if state.round_num >= 5 and state.shop_level < 3:
		while state.shop_level < 3 and state.gold >= state.levelup_current_cost + 3:
			if not _try_levelup(state):
				break

	var pressure: float = _get_enemy_pressure(state.round_num)
	var reroll_budget := 4 + int(maxf(pressure - 1.0, 0.0) * 3.0)  # 4 at 1×, 7 at 2×

	var actions := 0
	var rerolls := 0
	while actions < MAX_ACTIONS:
		actions += 1
		var bought := _try_buy_best(state, shop, -1)
		if not bought:
			if rerolls < reroll_budget and state.gold >= _get_reroll_cost() + 2 and shop.reroll():
				rerolls += 1
				continue
			break


## Theme-focused: per-strategy parameterized behavior.
## v7: M1 interest banking, M2 slow-roll, M4 chain urgency, M5 economy transition.
func _play_theme_focused(state: GameState, shop: RefCounted) -> void:
	var preferred_theme: int = _THEME_MAP.get(strategy, Enums.CardTheme.NEUTRAL)
	var config: Dictionary = _STRATEGY_CONFIG.get(strategy, _STRATEGY_CONFIG["steampunk_focused"])

	_try_cheap_levelup(state)

	# Per-strategy levelup schedule
	var target_level := 1
	var schedule: Dictionary = config["levelup_schedule"]
	for round_threshold in schedule:
		if state.round_num >= round_threshold:
			target_level = maxi(target_level, schedule[round_threshold])

	# M1: Interest-aware gold reserve (replaces flat gold_reserve mid-game)
	var interest_floor: int = _get_universal_interest_floor(state.round_num)
	var gold_reserve: int = maxi(config["gold_reserve"], interest_floor)
	var pressure: float = _get_enemy_pressure(state.round_num)
	var pressure_excess: float = maxf(pressure - 1.0, 0.0)
	# M5: After aggro transition, drop gold reserve to 0 (all-in)
	if state.round_num >= int(_p("aggro_transition_round", 10)):
		gold_reserve = 0
	else:
		gold_reserve = maxi(gold_reserve - int(pressure_excess * 2.0), 0)

	# M2: Slow-roll — skip scheduled levelup if board strong + achievable merge
	var do_levelup := not _should_delay_levelup(state)

	if do_levelup:
		while state.shop_level < target_level and state.gold >= state.levelup_current_cost + gold_reserve:
			if not _try_levelup(state):
				break

	# Reroll budget: base + late bonus + merge bonus + chain/capstone/foundation urgency
	var max_rerolls: int = config["max_rerolls_base"]
	if state.round_num >= 6 and state.shop_level >= 3:
		max_rerolls = config["max_rerolls_late"]
	if _H.has_achievable_merge(state):
		# Scale reroll budget by merge probability at current shop level
		var p_merge := _H.merge_find_probability(state, _genome)
		var merge_extra := mini(int(p_merge * 10.0), 5)  # 0-5 extra based on find chance
		max_rerolls = maxi(max_rerolls, config["max_rerolls_late"] + merge_extra)
	max_rerolls += int(pressure_excess * 2.0)

	# Capstone urgency
	var capstone_cards: Array = config.get("capstone_cards", [])
	if state.shop_level >= 4 and not _H.has_any_card(state, capstone_cards):
		max_rerolls += int(_p("capstone_urgency_rerolls", 3))

	# M4: Chain pair urgency — if key chain partners are missing, reroll harder
	var board_ids := _H.get_board_ids(state)
	if _H.has_incomplete_chain_pair(board_ids, preferred_theme):
		max_rerolls += int(_p("chain_pair_reroll_bonus", 3))

	# Foundation urgency: in R1-R4, if no foundation from build path
	if state.round_num <= 4:
		var bp_path: Dictionary = _build_path.detect_build_path(strategy, board_ids)
		var has_foundation := false
		if not bp_path.is_empty():
			for cid in bp_path["phases"].get("foundation", []):
				if cid in board_ids:
					has_foundation = true
					break
		if not has_foundation:
			max_rerolls += int(_p("foundation_urgency_rerolls", 5))

	var actions := 0
	var rerolls := 0
	while actions < MAX_ACTIONS:
		actions += 1
		var bought := _try_buy_best(state, shop, preferred_theme)
		if bought:
			continue

		if rerolls < max_rerolls and state.gold >= _get_reroll_cost() + gold_reserve:
			if shop.reroll():
				rerolls += 1
				continue
		break

	# Levelup with leftover gold if affordable
	if state.gold >= state.levelup_current_cost + gold_reserve:
		_try_levelup(state)


## Hybrid: buy a mix, commit to dominant theme by mid-game.
## v7: M1 interest banking, M5 economy transition.
func _play_hybrid(state: GameState, shop: RefCounted) -> void:
	_try_cheap_levelup(state)

	# M1: Interest-aware levelup buffer
	var interest_floor: int = _get_universal_interest_floor(state.round_num)
	var levelup_buffer: int = maxi(4, interest_floor)
	if state.gold >= state.levelup_current_cost + levelup_buffer:
		_try_levelup(state)

	var preferred_theme := -1
	if state.round_num >= 4:
		preferred_theme = _H.detect_dominant_theme(state)

	var pressure: float = _get_enemy_pressure(state.round_num)
	var max_rerolls := 2
	if _H.has_achievable_merge(state):
		var p_merge := _H.merge_find_probability(state, _genome)
		max_rerolls = maxi(max_rerolls, 2 + mini(int(p_merge * 8.0), 4))
	max_rerolls += int(maxf(pressure - 1.0, 0.0) * 2.0)

	# M1: Gold floor for rerolls respects interest banking
	# M5: After aggro transition, no floor
	var reroll_floor: int = 3
	if state.round_num >= int(_p("aggro_transition_round", 10)):
		reroll_floor = 1
	elif interest_floor > 0:
		reroll_floor = maxi(reroll_floor, interest_floor)

	var actions := 0
	var rerolls := 0
	while actions < MAX_ACTIONS:
		actions += 1
		var bought := _try_buy_best(state, shop, preferred_theme)
		if not bought:
			if rerolls < max_rerolls and state.gold >= _get_reroll_cost() + reroll_floor and shop.reroll():
				rerolls += 1
				continue
			break


# --- Buy logic ---

func _try_buy_best(state: GameState, shop: RefCounted, preferred_theme: int) -> bool:
	var best_slot := -1
	var best_score := -999.0

	for i in shop.offered_ids.size():
		var card_id: String = shop.offered_ids[i]
		if card_id == "":
			continue

		var tmpl: Dictionary = CardDB.get_template(card_id)
		var cost: int = tmpl.get("cost", 99)
		if cost > state.gold:
			continue

		var score := _score_card(card_id, tmpl, preferred_theme, state)
		if score > best_score:
			best_score = score
			best_slot = i

	if best_slot < 0:
		return false

	if best_score < -3.0:
		return false

	if not _H.has_space(state):
		if best_score >= 15.0:
			var sold := _sell_weakest_for_upgrade(state)
			if not sold:
				return false
		else:
			return false

	return shop.try_purchase(best_slot)


## Score a card for purchase priority.
## v5: Reads genome activation_caps, strategy core cards, enemy pressure.
func _score_card(card_id: String, tmpl: Dictionary, preferred_theme: int, state: GameState) -> float:
	var score := 0.0
	var theme: int = tmpl.get("theme", Enums.CardTheme.NEUTRAL)
	var tier: int = tmpl.get("tier", 1)
	var round_num: int = state.round_num
	var timing: int = tmpl.get("trigger_timing", -1)

	# --- Theme match (Tier 1 params) ---
	var theme_bonus: float = _p("theme_match_bonus", 15.0)
	var off_penalty: float = _p("off_theme_penalty", 20.0)
	var crit_bonus: float = _p("critical_path_bonus", 8.0)
	if preferred_theme >= 0:
		if theme == preferred_theme:
			score += theme_bonus
			if _THEME_CRITICAL.has(preferred_theme) and card_id in _THEME_CRITICAL[preferred_theme]:
				score += crit_bonus
		elif theme == Enums.CardTheme.NEUTRAL:
			if round_num <= 4:
				score += 3.0
			elif round_num <= 8:
				score += 1.0
			else:
				score -= 2.0
		else:
			score -= off_penalty
	else:
		if theme == Enums.CardTheme.NEUTRAL:
			score += 3.0

	# --- Strategy core card bonus (Tier 1) ---
	var config: Dictionary = _STRATEGY_CONFIG.get(strategy, {})
	var core_cards: Array = config.get("core_cards", [])
	if card_id in core_cards:
		score += _p("core_card_bonus", 12.0)

	# --- Tier value ---
	score += tier * 2.0

	# --- Build path detection (used by merge gate + engine completion modifier) ---
	var board_ids := _H.get_board_ids(state)
	var bp_path: Dictionary = _build_path.detect_build_path(strategy, board_ids)

	# --- Merge potential (Tier 1) — ★1-aware + pool-aware ---
	var star1_copies := _H.count_star1_copies(state, card_id)
	if star1_copies == 2:
		score += _p("merge_imminent_bonus", 30.0)
	elif star1_copies == 1:
		var pool_left := _pool_remaining(state, card_id)
		var merge_prog := _p("merge_progress_bonus", 8.0)
		# Early game: pairs are more valuable (more rounds to complete merge)
		if round_num <= 6:
			merge_prog *= 1.5
		# Scale by tier accessibility — T1 pair at ShopLv4 (10%) is less valuable
		# than T1 pair at ShopLv1 (100%), because 3rd copy is harder to find
		var tier_frac := _tier_weight_fraction(tier, state.shop_level)
		merge_prog *= maxf(tier_frac, 0.1)  # floor at 10% to avoid zeroing out
		if pool_left >= 2:
			score += merge_prog
		elif pool_left == 1:
			score += merge_prog * 0.5

	# --- Chain synergy (Layer1 event chains, Tier 1) ---
	var syn_bonus: float = _p("synergy_pair_bonus", 6.0)
	var chain_bonus := 0.0
	if _CHAIN_PAIRS.has(card_id):
		for partner_id in _CHAIN_PAIRS[card_id]:
			if partner_id in board_ids:
				chain_bonus += syn_bonus
				break
	for owned_id in board_ids:
		if _CHAIN_PAIRS.has(owned_id) and card_id in _CHAIN_PAIRS[owned_id]:
			chain_bonus += syn_bonus
			break
	score += chain_bonus * (1.0 + round_num * 0.05)

	# --- Theme-internal synergy ---
	if _THEME_SYNERGY.has(card_id):
		var synergy_count := 0
		for partner_id in _THEME_SYNERGY[card_id]:
			if partner_id in board_ids:
				synergy_count += 1
		score += synergy_count * 4.0

	# --- Round-adaptive tier preference (Tier 1) ---
	var late_bonus: float = _p("late_tier_bonus", 6.0)
	if round_num >= 10 and tier >= 4:
		score += late_bonus
	elif round_num >= 5 and tier >= 3:
		score += late_bonus * 0.5

	# --- Timing-aware purchase priority ---
	if timing >= 0:
		score += _board_eval.timing_modifier(timing, round_num) * 0.3

	# --- POST_COMBAT_DEFEAT penalty when winning ---
	if timing == Enums.TriggerTiming.POST_COMBAT_DEFEAT and _recent_wins >= 3:
		score -= 10.0

	# --- Capstone urgency in late game ---
	if tier == 5 and round_num >= 10:
		score += 10.0

	# --- Duplicate card diminishing returns (all star levels) ---
	var total_copies := _H.count_copies(state, card_id)
	if total_copies >= 3:
		score -= 10.0


	# --- Genome: activation cap penalty (continuous) ---
	if _genome:
		var cap: int = _genome.get_activation_cap(card_id)
		if cap == 0:
			score -= 20.0  # Card is disabled by genome
		elif cap > 0:
			# Continuous decay: penalty = 8 / cap (cap=1→-8, cap=2→-4, cap=3→-2.7, cap=5→-1.6)
			score -= 8.0 / maxf(float(cap), 1.0)

	# --- Build path: engine completion modifier ---
	if not bp_path.is_empty():
		score += _build_path.score_card_modifier(card_id, bp_path, board_ids, round_num)

	# --- Theme state context bonus (trees, rank, unit caps, synergy chains) ---
	score += _theme_scorer.score_buy_bonus(
		card_id, tmpl, preferred_theme, _H.get_board_cards(state), _genome)

	return score


# --- Bench cleanup ---
func _cleanup_bench(state: GameState) -> void:
	var preferred_theme: int = _THEME_MAP.get(strategy, -1)
	var board_ids := _H.get_board_ids(state)

	var bench_count := 0
	for card in state.bench:
		if card != null:
			bench_count += 1

	if bench_count < 6:
		return

	var sold := 0
	while sold < 2:
		var worst_idx := -1
		var worst_val := 999.0

		for i in state.bench.size():
			if state.bench[i] == null:
				continue
			var card: CardInstance = state.bench[i]
			var val := _card_value(card, state)
			if preferred_theme >= 0:
				var card_theme: int = card.template.get("theme", 0)
				if card_theme != preferred_theme and card_theme != Enums.CardTheme.NEUTRAL:
					val -= 10.0
			if val < worst_val:
				worst_val = val
				worst_idx = i

		if worst_idx >= 0 and worst_val < _p("bench_sell_threshold", 12.0):
			state.sell_card("bench", worst_idx)
			sold += 1
		else:
			break


# --- Bench promotion logic ---

func _promote_bench(state: GameState) -> void:
	var actions: Array = _board_eval.find_promotions(
		state.board, state.bench, state.field_slots,
		strategy, state.round_num)
	for a in actions:
		var bi: int = a["bench_idx"]
		var fi: int = a["board_idx"]
		if a["action"] == "place":
			if state.bench[bi] != null and fi < state.board.size() and state.board[fi] == null:
				state.move_card("bench", bi, "board", fi)
		elif a["action"] == "swap":
			if state.bench[bi] != null and fi < state.board.size() and state.board[fi] != null:
				state.sell_card("board", fi)
				state.move_card("bench", bi, "board", fi)


## Evaluate a card's overall value on the board.
func _card_value(card: CardInstance, state: GameState) -> float:
	var cid: String = card.get_base_id()
	var tier: int = card.template.get("tier", 1)
	var star: int = card.star_level

	var total_cp: float = card.get_total_atk() + card.get_total_hp()
	var val: float = log(maxf(total_cp, 1.0)) * 5.0

	val += star * 8.0
	val += tier * 1.5

	# Timing-aware value differentiation
	var timing: int = card.template.get("trigger_timing", -1)
	if timing >= 0:
		val += _board_eval.timing_modifier(timing, state.round_num) * 0.5

	var board_ids := _H.get_board_ids(state)
	val += _H.count_synergies(cid, board_ids) * 3.0

	# Protect merge candidates (★1 pairs only — ★1+★2 can't merge)
	var star1_copies := _H.count_star1_copies(state, cid)
	if star1_copies >= 2:
		val += 20.0
	elif star1_copies == 1:
		# Mild protection for pair potential (don't sell 1st copy easily)
		val += 5.0

	var preferred_theme: int = _THEME_MAP.get(strategy, -1)
	if preferred_theme >= 0:
		var card_theme: int = card.template.get("theme", 0)
		if card_theme == preferred_theme:
			val += 5.0
			if _THEME_CRITICAL.has(preferred_theme) and cid in _THEME_CRITICAL[preferred_theme]:
				val += 10.0
		elif card_theme != Enums.CardTheme.NEUTRAL:
			val -= 5.0

	# Strategy core card bonus
	var config: Dictionary = _STRATEGY_CONFIG.get(strategy, {})
	var core_cards: Array = config.get("core_cards", [])
	if cid in core_cards:
		val += 8.0

	# Genome activation cap: continuous penalty on board value
	if _genome:
		var cap: int = _genome.get_activation_cap(cid)
		if cap == 0:
			val -= 15.0
		elif cap > 0:
			val -= 6.0 / maxf(float(cap), 1.0)

	# Build path: protect engine infrastructure, penalize anti cards
	var bp_path: Dictionary = _build_path.detect_build_path(strategy, board_ids)
	if not bp_path.is_empty():
		val += _build_path.card_value_modifier(cid, bp_path, board_ids, state.round_num)

	# Theme state accumulated value (trees, rank, counters)
	val += _theme_scorer.card_value_bonus(card, _H.get_board_cards(state), _genome)

	return val


# --- Sell logic ---

func _sell_weakest_for_upgrade(state: GameState) -> bool:
	var worst_zone := ""
	var worst_idx := -1
	var worst_val := 999.0

	for i in state.bench.size():
		if state.bench[i] == null:
			continue
		var val := _card_value(state.bench[i], state)
		if val < worst_val:
			worst_val = val
			worst_zone = "bench"
			worst_idx = i

	if worst_val > 20.0:
		for i in state.board.size():
			if state.board[i] == null:
				continue
			var c: CardInstance = state.board[i]
			if c.star_level >= 2:
				continue
			var val := _card_value(c, state)
			if val < worst_val:
				worst_val = val
				worst_zone = "board"
				worst_idx = i

	if worst_idx >= 0:
		state.sell_card(worst_zone, worst_idx)
		return true
	return false


func _transition_board(state: GameState) -> void:
	var board_ids := _H.get_board_ids(state)

	for i in state.board.size():
		if state.board[i] == null:
			continue
		var c: CardInstance = state.board[i]
		var tier: int = c.template.get("tier", 1)

		if tier > 1 or c.star_level > 1:
			continue
		if _H.count_star1_copies(state, c.get_base_id()) >= 2:
			continue
		if _H.count_synergies(c.get_base_id(), board_ids) >= 2:
			continue
		if c.get_total_atk() + c.get_total_hp() > 300.0:
			continue

		state.sell_card("board", i)
		break


func _try_sell_weak(state: GameState) -> void:
	var total_cards := _H.count_all_cards(state)
	if total_cards < 14:
		return

	var worst_zone := ""
	var worst_idx := -1
	var worst_score := 999.0

	for i in state.bench.size():
		if state.bench[i] == null:
			continue
		var c: CardInstance = state.bench[i]
		var val := _card_value(c, state)
		if val < worst_score:
			worst_score = val
			worst_zone = "bench"
			worst_idx = i

	if worst_idx >= 0 and worst_score < 15.0:
		state.sell_card(worst_zone, worst_idx)


# --- Board arrangement ---

func _arrange_board(state: GameState) -> void:
	# Move any remaining bench cards to empty board slots
	for bi in state.bench.size():
		if state.bench[bi] == null:
			continue
		for fi in state.field_slots:
			if state.board[fi] == null:
				state.move_card("bench", bi, "board", fi)
				break

	# Collect active cards
	var active: Array = []
	var active_indices: Array = []
	for i in state.board.size():
		if state.board[i] != null:
			active.append(state.board[i])
			active_indices.append(i)

	if active.size() <= 1:
		return

	# Solve optimal positions
	var ordered: Array = _position_solver.solve_positions(active)

	# Write back
	for idx in active_indices:
		state.board[idx] = null
	var slot := 0
	for card in ordered:
		while slot < state.field_slots and state.board[slot] != null:
			slot += 1
		if slot < state.field_slots:
			state.board[slot] = card
			slot += 1


# Helpers delegated to ai_helpers.gd (static utilities).
