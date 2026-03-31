extends GutTest
## GameState 동작 테스트
## 참조: game_state.gd, handoff.md P2
##
## 초기 상태 / 이자 / 벤치 관리 / 카드 이동 / 판매 / 합성을 검증.


var _gs: GameState = null


func before_each() -> void:
	_gs = GameState.new()


# ================================================================
# 초기 상태
# ================================================================

func test_initial_gold_zero() -> void:
	assert_eq(_gs.gold, 0, "초기 골드 0")


func test_initial_hp_30() -> void:
	assert_eq(_gs.hp, 30, "초기 HP 30")


func test_board_size_8() -> void:
	assert_eq(_gs.board.size(), 8, "보드 8칸")


func test_bench_size_8() -> void:
	assert_eq(_gs.bench.size(), 8, "벤치 8칸")


func test_initial_board_count_0() -> void:
	assert_eq(_gs.board_count(), 0, "초기 보드 카드 0")


# ================================================================
# calc_interest
# ================================================================

func test_interest_zero_gold() -> void:
	_gs.gold = 0
	assert_eq(_gs.calc_interest(), 0, "골드 0 → 이자 0")


func test_interest_5_gold() -> void:
	_gs.gold = 5
	assert_eq(_gs.calc_interest(), 1, "골드 5 → 이자 1")


func test_interest_100_gold_capped() -> void:
	_gs.gold = 100
	assert_eq(_gs.calc_interest(), 2, "골드 100 → 이자 상한 2")


# ================================================================
# 벤치 관리
# ================================================================

func test_add_to_bench_first_slot_index_0() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	var idx: int = _gs.add_to_bench(card)
	assert_eq(idx, 0, "첫 빈 슬롯 = 0")
	assert_eq(_gs.bench[0], card, "벤치[0]에 카드 배치")


func test_add_to_bench_full_returns_minus1() -> void:
	for i in 8:
		_gs.bench[i] = CardInstance.create("sp_assembly")
	var card: CardInstance = CardInstance.create("sp_assembly")
	var idx: int = _gs.add_to_bench(card)
	assert_eq(idx, -1, "벤치 만석 → -1")


# ================================================================
# remove_card / sell_card
# ================================================================

func test_remove_card_returns_card_and_nulls_slot() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	_gs.board[0] = card
	var removed: CardInstance = _gs.remove_card("board", 0)
	assert_eq(removed, card, "제거된 카드 반환")
	assert_null(_gs.board[0], "슬롯 null 처리")


func test_remove_card_null_slot_returns_null() -> void:
	var removed: CardInstance = _gs.remove_card("board", 0)
	assert_null(removed, "빈 슬롯 → null")


func test_sell_card_tier1_refunds_2_gold() -> void:
	## sp_assembly: tier1, cost=2, refund=2×1.0=2
	var card: CardInstance = CardInstance.create("sp_assembly")
	_gs.board[0] = card
	_gs.gold = 0
	var refund: int = _gs.sell_card("board", 0)
	assert_eq(refund, 2, "환급 2골드")
	assert_eq(_gs.gold, 2, "골드 잔액 2")


# ================================================================
# move_card
# ================================================================

func test_move_bench_to_board_success() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	_gs.bench[0] = card
	var result: bool = _gs.move_card("bench", 0, "board", 0)
	assert_true(result, "이동 성공")
	assert_eq(_gs.board[0], card, "보드[0]에 카드")
	assert_null(_gs.bench[0], "벤치[0] 비워짐")


func test_move_swaps_if_target_occupied() -> void:
	var card_a: CardInstance = CardInstance.create("sp_assembly")
	var card_b: CardInstance = CardInstance.create("sp_workshop")
	_gs.board[0] = card_a
	_gs.board[1] = card_b
	var result: bool = _gs.move_card("board", 0, "board", 1)
	assert_true(result, "스왑 성공")
	assert_eq(_gs.board[0], card_b, "board[0] = B")
	assert_eq(_gs.board[1], card_a, "board[1] = A")


func test_move_card_null_source_returns_false() -> void:
	var result: bool = _gs.move_card("board", 0, "board", 1)
	assert_false(result, "빈 소스 → false")


# ================================================================
# try_merge
# ================================================================

func test_try_merge_3_copies_star1_to_star2() -> void:
	for i in 3:
		_gs.board[i] = CardInstance.create("sp_assembly")
	var result: Dictionary = _gs.try_merge("sp_assembly")
	assert_eq(result.get("old_star", -1), 1, "이전 ★1")
	assert_eq(result.get("new_star", -1), 2, "합성 후 ★2")


func test_try_merge_removes_2_copies_from_board() -> void:
	for i in 3:
		_gs.board[i] = CardInstance.create("sp_assembly")
	_gs.try_merge("sp_assembly")
	# board[0]에 생존자, board[1], board[2]는 null
	assert_not_null(_gs.board[0], "생존자 존재")
	assert_null(_gs.board[1], "기증자 1 제거")
	assert_null(_gs.board[2], "기증자 2 제거")


func test_try_merge_applies_130_stat_boost() -> void:
	## ★1→★2 합성 시 multiply_stats(0.30, 0.30)
	var base_card: CardInstance = CardInstance.create("sp_assembly")
	var base_atk: float = base_card.get_total_atk()
	var base_units: int = base_card.get_total_units()
	for i in 3:
		_gs.board[i] = CardInstance.create("sp_assembly")
	var result: Dictionary = _gs.try_merge("sp_assembly")
	var merged: CardInstance = result["card"]
	# 유닛 3배 흡수 (3장 × 3기 = 9기) + ×1.30 스탯
	assert_eq(merged.get_total_units(), base_units * 3, "유닛 3배 흡수")
	assert_gt(merged.get_total_atk(), base_atk * 3.0 * 1.29, "ATK > base×3×1.29")


func test_try_merge_below_3_returns_empty() -> void:
	_gs.board[0] = CardInstance.create("sp_assembly")
	_gs.board[1] = CardInstance.create("sp_assembly")
	var result: Dictionary = _gs.try_merge("sp_assembly")
	assert_true(result.is_empty(), "2장 → 합성 불가")


func test_try_merge_star2_to_star3() -> void:
	## sp_assembly는 T1이라 ★2 전용 템플릿 없음 → evolve 후에도 template_id 유지
	for i in 3:
		var card: CardInstance = CardInstance.create("sp_assembly")
		card.evolve_star()  # ★1→★2, template_id 그대로 "sp_assembly"
		_gs.board[i] = card
	var result: Dictionary = _gs.try_merge("sp_assembly")
	assert_eq(result.get("old_star", -1), 2, "이전 ★2")
	assert_eq(result.get("new_star", -1), 3, "합성 후 ★3")


func test_try_merge_mixed_stars_no_merge() -> void:
	## ★1 2장 + ★2 1장 = 같은 template_id지만 star_level 불일치 → 합성 불가
	_gs.board[0] = CardInstance.create("sp_assembly")
	_gs.board[1] = CardInstance.create("sp_assembly")
	var star2: CardInstance = CardInstance.create("sp_assembly")
	star2.evolve_star()
	_gs.board[2] = star2
	var result: Dictionary = _gs.try_merge("sp_assembly")
	assert_true(result.is_empty(), "혼합 ★ → 합성 불가")
