extends GutTest
## ★합성 시스템 테스트
## 참조: game_state.gd try_merge, card_instance.gd evolve_star/multiply_stats
##
## ★1×3→★2 / ★2×3→★3 / 유닛 흡수 / 스탯 보너스 / 실패 케이스 검증.


var _state: GameState = null


func before_each() -> void:
	_state = GameState.new()


# ================================================================
# try_merge 기본 성공
# ================================================================

func test_merge_3_star1_returns_star2() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_assembly")
	_state.board[2] = CardInstance.create("sp_assembly")
	var result: Dictionary = _state.try_merge("sp_assembly")
	assert_false(result.is_empty(), "3장 → 합성 성공")
	assert_eq(result["old_star"], 1, "이전 ★1")
	assert_eq(result["new_star"], 2, "합성 후 ★2")


func test_merge_survivor_is_first_copy() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_assembly")
	_state.board[2] = CardInstance.create("sp_assembly")
	var first_card: CardInstance = _state.board[0]
	var result: Dictionary = _state.try_merge("sp_assembly")
	assert_eq(result["card"], first_card, "첫 번째 카드가 생존자")


func test_merge_removes_2_donors() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_assembly")
	_state.board[2] = CardInstance.create("sp_assembly")
	_state.try_merge("sp_assembly")
	assert_eq(_state.board[1], null, "두 번째 슬롯 비워짐")
	assert_eq(_state.board[2], null, "세 번째 슬롯 비워짐")
	assert_ne(_state.board[0], null, "생존자 유지")


func test_merge_absorbs_donor_units() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_assembly")
	_state.board[2] = CardInstance.create("sp_assembly")
	var units_one: int = _state.board[0].get_total_units()
	_state.try_merge("sp_assembly")
	# 3장의 유닛이 1장에 합산
	assert_eq(_state.board[0].get_total_units(), units_one * 3, "유닛 3배 흡수")


# ================================================================
# ★1→★2 보너스: multiply_stats(0.30)
# ================================================================

func test_star2_merge_applies_130_multiplier() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_assembly")
	_state.board[2] = CardInstance.create("sp_assembly")
	var atk_before: float = _state.board[0].get_total_atk()
	_state.try_merge("sp_assembly")
	# ★2 보너스: ×1.30 ATK + 유닛 흡수(3배) → ATK = base_atk * 3 * 1.30
	var expected: float = atk_before * 3.0 * 1.30
	assert_almost_eq(_state.board[0].get_total_atk(), expected, expected * 0.01, "★2 ATK ×1.30 적용")


# ================================================================
# ★2→★3 합성
# ================================================================

func test_merge_3_star2_returns_star3() -> void:
	for i in 3:
		var card: CardInstance = CardInstance.create("sp_assembly")
		card.evolve_star()  # ★1→★2
		_state.board[i] = card
	var result: Dictionary = _state.try_merge("sp_assembly")
	assert_false(result.is_empty(), "★2 ×3 → 합성 성공")
	assert_eq(result["old_star"], 2, "이전 ★2")
	assert_eq(result["new_star"], 3, "합성 후 ★3")


func test_star3_merge_no_extra_multiplier() -> void:
	## ★2→★3은 multiply_stats 보너스 없음 (old_star==1일 때만)
	for i in 3:
		var card: CardInstance = CardInstance.create("sp_assembly")
		card.evolve_star()
		_state.board[i] = card
	var atk_before: float = _state.board[0].get_total_atk()
	var units_one: int = _state.board[0].get_total_units()
	_state.try_merge("sp_assembly")
	# 유닛 3배 흡수만, multiply_stats 없음
	var expected: float = atk_before * float(units_one * 3) / float(units_one)
	assert_almost_eq(_state.board[0].get_total_atk(), expected, expected * 0.01, "★3 ATK = 유닛 흡수만")


# ================================================================
# 실패 케이스
# ================================================================

func test_merge_fails_with_only_2_copies() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_assembly")
	var result: Dictionary = _state.try_merge("sp_assembly")
	assert_true(result.is_empty(), "2장 → 합성 불가")


func test_merge_fails_with_different_cards() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_workshop")
	_state.board[2] = CardInstance.create("sp_furnace")
	var result: Dictionary = _state.try_merge("sp_assembly")
	assert_true(result.is_empty(), "다른 카드 → 합성 불가")


func test_merge_fails_with_mixed_star_levels() -> void:
	## ★1 ×2 + ★2 ×1 → 같은 ★ 3장이 아니므로 합성 불가
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_assembly")
	var star2: CardInstance = CardInstance.create("sp_assembly")
	star2.evolve_star()
	_state.board[2] = star2
	var result: Dictionary = _state.try_merge("sp_assembly")
	# ★1이 2장뿐 → 합성 불가
	assert_true(result.is_empty(), "★1×2 + ★2×1 → 합성 불가")


func test_merge_no_cards_returns_empty() -> void:
	var result: Dictionary = _state.try_merge("sp_assembly")
	assert_true(result.is_empty(), "카드 없음 → 빈 결과")


# ================================================================
# 보드+벤치 교차 합성
# ================================================================

func test_merge_across_board_and_bench() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.bench[0] = CardInstance.create("sp_assembly")
	_state.bench[1] = CardInstance.create("sp_assembly")
	var result: Dictionary = _state.try_merge("sp_assembly")
	assert_false(result.is_empty(), "보드1 + 벤치2 = 3장 → 합성 성공")
	assert_eq(result["new_star"], 2, "★2")


func test_merge_donors_removed_from_bench() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.bench[0] = CardInstance.create("sp_assembly")
	_state.bench[1] = CardInstance.create("sp_assembly")
	_state.try_merge("sp_assembly")
	assert_eq(_state.bench[0], null, "벤치 도너 1 제거")
	assert_eq(_state.bench[1], null, "벤치 도너 2 제거")


# ================================================================
# evolve_star 개별 검증
# ================================================================

func test_evolve_star_increments_level() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	assert_eq(card.star_level, 1, "초기 ★1")
	card.evolve_star()
	assert_eq(card.star_level, 2, "진화 후 ★2")
	card.evolve_star()
	assert_eq(card.star_level, 3, "진화 후 ★3")


func test_evolve_star_capped_at_3() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	card.evolve_star()  # ★2
	card.evolve_star()  # ★3
	card.evolve_star()  # 여전히 ★3
	assert_eq(card.star_level, 3, "★3 초과 불가")


func test_evolve_star_resets_threshold_fired() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	card.threshold_fired = true
	card.evolve_star()
	assert_false(card.threshold_fired, "진화 시 threshold 리셋")
