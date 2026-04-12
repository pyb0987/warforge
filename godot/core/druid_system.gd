class_name DruidSystem
extends "res://core/theme_system.gd"
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
	return Enums.empty_result()


func process_event_card(_card: CardInstance, _idx: int, _board: Array,
		_event: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
	# Druid has no ON_EVENT cards in growth chain
	return Enums.empty_result()


# --- External hooks (combat engine) ---


## Battle start: dr_lifebeat, dr_spore_cloud.
func apply_battle_start(card: CardInstance, idx: int, board: Array) -> Dictionary:
	match card.get_base_id():
		"dr_lifebeat": return _lifebeat_battle(card, idx, board)
		"dr_spore_cloud": return _spore_cloud_battle(card)
	return Enums.empty_result()


## Post combat: dr_grace economy.
func apply_post_combat(card: CardInstance, _idx: int, _board: Array,
		won: bool) -> Dictionary:
	if card.get_base_id() == "dr_grace":
		return _grace_post(card, won)
	return Enums.empty_result()


## Persistent combat: dr_wrath ATK buff.
func apply_persistent(card: CardInstance) -> void:
	if card.get_base_id() != "dr_wrath":
		return
	var effs := CardDB.get_theme_effects("dr_wrath", card.star_level)
	var eff := _find_eff(effs, "tree_temp_buff")
	var unit_cap: int = eff.get("unit_cap", 5)
	if card.get_total_units() > unit_cap:
		return
	var trees := _trees(card)
	if eff.has("atk_mult"):
		# ★3: multiplicative buff
		card.temp_mult_buff(eff.get("atk_mult", 1.5))
		# HP ×1.3, kill HP recover → combat engine
	else:
		# ★1/★2: additive percentage buff
		var atk_pct: float = eff.get("atk_base_pct", 0.8) + trees * eff.get("atk_tree_pct", 0.05)
		card.temp_buff(null, atk_pct)
		# ★2 HP +60% handled by combat engine


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


## Find first effect dict with matching action (and optional target).
func _find_eff(effs: Array, action: String, target: String = "") -> Dictionary:
	for e in effs:
		if e.get("action") == action:
			if target == "" or e.get("target", "") == target:
				return e
	return {}


## 양성가 보너스 포함 breed: breed 성공 시 확률로 1기 추가 (이벤트 미방출).
func _breed_with_bonus(target: CardInstance) -> bool:
	var ok := target.breed_strongest()
	if ok and bonus_spawn_chance > 0.0 and bonus_rng != null:
		if bonus_rng.randf() < bonus_spawn_chance:
			target.breed_strongest()
	return ok


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
	var effs := CardDB.get_theme_effects("dr_cradle", card.star_level)
	# effs = [{"action":"tree_add","target":"self","count":N}, {"action":"tree_add","target":"right_adj/both_adj","count":N}]
	var self_eff := _find_eff(effs, "tree_add", "self")
	var adj_eff := _find_eff(effs, "tree_add", "right_adj")
	if adj_eff.is_empty():
		adj_eff = _find_eff(effs, "tree_add", "both_adj")
	var self_n: int = self_eff.get("count", 1)
	var adj_n: int = adj_eff.get("count", 1)
	var both: bool = adj_eff.get("target", "right_adj") == "both_adj"

	_add_trees(card, self_n)
	for ni in _adj_druid_indices(idx, board, both):
		_add_trees(board[ni], adj_n)

	return Enums.empty_result()


func _origin(card: CardInstance, idx: int, board: Array) -> Dictionary:
	var effs := CardDB.get_theme_effects("dr_origin", card.star_level)
	var add_eff := _find_eff(effs, "tree_add", "self")
	var absorb_eff := _find_eff(effs, "tree_absorb")
	var breed_eff := _find_eff(effs, "tree_breed")

	var self_add: int = add_eff.get("count", 1)
	var absorb: int = absorb_eff.get("count", 1)
	var breed_thresh: int = breed_eff.get("tree_thresh", 6)
	var breed_count: int = breed_eff.get("count", 1)
	var penalty: float = breed_eff.get("penalty_pct", 0.04)
	var breed_both: bool = breed_eff.get("target", "adj_or_self") == "both_adj_or_self"

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
				_breed_with_bonus(card)
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
					_breed_with_bonus(target)
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
	var effs := CardDB.get_theme_effects("dr_earth", card.star_level)
	var add_eff := _find_eff(effs, "tree_add", "self")
	var enhance_eff := _find_eff(effs, "druid_unit_enhance")

	_add_trees(card, add_eff.get("count", 1))

	var druid_units := _druid_unit_count(board)
	var divisor: int = enhance_eff.get("divisor", 5)
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

	# Bonus tiers (★2+)
	var bonus_tiers: Array = enhance_eff.get("bonus_tiers", [])
	if not bonus_tiers.is_empty():
		var bonus := 0.0
		# Tiers are ordered ascending by unit_gte; pick the highest matching tier
		for tier in bonus_tiers:
			if druid_units >= tier.get("unit_gte", 999):
				bonus = tier.get("bonus_pct", 0.0)
		if bonus > 0:
			for entry in _druid_entries(board):
				(entry["card"] as CardInstance).enhance(null, bonus, bonus)

	return {"events": events, "gold": 0, "terazin": 0}


func _deep(card: CardInstance, idx: int) -> Dictionary:
	var effs := CardDB.get_theme_effects("dr_deep", card.star_level)
	var add_eff := _find_eff(effs, "tree_add", "self")
	var enhance_eff := _find_eff(effs, "tree_enhance")

	_add_trees(card, add_eff.get("count", 1))
	var trees := _trees(card)
	var units := card.get_total_units()

	# dr_deep_rate Genome override replaces the ★1 base rate (0.008).
	# Per-star scaling is preserved: YAML stores pre-scaled values, but the override
	# is always the ★1 rate. Scale factor = yaml_star_base / yaml_star1_base.
	var yaml_star1_base := 0.008  # ★1 YAML base_pct (constant — never changes)
	var yaml_base: float = enhance_eff.get("base_pct", yaml_star1_base)
	var star_scale := yaml_base / yaml_star1_base if yaml_star1_base > 0.0 else 1.0
	var override_rate: float = card_effects.get("dr_deep_rate", yaml_star1_base)
	var base_pct := override_rate * star_scale

	var low_unit_data: Dictionary = enhance_eff.get("low_unit", {})
	var low_thresh: int = low_unit_data.get("thresh", 3)
	var yaml_low: float = low_unit_data.get("pct", yaml_base * 1.5)
	var low_scale := yaml_low / yaml_base if yaml_base > 0.0 else 1.5
	var low_pct := override_rate * star_scale * low_scale

	var tree_bonus_data: Dictionary = enhance_eff.get("tree_bonus", {})
	var mult_thresh: int = tree_bonus_data.get("thresh", 10)
	var mult: float = tree_bonus_data.get("mult", 1.3)

	var actual_rate := low_pct if units <= low_thresh else base_pct
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
	var effs := CardDB.get_theme_effects("dr_wt_root", card.star_level)
	var add_eff := _find_eff(effs, "tree_add", "self")
	var dist_eff := _find_eff(effs, "tree_distribute")

	_add_trees(card, add_eff.get("count", 1))
	var trees := _trees(card)

	# Tiers are ordered ascending by tree_gte; pick the highest matching tier's amount
	var tiers: Array = dist_eff.get("tiers", [])
	var dist := 0
	for tier in tiers:
		if trees >= tier.get("tree_gte", 999):
			dist = tier.get("amount", 0)

	if dist > 0:
		for entry in _druid_entries(board):
			var c: CardInstance = entry["card"]
			if c != card:
				_add_trees(c, dist)

	return Enums.empty_result()


func _world(card: CardInstance, idx: int, board: Array) -> Dictionary:
	var effs := CardDB.get_theme_effects("dr_world", card.star_level)
	var self_add_eff := _find_eff(effs, "tree_add", "self")
	var all_add_eff := _find_eff(effs, "tree_add", "all_other_druid")
	var mult_eff := _find_eff(effs, "multiply_stats")

	var self_trees: int = self_add_eff.get("count", 2)
	var all_trees: int = all_add_eff.get("count", 1)

	_add_trees(card, self_trees)
	for entry in _druid_entries(board):
		var c: CardInstance = entry["card"]
		if c != card:
			_add_trees(c, all_trees)

	var trees := _trees(card)
	var unit_cap: int = mult_eff.get("unit_cap", 20)
	if _druid_unit_count(board) > unit_cap:
		return Enums.empty_result()

	# Multiplicative growth per round
	var base_atk: float = mult_eff.get("atk_base", 1.10)
	var atk_div: float = mult_eff.get("atk_tree_step", 30.0)
	var base_hp: float = mult_eff.get("hp_base", 1.05)
	var hp_div: float = mult_eff.get("hp_tree_step", 30.0)

	var tree_atk: float = floorf(trees / atk_div) * (mult_eff.get("atk_per_tree", 0.1) as float)
	var tree_hp: float = floorf(trees / hp_div) * (mult_eff.get("hp_per_tree", 0.05) as float)
	card.multiply_stats(base_atk + tree_atk - 1.0, base_hp + tree_hp - 1.0)

	# AS multiplier stored for combat engine
	var as_base: float = mult_eff.get("as_base", 1.05)
	var as_div: float = mult_eff.get("as_tree_step", 30.0)
	var as_per: float = mult_eff.get("as_per_tree", 0.05)
	card.theme_state["as_mult"] = as_base + floorf(trees / as_div) * as_per

	return {
		"events": [{
			"layer1": Enums.Layer1.ENHANCED,
			"layer2": Enums.Layer2.TREE_GROW,
			"source_idx": idx, "target_idx": idx,
		}],
		"gold": 0, "terazin": 0,
	}


# --- Battle hooks ---


func _lifebeat_battle(card: CardInstance, idx: int, board: Array) -> Dictionary:
	var effs := CardDB.get_theme_effects("dr_lifebeat", card.star_level)
	var add_eff := _find_eff(effs, "tree_add", "self")
	var shield_eff := _find_eff(effs, "tree_shield")

	_add_trees(card, add_eff.get("count", 1))
	var trees := _trees(card)

	var base_pct: float = shield_eff.get("base_pct", 0.05)
	var tree_pct: float = shield_eff.get("tree_scale_pct", 0.03)
	var low_unit_data: Dictionary = shield_eff.get("low_unit", {})
	var unit_thresh: int = low_unit_data.get("thresh", 3)
	var low_mult: float = low_unit_data.get("mult", 1.5)

	var shield := base_pct + trees * tree_pct
	if card.get_total_units() <= unit_thresh:
		shield *= low_mult

	var target: String = shield_eff.get("target", "self_and_both_adj")
	match target:
		"all_druid":
			for c in board:
				if c != null and c.template.get("theme", -1) == Enums.CardTheme.DRUID:
					c.shield_hp_pct += shield
		"self_and_both_adj":
			card.shield_hp_pct += shield
			if idx > 0 and board[idx - 1] != null:
				board[idx - 1].shield_hp_pct += shield
			if idx + 1 < board.size() and board[idx + 1] != null:
				board[idx + 1].shield_hp_pct += shield
		_:
			card.shield_hp_pct += shield
	return Enums.empty_result()


func _spore_cloud_battle(card: CardInstance) -> Dictionary:
	var effs := CardDB.get_theme_effects("dr_spore_cloud", card.star_level)
	var trees := _trees(card)

	for eff in effs:
		if eff.get("action") != "debuff_store":
			continue
		var stat: String = eff.get("stat", "as")
		var base_pct: float = eff.get("base_pct", 0.15)
		var tree_scale: float = eff.get("tree_scale_pct", 0.015)
		var cap: float = eff.get("cap", 0.5)
		var debuff := minf(base_pct + trees * tree_scale, cap)
		if stat == "as":
			card.theme_state["enemy_as_debuff"] = debuff
		elif stat == "atk":
			card.theme_state["enemy_atk_debuff"] = debuff

	return Enums.empty_result()


func _grace_post(card: CardInstance, won: bool) -> Dictionary:
	var effs := CardDB.get_theme_effects("dr_grace", card.star_level)
	var eff := _find_eff(effs, "tree_gold")
	var trees := _trees(card)

	var base_gold: int = eff.get("base_gold", 1)
	var tree_divisor: int = eff.get("tree_divisor", 3)
	var win_half: bool = eff.get("win_half", false)
	var terazin_thresh: int = eff.get("terazin_thresh", 10)
	var terazin_amt: int = eff.get("terazin", 1)

	var gold := base_gold + trees / tree_divisor
	if not won and win_half:
		gold /= 2
	var terazin := terazin_amt if trees >= terazin_thresh else 0
	return {"events": [], "gold": gold, "terazin": terazin}
