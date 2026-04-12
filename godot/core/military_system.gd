class_name MilitarySystem
extends "res://core/theme_system.gd"
## Military theme system: rank/training + conscription.
## RS cards (barracks, outpost, special_ops, command) train/conscript;
## OE cards (academy, conscript_react, factory) chain off TRAIN/CONSCRIPT events.

# Conscription unit pool (growth chain uses weighted random)
const CONSCRIPT_POOL: Array = [
	{"id": "ml_recruit", "weight": 3},
	{"id": "ml_drone", "weight": 2},
	{"id": "ml_biker", "weight": 2},
	{"id": "ml_infantry", "weight": 1},
	{"id": "ml_shield", "weight": 1},
	{"id": "ml_plasma", "weight": 1},
]

## Deferred conscription requests — filled by _outpost(), consumed by game_manager.
## Each entry: {card_ref: CardInstance, card_idx: int, count: int}
var pending_conscriptions: Array = []


# --- Chain integration ---


func process_rs_card(card: CardInstance, idx: int, board: Array,
		rng: RandomNumberGenerator) -> Dictionary:
	match card.get_base_id():
		"ml_barracks": return _barracks(card, idx, board)
		"ml_outpost": return _outpost(card, idx, board, rng)
		"ml_special_ops": return _special_ops(card, idx, board)
		"ml_command": return _command(card, idx, board)
	return Enums.empty_result()


func process_event_card(card: CardInstance, idx: int, board: Array,
		event: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	match card.get_base_id():
		"ml_academy": return _academy(card, idx, board, event)
		"ml_conscript": return _conscript_react(card, idx, board, event, rng)
		"ml_factory": return _factory(card, idx)
	return Enums.empty_result()


# --- External hooks (combat engine) ---


func apply_battle_start(card: CardInstance, _idx: int, board: Array) -> Dictionary:
	match card.get_base_id():
		"ml_tactical": return _tactical_battle(card, board)
		"ml_assault": return _assault_battle(card, board)
	return Enums.empty_result()


func apply_post_combat(card: CardInstance, _idx: int, board: Array,
		won: bool) -> Dictionary:
	if card.get_base_id() == "ml_supply":
		return _supply_post(card, board, won)
	return Enums.empty_result()


## Persistent combat: ml_command revive stored for combat engine.
func apply_persistent(card: CardInstance) -> void:
	if card.get_base_id() != "ml_command":
		return
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var revive_eff := _find_eff(effs, "revive")
	card.theme_state["revive_hp_pct"] = revive_eff.get("hp_pct", 0.50)
	card.theme_state["revive_limit"] = revive_eff.get("limit_per_combat", 1)


# --- Rank / Conscription helpers ---


func _find_eff(effs: Array, action: String, target: String = "") -> Dictionary:
	for e in effs:
		if e.get("action") == action:
			if target == "" or e.get("target", "") == target:
				return e
	return {}


func _rank(card: CardInstance) -> int:
	return card.theme_state.get("rank", 0)


func _add_rank(card: CardInstance, n: int) -> void:
	card.theme_state["rank"] = _rank(card) + n


func _train_card(card: CardInstance, idx: int, amount: int) -> Array:
	## Train a card: add rank, check thresholds, return TRAIN events.
	var old_rank := _rank(card)
	_add_rank(card, amount)
	_check_thresholds(card, old_rank, _rank(card))
	return [{
		"layer1": Enums.Layer1.ENHANCED,
		"layer2": Enums.Layer2.TRAIN,
		"source_idx": idx, "target_idx": idx,
	}]


func _check_thresholds(card: CardInstance, old: int, new_rank: int) -> void:
	var triggered: Dictionary = card.theme_state.get("rank_triggers", {})
	var base := card.get_base_id()
	var effs := CardDB.get_theme_effects(base, card.star_level)
	var thresh_eff := _find_eff(effs, "rank_threshold")
	if thresh_eff.is_empty():
		card.theme_state["rank_triggers"] = triggered
		return

	var tiers: Array = thresh_eff.get("tiers", [])
	for tier in tiers:
		var rank_val: int = tier.get("rank", -1)
		if rank_val < 0:
			continue
		if old < rank_val and new_rank >= rank_val and not triggered.get(rank_val, false):
			triggered[rank_val] = true
			var unit_id: String = tier.get("unit", "")
			var count: int = tier.get("count", 1)
			for _i in count:
				_add_with_bonus(card, unit_id, 1)

	card.theme_state["rank_triggers"] = triggered


## Return the next unfired rank threshold for a military card, or -1 if none.
static func get_next_threshold(card: CardInstance) -> int:
	var base := card.get_base_id()
	var rank: int = card.theme_state.get("rank", 0)
	var triggered: Dictionary = card.theme_state.get("rank_triggers", {})
	var effs := CardDB.get_theme_effects(base, card.star_level)
	var thresh_eff: Dictionary = {}
	for e in effs:
		if e.get("action") == "rank_threshold":
			thresh_eff = e
			break
	if thresh_eff.is_empty():
		return -1
	var tiers: Array = thresh_eff.get("tiers", [])
	for tier in tiers:
		var t: int = tier.get("rank", -1)
		if t >= 0 and not triggered.get(t, false):
			return t
	return -1


## 양성가 보너스 포함 유닛 추가 (이벤트 미방출).
func _add_with_bonus(target: CardInstance, unit_id: String, count: int) -> int:
	var added := target.add_specific_unit(unit_id, count)
	var bonus := CardInstance.roll_bonus_count(added, bonus_spawn_chance, bonus_rng)
	if bonus > 0:
		target.add_specific_unit(unit_id, bonus)
	return added


func _conscript(target: CardInstance, count: int, rng: RandomNumberGenerator) -> int:
	var added := 0
	for _i in count:
		var uid := _weighted_pick(rng)
		var n := target.add_specific_unit(uid, 1)
		added += n
		# 양성가 보너스: 징집 유닛 각각 확률로 1기 추가 (이벤트 미방출)
		if n > 0 and bonus_spawn_chance > 0.0 and bonus_rng != null:
			if bonus_rng.randf() < bonus_spawn_chance:
				added += target.add_specific_unit(uid, 1)
	return added


func _weighted_pick(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for entry in CONSCRIPT_POOL:
		total += entry["weight"]
	var r := rng.randf() * total
	var cum := 0.0
	for entry in CONSCRIPT_POOL:
		cum += entry["weight"]
		if r <= cum:
			return entry["id"]
	return CONSCRIPT_POOL[0]["id"]


func _military_indices(board: Array) -> Array[int]:
	var result: Array[int] = []
	for i in board.size():
		if (board[i] as CardInstance).template.get("theme", -1) == Enums.CardTheme.MILITARY:
			result.append(i)
	return result


func _army_card_count(board: Array) -> int:
	return _military_indices(board).size()


func _conscript_evt(src: int, tgt: int) -> Dictionary:
	return {
		"layer1": Enums.Layer1.UNIT_ADDED,
		"layer2": Enums.Layer2.CONSCRIPT,
		"source_idx": src, "target_idx": tgt,
	}


# --- RS cards ---


func _barracks(card: CardInstance, idx: int, board: Array) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var self_train_eff := _find_eff(effs, "train", "self")
	var self_train: int = self_train_eff.get("amount", 1)

	var events: Array = []
	events.append_array(_train_card(card, idx, self_train))

	# Adjacent army cards +1 training
	for di in [-1, 1]:
		var ni: int = idx + di
		if ni >= 0 and ni < board.size():
			var adj: CardInstance = board[ni]
			if adj.template.get("theme", -1) == Enums.CardTheme.MILITARY:
				events.append_array(_train_card(adj, ni, 1))

	return {"events": events, "gold": 0, "terazin": 0}


func _outpost(card: CardInstance, idx: int, board: Array,
		rng: RandomNumberGenerator) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var self_eff := _find_eff(effs, "conscript", "self")
	var count: int = self_eff.get("count", 2)

	var events: Array = []
	# Self-conscription deferred for player choice (3-pick-1 UI)
	pending_conscriptions.append({"card_ref": card, "card_idx": idx, "count": count})
	events.append(_conscript_evt(idx, idx))

	# ★2+: adjacent army cards get random units (stays random)
	var adj_eff := _find_eff(effs, "conscript", "right_adj")
	var both_adj_eff := _find_eff(effs, "conscript", "both_adj")
	var has_adj := not adj_eff.is_empty() or not both_adj_eff.is_empty()
	if has_adj:
		var both := not both_adj_eff.is_empty()
		var adj_list: Array[int] = []
		if both:
			if idx > 0: adj_list.append(idx - 1)
			if idx + 1 < board.size(): adj_list.append(idx + 1)
		else:
			if idx + 1 < board.size(): adj_list.append(idx + 1)

		for ni in adj_list:
			var adj: CardInstance = board[ni]
			if adj.template.get("theme", -1) == Enums.CardTheme.MILITARY:
				_conscript(adj, 1, rng)
				events.append(_conscript_evt(idx, ni))

	return {"events": events, "gold": 0, "terazin": 0}


func _special_ops(card: CardInstance, idx: int, board: Array) -> Dictionary:
	var events: Array = []
	events.append_array(_train_card(card, idx, 1))

	for di in [-1, 1]:
		var ni: int = idx + di
		if ni >= 0 and ni < board.size():
			var adj: CardInstance = board[ni]
			if adj.template.get("theme", -1) == Enums.CardTheme.MILITARY:
				events.append_array(_train_card(adj, ni, 1))

	return {"events": events, "gold": 0, "terazin": 0}


func _command(card: CardInstance, idx: int, board: Array) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var train_eff := _find_eff(effs, "train", "all_military")
	var amount: int = train_eff.get("amount", 1)

	var events: Array = []
	for mi in _military_indices(board):
		events.append_array(_train_card(board[mi], mi, amount))

	return {"events": events, "gold": 0, "terazin": 0}


# --- OE cards ---


func _academy(card: CardInstance, idx: int, board: Array,
		event: Dictionary) -> Dictionary:
	var target_idx: int = event.get("target_idx", -1)
	if target_idx < 0 or target_idx >= board.size():
		return Enums.empty_result()

	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var train_eff := _find_eff(effs, "train", "event_target")
	var enhance_eff := _find_eff(effs, "enhance", "event_target")
	var bonus_train: int = train_eff.get("amount", 1)
	var growth: float = enhance_eff.get("atk_pct", 0.0)

	var target: CardInstance = board[target_idx]
	var events: Array = []
	events.append_array(_train_card(target, target_idx, bonus_train))
	if growth > 0:
		target.enhance(null, growth, 0.0)

	return {"events": events, "gold": 0, "terazin": 0}


func _conscript_react(card: CardInstance, idx: int, board: Array,
		event: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var target_idx: int = event.get("target_idx", -1)
	if target_idx < 0 or target_idx >= board.size():
		return Enums.empty_result()

	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var con_eff := _find_eff(effs, "conscript", "event_target")
	var add_n: int = con_eff.get("count", 1)

	var target: CardInstance = board[target_idx]
	_conscript(target, add_n, rng)
	return {"events": [_conscript_evt(idx, target_idx)], "gold": 0, "terazin": 0}


func _factory(card: CardInstance, _idx: int) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var prod_eff := _find_eff(effs, "counter_produce")
	var threshold: int = prod_eff.get("threshold", 10)
	var rewards: Dictionary = prod_eff.get("rewards", {})

	var counter: int = card.theme_state.get("conscript_counter", 0)
	counter += 1

	var terazin := 0
	if counter >= threshold:
		counter -= threshold
		terazin += rewards.get("terazin", 1)
		var enhance_pct: float = rewards.get("enhance_atk_pct", 0.0)
		if enhance_pct > 0.0:
			card.enhance(null, enhance_pct, 0.0)

	card.theme_state["conscript_counter"] = counter
	return {"events": [], "gold": 0, "terazin": terazin}


# --- Battle hooks ---


func _tactical_battle(card: CardInstance, board: Array) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var buff_eff := _find_eff(effs, "rank_buff", "all_military")
	var shield_per_rank: float = buff_eff.get("shield_per_rank", 0.02)
	var atk_per_unit: float = buff_eff.get("atk_per_unit", 0.005)

	var rank := _rank(card)
	var total_units := 0
	for mi in _military_indices(board):
		total_units += (board[mi] as CardInstance).get_total_units()

	var shield_pct := rank * shield_per_rank
	var atk_pct := float(total_units) * atk_per_unit

	for mi in _military_indices(board):
		var mc: CardInstance = board[mi]
		mc.shield_hp_pct += shield_pct
		mc.temp_buff(null, atk_pct)
	return Enums.empty_result()


func _assault_battle(card: CardInstance, board: Array) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var buff_eff := _find_eff(effs, "swarm_buff", "all_military")
	var atk_per_unit: float = buff_eff.get("atk_per_unit", 0.01)
	var ms_bonus_def: Dictionary = buff_eff.get("ms_bonus", {})
	var ms_thresh: int = ms_bonus_def.get("unit_thresh", 15)
	var ms_bonus_val: int = ms_bonus_def.get("bonus", 1)

	var total_units := 0
	for mi in _military_indices(board):
		total_units += (board[mi] as CardInstance).get_total_units()

	var atk_pct := float(total_units) * atk_per_unit
	for mi in _military_indices(board):
		(board[mi] as CardInstance).temp_buff(null, atk_pct)

	if total_units >= ms_thresh:
		card.theme_state["ms_bonus"] = ms_bonus_val
	return Enums.empty_result()


func _supply_post(card: CardInstance, board: Array, won: bool) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var econ_eff := _find_eff(effs, "economy")
	var base_gold: int = econ_eff.get("gold_base", 1)
	var per_card: float = econ_eff.get("gold_per", 0.5)
	var halve_on_loss: bool = econ_eff.get("halve_on_loss", false)
	var terazin_def: Dictionary = econ_eff.get("terazin", {})

	var army_n := _army_card_count(board)
	var gold := base_gold + int(army_n * per_card)
	if not won and halve_on_loss:
		gold /= 2

	var terazin := 0
	if not terazin_def.is_empty():
		var cond: String = terazin_def.get("condition", "")
		var thresh: int = terazin_def.get("thresh", 0)
		if cond == "rank_gte" and _rank(card) >= thresh:
			terazin = terazin_def.get("amount", 1)

	return {"events": [], "gold": gold, "terazin": terazin}


# --- Deferred conscription helpers (3-pick-1 UI) ---


func clear_pending() -> void:
	pending_conscriptions.clear()


func pick_conscript_options(rng: RandomNumberGenerator, count: int = 3) -> Array[String]:
	var result: Array[String] = []
	for _i in count:
		result.append(_weighted_pick(rng))
	return result


func apply_conscript(card: CardInstance, unit_id: String) -> int:
	var added := card.add_specific_unit(unit_id, 1)
	if added > 0 and bonus_spawn_chance > 0.0 and bonus_rng != null:
		if bonus_rng.randf() < bonus_spawn_chance:
			added += card.add_specific_unit(unit_id, 1)
	return added
