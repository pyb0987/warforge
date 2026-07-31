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
		"dr_prune": return _prune(card, idx, board)
		"dr_deep": return _deep(card, idx)
		"dr_wt_root": return _wt_root(card, idx, board)
		"dr_world": return _world(card, idx, board)
	return Enums.empty_result()


func process_event_card(card: CardInstance, idx: int, board: Array,
		event: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
	if card.get_base_id() == "dr_resonance":
		return _resonance(card, idx, board, event)
	# Other druid cards have no ON_EVENT triggers in growth chain
	return Enums.empty_result()


# --- External hooks (combat engine) ---


## Battle start: Druid common tree combat bonus + per-card BS effects.
func apply_battle_start(card: CardInstance, idx: int, board: Array) -> Dictionary:
	var result := Enums.empty_result()
	match card.get_base_id():
		"dr_lifebeat":
			result = _merge_result(result, _lifebeat_battle(card, idx, board))
		"dr_spore_cloud":
			result = _merge_result(result, _spore_cloud_battle(card))
	result = _merge_result(result, _tree_combat_bonus(card, idx))
	return result


## Aggregate enemy-facing combat debuffs prepared by battle-start Druid effects.
## Duplicate debuff cards use strongest-effect-wins to avoid mandatory stacking.
func collect_enemy_battle_debuffs(board: Array) -> Dictionary:
	var atk_pct := 0.0
	var as_pct := 0.0
	for card in board:
		var c := card as CardInstance
		if c == null:
			continue
		atk_pct = maxf(atk_pct, float(c.theme_state.get("enemy_atk_debuff", 0.0)))
		as_pct = maxf(as_pct, float(c.theme_state.get("enemy_as_debuff", 0.0)))
	return {
		"atk_pct": minf(atk_pct, 0.5),
		"as_pct": minf(as_pct, 0.5),
	}


## Read-only card/stack contribution snapshot for Druid combat observability.
## Call after persistent + battle-start hooks when the desired question is
## "what state will Druid cards contribute to combat from here?"
func build_combat_snapshot(board: Array) -> Dictionary:
	var card_rows: Array = []
	var forest_depth := 0
	var druid_units := 0
	var druid_total_atk := 0.0
	var druid_total_hp := 0.0
	var druid_total_dps := 0.0

	for i in board.size():
		var card: CardInstance = board[i] as CardInstance
		if card == null or not _is_druid_card(card):
			continue
		var row := _build_card_snapshot(card, i)
		card_rows.append(row)
		forest_depth += int(row["trees"])
		druid_units += int(row["units"])
		druid_total_atk += float(row["total_atk"])
		druid_total_hp += float(row["total_hp"])
		druid_total_dps += float(row["total_dps"])

	return {
		"forest_depth": forest_depth,
		"druid_count": card_rows.size(),
		"druid_units": druid_units,
		"druid_total_atk": druid_total_atk,
		"druid_total_hp": druid_total_hp,
		"druid_total_dps": druid_total_dps,
		"enemy_debuffs": collect_enemy_battle_debuffs(board),
		"cards": card_rows,
	}


func _merge_result(base: Dictionary, extra: Dictionary) -> Dictionary:
	base["events"].append_array(extra.get("events", []))
	base["gold"] += extra.get("gold", 0)
	base["terazin"] += extra.get("terazin", 0)
	return base


func _tree_combat_bonus(card: CardInstance, idx: int) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var eff := _find_eff(effs, "tree_combat_bonus", "self")
	if eff.is_empty():
		return Enums.empty_result()

	var trees := _trees(card)
	var per_tree: float = eff.get("per_tree_pct", 0.02)
	var cap: float = eff.get("cap_pct", 0.2)
	var bonus := minf(float(trees) * per_tree, cap)
	if bonus <= 0.0:
		return Enums.empty_result()

	card.temp_mult_buff(1.0 + bonus, 1.0 + bonus)
	return {
		"events": [{
			"layer1": Enums.Layer1.ENHANCED,
			"layer2": Enums.Layer2.TREE_GROW,
			"source_idx": idx, "target_idx": idx,
		}],
		"gold": 0, "terazin": 0,
	}


## Post combat: dr_grace economy.
func apply_post_combat(card: CardInstance, _idx: int, _board: Array,
		won: bool) -> Dictionary:
	if card.get_base_id() == "dr_grace":
		return _grace_post(card, won)
	return Enums.empty_result()


## Persistent combat: dr_wrath ATK buff.
func apply_persistent(card: CardInstance, _board: Array = []) -> void:
	if card.get_base_id() != "dr_wrath":
		return
	card.theme_state["kill_hp_recover_pct"] = 0.0
	var effs := CardDB.get_theme_effects("dr_wrath", card.star_level)
	var eff := _find_eff(effs, "tree_temp_buff")
	var unit_cap: int = eff.get("unit_cap", 5)
	if card.get_total_units() > unit_cap:
		return
	var trees := _trees(card)
	if eff.has("atk_mult"):
		card.temp_mult_buff(
			eff.get("atk_mult", 1.5),
			eff.get("hp_mult", 1.0))
		var recover_pct := _kill_recover_pct(eff.get("kill_hp_recover", 0.0))
		if recover_pct > 0.0:
			card.theme_state["kill_hp_recover_pct"] = recover_pct
	else:
		var atk_pct: float = eff.get("atk_base_pct", 0.8) + trees * eff.get("atk_tree_pct", 0.05)
		var hp_pct: float = eff.get("hp_pct", 0.0)
		card.temp_buff(null, atk_pct)
		if hp_pct > 0.0:
			card.temp_mult_buff(1.0, 1.0 + hp_pct)


func _kill_recover_pct(value) -> float:
	if typeof(value) == TYPE_BOOL:
		return 0.15 if value else 0.0
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return clampf(float(value), 0.0, 1.0)
	return 0.0


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


## Find first effect dict with matching (action, target). Emits push_error
## on duplicate matches — later matches are silently shadowed, which is
## always a bug at the call site (_spore_cloud_battle iterates via explicit
## ``for eff in effs`` loop rather than _find_eff precisely because it
## legitimately has multiple debuff_store entries per star).
func _find_eff(effs: Array, action: String, target: String = "") -> Dictionary:
	var first := {}
	var matches := 0
	for e in effs:
		if e.get("action") == action:
			if target == "" or e.get("target", "") == target:
				matches += 1
				if matches == 1:
					first = e
	if matches > 1:
		push_error("_find_eff shadowed duplicates: action=%s target=%s matches=%d — use explicit loop" % [action, target, matches])
	return first


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


func _is_druid_card(card: CardInstance) -> bool:
	var base_tmpl := CardDB.get_template(card.get_base_id())
	var theme: int = base_tmpl.get("theme", card.template.get("theme", -1))
	return theme == Enums.CardTheme.DRUID


func _build_card_snapshot(card: CardInstance, idx: int) -> Dictionary:
	var stack_rows: Array = []
	var total_atk := 0.0
	var total_hp := 0.0
	var total_dps := 0.0

	for stack in card.stacks:
		var row := _build_stack_snapshot(card, stack)
		stack_rows.append(row)
		total_atk += float(row["total_atk"])
		total_hp += float(row["total_hp"])
		total_dps += float(row["total_dps"])

	return {
		"idx": idx,
		"id": card.get_base_id(),
		"star": card.star_level,
		"trees": _trees(card),
		"units": card.get_total_units(),
		"total_atk": total_atk,
		"total_hp": total_hp,
		"total_dps": total_dps,
		"growth_atk_pct": card.growth_atk_pct,
		"growth_hp_pct": card.growth_hp_pct,
		"unique_buff_pct": card.unique_buff_pct,
		"upgrade_as_mult": card.upgrade_as_mult,
		"unique_as_mult": card.unique_as_mult,
		"temp_as_mult": card.temp_as_mult,
		"shield_hp_pct": card.shield_hp_pct,
		"enemy_atk_debuff": float(card.theme_state.get("enemy_atk_debuff", 0.0)),
		"enemy_as_debuff": float(card.theme_state.get("enemy_as_debuff", 0.0)),
		"kill_hp_recover_pct": float(card.theme_state.get("kill_hp_recover_pct", 0.0)),
		"mechanics": _card_mechanics_snapshot(card),
		"stacks": stack_rows,
	}


func _build_stack_snapshot(card: CardInstance, stack: Dictionary) -> Dictionary:
	var ut: Dictionary = stack["unit_type"]
	var count := int(stack.get("count", 0))
	var eff_atk := card.eff_atk_for(stack)
	var eff_hp := card.eff_hp_for(stack)
	var base_interval := float(ut.get("attack_speed", 1.0))
	var final_interval := base_interval \
		* card.upgrade_as_mult \
		* card.unique_as_mult \
		* card.temp_as_mult
	var total_atk := float(count) * eff_atk
	var total_hp := float(count) * eff_hp
	var total_dps := total_atk / maxf(final_interval, 0.01)
	return {
		"unit_id": ut.get("id", ""),
		"count": count,
		"eff_atk": eff_atk,
		"eff_hp": eff_hp,
		"base_attack_interval": base_interval,
		"upgrade_as_mult": card.upgrade_as_mult,
		"unique_as_mult": card.unique_as_mult,
		"temp_as_mult": card.temp_as_mult,
		"final_attack_interval": final_interval,
		"total_atk": total_atk,
		"total_hp": total_hp,
		"total_dps": total_dps,
		"range": int(ut.get("range", 0)) + card.upgrade_range \
			+ int(card.theme_state.get("range_bonus", 0)),
		"move_speed": int(ut.get("move_speed", 0)) + card.upgrade_move_speed,
		"def": card.upgrade_def,
	}


func _card_mechanics_snapshot(card: CardInstance) -> Array:
	var rows: Array = []
	for mech in card.get_all_mechanics():
		rows.append(mech.duplicate(true))
	var recover_pct := float(card.theme_state.get("kill_hp_recover_pct", 0.0))
	if recover_pct > 0.0:
		rows.append({"type": "kill_hp_recover", "heal_hp_pct": recover_pct})
	return rows


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
	var enhance_eff := _find_eff(effs, "tree_enhance")

	_add_trees(card, add_eff.get("count", 1))

	# Absorb from adjacent druid cards
	var absorb: int = absorb_eff.get("count", 1)
	for di in [-1, 1]:
		var ni: int = idx + di
		if ni >= 0 and ni < board.size():
			var adj: CardInstance = board[ni]
			if adj.template.get("theme", -1) == Enums.CardTheme.DRUID:
				var take := mini(_trees(adj), absorb)
				_add_trees(adj, -take)
				_add_trees(card, take)

	# tree_enhance all_druid — like dr_deep but all_druid range, lower rates
	var trees := _trees(card)
	var base_pct: float = enhance_eff.get("base_pct", 0.004)
	var low_unit_data: Dictionary = enhance_eff.get("low_unit", {})
	var low_thresh: int = low_unit_data.get("thresh", 3)
	var low_pct: float = low_unit_data.get("pct", base_pct * 1.5)
	var tree_bonus_data: Dictionary = enhance_eff.get("tree_bonus", {})
	var bonus_thresh: int = tree_bonus_data.get("thresh", 999)
	var bonus_growth: float = tree_bonus_data.get("bonus_growth_pct", 0.0)

	var units := card.get_total_units()
	var rate := low_pct if units <= low_thresh else base_pct
	var growth := float(trees) * rate
	if trees >= bonus_thresh and bonus_growth > 0:
		growth += bonus_growth

	var events: Array = []
	if growth > 0:
		for entry in _druid_entries(board):
			(entry["card"] as CardInstance).enhance(null, growth, growth)
		events.append({
			"layer1": Enums.Layer1.ENHANCED,
			"layer2": Enums.Layer2.TREE_GROW,
			"source_idx": idx, "target_idx": idx,
		})
	return {"events": events, "gold": 0, "terazin": 0}


func _prune(card: CardInstance, idx: int, board: Array) -> Dictionary:
	var effs := CardDB.get_theme_effects("dr_prune", card.star_level)
	var add_eff := _find_eff(effs, "tree_add", "self")
	var prune_eff := _find_eff(effs, "prune")

	_add_trees(card, add_eff.get("count", 1))

	var prune_count: int = prune_eff.get("count", 2)
	var min_units: int = prune_eff.get("min_units", 3)
	var enhance_pct: float = prune_eff.get("enhance_pct", 0.0)

	# Find the card with the most units on the field
	var target_card: CardInstance = null
	var target_idx: int = -1
	var max_units: int = 0
	for i in board.size():
		var c: CardInstance = board[i]
		var u: int = c.get_total_units()
		if u > max_units:
			max_units = u
			target_card = c
			target_idx = i

	var events: Array = []
	# Skip if target has too few units (min_units=3 → skip if ≤2)
	if target_card != null and max_units >= min_units:
		var pruned := 0
		for _i in prune_count:
			if target_card.remove_weakest_unit():
				pruned += 1
		if pruned > 0:
			# 🌳 added to the pruned card (가지치기 당한 카드에 귀속)
			_add_trees(target_card, pruned)
			events.append({
				"layer1": Enums.Layer1.UNIT_REMOVED,
				"layer2": Enums.Layer2.TREE_GROW,
				"source_idx": idx, "target_idx": target_idx,
			})
			# ★2+: enhance the pruned card's remaining units
			if enhance_pct > 0:
				target_card.enhance(null, enhance_pct, enhance_pct)
				events.append({
					"layer1": Enums.Layer1.ENHANCED,
					"layer2": Enums.Layer2.TREE_GROW,
					"source_idx": idx, "target_idx": target_idx,
				})

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


## 필드 전체 드루이드 카드의 🌳 합 — multiply_stats 의 tree_source.
## YAML 의 `tree_source: forest_depth` 에 대응 (2026-04-21 bugfix:
## 기존 구현이 self 트리만 참조해 UI desc '전체 나무 수' 와 불일치했음).
func _forest_depth(board: Array) -> int:
	var total := 0
	for entry in _druid_entries(board):
		total += _trees(entry["card"])
	return total


## 세계수 RS — 매 라운드 누적 가산 ATK/HP/AS 버프.
## 이번 라운드 증분 Δ = floor(forest_depth / tree_step) * per_step
## 모든 ally.unique_buff_pct += Δ (가산 누적, 라운드 간 보존).
## 적용:
##   stack.unique_atk_mult = 1.0 + unique_buff_pct
##   stack.unique_hp_mult = 1.0 + unique_buff_pct
##   card.unique_as_mult  = 1.0 / (1.0 + unique_buff_pct)  # 빨라짐
## (★ 합성 시 absorb_donor 가 unique_buff_pct max → 다음 RS 에서 일관 재계산.)
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

	var trees := _forest_depth(board)
	var per_step: float = mult_eff.get("per_step", 0.05)
	var tree_step: float = mult_eff.get("tree_step", 30.0)
	if tree_step <= 0.0:
		tree_step = 30.0
	var increment: float = floorf(trees / tree_step) * per_step

	for i in board.size():
		var target: CardInstance = board[i]
		if target == null:
			continue
		target.unique_buff_pct += increment
		var pct: float = target.unique_buff_pct
		for s in target.stacks:
			s["unique_atk_mult"] = 1.0 + pct
			s["unique_hp_mult"] = 1.0 + pct
		target.unique_as_mult = 1.0 / (1.0 + pct)
		target.stats_changed.emit()

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

	var shield_eff := _find_eff(effs, "tree_shield")
	if not shield_eff.is_empty():
		var shield := float(shield_eff.get("base_pct", 0.0))
		shield += trees * float(shield_eff.get("tree_scale_pct", 0.0))
		card.shield_hp_pct += shield

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
	var reroll_eff := _find_eff(effs, "free_reroll")
	var free_rerolls: int = int(reroll_eff.get("value", 0)) if not reroll_eff.is_empty() else 0
	return {
		"events": [],
		"gold": gold,
		"terazin": terazin,
		"free_rerolls": free_rerolls,
	}


## dr_resonance (T4): 비-druid 카드의 UA 이벤트 감지 → tree_add + self enhance.
## intertheme bridge — 다른 테마의 spawn에 반응해 드루이드 자원(tree) 생성.
## filter: non_druid_target — event.target_idx 카드가 druid면 무시
## (multi-review C-A/C-B 지적 반영, board 참조로 target theme 검사).
func _resonance(card: CardInstance, idx: int, board: Array, event: Dictionary) -> Dictionary:
	# 자기 source 무시 (무한 루프 방지)
	if event.get("source_idx", -1) == idx:
		return Enums.empty_result()
	# Target이 druid이면 무시 (filter: non_druid_target). omni-theme 도 druid 매치.
	var target_idx: int = event.get("target_idx", -1)
	if target_idx >= 0 and target_idx < board.size() and board[target_idx] != null:
		var target: CardInstance = board[target_idx]
		if target.is_omni_theme or target.template.get("theme", -1) == Enums.CardTheme.DRUID:
			return Enums.empty_result()

	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var eff := _find_eff(effs, "mirror_spawn_to_tree")
	if eff.is_empty():
		return Enums.empty_result()

	# 트리 자원 추가 — _add_trees helper 사용 (floor guard, druid 일관성)
	var tree_add: int = eff.get("tree_add", 1)
	if tree_add > 0:
		_add_trees(card, tree_add)

	# Self enhance
	var atk_pct: float = eff.get("self_atk_pct", 0.0)
	var hp_pct: float = eff.get("self_hp_pct", 0.0)
	if atk_pct > 0.0 or hp_pct > 0.0:
		card.enhance(null, atk_pct, hp_pct)

	return {
		"events": [{
			"layer1": Enums.Layer1.ENHANCED,
			"layer2": -1,
			"source_idx": idx, "target_idx": idx,
		}],
		"gold": 0, "terazin": 0,
	}
