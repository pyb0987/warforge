extends HBoxContainer
## Upgrade shop: offers 2 upgrades per round, purchasable with terazin.
## Visible from shop Lv2+ (round 3+). Separate from card shop.

signal upgrade_purchase_requested(upgrade_id: String, slot_idx: int)

var _game_state: GameState
var _rng: RandomNumberGenerator
var _upgrade_slots: Array = []  # Array of Panel (upgrade_visual instances)
var _offered_ids: Array[String] = []


func setup(state: GameState, rng: RandomNumberGenerator) -> void:
	_game_state = state
	_rng = rng
	_create_slots()


func _create_slots() -> void:
	var slot_count := Talisman.get_upgrade_shop_slots(_game_state)
	for i in slot_count:
		var slot: Panel = preload("res://scenes/build/upgrade_visual.tscn").instantiate()
		slot.custom_minimum_size = Vector2(140, 160)
		add_child(slot)
		_upgrade_slots.append(slot)
		slot.gui_input.connect(_on_slot_input.bind(i))


func refresh_upgrades() -> void:
	## Roll upgrades (70% common / 30% rare). Slot count from Talisman.
	_offered_ids.clear()
	var slot_count := Talisman.get_upgrade_shop_slots(_game_state)
	for i in slot_count:
		var rarity := _roll_rarity()
		var uid := _pick_upgrade(rarity)
		_offered_ids.append(uid)
	_update_visuals()


func reroll_upgrades() -> bool:
	## Spend 1 terazin to re-roll upgrade slots only. Returns false if can't afford.
	if _game_state.terazin < Enums.UPGRADE_REROLL_COST:
		return false
	_game_state.terazin -= Enums.UPGRADE_REROLL_COST
	refresh_upgrades()
	_game_state.state_changed.emit()
	return true


func mark_sold(slot_idx: int) -> void:
	if slot_idx >= 0 and slot_idx < _offered_ids.size():
		_offered_ids[slot_idx] = ""
		_update_visuals()


func is_available() -> bool:
	## Upgrade shop visible from shop Lv2+ (round 3+).
	return _game_state.round_num >= 3


func get_upgrade_cost(slot_idx: int) -> int:
	if slot_idx < 0 or slot_idx >= _offered_ids.size():
		return 0
	var uid: String = _offered_ids[slot_idx]
	if uid == "":
		return 0
	var base_cost: int = UpgradeDB.get_upgrade(uid).get("cost", 0)
	# ⚒️ 단조사: 커먼 업그레이드 비용 -1 테라진
	var rarity: int = UpgradeDB.get_upgrade(uid).get("rarity", 0)
	if rarity == Enums.UpgradeRarity.COMMON:
		base_cost -= Commander.get_common_upgrade_discount(_game_state)
	return maxi(base_cost, 0)


func _roll_rarity() -> int:
	# 70% common, 30% rare. 💰 연금술사: 에픽 10% 추가 (common 60%, rare 30%, epic 10%).
	var roll := _rng.randi_range(0, 99)
	if Commander.can_shop_epic(_game_state):
		if roll < 60:
			return Enums.UpgradeRarity.COMMON
		elif roll < 90:
			return Enums.UpgradeRarity.RARE
		else:
			return Enums.UpgradeRarity.EPIC
	if roll < 70:
		return Enums.UpgradeRarity.COMMON
	return Enums.UpgradeRarity.RARE


func _pick_upgrade(rarity: int) -> String:
	var candidates := UpgradeDB.get_ids_by_rarity(rarity)
	if candidates.is_empty():
		return ""
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _update_visuals() -> void:
	for i in _upgrade_slots.size():
		var slot: Panel = _upgrade_slots[i]
		if i < _offered_ids.size() and _offered_ids[i] != "":
			slot.call("setup_upgrade", _offered_ids[i], true)
		else:
			slot.call("clear")


func _on_slot_input(event: InputEvent, slot_idx: int) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if slot_idx < 0 or slot_idx >= _offered_ids.size():
		return
	var uid: String = _offered_ids[slot_idx]
	if uid == "":
		return

	var cost := get_upgrade_cost(slot_idx)
	if _game_state.terazin < cost:
		print("[UpgradeShop] Not enough terazin (%d < %d)" % [_game_state.terazin, cost])
		return

	# Deduct immediately — refund on cancel
	_game_state.terazin -= cost
	_game_state.state_changed.emit()
	upgrade_purchase_requested.emit(uid, slot_idx)
