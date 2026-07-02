extends GutTest
## BuildPhase in-run tutorial hint contract for G-8.

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


func test_tutorial_prompts_upgrade_target_during_pending_purchase() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_setup()
	_set_upgrade_offers(["C1"])
	_bp.set_tutorial_enabled(true)

	_begin_shop_upgrade_purchase("C1", 0)

	assert_string_contains(_bp.get_tutorial_hint_text(), "업그레이드 대상 선택")
	assert_string_contains(_bp.get_tutorial_hint_text(), "슬롯 표시")


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
