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


func test_raider_free_upgrade_selection_attaches_with_reward_source() -> void:
	var attached: Array = []
	var finished: Array = []
	_state.upgrade_attached_to_card.connect(
		func(upgrade_id: String, source: String, target_card_id: String, target_idx: int):
			attached.append({
				"upgrade_id": upgrade_id,
				"source": source,
				"target_card_id": target_card_id,
				"target_idx": target_idx,
			}))
	_bp.free_upgrade_finished.connect(func(applied: bool): finished.append(applied))

	_bp.start_free_upgrade_selection("C1", "raider_win_streak")

	assert_true(_bp.target_overlay.visible, "무료 업그레이드도 대상 선택 overlay 표시")
	assert_string_contains(
		_bp.get_node("TargetSelectOverlay/InstructionLabel").text,
		"Raider 3-win reward")
	assert_eq(_state.terazin, 20, "무료 보상은 테라진 차감 없음")

	_bp._on_target_selected(0)

	var card: CardInstance = _state.board[0]
	assert_eq(card.upgrades.size(), 1)
	assert_eq(card.upgrades[0]["id"], "C1")
	assert_eq(finished, [true], "무료 업그레이드 완료 signal")
	assert_eq(attached.size(), 1)
	assert_eq(attached[0]["source"], "raider_win_streak")
	assert_eq(attached[0]["target_card_id"], "sp_assembly")
	assert_eq(attached[0]["target_idx"], 0)
	assert_false(_bp.target_overlay.visible, "부착 후 대상 선택 오버레이 닫힘")


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


func test_target_overlay_guidance_avoids_bottom_controls_and_tutorial() -> void:
	_begin_shop_upgrade_purchase("C1", 0)

	var instruction := _bp.get_node("TargetSelectOverlay/InstructionLabel") as Control
	var detail := _bp.get_node("TargetSelectOverlay/DetailLabel") as Control
	var confirm := _bp.get_node("ConfirmButton") as Control
	var tutorial := _bp.get_node("TutorialHintPanel") as Control

	assert_false(instruction.get_global_rect().intersects(confirm.get_global_rect()),
		"instruction label avoids BUILD COMPLETE")
	assert_false(detail.get_global_rect().intersects(confirm.get_global_rect()),
		"detail label avoids BUILD COMPLETE")
	assert_false(instruction.get_global_rect().intersects(tutorial.get_global_rect()),
		"instruction label avoids tutorial panel")
	assert_false(detail.get_global_rect().intersects(tutorial.get_global_rect()),
		"detail label avoids tutorial panel")


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


func test_card_shop_refresh_keeps_upgrade_offers() -> void:
	var before: Array = _bp.upgrade_shop._offered_ids.duplicate()

	_bp.refresh_shop()

	assert_eq(_bp.upgrade_shop._offered_ids, before,
		"카드 상점 리프레시는 업그레이드 상점을 바꾸지 않음")


func test_phase_shop_refresh_can_refresh_upgrade_offers() -> void:
	_set_upgrade_offers(["__sentinel_common__", "__sentinel_rare__"])

	_bp.refresh_shop(true)

	assert_eq(_bp.upgrade_shop._offered_ids.size(), Enums.UPGRADE_SHOP_SLOTS)
	for id in _bp.upgrade_shop._offered_ids:
		assert_ne(id, "", "라운드 진입 리프레시는 업그레이드 제안을 채움")
	assert_false(_bp.upgrade_shop._offered_ids.has("__sentinel_common__"))
	assert_false(_bp.upgrade_shop._offered_ids.has("__sentinel_rare__"))


func test_reroll_copy_distinguishes_card_and_upgrade_scope() -> void:
	_bp._refresh_all()

	assert_string_contains(_bp.get_node("ShopLabel").text, "CARD SHOP")
	assert_string_contains(_bp.get_node("ShopLabel").text, "R:cards")
	assert_string_contains(_bp.get_node("UpgradeShopLabel").text, "T:upgrades only")
	assert_string_contains(_bp.get_node("UpgradeRerollButton").text, "UPG REROLL")


func test_hud_shows_commander_and_talisman_names() -> void:
	_state.commander_type = Enums.CommanderType.GAMBLER
	_state.talisman_type = Enums.TalismanType.TWO_FACED_COIN
	_bp.shop._coin_slots = {"discount_idx": 0, "markup_idx": 1}

	_bp._refresh_all()

	var text: String = _bp.get_identity_text()
	assert_string_contains(text, "커맨더:")
	assert_string_contains(text, "부적:")
	assert_string_contains(text, "도박꾼")
	assert_string_contains(text, "양면 동전")
	assert_string_contains(text, "리롤 50%")
	assert_string_contains(text, "합성 환급")
	assert_string_contains(text, "-50%/+50%")
	assert_string_contains(text, "할인 1")
	assert_string_contains(text, "할증 2")
	assert_false(text.contains("C:"), "커맨더 효과는 축약 C: 대신 이름 줄에 표시")
	assert_false(text.contains("T:"), "부적 효과는 축약 T: 대신 이름 줄에 표시")


func test_hud_updates_flint_ready_and_used_status() -> void:
	_state.commander_type = Enums.CommanderType.GAMBLER
	_state.talisman_type = Enums.TalismanType.FLINT
	_state.talisman_state["first_growth_used"] = false
	_bp._refresh_all()

	var ready_text: String = _bp.get_identity_text()
	assert_string_contains(ready_text, "부싯돌")
	assert_string_contains(ready_text, "첫 성장 효과 ×2 준비")

	_state.talisman_state["first_growth_used"] = true
	_bp._refresh_all()

	var used_text: String = _bp.get_identity_text()
	assert_string_contains(used_text, "부싯돌")
	assert_string_contains(used_text, "첫 성장 효과 ×2 사용됨")


func test_hud_shows_compact_run_progress_rail() -> void:
	_state.round_num = 5
	_bp._refresh_all()

	var rail_text: String = _bp.get_run_progress_rail_text()
	assert_string_contains(rail_text, "R5 NOW")
	assert_string_contains(rail_text, "rewards")
	assert_string_contains(rail_text, "R4 done")
	assert_string_contains(rail_text, "R8 next")
	assert_string_contains(rail_text, "R12")
	assert_string_contains(rail_text, "R15 final")
	assert_string_contains(_bp.get_round_label_text(), rail_text)


func test_shop_card_visual_marks_two_faced_coin_slots() -> void:
	_state.talisman_type = Enums.TalismanType.TWO_FACED_COIN
	_bp.shop._offered_ids.assign(["sp_assembly", "sp_assembly", "sp_assembly"])
	_bp.shop._coin_slots = {"discount_idx": 0, "markup_idx": 1}

	_bp.shop._update_visuals()

	var discount_visual = _bp.shop._shop_slots[0]
	var markup_visual = _bp.shop._shop_slots[1]
	assert_true(discount_visual.visible)
	assert_true(markup_visual.visible)
	assert_eq(discount_visual.get_shop_price_note(), "-50%")
	assert_eq(markup_visual.get_shop_price_note(), "+50%")
	assert_string_contains(discount_visual.get_face_tier_text(), "1g COIN -50%")
	assert_string_contains(markup_visual.get_face_tier_text(), "3g COIN +50%")

	var discount_style := discount_visual.get_theme_stylebox("panel") as StyleBoxFlat
	var markup_style := markup_visual.get_theme_stylebox("panel") as StyleBoxFlat
	assert_eq(discount_style.border_width_left, 4)
	assert_eq(markup_style.border_width_left, 4)


func test_shop_card_visual_exposes_compact_role_cues() -> void:
	_bp.shop._offered_ids.assign([
		"sp_assembly",
		"sp_workshop",
		"ne_envoy",
		"",
	])

	_bp.shop._update_visuals()

	var starter_visual = _bp.shop._shop_slots[0]
	var reactor_visual = _bp.shop._shop_slots[1]
	var economy_visual = _bp.shop._shop_slots[2]
	var empty_visual = _bp.shop._shop_slots[3]

	assert_eq(starter_visual.get_face_role_text(), "시작 · 유닛+")
	assert_eq(reactor_visual.get_face_role_text(), "반응 · 강화")
	assert_eq(economy_visual.get_face_role_text(), "시작 · 경제")
	assert_true(starter_visual.get_node("RoleLabel").visible)
	assert_true(reactor_visual.get_node("RoleLabel").visible)
	assert_true(economy_visual.get_node("RoleLabel").visible)
	assert_eq(empty_visual.get_face_role_text(), "")


func test_upgrade_reroll_button_disabled_when_unaffordable_or_pending() -> void:
	_state.terazin = 0
	_bp._refresh_all()
	assert_true(_bp.get_node("UpgradeRerollButton").disabled, "테라진 부족 시 비활성")

	_state.terazin = 20
	_bp._refresh_all()
	_begin_shop_upgrade_purchase("C1", 0)
	assert_true(_bp.get_node("UpgradeRerollButton").disabled, "대상 선택 중 비활성")
	assert_false(_bp.reroll_upgrades(), "대상 선택 중에는 리롤 실패")
