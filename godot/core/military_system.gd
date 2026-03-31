class_name MilitarySystem
extends RefCounted
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


# --- Chain integration ---


func process_rs_card(card: CardInstance, idx: int, board: Array,
		rng: RandomNumberGenerator) -> Dictionary:
	match card.get_base_id():
		"ml_barracks": return _barracks(card, idx, board)
		"ml_outpost": return _outpost(card, idx, board, rng)
		"ml_special_ops": return _special_ops(card, idx, board)
		"ml_command": return _command(card, idx, board)
	return _empty()


func process_event_card(card: CardInstance, idx: int, board: Array,
		event: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	match card.get_base_id():
		"ml_academy": return _academy(card, idx, board, event)
		"ml_conscript": return _conscript_react(card, idx, board, event, rng)
		"ml_factory": return _factory(card, idx)
	return _empty()


# --- External hooks (combat engine) ---


func apply_battle_start(card: CardInstance, _idx: int, board: Array) -> Dictionary:
	match card.get_base_id():
		"ml_tactical": return _tactical_battle(card, board)
		"ml_assault": return _assault_battle(card, board)
	return _empty()


func apply_post_combat(card: CardInstance, _idx: int, board: Array,
		won: bool) -> Dictionary:
	if card.get_base_id() == "ml_supply":
		return _supply_post(card, board, won)
	return _empty()


## Persistent combat: ml_command revive stored for combat engine.
func apply_persistent(card: CardInstance) -> void:
	if card.get_base_id() != "ml_command":
		return
	var revive_hp := 0.50
	var revive_limit := 1
	match card.star_level:
		2:
			revive_hp = 0.75
		3:
			revive_hp = 1.0
			revive_limit = 3
	card.theme_state["revive_hp_pct"] = revive_hp
	card.theme_state["revive_limit"] = revive_limit


# --- Rank / Conscription helpers ---


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

	if base == "ml_barracks":
		# Rank 3→Soldier, Rank 5→Plasma, Rank 8→Walker
		if old < 3 and new_rank >= 3 and not triggered.get(3, false):
			triggered[3] = true
			card.add_specific_unit("ml_infantry", 1)
		if old < 5 and new_rank >= 5 and not triggered.get(5, false):
			triggered[5] = true
			card.add_specific_unit("ml_plasma", 1)
		if old < 8 and new_rank >= 8 and not triggered.get(8, false):
			triggered[8] = true
			card.add_specific_unit("ml_walker", 1)
	elif base == "ml_special_ops":
		# Rank threshold for leader generation
		var leader_rank := 8
		match card.star_level:
			2: leader_rank = 6
			3: leader_rank = 5
		if old < leader_rank and new_rank >= leader_rank and not triggered.get(leader_rank, false):
			triggered[leader_rank] = true
			card.add_specific_unit("ml_commander", 1)
			if card.star_level >= 3:
				card.add_specific_unit("ml_commander", 1)

	card.theme_state["rank_triggers"] = triggered


func _conscript(target: CardInstance, count: int, rng: RandomNumberGenerator) -> int:
	var added := 0
	for _i in count:
		var uid := _weighted_pick(rng)
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
	# ★1: train +1 self, +1 adj army  |  ★2: +2 self, +1 adj  |  ★3: +2 self + thresholds
	var self_train := 1
	match card.star_level:
		2: self_train = 2
		3: self_train = 2

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
	# ★1: conscript 2  |  ★2: +adj army 1  |  ★3: conscript 3, both adj
	var count := 2
	if card.star_level >= 3:
		count = 3

	var events: Array = []
	_conscript(card, count, rng)
	events.append(_conscript_evt(idx, idx))

	# ★2+: adjacent army cards get random units
	if card.star_level >= 2:
		var both := card.star_level >= 3
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
	# ★1: train +1 self, +1 adj  |  ★2/★3: same + rank threshold leaders
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
	# ★1: all army +1  |  ★3: all +2
	var amount := 1
	if card.star_level >= 3:
		amount = 2

	var events: Array = []
	for mi in _military_indices(board):
		events.append_array(_train_card(board[mi], mi, amount))

	return {"events": events, "gold": 0, "terazin": 0}


# --- OE cards ---


func _academy(card: CardInstance, idx: int, board: Array,
		event: Dictionary) -> Dictionary:
	# ★1: target +1 training  |  ★2: +ATK 2%  |  ★3: +2 training, +ATK 3%
	var target_idx: int = event.get("target_idx", -1)
	if target_idx < 0 or target_idx >= board.size():
		return _empty()

	var target: CardInstance = board[target_idx]
	var bonus_train := 1
	var growth := 0.0
	match card.star_level:
		2: growth = 0.02
		3:
			bonus_train = 2
			growth = 0.03

	var events: Array = []
	events.append_array(_train_card(target, target_idx, bonus_train))
	if growth > 0:
		target.enhance(null, growth, 0.0)

	return {"events": events, "gold": 0, "terazin": 0}


func _conscript_react(card: CardInstance, idx: int, board: Array,
		event: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	# ★1: target +1 random  |  ★2: +2  |  ★3: +2 (enhanced)
	var target_idx: int = event.get("target_idx", -1)
	if target_idx < 0 or target_idx >= board.size():
		return _empty()

	var target: CardInstance = board[target_idx]
	var add_n := 1
	match card.star_level:
		2: add_n = 2
		3: add_n = 2

	_conscript(target, add_n, rng)
	return {"events": [_conscript_evt(idx, target_idx)], "gold": 0, "terazin": 0}


func _factory(card: CardInstance, _idx: int) -> Dictionary:
	# ★1: counter+1, 10→terazin  |  ★2: 8→terazin+ATK3%  |  ★3: 6→2terazin+ATK5%
	var counter: int = card.theme_state.get("conscript_counter", 0)
	counter += 1

	var threshold := 10
	match card.star_level:
		2: threshold = 8
		3: threshold = 6

	var terazin := 0
	if counter >= threshold:
		counter -= threshold
		terazin += 1
		if card.star_level >= 3:
			terazin += 1
		if card.star_level >= 2:
			var growth := 0.03 if card.star_level == 2 else 0.05
			card.enhance(null, growth, 0.0)

	card.theme_state["conscript_counter"] = counter
	return {"events": [], "gold": 0, "terazin": terazin}


# --- Battle hooks ---


func _tactical_battle(card: CardInstance, board: Array) -> Dictionary:
	var rank := _rank(card)
	var total_units := 0
	for mi in _military_indices(board):
		total_units += (board[mi] as CardInstance).get_total_units()

	var shield_pct := rank * 0.02
	var atk_pct := float(total_units) * 0.005
	match card.star_level:
		2:
			shield_pct = rank * 0.03
			atk_pct = float(total_units) * 0.008
		3:
			shield_pct = rank * 0.04
			atk_pct = float(total_units) * 0.01

	for mi in _military_indices(board):
		var mc: CardInstance = board[mi]
		mc.shield_hp_pct += shield_pct
		mc.temp_buff(null, atk_pct)
	return _empty()


func _assault_battle(card: CardInstance, board: Array) -> Dictionary:
	var total_units := 0
	for mi in _military_indices(board):
		total_units += (board[mi] as CardInstance).get_total_units()

	var atk_pct := float(total_units) * 0.01
	match card.star_level:
		2: atk_pct = float(total_units) * 0.015
		3: atk_pct = float(total_units) * 0.02

	for mi in _military_indices(board):
		(board[mi] as CardInstance).temp_buff(null, atk_pct)

	# MS bonus for combat engine
	var ms_thresh := 15
	match card.star_level:
		2: ms_thresh = 12
		3: ms_thresh = 10
	if total_units >= ms_thresh:
		card.theme_state["ms_bonus"] = 1
	return _empty()


func _supply_post(card: CardInstance, board: Array, won: bool) -> Dictionary:
	var army_n := _army_card_count(board)
	var base_gold := 1
	var per_card := 0.5
	match card.star_level:
		2:
			base_gold = 2
			per_card = 1.0
		3:
			base_gold = 2
			per_card = 1.0
	var gold := base_gold + int(army_n * per_card)
	if not won and card.star_level < 2:
		gold /= 2
	var terazin := 0
	if card.star_level >= 3 and _rank(card) >= 5:
		terazin = 1
	return {"events": [], "gold": gold, "terazin": terazin}


func _empty() -> Dictionary:
	return {"events": [], "gold": 0, "terazin": 0}
