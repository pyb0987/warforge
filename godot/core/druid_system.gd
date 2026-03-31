class_name DruidSystem
extends RefCounted
## Druid theme system: 🌳 tree counter, growth, breed, world tree multiplicative.
## All 10 druid cards handled here. RS cards process during growth chain;
## BS/PC/PERSISTENT cards provide hooks for combat engine.


# --- Chain integration ---


func process_rs_card(card: CardInstance, idx: int, board: Array,
		_rng: RandomNumberGenerator) -> Dictionary:
	match card.get_base_id():
		"dr_cradle": return _cradle(card, idx, board)
		"dr_origin": return _origin(card, idx, board)
		"dr_earth": return _earth(card, idx, board)
		"dr_deep": return _deep(card, idx)
		"dr_wt_root": return _wt_root(card, idx, board)
		"dr_world": return _world(card, idx, board)
	return _empty()


func process_event_card(_card: CardInstance, _idx: int, _board: Array,
		_event: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
	# Druid has no ON_EVENT cards in growth chain
	return _empty()


# --- External hooks (combat engine) ---


## Battle start: dr_lifebeat, dr_spore_cloud.
func apply_battle_start(card: CardInstance, _idx: int, board: Array) -> Dictionary:
	match card.get_base_id():
		"dr_lifebeat": return _lifebeat_battle(card)
		"dr_spore_cloud": return _spore_cloud_battle(card)
	return _empty()


## Post combat: dr_grace economy.
func apply_post_combat(card: CardInstance, _idx: int, _board: Array,
		won: bool) -> Dictionary:
	if card.get_base_id() == "dr_grace":
		return _grace_post(card, won)
	return _empty()


## Persistent combat: dr_wrath ATK buff.
func apply_persistent(card: CardInstance) -> void:
	if card.get_base_id() != "dr_wrath":
		return
	if card.get_total_units() > 5:
		return
	var trees := _trees(card)
	match card.star_level:
		1:
			card.temp_buff(null, 0.80 + trees * 0.05)
		2:
			card.temp_buff(null, 1.20 + trees * 0.08)
			# HP +60% handled by combat engine
		3:
			card.temp_mult_buff(1.5)
			# HP ×1.3, kill HP recover → combat engine


## Druid card sale: distribute 🌳 evenly to other druid cards.
func on_sell(sold_card: CardInstance, board: Array) -> void:
	if sold_card.template.get("theme", -1) != Enums.CardTheme.DRUID:
		return
	var trees_to_dist := _trees(sold_card)
	if trees_to_dist <= 0:
		return
	var druids: Array = []
	for c in board:
		var ci: CardInstance = c
		if ci != sold_card and ci.template.get("theme", -1) == Enums.CardTheme.DRUID:
			druids.append(ci)
	if druids.is_empty():
		return
	var per_card := trees_to_dist / druids.size()
	var remainder := trees_to_dist % druids.size()
	for i in druids.size():
		var bonus := per_card + (1 if i < remainder else 0)
		_add_trees(druids[i], bonus)


# --- 🌳 helpers ---


func _trees(card: CardInstance) -> int:
	return card.theme_state.get("trees", 0)


func _add_trees(card: CardInstance, n: int) -> void:
	card.theme_state["trees"] = maxi(_trees(card) + n, 0)


func _druid_entries(board: Array) -> Array:
	## Returns [{card, idx}] for all druid cards on board.
	var result: Array = []
	for i in board.size():
		var c: CardInstance = board[i]
		if c.template.get("theme", -1) == Enums.CardTheme.DRUID:
			result.append({"card": c, "idx": i})
	return result


func _druid_unit_count(board: Array) -> int:
	var count := 0
	for entry in _druid_entries(board):
		count += (entry["card"] as CardInstance).get_total_units()
	return count


func _adj_druid_indices(idx: int, board: Array, both: bool) -> Array[int]:
	var result: Array[int] = []
	if both:
		if idx > 0 and (board[idx - 1] as CardInstance).template.get("theme", -1) == Enums.CardTheme.DRUID:
			result.append(idx - 1)
		if idx + 1 < board.size() and (board[idx + 1] as CardInstance).template.get("theme", -1) == Enums.CardTheme.DRUID:
			result.append(idx + 1)
	else:
		if idx + 1 < board.size() and (board[idx + 1] as CardInstance).template.get("theme", -1) == Enums.CardTheme.DRUID:
			result.append(idx + 1)
	return result


# --- RS card implementations ---


func _cradle(card: CardInstance, idx: int, board: Array) -> Dictionary:
	# ★1: 🌳+1 self, +1 right  |  ★2: +2 self, +1 both  |  ★3: +3 self, +2 both
	var self_n := 1
	var adj_n := 1
	var both := false
	match card.star_level:
		2:
			self_n = 2
			both = true
		3:
			self_n = 3
			adj_n = 2
			both = true

	_add_trees(card, self_n)
	for ni in _adj_druid_indices(idx, board, both):
		_add_trees(board[ni], adj_n)

	return _empty()


func _origin(card: CardInstance, idx: int, board: Array) -> Dictionary:
	# ★1: 🌳+1, absorb adj 🌳1, 🌳6+ breed (growth -4%p)
	# ★2: 🌳+1, absorb 🌳2, 🌳5+ breed×2 (-3%p)
	# ★3: 🌳+2, absorb 🌳2, 🌳5+ both adj breed×2 (no penalty)
	var self_add := 1
	var absorb := 1
	var breed_thresh := 6
	var breed_count := 1
	var penalty := 0.04
	var breed_both := false
	match card.star_level:
		2:
			absorb = 2
			breed_thresh = 5
			breed_count = 2
			penalty = 0.03
		3:
			self_add = 2
			absorb = 2
			breed_thresh = 5
			breed_count = 2
			penalty = 0.0
			breed_both = true

	_add_trees(card, self_add)

	# Absorb from adjacent druid cards
	for di in [-1, 1]:
		var ni: int = idx + di
		if ni >= 0 and ni < board.size():
			var adj: CardInstance = board[ni]
			if adj.template.get("theme", -1) == Enums.CardTheme.DRUID:
				var take := mini(_trees(adj), absorb)
				_add_trees(adj, -take)
				_add_trees(card, take)

	# Breed if threshold met
	var events: Array = []
	if _trees(card) >= breed_thresh:
		var targets := _adj_druid_indices(idx, board, breed_both)
		# Fallback: breed on self if no adjacent druid
		if targets.is_empty():
			for _b in breed_count:
				card.breed_strongest()
			if penalty > 0:
				card.growth_atk_pct -= penalty
				card.growth_hp_pct -= penalty
			events.append({
				"layer1": Enums.Layer1.UNIT_ADDED,
				"layer2": Enums.Layer2.BREED,
				"source_idx": idx, "target_idx": idx,
			})
		else:
			for ti in targets:
				var target: CardInstance = board[ti]
				for _b in breed_count:
					target.breed_strongest()
				if penalty > 0:
					target.growth_atk_pct -= penalty
					target.growth_hp_pct -= penalty
				events.append({
					"layer1": Enums.Layer1.UNIT_ADDED,
					"layer2": Enums.Layer2.BREED,
					"source_idx": idx, "target_idx": ti,
				})

	return {"events": events, "gold": 0, "terazin": 0}


func _earth(card: CardInstance, idx: int, board: Array) -> Dictionary:
	# ★1: 🌳+1, all druid growth ⌊units÷5⌋%
	# ★2: ⌊÷4⌋%, 8→+2%, 12→+3%
	# ★3: 🌳+2, ⌊÷3⌋%, battle shield (stored for combat)
	_add_trees(card, 2 if card.star_level >= 3 else 1)

	var druid_units := _druid_unit_count(board)
	var divisor := 5
	match card.star_level:
		2: divisor = 4
		3: divisor = 3

	var growth_pct := float(druid_units / divisor) / 100.0
	var events: Array = []

	if growth_pct > 0:
		for entry in _druid_entries(board):
			(entry["card"] as CardInstance).enhance(null, growth_pct, growth_pct)
		events.append({
			"layer1": Enums.Layer1.ENHANCED,
			"layer2": Enums.Layer2.TREE_GROW,
			"source_idx": idx, "target_idx": idx,
		})

	# ★2+: bonus tiers
	if card.star_level >= 2:
		var bonus := 0.0
		if druid_units >= 12:
			bonus = 0.03
		elif druid_units >= 8:
			bonus = 0.02
		if bonus > 0:
			for entry in _druid_entries(board):
				(entry["card"] as CardInstance).enhance(null, bonus, bonus)

	return {"events": events, "gold": 0, "terazin": 0}


func _deep(card: CardInstance, idx: int) -> Dictionary:
	# ★1: 🌳+1, Growth(0.8), ≤3→Growth(1.2), 🌳10+→×1.3 growth
	# ★2: 🌳+1, Growth(1.2)/≤3→1.8, 🌳8+→×1.3
	# ★3: 🌳+2, Growth(1.2)/≤3→1.8, 🌳8+→×1.5
	_add_trees(card, 2 if card.star_level >= 3 else 1)
	var trees := _trees(card)
	var units := card.get_total_units()

	var rate := 0.008  # Growth(0.8) = 🌳 × 0.8%
	var low_rate := 0.012  # Growth(1.2) for few units
	var low_thresh := 3
	var mult_thresh := 10
	var mult := 1.3
	match card.star_level:
		2:
			rate = 0.012
			low_rate = 0.018
			mult_thresh = 8
		3:
			rate = 0.012
			low_rate = 0.018
			mult_thresh = 8
			mult = 1.5

	var actual_rate := low_rate if units <= low_thresh else rate
	var growth := float(trees) * actual_rate
	if trees >= mult_thresh:
		growth *= mult

	var events: Array = []
	if growth > 0:
		card.enhance(null, growth, growth)
		events.append({
			"layer1": Enums.Layer1.ENHANCED,
			"layer2": Enums.Layer2.TREE_GROW,
			"source_idx": idx, "target_idx": idx,
		})
	return {"events": events, "gold": 0, "terazin": 0}


func _wt_root(card: CardInstance, idx: int, board: Array) -> Dictionary:
	# ★1: 🌳+1, 🌳4+→all druid+1, 🌳8+→all+2
	# ★2: 🌳+1, 🌳3→+1, 🌳6→+2
	# ★3: 🌳+2, 🌳3→+1, 🌳6→+2, 🌳8→epic shop (UI)
	_add_trees(card, 2 if card.star_level >= 3 else 1)
	var trees := _trees(card)

	var thresh_low := 4
	var thresh_high := 8
	match card.star_level:
		2:
			thresh_low = 3
			thresh_high = 6
		3:
			thresh_low = 3
			thresh_high = 6

	var dist := 0
	if trees >= thresh_high:
		dist = 2
	elif trees >= thresh_low:
		dist = 1

	if dist > 0:
		for entry in _druid_entries(board):
			var c: CardInstance = entry["card"]
			if c != card:
				_add_trees(c, dist)

	return _empty()


func _world(card: CardInstance, idx: int, board: Array) -> Dictionary:
	# ★1: 🌳+2 self, all+1. [≤20u] ATK×1.1+⌊🌳÷30⌋×0.1, HP×1.05+same, AS stored
	# ★2: 🌳+3, all+2. ATK×1.15, ÷20  |  ★3: 🌳+3, all+2. ATK×1.3, ÷10, ≤30u
	var self_trees := 2
	var all_trees := 1
	match card.star_level:
		2:
			self_trees = 3
			all_trees = 2
		3:
			self_trees = 3
			all_trees = 2

	_add_trees(card, self_trees)
	for entry in _druid_entries(board):
		var c: CardInstance = entry["card"]
		if c != card:
			_add_trees(c, all_trees)

	var trees := _trees(card)
	var unit_cap := 20
	if card.star_level >= 3:
		unit_cap = 30
	if card.get_total_units() > unit_cap:
		return _empty()

	# Multiplicative growth per round
	var base_atk := 1.10
	var atk_div := 30.0
	var base_hp := 1.05
	var hp_div := 30.0
	match card.star_level:
		2:
			base_atk = 1.15
			atk_div = 20.0
		3:
			base_atk = 1.30
			atk_div = 10.0

	var tree_atk := floorf(trees / atk_div) * 0.1
	var tree_hp := floorf(trees / hp_div) * 0.05
	card.multiply_stats(base_atk + tree_atk - 1.0, base_hp + tree_hp - 1.0)

	# AS multiplier stored for combat engine
	card.theme_state["as_mult"] = 1.05 + floorf(trees / 30.0) * 0.05

	return {
		"events": [{
			"layer1": Enums.Layer1.ENHANCED,
			"layer2": Enums.Layer2.TREE_GROW,
			"source_idx": idx, "target_idx": idx,
		}],
		"gold": 0, "terazin": 0,
	}


# --- Battle hooks ---


func _lifebeat_battle(card: CardInstance) -> Dictionary:
	_add_trees(card, 2 if card.star_level >= 3 else 1)
	var trees := _trees(card)
	var base_pct := 0.05
	var tree_pct := 0.03
	var unit_thresh := 3
	match card.star_level:
		2:
			base_pct = 0.08
			tree_pct = 0.04
			unit_thresh = 4
		3:
			base_pct = 0.08
			tree_pct = 0.05
			unit_thresh = 5
	var shield := base_pct + trees * tree_pct
	if card.get_total_units() <= unit_thresh:
		shield *= 1.5
	card.shield_hp_pct += shield
	return _empty()


func _spore_cloud_battle(card: CardInstance) -> Dictionary:
	var trees := _trees(card)
	var as_debuff := minf(0.15 + trees * 0.015, 0.50)
	match card.star_level:
		2: as_debuff = minf(0.20 + trees * 0.02, 0.50)
		3: as_debuff = minf(0.30 + trees * 0.025, 0.50)
	card.theme_state["enemy_as_debuff"] = as_debuff
	if card.star_level >= 2:
		var atk_debuff := minf(0.20 + trees * 0.02, 0.50)
		if card.star_level >= 3:
			atk_debuff = minf(0.30 + trees * 0.02, 0.50)
		card.theme_state["enemy_atk_debuff"] = atk_debuff
	return _empty()


func _grace_post(card: CardInstance, won: bool) -> Dictionary:
	var trees := _trees(card)
	var base_gold := 1
	var terazin := 0
	match card.star_level:
		1:
			if trees >= 10: terazin = 1
		2:
			base_gold = 2
			if trees >= 8: terazin = 1
		3:
			base_gold = 2
			if trees >= 8: terazin = 1
	var gold := base_gold + trees / 3
	if not won and card.star_level < 2:
		gold /= 2
	return {"events": [], "gold": gold, "terazin": terazin}


func _empty() -> Dictionary:
	return {"events": [], "gold": 0, "terazin": 0}
