extends HBoxContainer
## Shop: offers 6 cards from the pool, tiered probability.

signal card_purchased(template_id: String)
signal card_merged(card: CardInstance, old_star: int, new_star: int)

var _game_state: GameState
var _rng: RandomNumberGenerator
var _shop_slots: Array = []  # Array of Panel (card visuals)

## Tier probability by shop level (1-indexed).
## Level 1: only T1-T2. Level 6: T1-T5.
## Tier weights from upgrade.md (확정)
const TIER_WEIGHTS := {
	1: {1: 100, 2: 0, 3: 0, 4: 0, 5: 0},
	2: {1: 70, 2: 28, 3: 2, 4: 0, 5: 0},
	3: {1: 35, 2: 45, 3: 18, 4: 2, 5: 0},
	4: {1: 10, 2: 25, 3: 42, 4: 20, 5: 3},
	5: {1: 0, 2: 10, 3: 25, 4: 45, 5: 20},
	6: {1: 0, 2: 0, 3: 10, 4: 40, 5: 50},
}

## Shop level increases at these rounds.
const LEVEL_UP_ROUNDS := {1: 1, 3: 2, 5: 3, 7: 4, 9: 5, 12: 6}

var _offered_ids: Array[String] = []


func setup(state: GameState, rng: RandomNumberGenerator) -> void:
	_game_state = state
	_rng = rng
	_create_slots()


func _create_slots() -> void:
	for i in 6:
		var slot: Panel = preload("res://scenes/build/card_visual.tscn").instantiate()
		slot.custom_minimum_size = Vector2(120, 160)
		add_child(slot)
		_shop_slots.append(slot)
		# Connect click to purchase
		slot.gui_input.connect(_on_slot_input.bind(i))


func refresh_shop() -> void:
	## Generate 6 new cards based on current shop level.
	var level := _get_shop_level()
	_offered_ids.clear()

	for i in 6:
		var tier := _roll_tier(level)
		var card_id := _pick_card_of_tier(tier)
		_offered_ids.append(card_id)

	_update_visuals()


func reroll() -> bool:
	## Spend gold to reroll. Returns false if can't afford.
	if _game_state.gold < Enums.REROLL_COST:
		return false
	_game_state.gold -= Enums.REROLL_COST
	refresh_shop()
	_game_state.state_changed.emit()
	return true


func try_purchase(slot_idx: int) -> bool:
	## Purchase card at slot_idx. Returns false if can't afford or bench full.
	if slot_idx < 0 or slot_idx >= _offered_ids.size():
		return false
	var card_id: String = _offered_ids[slot_idx]
	if card_id == "":
		return false  # already purchased

	var tmpl := CardDB.get_template(card_id)
	var cost: int = tmpl.get("cost", 99)
	if _game_state.gold < cost:
		print("[Shop] Not enough gold (%d < %d)" % [_game_state.gold, cost])
		return false

	var card := CardInstance.create(card_id)
	if card == null:
		return false

	var bench_idx := _game_state.add_to_bench(card)
	if bench_idx < 0:
		print("[Shop] Bench full!")
		return false

	_game_state.gold -= cost
	_offered_ids[slot_idx] = ""  # mark as sold
	print("[Shop] Bought %s for %dg → bench[%d]" % [tmpl.get("name", card_id), cost, bench_idx])

	# Auto-merge check
	var merge_result := _game_state.try_merge(card_id)
	if not merge_result.is_empty():
		var merged: CardInstance = merge_result["card"]
		print("[Merge] ★ %s evolved! ★%d→★%d (%du)" % [
			merged.get_name(), merge_result["old_star"], merge_result["new_star"],
			merged.get_total_units()])
		card_merged.emit(merged, merge_result["old_star"], merge_result["new_star"])

	_update_visuals()
	_game_state.state_changed.emit()
	return true


func _get_shop_level() -> int:
	var level := 1
	for r in LEVEL_UP_ROUNDS:
		if _game_state.round_num >= r:
			level = LEVEL_UP_ROUNDS[r]
	return level


func _roll_tier(level: int) -> int:
	var weights: Dictionary = TIER_WEIGHTS.get(level, TIER_WEIGHTS[1])
	var total := 0
	for t in weights:
		total += weights[t]
	var roll := _rng.randi_range(0, total - 1)
	var cumulative := 0
	for t in weights:
		cumulative += weights[t]
		if roll < cumulative:
			return t
	return 1


func _pick_card_of_tier(tier: int) -> String:
	## Pick a random card of the given tier from the full pool.
	var candidates: Array[String] = []
	for id in CardDB.get_all_ids():
		var tmpl := CardDB.get_template(id)
		if tmpl.get("tier", 0) == tier and not id.ends_with("_s2"):
			candidates.append(id)
	if candidates.is_empty():
		# Fallback to any T1
		return _pick_card_of_tier(1) if tier != 1 else "sp_assembly"
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _update_visuals() -> void:
	for i in _shop_slots.size():
		var slot: Panel = _shop_slots[i]
		if i < _offered_ids.size() and _offered_ids[i] != "":
			var card := CardInstance.create(_offered_ids[i])
			slot.call("setup", card, "shop", i)
		else:
			slot.call("clear")


func _on_slot_input(event: InputEvent, slot_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		try_purchase(slot_idx)
