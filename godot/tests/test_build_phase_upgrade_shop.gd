extends GutTest
## BuildPhase upgrade shop UX contract.

const BuildPhaseScene = preload("res://scenes/build/build_phase.tscn")

var _bp = null
var _state: GameState = null
var _rng: RandomNumberGenerator = null


func before_each() -> void:
	_bp = BuildPhaseScene.instantiate()
	add_child_autofree(_bp)
	_state = GameState.new()
	_state.round_num = 1
	_state.gold = 20
	_state.terazin = 20
	_state.board[0] = CardInstance.create("sp_assembly")
	_rng = RandomNumberGenerator.new()
	_rng.seed = 42
	_bp.setup(_state, _rng)
	_set_upgrade_offers(["C1", "R1"])


func _set_upgrade_offers(ids: Array[String]) -> void:
	_bp.upgrade_shop._offered_ids.assign(ids)
	_bp.upgrade_shop.refresh_offer_visuals()


func _begin_shop_upgrade_purchase(upgrade_id: String, slot_idx: int) -> int:
	var cost: int = _bp.upgrade_shop.get_upgrade_cost(slot_idx)
	_state.terazin -= cost
	_bp._on_upgrade_purchase_requested(upgrade_id, slot_idx)
	return cost


func test_shop_upgrade_attaches_to_selected_field_card() -> void:
	var attached: Array = []
	_state.upgrade_attached_to_card.connect(
		func(upgrade_id: String, source: String, target_card_id: String, target_idx: int):
			attached.append({
				"upgrade_id": upgrade_id,
				"source": source,
				"target_card_id": target_card_id,
				"target_idx": target_idx,
			}))

	var cost := _begin_shop_upgrade_purchase("C1", 0)
	assert_false(_bp.can_reroll_upgrades(), "대상 선택 중 업그레이드 리롤 비활성")

	_bp._on_target_selected(0)

	var card: CardInstance = _state.board[0]
	assert_eq(card.upgrades.size(), 1)
	assert_eq(card.upgrades[0]["id"], "C1")
	assert_eq(_state.terazin, 20 - cost)
	assert_eq(_bp.upgrade_shop._offered_ids[0], "", "구매한 업그레이드 슬롯 비움")
	assert_eq(attached.size(), 1)
	assert_eq(attached[0]["source"], "shop")
	assert_eq(attached[0]["target_card_id"], "sp_assembly")
	assert_eq(attached[0]["target_idx"], 0)
	assert_false(_bp.target_overlay.visible, "부착 후 대상 선택 오버레이 닫힘")
	assert_eq(_bp.target_overlay.get_preview_texts(), [], "부착 후 미리보기 정리")


func test_shop_upgrade_cancel_refunds_terazin() -> void:
	var refunds: Array = []
	_state.upgrade_refunded.connect(
		func(upgrade_id: String, cost: int, reason: String, terazin_after: int):
			refunds.append({
				"upgrade_id": upgrade_id,
				"cost": cost,
				"reason": reason,
				"terazin_after": terazin_after,
			}))

	var cost := _begin_shop_upgrade_purchase("C1", 0)
	assert_eq(_state.terazin, 20 - cost)

	_bp._on_target_cancelled()

	assert_eq(_state.terazin, 20)
	assert_true(_bp._pending_upgrade.is_empty())
	assert_eq(refunds.size(), 1)
	assert_eq(refunds[0]["upgrade_id"], "C1")
	assert_eq(refunds[0]["cost"], cost)
	assert_eq(refunds[0]["reason"], "cancelled")
	assert_eq(refunds[0]["terazin_after"], 20)
	assert_false(_bp.target_overlay.visible, "취소 후 대상 선택 오버레이 닫힘")
	assert_eq(_bp.target_overlay.get_preview_texts(), [], "취소 후 미리보기 정리")


func test_upgrade_target_overlay_previews_effect_and_slots() -> void:
	_begin_shop_upgrade_purchase("C1", 0)

	assert_true(_bp.target_overlay.visible)
	assert_string_contains(_bp.get_node("TargetSelectOverlay/DetailLabel").text, "강화합금")
	assert_string_contains(_bp.get_node("TargetSelectOverlay/DetailLabel").text, "ATK +15%")
	var notes: Array[String] = _bp.target_overlay.get_preview_texts()
	assert_eq(notes.size(), 1)
	assert_string_contains(notes[0], "Slots 0/5 -> 1/5")
	assert_string_contains(notes[0], "ATK +15%")


func test_upgrade_target_overlay_marks_full_slots_ineligible() -> void:
	var full_card := CardInstance.create("sp_workshop")
	for _i in Enums.MAX_UPGRADE_SLOTS:
		assert_true(full_card.attach_upgrade("C1"))
	_state.board[1] = full_card
	_bp._refresh_all()

	_begin_shop_upgrade_purchase("R1", 1)

	var joined := "\n".join(_bp.target_overlay.get_preview_texts())
	assert_string_contains(joined, "Slots 0/5 -> 1/5")
	assert_string_contains(joined, "FULL 5/5")
	assert_string_contains(joined, "Lifesteal 15%")


func test_shop_upgrade_no_eligible_field_card_refunds_immediately() -> void:
	_state.board[0] = null
	_bp._refresh_all()
	var refunds: Array = []
	_state.upgrade_refunded.connect(
		func(upgrade_id: String, cost: int, reason: String, terazin_after: int):
			refunds.append({
				"upgrade_id": upgrade_id,
				"cost": cost,
				"reason": reason,
				"terazin_after": terazin_after,
			}))

	var cost := _begin_shop_upgrade_purchase("C1", 0)

	assert_eq(_state.terazin, 20)
	assert_true(_bp._pending_upgrade.is_empty())
	assert_eq(refunds.size(), 1)
	assert_eq(refunds[0]["cost"], cost)
	assert_eq(refunds[0]["reason"], "no_eligible_cards")


func test_upgrade_reroll_button_spends_terazin_and_emits_signal() -> void:
	_state.terazin = 3
	_bp._refresh_all()
	var events: Array = []
	_bp.upgrade_rerolled.connect(func(cost: int, terazin_after: int):
		events.append({"cost": cost, "terazin_after": terazin_after}))

	_bp.get_node("UpgradeRerollButton").pressed.emit()

	assert_eq(_state.terazin, 2)
	assert_eq(events, [{"cost": Enums.UPGRADE_REROLL_COST, "terazin_after": 2}])
	assert_false(_bp.get_node("UpgradeRerollButton").disabled)


func test_upgrade_reroll_button_disabled_when_unaffordable_or_pending() -> void:
	_state.terazin = 0
	_bp._refresh_all()
	assert_true(_bp.get_node("UpgradeRerollButton").disabled, "테라진 부족 시 비활성")

	_state.terazin = 20
	_bp._refresh_all()
	_begin_shop_upgrade_purchase("C1", 0)
	assert_true(_bp.get_node("UpgradeRerollButton").disabled, "대상 선택 중 비활성")
	assert_false(_bp.reroll_upgrades(), "대상 선택 중에는 리롤 실패")
