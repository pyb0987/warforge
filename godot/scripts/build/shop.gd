extends HBoxContainer
## Shop: offers 6 cards from the pool, tiered probability.

signal card_purchased(template_id: String, slot_idx: int, cost: int)
signal card_merged(card: CardInstance, old_star: int, new_star: int)

var _game_state: GameState
var _rng: RandomNumberGenerator
var _genome: Genome = null
var _shop_slots: Array = []  # Array of Panel (card visuals)

## Tier probability and card picking are delegated to ShopPicker
## (core/data/shop_picker.gd) so that play and sim share one source.

var _offered_ids: Array[String] = []
var _coin_slots: Dictionary = {}  # 🪙 양면 동전: {discount_idx, markup_idx}


func setup(state: GameState, rng: RandomNumberGenerator, genome: Genome = null) -> void:
	_game_state = state
	_rng = rng
	_genome = genome
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
	## Generate cards based on current shop level.
	_return_unsold_to_pool()
	var level := _get_shop_level()
	_offered_ids.clear()

	var shop_size := 6 + BossReward.get_shop_size_bonus(_game_state)
	_ensure_slot_count(shop_size)
	for i in shop_size:
		var tier := _roll_tier(level)
		var card_id := _pick_card_of_tier(tier)
		_offered_ids.append(card_id)

	# 🪙 양면 동전: 할인/할증 슬롯 결정
	_coin_slots = Talisman.roll_coin_slots(_game_state, _offered_ids.size(), _rng)

	_update_visuals()


func reroll() -> bool:
	## Spend gold to reroll. Returns false if can't afford.
	var cost: int = _genome.get_reroll_cost() if _genome else Enums.REROLL_COST
	if _game_state.gold < cost:
		return false
	_game_state.gold -= cost
	_game_state.round_rerolls += 1
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
	var base_cost: int = tmpl.get("cost", 99)
	var cost: int = Talisman.apply_coin_price(base_cost, slot_idx, _coin_slots)
	if _game_state.gold < cost:
		print("[Shop] Not enough gold (%d < %d)" % [_game_state.gold, cost])
		return false

	# spawn_card funnel: create + commander 보너스 + add_to_bench + try_merge(fresh_ref).
	# 구매한 ★1은 fresh로 추적되어 합성 시 유닛 흡수에서 제외(2장분량 정책).
	var spawn_result := _game_state.spawn_card(card_id)
	if spawn_result.is_empty():
		return false  # create 실패
	var card: CardInstance = spawn_result["card"]
	var bench_idx: int = spawn_result["bench_idx"]
	if bench_idx < 0:
		print("[Shop] Bench full!")
		return false

	_game_state.gold -= cost
	_offered_ids[slot_idx] = ""  # mark as sold
	print("[Shop] Bought %s for %dg → bench[%d]" % [tmpl.get("name", card_id), cost, bench_idx])
	card_purchased.emit(card_id, slot_idx, cost)

	var merge_steps: Array = spawn_result["merge_steps"]
	for step in merge_steps:
		var merged: CardInstance = step["card"]
		print("[Merge] ★ %s evolved! ★%d→★%d (%du)" % [
			merged.get_name(), step["old_star"], step["new_star"],
			merged.get_total_units()])
		card_merged.emit(merged, step["old_star"], step["new_star"])

	_update_visuals()
	_game_state.state_changed.emit()
	return true


func _ensure_slot_count(count: int) -> void:
	if not is_inside_tree():
		return
	while _shop_slots.size() < count:
		var idx := _shop_slots.size()
		var slot: Panel = preload("res://scenes/build/card_visual.tscn").instantiate()
		slot.custom_minimum_size = Vector2(120, 160)
		add_child(slot)
		_shop_slots.append(slot)
		slot.gui_input.connect(_on_slot_input.bind(idx))


func _get_shop_level() -> int:
	return _game_state.shop_level


func _roll_tier(level: int) -> int:
	return ShopPicker.roll_tier(level, _rng, _genome)


func _pick_card_of_tier(tier: int) -> String:
	return ShopPicker.pick_card(tier, _rng, _game_state, _game_state.card_pool)


## 미구매 카드를 풀에 반환 (리롤/리프레시 전 호출).
func _return_unsold_to_pool() -> void:
	if _game_state.card_pool == null:
		return
	for id in _offered_ids:
		if id != "":
			_game_state.card_pool.return_cards(id, 1)


func _update_visuals() -> void:
	for i in _shop_slots.size():
		var slot: Panel = _shop_slots[i]
		if i < _offered_ids.size() and _offered_ids[i] != "":
			# 상점 슬롯 시각 미리보기 — 벤치/보드 미진입.
			var card := CardInstance.create(_offered_ids[i])  # lint:allow card-create
			slot.call("setup", card, "shop", i)
		else:
			slot.call("clear")


func _on_slot_input(event: InputEvent, slot_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			try_purchase(slot_idx)
