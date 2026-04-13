extends Control
## Build phase UI: shop + field slots + bench slots + card drag-and-drop.

signal build_confirmed
signal sell_performed(zone: String, idx: int, sold_card: CardInstance)
signal merge_performed(card: CardInstance)

var game_state: GameState = null
var _field_visuals: Array = []
var _bench_visuals: Array = []
var _pending_upgrade: Dictionary = {}  # {upgrade_id, slot_idx, cost}
var _pending_merge_card: CardInstance = null
var _upgrade_choice_popup = null  # set by game_manager

@onready var shop: HBoxContainer = $Shop
@onready var upgrade_shop: HBoxContainer = $UpgradeShop
@onready var target_overlay: Control = $TargetSelectOverlay
@onready var field_container: HBoxContainer = $FieldContainer
@onready var bench_container: HBoxContainer = $BenchContainer
@onready var confirm_button: Button = $ConfirmButton
@onready var gold_label: Label = $HUD/GoldLabel
@onready var terazin_label: Label = $HUD/TerazinLabel
@onready var round_label: Label = $HUD/RoundLabel
@onready var hp_label: Label = $HUD/HPLabel
@onready var shop_label: Label = $ShopLabel
@onready var upgrade_shop_label: Label = $UpgradeShopLabel


func setup(state: GameState, rng: RandomNumberGenerator, genome: Genome = null) -> void:
	game_state = state
	game_state.state_changed.connect(_refresh_all)
	confirm_button.pressed.connect(_on_confirm_pressed)
	_create_slots()
	shop.setup(state, rng, genome)
	shop.card_merged.connect(_on_card_merged)
	upgrade_shop.setup(state, rng)
	upgrade_shop.upgrade_purchase_requested.connect(_on_upgrade_purchase_requested)
	target_overlay.target_selected.connect(_on_target_selected)
	target_overlay.target_cancelled.connect(_on_target_cancelled)
	target_overlay.visible = false
	_refresh_all()


func set_upgrade_choice_popup(popup) -> void:
	_upgrade_choice_popup = popup
	if _upgrade_choice_popup:
		_upgrade_choice_popup.upgrade_chosen.connect(_on_merge_upgrade_chosen)


func refresh_shop() -> void:
	shop.refresh_shop()
	if upgrade_shop.is_available():
		upgrade_shop.refresh_upgrades()


func get_shop_offered() -> Array:
	return shop._offered_ids


func reroll() -> bool:
	return shop.reroll()


func reroll_upgrades() -> bool:
	if not upgrade_shop.is_available():
		return false
	return upgrade_shop.reroll_upgrades()


func _create_slots() -> void:
	for i in Enums.MAX_FIELD_SLOTS:
		var slot := _create_card_slot("board", i)
		field_container.add_child(slot)
		_field_visuals.append(slot)
		slot.visible = i < game_state.field_slots

	for i in Enums.MAX_BENCH_SLOTS:
		var slot := _create_card_slot("bench", i)
		bench_container.add_child(slot)
		_bench_visuals.append(slot)


func _create_card_slot(zone_name: String, idx: int) -> Panel:
	var slot: Panel = preload("res://scenes/build/card_visual.tscn").instantiate()
	slot.zone = zone_name
	slot.slot_idx = idx
	slot.custom_minimum_size = Vector2(120, 160)
	return slot


func _refresh_all() -> void:
	for i in _field_visuals.size():
		_field_visuals[i].visible = i < game_state.field_slots
		var card = game_state.board[i]
		_field_visuals[i].setup(card, "board", i)

	for i in _bench_visuals.size():
		var card = game_state.bench[i]
		_bench_visuals[i].setup(card, "bench", i)

	if gold_label:
		var interest: int = game_state.calc_interest()
		gold_label.text = "Gold: %d (+%di)" % [game_state.gold, interest]
	if terazin_label:
		terazin_label.text = "Terazin: %d" % game_state.terazin
	if round_label:
		round_label.text = "Round %d/%d" % [game_state.round_num, Enums.MAX_ROUNDS]
	if hp_label:
		hp_label.text = "HP: %d" % game_state.hp
	if shop_label:
		var level: int = shop._get_shop_level()
		if level < Enums.LEVELUP_MAX:
			shop_label.text = "SHOP Lv%d (R:reroll -%dg | F:levelup -%dg)" % [
				level, Enums.REROLL_COST, game_state.levelup_current_cost]
		else:
			shop_label.text = "SHOP Lv%d MAX (R:reroll -%dg)" % [level, Enums.REROLL_COST]
		# 이번 라운드 한정 무료 리롤 저축분이 있으면 배지 표시.
		# 사용자가 R 키를 누를 때 commander 확률 후 우선 소진된다.
		if game_state.pending_free_rerolls > 0:
			shop_label.text += "  [무료 리롤 ×%d]" % game_state.pending_free_rerolls

	# Upgrade shop visibility (Lv2+ = round 3+)
	var upg_visible: bool = upgrade_shop.is_available()
	upgrade_shop.visible = upg_visible
	if upgrade_shop_label:
		upgrade_shop_label.visible = upg_visible
		if upg_visible:
			upgrade_shop_label.text = "UPGRADES (T to reroll -%dt)" % Enums.UPGRADE_REROLL_COST


func _on_card_dropped(data: Dictionary, to_zone: String, to_idx: int) -> void:
	var from_zone: String = data["source_zone"]
	var from_idx: int = data["source_idx"]
	if from_zone == to_zone and from_idx == to_idx:
		return
	game_state.move_card(from_zone, from_idx, to_zone, to_idx)


func _on_card_sell(zone: String, idx: int) -> void:
	# 카드 정보를 판매 전에 캡처 (영혼 항아리용)
	var zone_arr := game_state.board if zone == "board" else game_state.bench
	var sold_card: CardInstance = zone_arr[idx] if idx < zone_arr.size() else null
	# 슬롯 위치를 판매 전에 캡처 (플로팅 텍스트용)
	var visuals := _field_visuals if zone == "board" else _bench_visuals
	var slot_pos: Vector2 = visuals[idx].global_position if idx < visuals.size() else Vector2.ZERO
	var refund := game_state.sell_card(zone, idx)
	if refund > 0:
		print("[Sell] +%dg refund | Gold=%d" % [refund, game_state.gold])
		_show_floating_gold(slot_pos, refund)
		sell_performed.emit(zone, idx, sold_card)


func _on_confirm_pressed() -> void:
	build_confirmed.emit()


# --- Upgrade purchase flow ---


func _on_upgrade_purchase_requested(upgrade_id: String, slot_idx: int) -> void:
	var cost: int = upgrade_shop.get_upgrade_cost(slot_idx)
	# Terazin already deducted by upgrade_shop. Refund on failure/cancel.
	game_state.upgrade_purchased.emit(upgrade_id, slot_idx, cost, game_state.terazin)
	var has_eligible := false
	for card in game_state.board:
		if card != null and (card as CardInstance).can_attach_upgrade():
			has_eligible = true
			break
	if not has_eligible:
		print("[UpgradeShop] No eligible field cards — refund %dt" % cost)
		game_state.terazin += cost
		game_state.upgrade_refunded.emit(upgrade_id, cost, "no_eligible_cards", game_state.terazin)
		game_state.state_changed.emit()
		return

	_pending_upgrade = {"upgrade_id": upgrade_id, "slot_idx": slot_idx, "cost": cost}
	target_overlay.start_selection(_field_visuals, game_state.board)


func _on_target_selected(field_idx: int) -> void:
	if _pending_upgrade.is_empty():
		return
	var card: CardInstance = game_state.board[field_idx]
	var upgrade_id: String = _pending_upgrade["upgrade_id"]
	if card == null or not card.can_attach_upgrade():
		print("[UpgradeShop] Card no longer eligible — refund %dt" % _pending_upgrade["cost"])
		_refund_pending_upgrade("card_invalid")
		return
	# Terazin already deducted — just attach
	card.attach_upgrade(upgrade_id)
	upgrade_shop.mark_sold(_pending_upgrade["slot_idx"])
	var upg_name: String = UpgradeDB.get_upgrade(upgrade_id).get("name", "???")
	print("[UpgradeShop] %s → %s (-%dt)" % [upg_name, card.get_name(), _pending_upgrade["cost"]])
	game_state.upgrade_attached_to_card.emit(upgrade_id, "shop", card.get_base_id(), field_idx)
	_pending_upgrade = {}
	game_state.state_changed.emit()


func _on_target_cancelled() -> void:
	if not _pending_upgrade.is_empty():
		print("[UpgradeShop] Cancelled — refund %dt" % _pending_upgrade["cost"])
		_refund_pending_upgrade("cancelled")


func _refund_pending_upgrade(reason: String = "unknown") -> void:
	var upgrade_id: String = _pending_upgrade.get("upgrade_id", "")
	var cost: int = _pending_upgrade.get("cost", 0)
	game_state.terazin += cost
	_pending_upgrade = {}
	game_state.upgrade_refunded.emit(upgrade_id, cost, reason, game_state.terazin)
	game_state.state_changed.emit()


# --- Merge bonus flow ---


func _on_card_merged(card: CardInstance, old_star: int, new_star: int) -> void:
	merge_performed.emit(card)

	if _upgrade_choice_popup == null:
		return
	if old_star == 1 and new_star == 2:
		_pending_merge_card = card
		_upgrade_choice_popup.show_choices(Enums.UpgradeRarity.RARE, 3)
	# sp_charger ★3: 합성 시 1회 에픽 업그레이드 + 3 테라진
	elif old_star == 2 and new_star == 3 and card.get_base_id() == "sp_charger":
		game_state.terazin += 3
		_pending_merge_card = card
		_upgrade_choice_popup.show_choices(Enums.UpgradeRarity.EPIC, 3)


func _on_merge_upgrade_chosen(upgrade_id: String) -> void:
	if _pending_merge_card == null:
		return
	if not _pending_merge_card.can_attach_upgrade():
		print("[MergeBonus] Card upgrade slots full, bonus lost")
		_pending_merge_card = null
		return
	_pending_merge_card.attach_upgrade(upgrade_id)
	var upg_name: String = UpgradeDB.get_upgrade(upgrade_id).get("name", "???")
	print("[MergeBonus] %s → %s" % [upg_name, _pending_merge_card.get_name()])
	# 머지 보너스 부착 → board/bench 에서 인덱스를 찾아 emit.
	var target_idx := _find_card_index(_pending_merge_card)
	game_state.upgrade_attached_to_card.emit(
		upgrade_id, "merge_bonus", _pending_merge_card.get_base_id(), target_idx)
	_pending_merge_card = null
	game_state.state_changed.emit()


func _show_floating_gold(at_pos: Vector2, amount: int) -> void:
	var lbl := Label.new()
	lbl.text = "+%dg" % amount
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.global_position = at_pos + Vector2(20, -10)
	lbl.z_index = 100
	add_child(lbl)
	var tween := create_tween()
	tween.tween_property(lbl, "global_position:y", lbl.global_position.y - 40, 0.8)
	tween.parallel().tween_property(lbl, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.tween_callback(lbl.queue_free)


func _find_card_index(card: CardInstance) -> int:
	for i in game_state.board.size():
		if game_state.board[i] == card:
			return i
	return -1
