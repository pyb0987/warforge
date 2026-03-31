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


func _init() -> void:
	_rng = RandomNumberGenerator.new()
	_theme_systems[Enums.CardTheme.STEAMPUNK] = SteampunkSystem.new()
	_theme_systems[Enums.CardTheme.DRUID] = DruidSystem.new()
	_theme_systems[Enums.CardTheme.PREDATOR] = PredatorSystem.new()
	_theme_systems[Enums.CardTheme.MILITARY] = MilitarySystem.new()


func set_seed(seed_val: int) -> void:
	_rng.seed = seed_val


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

	for i in board.size():
		var card: CardInstance = board[i]
		var tmpl := card.template
		var timing: int = tmpl.get("trigger_timing", -1)

		if timing != Enums.TriggerTiming.ROUND_START:
			continue

		var req_tenure: int = tmpl.get("require_tenure", 0)
		if req_tenure > 0 and card.tenure < req_tenure:
			continue

		var is_thresh: bool = tmpl.get("is_threshold", false)
		if is_thresh and card.threshold_fired:
			continue
		if is_thresh:
			card.threshold_fired = true

		var effects: Array = tmpl.get("effects", [])
		var theme: int = tmpl.get("theme", -1)
		var result: Dictionary

		if effects.is_empty() and theme in _theme_systems:
			result = _theme_systems[theme].process_rs_card(card, i, board, _rng)
		else:
			result = _execute_effects(card, i, board, -1, 0)

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
			var timing: int = tmpl.get("trigger_timing", -1)

			if timing != Enums.TriggerTiming.ON_EVENT:
				continue
			if not _trigger_matches(tmpl, event, i):
				continue
			if not card.can_activate():
				continue
			card.activations_used += 1

			var effects: Array = tmpl.get("effects", [])
			var theme: int = tmpl.get("theme", -1)
			var result: Dictionary

			if effects.is_empty() and theme in _theme_systems:
				result = _theme_systems[theme].process_event_card(card, i, board, event, _rng)
			else:
				result = _execute_effects(card, i, board, event["target_idx"], 0)

			queue.append_array(result["events"])
			gold_earned += result["gold"]
			terazin_earned += result["terazin"]
			chain_count += 1

			if verbose:
				var l2_name := _layer2_name(event.get("layer2", -1))
				print("    CHAIN %s[%d] ← %s → %devt" % [
					card.get_name(), i, l2_name, result["events"].size()])

	chain_completed.emit(chain_count, gold_earned)

	return {"chain_count": chain_count, "gold_earned": gold_earned, "terazin_earned": terazin_earned}


# ── Internal helpers ─────────────────────────────────────────────


func _trigger_matches(tmpl: Dictionary, event: Dictionary, card_idx: int) -> bool:
	var listen_l1: int = tmpl.get("trigger_layer1", -1)
	if listen_l1 != -1:
		if event.get("layer1", -1) != listen_l1:
			return false

	var listen_l2: int = tmpl.get("trigger_layer2", -1)
	if listen_l2 != -1:
		if event.get("layer2", -1) != listen_l2:
			return false

	var require_other: bool = tmpl.get("require_other_card", false)
	if require_other:
		if event.get("source_idx", -1) == card_idx:
			return false

	return true


func _resolve_targets(target: String, card_idx: int,
		event_target_idx: int, board_len: int) -> Array[int]:
	var result: Array[int] = []
	match target:
		"self":
			result.append(card_idx)
		"right_adj":
			var r := card_idx + 1
			if r < board_len:
				result.append(r)
		"both_adj":
			if card_idx > 0:
				result.append(card_idx - 1)
			if card_idx + 1 < board_len:
				result.append(card_idx + 1)
		"all_allies":
			for idx in board_len:
				result.append(idx)
		"event_target":
			if event_target_idx >= 0:
				result.append(event_target_idx)
	return result


func _execute_effects(card: CardInstance, card_idx: int,
		board: Array, event_target_idx: int,
		depth: int) -> Dictionary:
	var events: Array = []
	var gold := 0
	var terazin := 0

	var effects: Array = card.template.get("effects", [])

	for eff in effects:
		var action: String = eff.get("action", "")
		var target: String = eff.get("target", "self")
		var targets := _resolve_targets(target, card_idx, event_target_idx, board.size())

		for ti in targets:
			var target_card: CardInstance = board[ti]

			match action:
				"spawn":
					var count: int = eff.get("spawn_count", 1)
					for _n in count:
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
					var n := target_card.enhance(
						tag_filter,
						eff.get("enhance_atk_pct", 0.0),
						eff.get("enhance_hp_pct", 0.0))
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
						var sub := _execute_effects(target_card, ti, board, -1, depth + 1)
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

				"diversity_gold":
					# 차원 행상인: 테마 수 × N 골드
					var themes_seen: Dictionary = {}
					for c in board:
						var th: int = (c as CardInstance).template.get("theme", -1)
						themes_seen[th] = true
					gold += themes_seen.size()

	return {"events": events, "gold": gold, "terazin": terazin}


func _layer2_name(l2: int) -> String:
	match l2:
		Enums.Layer2.MANUFACTURE: return "MANUFACTURE"
		Enums.Layer2.UPGRADE: return "UPGRADE"
		Enums.Layer2.HATCH: return "HATCH"
		Enums.Layer2.METAMORPHOSIS: return "METAMORPHOSIS"
		Enums.Layer2.TRAIN: return "TRAIN"
		Enums.Layer2.CONSCRIPT: return "CONSCRIPT"
		_: return "L1"
