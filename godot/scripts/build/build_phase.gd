extends Control
## Build phase UI: shop + field slots + bench slots + card drag-and-drop.

signal build_confirmed
signal sell_performed(zone: String, idx: int)
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


func setup(state: GameState, rng: RandomNumberGenerator) -> void:
	game_state = state
	game_state.state_changed.connect(_refresh_all)
	confirm_button.pressed.connect(_on_confirm_pressed)
	_create_slots()
	shop.setup(state, rng)
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
		var card = game_state.board[i]
		_field_visuals[i].setup(card, "board", i)

	for i in _bench_visuals.size():
		var card = game_state.bench[i]
		_bench_visuals[i].setup(card, "bench", i)

	if gold_label:
		gold_label.text = "Gold: %d" % game_state.gold
	if terazin_label:
		terazin_label.text = "Terazin: %d" % game_state.terazin
	if round_label:
		round_label.text = "Round %d/%d" % [game_state.round_num, Enums.MAX_ROUNDS]
	if hp_label:
		hp_label.text = "HP: %d" % game_state.hp
	if shop_label:
		var level := shop._get_shop_level()
		shop_label.text = "SHOP Lv%d (click to buy, R to reroll -%dg)" % [level, Enums.REROLL_COST]

	# Upgrade shop visibility (Lv2+ = round 3+)
	var upg_visible := upgrade_shop.is_available()
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
	var refund := game_state.sell_card(zone, idx)
	if refund > 0:
		print("[Sell] +%dg refund | Gold=%d" % [refund, game_state.gold])
		sell_performed.emit(zone, idx)


func _on_confirm_pressed() -> void:
	build_confirmed.emit()


# --- Upgrade purchase flow ---


func _on_upgrade_purchase_requested(upgrade_id: String, slot_idx: int) -> void:
	var cost := upgrade_shop.get_upgrade_cost(slot_idx)
	# Terazin already deducted by upgrade_shop. Refund on failure/cancel.
	var has_eligible := false
	for card in game_state.board:
		if card != null and (card as CardInstance).can_attach_upgrade():
			has_eligible = true
			break
	if not has_eligible:
		print("[UpgradeShop] No eligible field cards — refund %dt" % cost)
		game_state.terazin += cost
		game_state.state_changed.emit()
		return

	_pending_upgrade = {"upgrade_id": upgrade_id, "slot_idx": slot_idx, "cost": cost}
	target_overlay.start_selection(_field_visuals, game_state.board)


func _on_target_selected(field_idx: int) -> void:
	if _pending_upgrade.is_empty():
		return
	var card: CardInstance = game_state.board[field_idx]
	if card == null or not card.can_attach_upgrade():
		print("[UpgradeShop] Card no longer eligible — refund %dt" % _pending_upgrade["cost"])
		_refund_pending_upgrade()
		return
	# Terazin already deducted — just attach
	card.attach_upgrade(_pending_upgrade["upgrade_id"])
	upgrade_shop.mark_sold(_pending_upgrade["slot_idx"])
	var upg_name := UpgradeDB.get_upgrade(_pending_upgrade["upgrade_id"]).get("name", "???")
	print("[UpgradeShop] %s → %s (-%dt)" % [upg_name, card.get_name(), _pending_upgrade["cost"]])
	_pending_upgrade = {}
	game_state.state_changed.emit()


func _on_target_cancelled() -> void:
	if not _pending_upgrade.is_empty():
		print("[UpgradeShop] Cancelled — refund %dt" % _pending_upgrade["cost"])
		_refund_pending_upgrade()


func _refund_pending_upgrade() -> void:
	game_state.terazin += _pending_upgrade["cost"]
	_pending_upgrade = {}
	game_state.state_changed.emit()


# --- Merge bonus flow ---


func _on_card_merged(card: CardInstance, old_star: int, new_star: int) -> void:
	merge_performed.emit(card)

	if _upgrade_choice_popup == null:
		return
	if old_star == 1 and new_star == 2:
		_pending_merge_card = card
		_upgrade_choice_popup.show_choices(Enums.UpgradeRarity.RARE, 3)
	elif old_star == 2 and new_star == 3:
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
	var upg_name := UpgradeDB.get_upgrade(upgrade_id).get("name", "???")
	print("[MergeBonus] %s → %s" % [upg_name, _pending_merge_card.get_name()])
	_pending_merge_card = null
	game_state.state_changed.emit()
