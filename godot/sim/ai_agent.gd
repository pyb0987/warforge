class_name AIAgent
extends RefCounted
## AI strategy agent for headless simulation.
## Makes build-phase decisions: buy, sell, reroll, levelup, arrange.
##
## v5: Multi-review driven overhaul (VETO response).
## Key improvements over v4:
##   - Per-strategy configs: levelup schedule, reroll budget, gold reserve, core cards
##   - Genome signal propagation: activation_caps → scoring, enemy_cp → spending
##   - Economy gold floor: minimum board phase respects gold reserve
##   - Adaptive spending: enemy pressure increases buy/reroll aggressiveness

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

## Per-strategy behavior parameters.
## levelup_targets: {round_num: target_shop_level} — by this round, aim for this level
## max_rerolls_base: base reroll budget per round
## max_rerolls_late: reroll budget after ShopLv3+ and R6+
## gold_reserve: keep this much gold after buying (0 = spend all)
## core_cards: highest priority cards for this strategy (beyond theme critical path)
## early_aggression: spend more in R1-R5 (true for predator/aggressive)
## Per-strategy config.
## v6: Faster levelup for non-military themes + aggressive T3+ seeking.
## levelup_schedule: {round: target_shop_level}
## core_cards: highest priority cards (beyond critical path)
## capstone_cards: T4/T5 game-changers that warrant extra rerolls
const _STRATEGY_CONFIG := {
	"steampunk_focused": {
		"levelup_schedule": {3: 2, 5: 3, 7: 4, 9: 5},
		"max_rerolls_base": 3,
		"max_rerolls_late": 6,
		"gold_reserve": 1,
		"core_cards": ["sp_charger", "sp_circulator", "sp_workshop"],
		"capstone_cards": ["sp_charger", "sp_arsenal", "sp_warmachine"],
	},
	"druid_focused": {
		"levelup_schedule": {3: 2, 5: 3, 7: 4, 9: 5},
		"max_rerolls_base": 3,
		"max_rerolls_late": 5,
		"gold_reserve": 1,
		"core_cards": ["dr_world", "dr_wt_root", "dr_deep"],
		"capstone_cards": ["dr_world", "dr_wrath", "dr_grace"],
	},
	"predator_focused": {
		"levelup_schedule": {3: 2, 5: 3, 7: 4, 9: 5},
		"max_rerolls_base": 4,
		"max_rerolls_late": 6,
		"gold_reserve": 0,
		"core_cards": ["pr_apex_hunt", "pr_queen", "pr_molt"],
		"capstone_cards": ["pr_apex_hunt", "pr_transcend"],
	},
	"military_focused": {
		"levelup_schedule": {3: 2, 5: 3, 8: 4, 10: 5},
		"max_rerolls_base": 2,
		"max_rerolls_late": 4,
		"gold_reserve": 2,
		"core_cards": ["ml_command", "ml_academy", "ml_special_ops"],
		"capstone_cards": ["ml_command", "ml_assault"],
	},
}

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

# ================================================================
# Chain synergy map (Layer1 event chains: RS → OE listeners)
# ================================================================

const _CHAIN_PAIRS := {
	"sp_assembly":  ["sp_workshop", "sp_line", "sp_charger"],
	"sp_furnace":   ["sp_workshop", "sp_charger"],
	"sp_workshop":  ["sp_circulator"],
	"sp_circulator": ["sp_workshop", "sp_line", "sp_charger"],
	"sp_line":      ["sp_workshop", "sp_line", "sp_charger"],
	"ne_earth_echo":     ["ne_wanderers", "ne_mana_crystal"],
	"ne_wild_pulse":     ["ne_mutant_adapt", "ne_ancient_catalyst"],
	"ne_ruin_resonance": ["ne_wanderers", "ne_mana_crystal", "ne_mutant_adapt", "ne_ancient_catalyst"],
	"ne_wanderers":      ["ne_mutant_adapt", "ne_ancient_catalyst"],
	"ne_mutant_adapt":   ["ne_wanderers", "ne_mana_crystal"],
	"ne_mana_crystal":   ["ne_wanderers"],
	"ne_ancient_catalyst": ["ne_mutant_adapt"],
}

# Theme-internal synergy (Layer2 systems)
const _THEME_SYNERGY := {
	"dr_cradle":     ["dr_origin", "dr_deep", "dr_wt_root", "dr_earth"],
	"dr_origin":     ["dr_cradle", "dr_deep", "dr_wt_root"],
	"dr_earth":      ["dr_cradle", "dr_origin", "dr_deep"],
	"dr_deep":       ["dr_cradle", "dr_origin", "dr_wt_root", "dr_world"],
	"dr_wt_root":    ["dr_cradle", "dr_origin", "dr_deep", "dr_world"],
	"dr_world":      ["dr_deep", "dr_wt_root", "dr_earth"],
	"dr_lifebeat":   ["dr_cradle", "dr_origin"],
	"dr_spore_cloud": ["dr_cradle", "dr_origin", "dr_deep"],
	"dr_grace":      ["dr_cradle", "dr_origin"],
	"pr_nest":       ["pr_molt", "pr_queen", "pr_carapace", "pr_harvest"],
	"pr_farm":       ["pr_molt", "pr_harvest"],
	"pr_queen":      ["pr_molt", "pr_carapace", "pr_harvest", "pr_apex_hunt"],
	"pr_molt":       ["pr_harvest", "pr_carapace", "pr_apex_hunt"],
	"pr_harvest":    ["pr_nest", "pr_queen", "pr_carapace"],
	"pr_carapace":   ["pr_molt", "pr_harvest", "pr_apex_hunt"],
	"pr_apex_hunt":  ["pr_molt", "pr_carapace"],
	"pr_transcend":  ["pr_molt", "pr_harvest", "pr_apex_hunt", "pr_swarm_sense"],
	"pr_swarm_sense": ["pr_nest", "pr_queen", "pr_transcend"],
	"pr_parasite":   ["pr_swarm_sense", "pr_nest", "pr_queen"],
	"ml_barracks":   ["ml_academy", "ml_conscript", "ml_tactical"],
	"ml_outpost":    ["ml_conscript", "ml_factory"],
	"ml_academy":    ["ml_barracks", "ml_special_ops", "ml_command"],
	"ml_conscript":  ["ml_outpost", "ml_factory"],
	"ml_command":    ["ml_academy", "ml_barracks", "ml_special_ops"],
	"ml_special_ops": ["ml_academy", "ml_tactical"],
	"ml_factory":    ["ml_outpost", "ml_conscript"],
	"ml_tactical":   ["ml_barracks", "ml_command", "ml_assault"],
	"ml_assault":    ["ml_barracks", "ml_outpost", "ml_command"],
	"ml_supply":     ["ml_barracks", "ml_outpost"],
}

# Critical path cards per theme — essential infrastructure
const _THEME_CRITICAL := {
	Enums.CardTheme.STEAMPUNK: ["sp_assembly", "sp_furnace", "sp_workshop", "sp_circulator", "sp_charger"],
	Enums.CardTheme.DRUID: ["dr_cradle", "dr_origin", "dr_deep", "dr_wt_root"],
	Enums.CardTheme.PREDATOR: ["pr_nest", "pr_farm", "pr_queen", "pr_molt"],
	Enums.CardTheme.MILITARY: ["ml_barracks", "ml_outpost", "ml_academy", "ml_conscript"],
}

const _POSITION_PRIORITY := {
	"sp_assembly": 10, "sp_furnace": 10,
	"sp_workshop": 30, "sp_circulator": 40, "sp_line": 50,
	"sp_interest": 60, "sp_barrier": 70, "sp_warmachine": 80, "sp_charger": 35,
	"sp_arsenal": 90,
	"ne_earth_echo": 10, "ne_wild_pulse": 10, "ne_ruin_resonance": 15,
	"ne_wanderers": 30, "ne_mutant_adapt": 40,
	"ne_mana_crystal": 35, "ne_ancient_catalyst": 45,
	"ne_merchant": 80, "ne_ruins": 20, "ne_awakening": 25,
	"ne_wildforce": 70, "ne_chimera_cry": 85, "ne_spirit_blessing": 75,
	"ne_dim_merchant": 15,
	"dr_cradle": 10, "dr_origin": 11, "dr_earth": 20,
	"dr_deep": 25, "dr_wt_root": 30, "dr_world": 35,
	"dr_lifebeat": 50, "dr_spore_cloud": 55, "dr_grace": 60, "dr_wrath": 45,
	"pr_nest": 10, "pr_farm": 15, "pr_queen": 12, "pr_transcend": 5,
	"pr_molt": 30, "pr_harvest": 35, "pr_carapace": 40,
	"pr_swarm_sense": 50, "pr_apex_hunt": 45, "pr_parasite": 55,
	"ml_barracks": 10, "ml_outpost": 15, "ml_command": 5,
	"ml_academy": 30, "ml_conscript": 35,
	"ml_special_ops": 20, "ml_factory": 40,
	"ml_tactical": 50, "ml_assault": 55, "ml_supply": 60,
}


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

	_cleanup_bench(state)
	_promote_bench(state)

	if state.round_num >= 7:
		_transition_board(state)

	_arrange_board(state)


# ================================================================
# Genome signal: enemy pressure → adaptive spending
# ================================================================

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


# ================================================================
# Strategy implementations
# ================================================================

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
## v6: Per-strategy levelup schedule, capstone-seeking rerolls, aggressive T3+ access.
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

	var gold_reserve: int = config["gold_reserve"]
	var pressure: float = _get_enemy_pressure(state.round_num)
	var pressure_excess: float = maxf(pressure - 1.0, 0.0)
	gold_reserve = maxi(gold_reserve - int(pressure_excess * 2.0), 0)

	# Prioritize levelup over buying — T3+ access is critical
	while state.shop_level < target_level and state.gold >= state.levelup_current_cost:
		if not _try_levelup(state):
			break

	# Reroll budget: base + late bonus + merge bonus + capstone urgency
	var max_rerolls: int = config["max_rerolls_base"]
	if state.round_num >= 6 and state.shop_level >= 3:
		max_rerolls = config["max_rerolls_late"]
	if _has_merge_candidate(state):
		max_rerolls = maxi(max_rerolls, config["max_rerolls_late"])
	max_rerolls += int(pressure_excess * 2.0)

	# Capstone urgency: if ShopLv4+ and no capstone card on board, reroll harder
	var capstone_cards: Array = config.get("capstone_cards", [])
	if state.shop_level >= 4 and not _has_any_card(state, capstone_cards):
		max_rerolls += 3

	# Foundation urgency: in R1-R4, if no foundation cards from build path, reroll harder
	if state.round_num <= 4:
		var board_ids := _get_board_ids(state)
		var bp_path: Dictionary = _build_path.detect_build_path(strategy, board_ids)
		var has_foundation := false
		if not bp_path.is_empty():
			var found_cards: Array = bp_path["phases"].get("foundation", [])
			for cid in found_cards:
				if cid in board_ids:
					has_foundation = true
					break
		if not has_foundation:
			max_rerolls += 5

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
func _play_hybrid(state: GameState, shop: RefCounted) -> void:
	_try_cheap_levelup(state)

	if state.gold >= state.levelup_current_cost + 4:
		_try_levelup(state)

	var preferred_theme := -1
	if state.round_num >= 4:
		preferred_theme = _detect_dominant_theme(state)

	var pressure: float = _get_enemy_pressure(state.round_num)
	var max_rerolls := 2
	if _has_merge_candidate(state):
		max_rerolls = 4
	max_rerolls += int(maxf(pressure - 1.0, 0.0) * 2.0)  # +1 at 1.5×, +2 at 2×

	var actions := 0
	var rerolls := 0
	while actions < MAX_ACTIONS:
		actions += 1
		var bought := _try_buy_best(state, shop, preferred_theme)
		if not bought:
			if rerolls < max_rerolls and state.gold >= _get_reroll_cost() + 3 and shop.reroll():
				rerolls += 1
				continue
			break


# ================================================================
# Buy logic
# ================================================================

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

	if not _has_space(state):
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

	# --- Theme match ---
	if preferred_theme >= 0:
		if theme == preferred_theme:
			score += 15.0
			if _THEME_CRITICAL.has(preferred_theme) and card_id in _THEME_CRITICAL[preferred_theme]:
				score += 8.0
		elif theme == Enums.CardTheme.NEUTRAL:
			if round_num <= 4:
				score += 3.0
			elif round_num <= 8:
				score += 1.0
			else:
				score -= 2.0
		else:
			# Stronger off-theme penalty: -20 (merge +30 still nets +10, but theme +15 wins)
			score -= 20.0
	else:
		if theme == Enums.CardTheme.NEUTRAL:
			score += 3.0

	# --- Strategy core card bonus ---
	var config: Dictionary = _STRATEGY_CONFIG.get(strategy, {})
	var core_cards: Array = config.get("core_cards", [])
	if card_id in core_cards:
		score += 12.0

	# --- Tier value ---
	score += tier * 2.0

	# --- Build path detection (used by merge gate + engine completion modifier) ---
	var board_ids := _get_board_ids(state)
	var bp_path: Dictionary = _build_path.detect_build_path(strategy, board_ids)

	# --- Merge potential ---
	var copy_count := _count_copies(state, card_id)
	if copy_count == 2:
		score += 30.0  # ★2 imminent
	elif copy_count == 1:
		score += 8.0   # ★1 progress

	# --- Chain synergy (Layer1 event chains) ---
	var chain_bonus := 0.0
	if _CHAIN_PAIRS.has(card_id):
		for partner_id in _CHAIN_PAIRS[card_id]:
			if partner_id in board_ids:
				chain_bonus += 6.0
				break
	for owned_id in board_ids:
		if _CHAIN_PAIRS.has(owned_id) and card_id in _CHAIN_PAIRS[owned_id]:
			chain_bonus += 6.0
			break
	score += chain_bonus * (1.0 + round_num * 0.05)

	# --- Theme-internal synergy ---
	if _THEME_SYNERGY.has(card_id):
		var synergy_count := 0
		for partner_id in _THEME_SYNERGY[card_id]:
			if partner_id in board_ids:
				synergy_count += 1
		score += synergy_count * 4.0

	# --- Round-adaptive tier preference ---
	if round_num >= 10 and tier >= 4:
		score += 6.0
	elif round_num >= 5 and tier >= 3:
		score += 3.0

	# --- Timing-aware purchase priority ---
	if timing >= 0:
		score += _board_eval.timing_modifier(timing, round_num) * 0.3

	# --- POST_COMBAT_DEFEAT penalty when winning ---
	if timing == Enums.TriggerTiming.POST_COMBAT_DEFEAT and _recent_wins >= 3:
		score -= 10.0

	# --- Capstone urgency in late game ---
	if tier == 5 and round_num >= 10:
		score += 10.0

	# --- Duplicate card diminishing returns ---
	if copy_count >= 3:
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

	return score


# ================================================================
# Bench cleanup
# ================================================================

func _cleanup_bench(state: GameState) -> void:
	var preferred_theme: int = _THEME_MAP.get(strategy, -1)
	var board_ids := _get_board_ids(state)

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

		if worst_idx >= 0 and worst_val < 12.0:
			state.sell_card("bench", worst_idx)
			sold += 1
		else:
			break


# ================================================================
# Bench promotion logic
# ================================================================

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

	var board_ids := _get_board_ids(state)
	val += _count_synergies(cid, board_ids) * 3.0

	var copies := _count_copies(state, cid)
	if copies >= 2:
		val += 20.0

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

	return val


# ================================================================
# Sell logic
# ================================================================

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
	var board_ids := _get_board_ids(state)

	for i in state.board.size():
		if state.board[i] == null:
			continue
		var c: CardInstance = state.board[i]
		var tier: int = c.template.get("tier", 1)

		if tier > 1 or c.star_level > 1:
			continue
		if _count_copies(state, c.get_base_id()) >= 2:
			continue
		if _count_synergies(c.get_base_id(), board_ids) >= 2:
			continue
		if c.get_total_atk() + c.get_total_hp() > 300.0:
			continue

		state.sell_card("board", i)
		break


func _try_sell_weak(state: GameState) -> void:
	var total_cards := _count_all_cards(state)
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


# ================================================================
# Theme detection (for hybrid)
# ================================================================

func _detect_dominant_theme(state: GameState) -> int:
	var counts := {}
	for card in state.board:
		if card == null:
			continue
		var theme: int = (card as CardInstance).template.get("theme", 0)
		if theme != Enums.CardTheme.NEUTRAL and theme != 0:
			counts[theme] = counts.get(theme, 0) + 1
	for card in state.bench:
		if card == null:
			continue
		var theme: int = (card as CardInstance).template.get("theme", 0)
		if theme != Enums.CardTheme.NEUTRAL and theme != 0:
			counts[theme] = counts.get(theme, 0) + 1

	var best_theme := -1
	var best_count := 1
	for t in counts:
		if counts[t] > best_count:
			best_count = counts[t]
			best_theme = t
	return best_theme


# ================================================================
# Board arrangement
# ================================================================

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


# ================================================================
# Helpers
# ================================================================

func _has_space(state: GameState) -> bool:
	for b in state.bench:
		if b == null:
			return true
	for b in state.board:
		if b == null:
			return true
	return false


func _count_copies(state: GameState, card_id: String) -> int:
	var count := 0
	for card in state.board:
		if card != null and (card as CardInstance).get_base_id() == card_id:
			count += 1
	for card in state.bench:
		if card != null and (card as CardInstance).get_base_id() == card_id:
			count += 1
	return count


func _get_board_ids(state: GameState) -> Dictionary:
	var ids := {}
	for card in state.board:
		if card != null:
			ids[(card as CardInstance).get_base_id()] = true
	for card in state.bench:
		if card != null:
			ids[(card as CardInstance).get_base_id()] = true
	return ids


func _count_synergies(card_id: String, board_ids: Dictionary) -> int:
	var count := 0
	if _CHAIN_PAIRS.has(card_id):
		for pid in _CHAIN_PAIRS[card_id]:
			if pid in board_ids:
				count += 1
	if _THEME_SYNERGY.has(card_id):
		for pid in _THEME_SYNERGY[card_id]:
			if pid in board_ids:
				count += 1
	return count


func _has_merge_candidate(state: GameState) -> bool:
	var counts := {}
	for card in state.board:
		if card != null:
			var cid: String = (card as CardInstance).get_base_id()
			counts[cid] = counts.get(cid, 0) + 1
	for card in state.bench:
		if card != null:
			var cid: String = (card as CardInstance).get_base_id()
			counts[cid] = counts.get(cid, 0) + 1
	for cid in counts:
		if counts[cid] == 2:
			return true
	return false


func _has_any_card(state: GameState, card_ids: Array) -> bool:
	for card in state.board:
		if card != null and (card as CardInstance).get_base_id() in card_ids:
			return true
	for card in state.bench:
		if card != null and (card as CardInstance).get_base_id() in card_ids:
			return true
	return false


func _count_theme_cards(state: GameState, theme: int) -> int:
	var count := 0
	for card in state.board:
		if card != null and (card as CardInstance).template.get("theme", 0) == theme:
			count += 1
	for card in state.bench:
		if card != null and (card as CardInstance).template.get("theme", 0) == theme:
			count += 1
	return count


func _count_all_cards(state: GameState) -> int:
	var count := 0
	for card in state.board:
		if card != null:
			count += 1
	for card in state.bench:
		if card != null:
			count += 1
	return count
