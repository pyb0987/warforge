extends GutTest
## 전략가 영웅 능력 UI 상태 머신 테스트.
## 참조: build_phase.gd begin_strategist_swap / _select_strategist_swap_slot


const BuildPhaseScript = preload("res://scripts/build/build_phase.gd")

var _bp = null
var _state: GameState = null


func before_each() -> void:
	_bp = BuildPhaseScript.new()
	_state = GameState.new()
	_state.commander_type = Enums.CommanderType.STRATEGIST
	_state.commander_state["hero_used"] = false
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_workshop")
	_bp.game_state = _state


func after_each() -> void:
	if _bp != null:
		_bp.free()
		_bp = null


func test_begin_strategist_swap_requires_strategist() -> void:
	_state.commander_type = Enums.CommanderType.NONE
	assert_false(_bp.begin_strategist_swap(), "비전략가는 swap 모드 시작 불가")
	assert_false(_bp._strategist_swap_active, "swap 모드 비활성")


func test_begin_strategist_swap_requires_two_board_cards() -> void:
	_state.board[1] = null
	assert_false(_bp.begin_strategist_swap(), "보드 카드 2장 미만이면 불가")
	assert_false(_bp._strategist_swap_active, "swap 모드 비활성")


func test_begin_strategist_swap_rejects_already_used() -> void:
	_state.commander_state["hero_used"] = true
	assert_false(_bp.begin_strategist_swap(), "이미 사용한 빌드에서는 불가")
	assert_false(_bp._strategist_swap_active, "swap 모드 비활성")


func test_select_two_cards_swaps_and_ends_mode() -> void:
	var card_a: CardInstance = _state.board[0]
	var card_b: CardInstance = _state.board[1]
	assert_true(_bp.begin_strategist_swap(), "swap 모드 시작")
	assert_true(_bp._select_strategist_swap_slot(0), "첫 카드 선택")
	assert_true(_bp._select_strategist_swap_slot(1), "두 번째 카드 선택")

	assert_eq(_state.board[0], card_b, "보드 0에 B")
	assert_eq(_state.board[1], card_a, "보드 1에 A")
	assert_true(_state.commander_state["hero_used"], "영웅 능력 사용 처리")
	assert_false(_bp._strategist_swap_active, "교환 후 swap 모드 종료")
	assert_eq(_bp._strategist_swap_first_idx, -1, "첫 선택 초기화")


func test_clicking_same_card_keeps_waiting_for_second_card() -> void:
	assert_true(_bp.begin_strategist_swap(), "swap 모드 시작")
	assert_true(_bp._select_strategist_swap_slot(0), "첫 카드 선택")
	assert_false(_bp._select_strategist_swap_slot(0), "같은 카드 재선택은 교환 아님")
	assert_true(_bp._strategist_swap_active, "두 번째 카드 대기 유지")
	assert_eq(_bp._strategist_swap_first_idx, 0, "첫 선택 유지")


func test_cancel_strategist_swap_clears_selection() -> void:
	assert_true(_bp.begin_strategist_swap(), "swap 모드 시작")
	assert_true(_bp._select_strategist_swap_slot(0), "첫 카드 선택")
	_bp.cancel_strategist_swap()
	assert_false(_bp._strategist_swap_active, "취소 후 비활성")
	assert_eq(_bp._strategist_swap_first_idx, -1, "첫 선택 초기화")
