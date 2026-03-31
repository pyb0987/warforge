extends GutTest
## ChainEngine _resolve_targets 타겟팅 로직 테스트
## 참조: chain_engine.gd _resolve_targets
##
## self / right_adj / both_adj / all_allies / event_target / 경계 케이스 검증.


var _engine: ChainEngine = null


func before_each() -> void:
	_engine = ChainEngine.new()
	_engine.set_seed(42)


# ================================================================
# "self" 타겟
# ================================================================

func test_self_returns_card_idx() -> void:
	var result: Array[int] = _engine._resolve_targets("self", 2, -1, 5)
	assert_eq(result, [2] as Array[int], "self → [card_idx]")


# ================================================================
# "right_adj" 타겟
# ================================================================

func test_right_adj_middle() -> void:
	var result: Array[int] = _engine._resolve_targets("right_adj", 1, -1, 5)
	assert_eq(result, [2] as Array[int], "idx=1 → right=[2]")


func test_right_adj_first() -> void:
	var result: Array[int] = _engine._resolve_targets("right_adj", 0, -1, 3)
	assert_eq(result, [1] as Array[int], "idx=0 → right=[1]")


func test_right_adj_last_empty() -> void:
	var result: Array[int] = _engine._resolve_targets("right_adj", 4, -1, 5)
	assert_eq(result.size(), 0, "idx=last → right 없음")


func test_right_adj_single_card() -> void:
	var result: Array[int] = _engine._resolve_targets("right_adj", 0, -1, 1)
	assert_eq(result.size(), 0, "보드 1장 → right 없음")


# ================================================================
# "both_adj" 타겟
# ================================================================

func test_both_adj_middle() -> void:
	var result: Array[int] = _engine._resolve_targets("both_adj", 2, -1, 5)
	assert_eq(result.size(), 2, "중앙 → 양쪽")
	assert_true(1 in result, "left adj")
	assert_true(3 in result, "right adj")


func test_both_adj_first() -> void:
	var result: Array[int] = _engine._resolve_targets("both_adj", 0, -1, 5)
	assert_eq(result.size(), 1, "첫 번째 → right만")
	assert_eq(result[0], 1, "right=1")


func test_both_adj_last() -> void:
	var result: Array[int] = _engine._resolve_targets("both_adj", 4, -1, 5)
	assert_eq(result.size(), 1, "마지막 → left만")
	assert_eq(result[0], 3, "left=3")


func test_both_adj_single_card() -> void:
	var result: Array[int] = _engine._resolve_targets("both_adj", 0, -1, 1)
	assert_eq(result.size(), 0, "보드 1장 → 양쪽 없음")


# ================================================================
# "all_allies" 타겟
# ================================================================

func test_all_allies_returns_all_indices() -> void:
	var result: Array[int] = _engine._resolve_targets("all_allies", 0, -1, 4)
	assert_eq(result.size(), 4, "4장 보드 → 4개")
	for i in 4:
		assert_true(i in result, "idx %d 포함" % i)


func test_all_allies_single() -> void:
	var result: Array[int] = _engine._resolve_targets("all_allies", 0, -1, 1)
	assert_eq(result, [0] as Array[int], "1장 → [0]")


# ================================================================
# "event_target" 타겟
# ================================================================

func test_event_target_valid_idx() -> void:
	var result: Array[int] = _engine._resolve_targets("event_target", 0, 3, 5)
	assert_eq(result, [3] as Array[int], "event_target=3 → [3]")


func test_event_target_negative_returns_empty() -> void:
	var result: Array[int] = _engine._resolve_targets("event_target", 0, -1, 5)
	assert_eq(result.size(), 0, "event_target=-1 → 빈 배열")


# ================================================================
# 미지원 타겟
# ================================================================

func test_unknown_target_returns_empty() -> void:
	var result: Array[int] = _engine._resolve_targets("nonexistent", 0, -1, 5)
	assert_eq(result.size(), 0, "미지원 → 빈 배열")
