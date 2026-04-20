class_name ChainEngine
extends RefCounted
## BFS growth chain engine. Ported from sim/engine/chain.py.
## Executes one round's growth chain: ROUND_START → BFS cascade.

const MAX_EVENTS := 100
const MAX_RETRIGGER_DEPTH := 3

# --- Signals for visualization (Sprint 4) ---
signal chain_event_fired(source_idx, target_idx, layer1, layer2, action)
signal chain_phase_started(phase_name)
signal chain_completed(chain_count, gold_earned)

var _rng: RandomNumberGenerator
var _theme_systems: Dictionary = {}

# --- Commander modifiers (set by game_manager) ---
var adjacency_range: int = 1  # 전략가: 2
var bonus_spawn_chance: float = 0.0  # 양성가: 0.3

# --- Talisman modifiers (set by game_manager) ---
var enhance_multiplier: float = 1.0   # 수은 방울: 1.25
var activation_bonus: int = 0          # 보스 보상: r8_3(+1), r12_3(+2)
var aoe_enhance: bool = false          # 보스 보상 r8_5: 강화 시 인접 50%
var flint_callback: Callable = Callable()  # 부싯돌: consume_flint_bonus
var cracked_egg_callback: Callable = Callable()  # 깨진 알: get_extra_spawn
## 폐품 상회(ne_scrapyard): pending_free_rerolls += N. 인자 = 추가할 리롤 수.
var pending_free_reroll_callback: Callable = Callable()


## 양성가 보너스를 테마 시스템에 전파.
func propagate_bonus_spawn() -> void:
	for sys in _theme_systems.values():
		sys.bonus_spawn_chance = bonus_spawn_chance
		sys.bonus_rng = _rng


## Genome card_effects를 테마 시스템에 전파.
func propagate_card_effects(effects: Dictionary) -> void:
	for sys in _theme_systems.values():
		sys.card_effects = effects


func _init() -> void:
	_rng = RandomNumberGenerator.new()
	_theme_systems[Enums.CardTheme.STEAMPUNK] = SteampunkSystem.new()
	_theme_systems[Enums.CardTheme.DRUID] = DruidSystem.new()
	_theme_systems[Enums.CardTheme.PREDATOR] = PredatorSystem.new()
	_theme_systems[Enums.CardTheme.MILITARY] = MilitarySystem.new()


func set_seed(seed_val: int) -> void:
	_rng.seed = seed_val


# ── Block access helpers ─────────────────────────────────────────

## Return the first block whose trigger_timing matches, or {} if absent.
## v2 schema: effects is a list of timing-block dicts.
func _find_block(tmpl: Dictionary, timing: int) -> Dictionary:
	for block in tmpl.get("effects", []):
		if block.get("trigger_timing", -1) == timing:
			return block
	return {}


## Return true if the card's block at `timing` exists and listen/require filters match.
func _trigger_matches_block(block: Dictionary, event: Dictionary, card_idx: int) -> bool:
	var listen_l1: int = block.get("trigger_layer1", -1)
	if listen_l1 != -1 and event.get("layer1", -1) != listen_l1:
		return false
	var listen_l2: int = block.get("trigger_layer2", -1)
	if listen_l2 != -1 and event.get("layer2", -1) != listen_l2:
		return false
	if block.get("require_other_card", false):
		if event.get("source_idx", -1) == card_idx:
			return false
	return true


## Execute one round's growth chain.
## Returns {"chain_count": int, "gold_earned": int, "terazin_earned": int}.
func run_growth_chain(board: Array, verbose: bool = false) -> Dictionary:
	# Reset activations, increment tenure
	for card in board:
		(card as CardInstance).reset_round()

	var queue: Array = []  # Array of {layer1, layer2, source_idx, target_idx}
	var chain_count := 0
	var gold_earned := 0
	var terazin_earned := 0

	# Phase 1: ROUND_START cards fire (left → right)
	chain_phase_started.emit("ROUND_START")
	var _flint_applied := false

	for i in board.size():
		var card: CardInstance = board[i]
		var tmpl := card.template
		var block := _find_block(tmpl, Enums.TriggerTiming.ROUND_START)
		if block.is_empty():
			continue

		var req_tenure: int = block.get("require_tenure", 0)
		if req_tenure > 0 and card.tenure < req_tenure:
			continue

		var is_thresh: bool = block.get("is_threshold", false)
		var _using_post_threshold := false
		if is_thresh and card.threshold_fired:
			if block.has("post_threshold_effects"):
				_using_post_threshold = true
			else:
				continue
		if is_thresh and not card.threshold_fired:
			card.threshold_fired = true

		# 🪨 부싯돌: 첫 RS 카드에 효과량 ×2 적용
		var flint_mult := 1.0
		if not _flint_applied and flint_callback.is_valid():
			flint_mult = flint_callback.call()
			if flint_mult > 1.0:
				_flint_applied = true

		var saved_enhance := enhance_multiplier
		if flint_mult > 1.0:
			enhance_multiplier *= flint_mult
			# spawn 효과량 2배는 _execute_actions의 spawn_count에서 처리

		var actions: Array = block.get("actions", [])
		var theme: int = tmpl.get("theme", -1)
		var impl: String = tmpl.get("impl", "card_db")
		var result: Dictionary

		if _using_post_threshold:
			var post_actions: Array = block.get("post_threshold_effects", [])
			result = _execute_actions(card, i, board, -1, 0, flint_mult, post_actions)
		elif impl == "theme_system" and theme in _theme_systems:
			result = _theme_systems[theme].process_rs_card(card, i, board, _rng)
		else:
			result = _execute_actions(card, i, board, -1, 0, flint_mult, actions)

		# conditional_effects: 기본 효과 실행 후 조건 충족 시 추가 효과
		var cond_effects: Array = block.get("conditional_effects", [])
		for cond in cond_effects:
			if _check_condition(cond, card, i, board):
				var cond_result := _execute_conditional(cond, card, i, board, flint_mult)
				result["events"].append_array(cond_result["events"])
				result["gold"] += cond_result["gold"]
				result["terazin"] += cond_result["terazin"]

		# 부싯돌 modifier 복원
		enhance_multiplier = saved_enhance

		queue.append_array(result["events"])
		gold_earned += result["gold"]
		terazin_earned += result["terazin"]
		chain_count += 1

		if verbose:
			print("    R.START %s[%d] → %devt" % [card.get_name(), i, result["events"].size()])

	# Phase 2: BFS event cascade
	chain_phase_started.emit("BFS_CASCADE")

	var safety := MAX_EVENTS
	while not queue.is_empty() and safety > 0:
		var event: Dictionary = queue.pop_front()
		safety -= 1

		for i in board.size():
			var card: CardInstance = board[i]
			var tmpl := card.template
			var block := _find_block(tmpl, Enums.TriggerTiming.ON_EVENT)
			if block.is_empty():
				continue
			if not _trigger_matches_block(block, event, i):
				continue
			var max_act: int = block.get("max_activations", -1)
			if not card.can_activate_with(max_act, activation_bonus):
				continue
			card.activations_used += 1

			var actions: Array = block.get("actions", [])
			var theme: int = tmpl.get("theme", -1)
			var impl: String = tmpl.get("impl", "card_db")
			var result: Dictionary

			if impl == "theme_system" and theme in _theme_systems:
				result = _theme_systems[theme].process_event_card(card, i, board, event, _rng)
			else:
				result = _execute_actions(card, i, board, event["target_idx"], 0, 1.0, actions)

			# conditional_effects: 기본 효과 후 조건 충족 시 추가 효과
			var cond_effects: Array = block.get("conditional_effects", [])
			for cond in cond_effects:
				if _check_condition(cond, card, i, board):
					var cond_result := _execute_conditional(cond, card, i, board, 1.0)
					result["events"].append_array(cond_result["events"])
					result["gold"] += cond_result["gold"]
					result["terazin"] += cond_result["terazin"]

			queue.append_array(result["events"])
			gold_earned += result["gold"]
			terazin_earned += result["terazin"]
			chain_count += 1

			if verbose:
				var l2_name := _layer2_name(event.get("layer2", -1))
				print("    CHAIN %s[%d] ← %s → %devt" % [
					card.get_name(), i, l2_name, result["events"].size()])

	chain_completed.emit(chain_count, gold_earned)

	var ret := {"chain_count": chain_count, "gold_earned": gold_earned, "terazin_earned": terazin_earned}
	# Collect deferred conscription requests from military system
	var mil_sys = _theme_systems.get(Enums.CardTheme.MILITARY)
	if mil_sys and not mil_sys.pending_conscriptions.is_empty():
		ret["pending_conscriptions"] = mil_sys.pending_conscriptions.duplicate()
		mil_sys.clear_pending()
	return ret


## Process ON_MERGE triggers (e.g., ne_spirit_blessing).
## Called when a card merge (★ upgrade) occurs.
## Returns {"terazin": int, "gold": int, "events": Array}.
func process_merge_triggers(board: Array, merged_card: CardInstance) -> Dictionary:
	var terazin := 0
	var gold := 0
	var events: Array = []
	var merged_idx: int = board.find(merged_card)

	for i in board.size():
		var card: CardInstance = board[i]
		var tmpl := card.template
		var block := _find_block(tmpl, Enums.TriggerTiming.ON_MERGE)
		if block.is_empty():
			continue
		var max_act: int = block.get("max_activations", -1)
		if not card.can_activate_with(max_act, activation_bonus):
			continue
		card.activations_used += 1

		var actions: Array = block.get("actions", [])
		var result := _execute_actions(card, i, board, merged_idx, 0, 1.0, actions)
		terazin += result["terazin"]
		gold += result["gold"]
		events.append_array(result["events"])

	return {"terazin": terazin, "gold": gold, "events": events}


## Process ON_SELL triggers (e.g., sp_arsenal absorb, druid 🌳 distribute).
## Called when a card is sold. sold_card is the removed CardInstance.
func process_sell_triggers(board: Array, sold_card: CardInstance) -> void:
	# Druid: distribute 🌳 from sold druid card to remaining druids
	var dr_sys = _theme_systems.get(Enums.CardTheme.DRUID)
	if dr_sys != null:
		dr_sys.on_sell(sold_card, board)

	# ON_SELL timing cards (e.g., sp_arsenal)
	var sp_sys = _theme_systems.get(Enums.CardTheme.STEAMPUNK)
	if sp_sys == null:
		return
	for card in board:
		var c := card as CardInstance
		if c == null:
			continue
		if _find_block(c.template, Enums.TriggerTiming.ON_SELL).is_empty():
			continue
		sp_sys.on_sell_trigger(c, sold_card)


## Process ON_REROLL triggers (e.g., sp_interest).
## Called when shop reroll occurs.
## Returns {"terazin": int, "gold": int, "events": Array}.
func process_reroll_triggers(board: Array) -> Dictionary:
	var terazin := 0
	var gold := 0
	var events: Array = []

	for i in board.size():
		var card: CardInstance = board[i]
		var tmpl := card.template
		var block := _find_block(tmpl, Enums.TriggerTiming.ON_REROLL)
		if block.is_empty():
			continue
		var max_act: int = block.get("max_activations", -1)
		if not card.can_activate_with(max_act, activation_bonus):
			continue
		card.activations_used += 1

		var actions: Array = block.get("actions", [])
		var result := _execute_actions(card, i, board, -1, 0, 1.0, actions)
		terazin += result["terazin"]
		gold += result["gold"]
		events.append_array(result["events"])

	return {"terazin": terazin, "gold": gold, "events": events}


## Process PERSISTENT effects (e.g., sp_warmachine range_bonus, dr_wrath ATK buff).
## Called before battle to populate theme_state and apply combat buffs.
func process_persistent(board: Array) -> void:
	for i in board.size():
		var card: CardInstance = board[i]
		var tmpl := card.template
		if _find_block(tmpl, Enums.TriggerTiming.PERSISTENT).is_empty():
			continue
		var theme: int = tmpl.get("theme", -1)
		if theme in _theme_systems:
			_theme_systems[theme].apply_persistent(card)


## Process BATTLE_START effects. Handles both inline effects and theme system delegation.
## Returns {"gold": int, "terazin": int, "events": Array}.
func process_battle_start(board: Array) -> Dictionary:
	var gold := 0
	var terazin := 0
	var events: Array = []

	for i in board.size():
		var card: CardInstance = board[i]
		var tmpl := card.template
		var block := _find_block(tmpl, Enums.TriggerTiming.BATTLE_START)
		if block.is_empty():
			continue

		var actions: Array = block.get("actions", [])
		var theme: int = tmpl.get("theme", -1)
		var impl: String = tmpl.get("impl", "card_db")

		var result: Dictionary
		if impl == "theme_system" and theme in _theme_systems:
			result = _theme_systems[theme].apply_battle_start(card, i, board)
		else:
			result = _execute_actions(card, i, board, -1, 0, 1.0, actions)

		# conditional_effects: 기본 효과 후 조건 충족 시 추가 효과
		var cond_effects: Array = block.get("conditional_effects", [])
		for cond in cond_effects:
			if _check_condition(cond, card, i, board):
				var cond_result := _execute_conditional(cond, card, i, board, 1.0)
				result["events"].append_array(cond_result["events"])
				result["gold"] += cond_result["gold"]
				result["terazin"] += cond_result["terazin"]

		gold += result["gold"]
		terazin += result["terazin"]
		events.append_array(result["events"])

	return {"gold": gold, "terazin": terazin, "events": events}


## Process POST_COMBAT / POST_COMBAT_DEFEAT / POST_COMBAT_VICTORY effects.
## Returns {"gold": int, "terazin": int, "events": Array}.
func process_post_combat(board: Array, won: bool) -> Dictionary:
	var gold := 0
	var terazin := 0
	var events: Array = []

	# Try each PC-family timing per card (one block matches at most).
	var pc_timings := [
		Enums.TriggerTiming.POST_COMBAT,
		Enums.TriggerTiming.POST_COMBAT_DEFEAT,
		Enums.TriggerTiming.POST_COMBAT_VICTORY,
	]

	for i in board.size():
		var card: CardInstance = board[i]
		var tmpl := card.template

		var block: Dictionary = {}
		var timing: int = -1
		for t in pc_timings:
			var b := _find_block(tmpl, t)
			if not b.is_empty():
				block = b
				timing = t
				break
		if block.is_empty():
			continue

		var should_fire := false
		match timing:
			Enums.TriggerTiming.POST_COMBAT:
				should_fire = true
			Enums.TriggerTiming.POST_COMBAT_DEFEAT:
				should_fire = not won
			Enums.TriggerTiming.POST_COMBAT_VICTORY:
				should_fire = won
		if not should_fire:
			continue
		var max_act: int = block.get("max_activations", -1)
		if not card.can_activate_with(max_act, activation_bonus):
			continue
		card.activations_used += 1

		var actions: Array = block.get("actions", [])
		var theme: int = tmpl.get("theme", -1)
		var impl: String = tmpl.get("impl", "card_db")
		var result: Dictionary

		if impl == "theme_system" and theme in _theme_systems:
			result = _theme_systems[theme].apply_post_combat(
				card, i, board, won)
		else:
			result = _execute_actions(card, i, board, -1, 0, 1.0, actions)

		# conditional_effects: 기본 효과 후 조건 충족 시 추가 효과 (RS/OE/BS 와 대칭)
		var cond_effects: Array = block.get("conditional_effects", [])
		for cond in cond_effects:
			if _check_condition(cond, card, i, board):
				var cond_result := _execute_conditional(cond, card, i, board, 1.0)
				result["events"].append_array(cond_result["events"])
				result["gold"] += cond_result["gold"]
				result["terazin"] += cond_result["terazin"]

		gold += result["gold"]
		terazin += result["terazin"]
		events.append_array(result["events"])

	return {"gold": gold, "terazin": terazin, "events": events}


## Process a combat event (attack/ally_death). Returns combat buffs to apply.
## event_type: "attack" | "ally_death"
## source_card_idx: which card's unit triggered the event (-1 if unknown)
## Returns {"buffs": [{card_idx, atk_pct, hp_pct}]}
func process_combat_event(board: Array, event_type: String,
		source_card_idx: int) -> Dictionary:
	var buffs: Array = []

	# P3: early return — 대응 타이밍 결정
	var expected_timing: int = -1
	match event_type:
		"attack":
			expected_timing = Enums.TriggerTiming.ON_COMBAT_ATTACK
		"ally_death":
			expected_timing = Enums.TriggerTiming.ON_COMBAT_DEATH
	if expected_timing == -1:
		return {"buffs": buffs}

	for i in board.size():
		var card: CardInstance = board[i]
		var tmpl := card.template
		var block := _find_block(tmpl, expected_timing)
		if block.is_empty():
			continue
		var max_act: int = block.get("max_activations", -1)
		if not card.can_activate_with(max_act, activation_bonus):
			continue
		card.activations_used += 1

		var actions: Array = block.get("actions", [])
		for eff in actions:
			var action: String = eff.get("action", "")
			if action == "combat_buff_pct":
				var target: String = eff.get("target", "self")
				var target_indices := _resolve_combat_targets(
					target, i, source_card_idx, board.size())
				for ti in target_indices:
					buffs.append({
						"card_idx": ti,
						"atk_pct": eff.get("buff_atk_pct", 0.0),
						"hp_pct": eff.get("buff_hp_pct", 0.0),
					})

	return {"buffs": buffs}


func _resolve_combat_targets(target: String, card_idx: int,
		source_card_idx: int, board_len: int) -> Array[int]:
	var result: Array[int] = []
	match target:
		"self":
			result.append(card_idx)
		"source":
			if source_card_idx >= 0:
				result.append(source_card_idx)
		"all_allies":
			for idx in board_len:
				result.append(idx)
	return result


# ── Internal helpers ─────────────────────────────────────────────


func _resolve_targets(target: String, card_idx: int,
		event_target_idx: int, board_len: int) -> Array[int]:
	var result: Array[int] = []
	match target:
		"self":
			result.append(card_idx)
		"right_adj":
			for offset in range(1, adjacency_range + 1):
				var r := card_idx + offset
				if r < board_len:
					result.append(r)
		"both_adj":
			for offset in range(1, adjacency_range + 1):
				if card_idx - offset >= 0:
					result.append(card_idx - offset)
				if card_idx + offset < board_len:
					result.append(card_idx + offset)
		"all_allies":
			for idx in board_len:
				result.append(idx)
		"event_target":
			if event_target_idx >= 0:
				result.append(event_target_idx)
	return result


## Execute a list of action dicts. Replaces the old _execute_effects which read
## effects off `card.template.effects`; now callers pass the list explicitly
## (e.g. from a matching block, a post_threshold clause, or a conditional).
func _execute_actions(card: CardInstance, card_idx: int,
		board: Array, event_target_idx: int,
		depth: int, flint_mult: float, actions: Array) -> Dictionary:
	var events: Array = []
	var gold := 0
	var terazin := 0

	for eff in actions:
		var action: String = eff.get("action", "")
		var target: String = eff.get("target", "self")
		var targets := _resolve_targets(target, card_idx, event_target_idx, board.size())

		for ti in targets:
			var target_card: CardInstance = board[ti]

			match action:
				"spawn":
					var count: int = int(eff.get("spawn_count", 1) * flint_mult)
					# 🥚 깨진 알: ★2+ 카드 유닛추가 시 +1
					if cracked_egg_callback.is_valid():
						count += cracked_egg_callback.call(target_card)
					var use_strongest: bool = eff.get("breed_strongest", false)
					for _n in count:
						# Board-level cap (2026-04-19): MAX_BOARD_UNITS 초과 시 spawn 중단.
						if _count_board_units(board) >= Enums.MAX_BOARD_UNITS:
							break
						if use_strongest:
							var best_id := _strongest_unit_id(target_card)
							if best_id != "":
								target_card.add_specific_unit(best_id, 1)
							else:
								target_card.spawn_random(_rng)
						elif bonus_spawn_chance > 0.0:
							target_card.spawn_random_with_bonus(_rng, bonus_spawn_chance)
						else:
							target_card.spawn_random(_rng)
					var ol1: int = eff.get("output_layer1", -1)
					if ol1 != -1:
						var evt := {
							"layer1": ol1,
							"layer2": eff.get("output_layer2", -1),
							"source_idx": card_idx,
							"target_idx": ti,
						}
						events.append(evt)
						chain_event_fired.emit(card_idx, ti, ol1, eff.get("output_layer2", -1), "spawn")

				"enhance_pct":
					var tag_filter = eff.get("unit_tag_filter", "")
					if tag_filter == "":
						tag_filter = null
					var atk_amt: float = eff.get("enhance_atk_pct", 0.0) * enhance_multiplier
					var hp_amt: float = eff.get("enhance_hp_pct", 0.0) * enhance_multiplier
					var n := target_card.enhance(tag_filter, atk_amt, hp_amt)
					# 🔄 광역 강화장 (r8_5): 인접 카드에 50% 강화
					if n > 0 and aoe_enhance:
						for adj_offset in [-1, 1]:
							var adj_i: int = ti + adj_offset
							if adj_i >= 0 and adj_i < board.size():
								(board[adj_i] as CardInstance).enhance(
									tag_filter, atk_amt * 0.5, hp_amt * 0.5)
					var ol1: int = eff.get("output_layer1", -1)
					if n > 0 and ol1 != -1:
						var evt := {
							"layer1": ol1,
							"layer2": eff.get("output_layer2", -1),
							"source_idx": card_idx,
							"target_idx": ti,
						}
						events.append(evt)
						chain_event_fired.emit(card_idx, ti, ol1, eff.get("output_layer2", -1), "enhance")

				"retrigger":
					if depth < MAX_RETRIGGER_DEPTH:
						# Retrigger re-runs the target card's current-block actions.
						var tc_block := _find_block(target_card.template, Enums.TriggerTiming.ROUND_START)
						var sub_actions: Array = tc_block.get("actions", [])
						var sub := _execute_actions(target_card, ti, board, -1, depth + 1, 1.0, sub_actions)
						events.append_array(sub["events"])
						gold += sub["gold"]
						terazin += sub["terazin"]

				"grant_gold":
					gold += eff.get("gold_amount", 0)

				"grant_terazin":
					terazin += eff.get("terazin_amount", 0)

				"shield_pct":
					target_card.shield_hp_pct += eff.get("shield_hp_pct", 0.0)

				"buff_pct":
					var tag_filter = eff.get("unit_tag_filter", "")
					if tag_filter == "":
						tag_filter = null
					target_card.temp_buff(tag_filter, eff.get("buff_atk_pct", 0.0))

				"scrap_adjacent":
					# 폐품 상회: 양쪽 인접 카드에서 최약 유닛 N기씩 제거.
					# 1기 이상 제거 성공 시 game_state.pending_free_rerolls += reroll_gain.
					# ★3: 제거 유닛 1기당 1골드.
					var n_each: int = eff.get("scrap_count", 1)
					var reroll_gain: int = eff.get("reroll_gain", 1)
					var gold_per_unit: int = eff.get("gold_per_unit", 0)
					var total_removed := 0
					for adj_offset in [-1, 1]:
						var adj_i: int = card_idx + adj_offset
						if adj_i < 0 or adj_i >= board.size():
							continue
						var adj: CardInstance = board[adj_i]
						var removed: int = adj.remove_weakest(n_each)
						total_removed += removed
					if total_removed > 0:
						if pending_free_reroll_callback.is_valid():
							pending_free_reroll_callback.call(reroll_gain)
						gold += total_removed * gold_per_unit

				"diversity_gold":
					# 차원 행상인: 테마 수 × gold_per_theme 골드
					var themes_seen: Dictionary = {}
					for c in board:
						var th: int = (c as CardInstance).template.get("theme", -1)
						themes_seen[th] = true
					var theme_count: int = themes_seen.size()
					var gpt: int = eff.get("gold_per_theme", 1)
					gold += theme_count * gpt
					# ★3: 테마 >= threshold 시 테마당 테라진
					var tz_threshold: int = eff.get("terazin_threshold", 0)
					if tz_threshold > 0 and theme_count >= tz_threshold:
						terazin += theme_count * eff.get("terazin_per_theme", 0)
					# ★3: 비중립(용병) 카드마다 유닛 1기 spawn
					var merc_spawn: int = eff.get("mercenary_spawn", 0)
					if merc_spawn > 0:
						var neutral_theme: int = Enums.CardTheme.NEUTRAL
						for c2 in board:
							var ci: CardInstance = c2 as CardInstance
							if ci.template.get("theme", -1) != neutral_theme:
								for _s in merc_spawn:
									if bonus_spawn_chance > 0.0:
										ci.spawn_random_with_bonus(_rng, bonus_spawn_chance)
									else:
										ci.spawn_random(_rng)
								events.append({"layer1": Enums.Layer1.UNIT_ADDED,
									"layer2": Enums.Layer2.NONE,
									"source_idx": card_idx, "target_idx": board.find(ci)})

	return {"events": events, "gold": gold, "terazin": terazin}


## 보드 전체 유닛 수 합계 (MAX_BOARD_UNITS 체크용, 2026-04-19 도입).
func _count_board_units(board: Array) -> int:
	var total := 0
	for c in board:
		if c != null:
			total += (c as CardInstance).get_total_units()
	return total


func _strongest_unit_id(card: CardInstance) -> String:
	var best_id := ""
	var best_cp := -1.0
	for s in card.stacks:
		var ut: Dictionary = s["unit_type"]
		var as_val: float = maxf(ut["attack_speed"], 0.01)
		var cp: float = float(ut["atk"]) / as_val * float(ut["hp"])
		if cp > best_cp:
			best_cp = cp
			best_id = ut.get("id", "")
	return best_id


func _check_condition(cond: Dictionary, card: CardInstance,
		_card_idx: int, _board: Array) -> bool:
	var cond_type: String = cond.get("condition", "")
	match cond_type:
		"unit_count_gte":
			return card.get_total_units() >= cond.get("threshold", 0)
		"unit_count_lte":
			return card.get_total_units() <= cond.get("threshold", 0)
		"tenure_gte":
			return card.tenure >= cond.get("threshold", 0)
		_:
			return false


func _execute_conditional(cond: Dictionary, card: CardInstance,
		card_idx: int, board: Array, flint_mult: float) -> Dictionary:
	var actions: Array = cond.get("effects", [])
	return _execute_actions(card, card_idx, board, -1, 0, flint_mult, actions)


func _layer2_name(l2: int) -> String:
	match l2:
		Enums.Layer2.MANUFACTURE: return "MANUFACTURE"
		Enums.Layer2.UPGRADE: return "UPGRADE"
		Enums.Layer2.HATCH: return "HATCH"
		Enums.Layer2.METAMORPHOSIS: return "METAMORPHOSIS"
		Enums.Layer2.TRAIN: return "TRAIN"
		Enums.Layer2.CONSCRIPT: return "CONSCRIPT"
		_: return "L1"
