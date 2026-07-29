extends GutTest
## BuildPhase in-run tutorial hint contract for G-8.

const BuildPhaseScene = preload("res://scenes/build/build_phase.tscn")
const UpgradeChoicePopupScene = preload("res://scenes/ui/upgrade_choice_popup.tscn")

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
	_rng = RandomNumberGenerator.new()
	_rng.seed = 42


func _setup() -> void:
	_bp.setup(_state, _rng)


func _set_upgrade_offers(ids: Array[String]) -> void:
	_bp.upgrade_shop._offered_ids.assign(ids)
	_bp.upgrade_shop.refresh_offer_visuals()
	_bp._refresh_all()


func _begin_shop_upgrade_purchase(upgrade_id: String, slot_idx: int) -> void:
	var cost: int = _bp.upgrade_shop.get_upgrade_cost(slot_idx)
	_state.terazin -= cost
	_bp._on_upgrade_purchase_requested(upgrade_id, slot_idx)


func test_tutorial_hidden_until_enabled() -> void:
	_setup()

	assert_false(_bp.get_node("TutorialHintPanel").visible)
	assert_eq(_bp.get_tutorial_hint_text(), "")


func test_tutorial_prompts_shop_purchase_first() -> void:
	_setup()

	_bp.set_tutorial_enabled(true)

	assert_true(_bp.get_node("TutorialHintPanel").visible)
	assert_string_contains(_bp.get_tutorial_hint_text(), "카드 구매")
	assert_string_contains(_bp.get_tutorial_hint_text(), "SHOP")


func test_build_readiness_prompts_first_purchase() -> void:
	_setup()

	assert_true(_bp.is_build_readiness_visible())
	var readiness: String = _bp.get_build_readiness_text()
	assert_string_contains(readiness, "FIELD: 0장")
	assert_string_contains(readiness, "체인/전투")
	assert_string_contains(readiness, "BENCH: 비어 있음")
	assert_string_contains(readiness, "ENEMY:")
	assert_string_contains(readiness, "ATK")
	assert_string_contains(readiness, "HP")
	assert_string_contains(readiness, "Next:")
	assert_string_contains(readiness, "SHOP에서 카드를 구매")


func test_run_milestone_points_to_next_boss_reward() -> void:
	_setup()

	assert_string_contains(_bp.get_run_milestone_text(), "Goal:")
	assert_string_contains(_bp.get_run_milestone_text(), "R4 boss reward")
	assert_string_contains(_bp.get_run_milestone_text(), "4 fights")
	assert_string_contains(_bp.get_round_label_text(), "Round 1/15")
	assert_string_contains(_bp.get_round_label_text(), "R4 boss reward")

	_state.round_num = 4
	_state.state_changed.emit()

	assert_string_contains(_bp.get_run_milestone_text(), "this fight")
	assert_string_contains(_bp.get_round_label_text(), "R4 boss reward")


func test_enemy_pressure_preview_is_visible_and_does_not_consume_rng() -> void:
	_setup()
	var state_before := _rng.state

	var preview_text: String = _bp.get_enemy_pressure_preview_text()
	var preview_data: Dictionary = _bp.get_enemy_pressure_preview_data()

	assert_string_contains(preview_text, "ENEMY:")
	assert_string_contains(preview_text, "R1")
	assert_string_contains(preview_text, "ATK")
	assert_string_contains(preview_text, "HP")
	assert_false(bool(preview_data.get("exact", true)),
		"BUILD preview is a non-exact pressure range")
	assert_eq(_rng.state, state_before,
		"reading the enemy preview does not advance shared build/battle RNG")


func test_build_readiness_prompts_bench_to_field() -> void:
	_state.bench[0] = CardInstance.create("sp_assembly")
	_setup()

	var readiness: String = _bp.get_build_readiness_text()

	assert_string_contains(readiness, "FIELD: 0장")
	assert_string_contains(readiness, "BENCH: 1장 대기")
	assert_string_contains(readiness, "ENEMY:")
	assert_string_contains(readiness, "FIELD로 드래그")


func test_build_readiness_reports_upgrade_ready() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_setup()
	_set_upgrade_offers(["C1"])

	var readiness: String = _bp.get_build_readiness_text()

	assert_string_contains(readiness, "FIELD: 1장 체인/전투 참가")
	assert_string_contains(readiness, "업그레이드하거나 BUILD COMPLETE")


func test_tutorial_prompts_bench_to_field_when_card_owned() -> void:
	_state.bench[0] = CardInstance.create("sp_assembly")
	_setup()

	_bp.set_tutorial_enabled(true)

	assert_string_contains(_bp.get_tutorial_hint_text(), "필드 배치")
	assert_string_contains(_bp.get_tutorial_hint_text(), "FIELD")


func test_tutorial_prompts_upgrade_when_board_ready() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_setup()
	_set_upgrade_offers(["C1"])

	_bp.set_tutorial_enabled(true)

	assert_string_contains(_bp.get_tutorial_hint_text(), "업그레이드")
	assert_string_contains(_bp.get_tutorial_hint_text(), "UPGRADES")


func test_tutorial_hides_during_upgrade_target_selection_and_restores_after_cancel() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_setup()
	_set_upgrade_offers(["C1"])
	_bp.set_tutorial_enabled(true)

	_begin_shop_upgrade_purchase("C1", 0)

	assert_false(_bp.get_node("TutorialHintPanel").visible,
		"target overlay owns the decision, so tutorial quiets")
	assert_eq(_bp.get_tutorial_hint_text(), "")

	_bp._on_target_cancelled()

	assert_true(_bp.get_node("TutorialHintPanel").visible,
		"tutorial returns after target selection closes")
	assert_string_contains(_bp.get_tutorial_hint_text(), "업그레이드")


func test_tutorial_hides_when_external_target_overlay_opens() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_setup()
	_bp.set_tutorial_enabled(true)
	assert_true(_bp.get_node("TutorialHintPanel").visible)

	_bp.target_overlay.start_selection(_bp._field_visuals, _state.board)

	assert_false(_bp.get_node("TutorialHintPanel").visible,
		"external target overlays also suppress tutorial hints")
	assert_false(_bp.is_build_readiness_visible(),
		"target overlay also suppresses the readiness cue")

	_bp.target_overlay.end_selection()

	assert_true(_bp.get_node("TutorialHintPanel").visible,
		"tutorial returns when external target overlay closes")
	assert_true(_bp.is_build_readiness_visible(),
		"readiness cue returns when target selection closes")


func test_tutorial_hides_while_merge_reward_popup_visible() -> void:
	_setup()
	var popup = UpgradeChoicePopupScene.instantiate()
	add_child_autofree(popup)
	popup.setup(_rng)
	_bp.set_upgrade_choice_popup(popup)
	_bp.set_tutorial_enabled(true)
	assert_true(_bp.get_node("TutorialHintPanel").visible)

	popup.show_choices(Enums.UpgradeRarity.RARE, 3)

	assert_false(_bp.get_node("TutorialHintPanel").visible,
		"merge reward popup owns the decision, so tutorial quiets")

	popup.visible = false

	assert_true(_bp.get_node("TutorialHintPanel").visible,
		"tutorial returns after merge reward popup closes")


func test_last_chain_history_hides_when_target_overlay_opens() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_setup()
	_bp.set_last_chain_history(
		"2 triggers | +1g",
		"#1 Round Start: 증기 조립소 -> 태엽 공방 +Unit\nComplete: 2 triggers, +1g")

	assert_true(_bp.is_last_chain_history_visible(),
		"last-chain history is visible on an idle build surface")
	assert_false(_bp.is_build_readiness_visible(),
		"last-chain history owns the lower side lane over readiness")

	_bp.target_overlay.start_selection(_bp._field_visuals, _state.board)

	assert_false(_bp.is_last_chain_history_visible(),
		"target overlay owns the screen, so last-chain history quiets")

	_bp.target_overlay.end_selection()

	assert_true(_bp.is_last_chain_history_visible(),
		"last-chain history returns when target selection closes")
	assert_string_contains(_bp.get_last_chain_history_text(), "Complete: 2 triggers")


func test_last_chain_history_display_compacts_recent_events() -> void:
	_setup()
	_bp.set_last_chain_history(
		"2 triggers",
		"#1 Round Start: [L->R] 증기 조립소 -> 태엽 공방 +Unit (Unit Added / Manufacture)\n"
		+ "#2 Cascade: [SELF] 태엽 공방 -> 태엽 공방 +Stats (Enhanced / Upgrade)\n"
		+ "Complete: 2 triggers, no gold")

	var display_text: String = _bp.get_last_chain_history_display_text()

	assert_string_contains(display_text, "2 triggers")
	assert_string_contains(display_text, "#1 [L->R] 증기 조립소 -> 태엽 공방 +Unit")
	assert_string_contains(display_text, "#2 [SELF] 태엽 공방 -> 태엽 공방 +Stats")
	assert_false(display_text.contains("Complete:"),
		"summary already covers completion, so visible panel uses event rows")
	assert_false(display_text.contains("(Unit Added / Manufacture)"),
		"compact panel omits raw layer detail")


func test_settlement_recap_shows_source_breakdown_and_quiets_tutorial() -> void:
	_setup()
	_bp.set_tutorial_enabled(true)
	assert_true(_bp.get_node("TutorialHintPanel").visible)

	_bp.set_last_settlement_recap({
		"round": 1,
		"next_round": 2,
		"gold_before": 11,
		"gold_after": 16,
		"gold_delta": 5,
		"base_income": 5,
		"interest": 0,
		"interest_basis_gold": 10,
		"terazin_before": 0,
		"terazin_after": 2,
		"terazin_delta": 2,
		"terazin_gain": 2,
		"commander_terazin": 0,
	})

	assert_true(_bp.is_last_settlement_recap_visible())
	assert_false(_bp.get_node("TutorialHintPanel").visible,
		"settlement recap owns the tutorial lane while it is fresh")
	var recap_text: String = _bp.get_last_settlement_recap_text()
	assert_string_contains(recap_text, "LAST SETTLEMENT R1")
	assert_string_contains(recap_text, "Gold: 11 -> 16")
	assert_string_contains(recap_text, "+5 income")
	assert_string_contains(recap_text, "+0 interest")
	assert_string_contains(recap_text, "Terazin: 0 -> 2")
	assert_string_contains(recap_text, "Next: R2 BUILD")
	assert_string_contains(recap_text, "R4 boss reward in 3 fights")

	_bp.clear_last_settlement_recap()

	assert_false(_bp.is_last_settlement_recap_visible())
	assert_true(_bp.get_node("TutorialHintPanel").visible,
		"tutorial returns after the settlement recap clears")


func test_settlement_recap_hides_when_target_overlay_opens() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_setup()
	_bp.set_last_settlement_recap({
		"round": 1,
		"next_round": 2,
		"gold_before": 11,
		"gold_after": 17,
		"gold_delta": 6,
		"base_income": 5,
		"interest": 1,
		"terazin_before": 0,
		"terazin_after": 2,
		"terazin_delta": 2,
		"terazin_gain": 2,
		"commander_terazin": 0,
	})
	assert_true(_bp.is_last_settlement_recap_visible())

	_bp.target_overlay.start_selection(_bp._field_visuals, _state.board)

	assert_false(_bp.is_last_settlement_recap_visible(),
		"target overlay owns the decision, so settlement recap quiets")

	_bp.target_overlay.end_selection()

	assert_true(_bp.is_last_settlement_recap_visible(),
		"settlement recap returns when target selection closes")


func test_tutorial_dismiss_hides_and_emits() -> void:
	_setup()
	var dismissed := [0]
	_bp.tutorial_dismissed.connect(func(): dismissed[0] += 1)
	_bp.set_tutorial_enabled(true)

	_bp.get_node("TutorialHintPanel/VBox/TutorialDismissButton").pressed.emit()
	_state.bench[0] = CardInstance.create("sp_assembly")
	_state.state_changed.emit()

	assert_eq(dismissed[0], 1)
	assert_false(_bp.get_node("TutorialHintPanel").visible)
