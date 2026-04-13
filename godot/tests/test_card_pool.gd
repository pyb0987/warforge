extends GutTest
## CardPool 카드 풀 고갈 메커니즘 테스트
## 참조: OBS-049, card_pool.gd
##
## TFT식 공유 카드 풀: 티어별 복사본 수 제한, 구매 시 소모, 판매/리롤 시 반환.


var _pool: CardPool = null


func before_each() -> void:
	_pool = CardPool.new()


func after_each() -> void:
	_pool = null


# ================================================================
# 초기화
# ================================================================

func test_init_pool_creates_entries_for_all_cards() -> void:
	_pool.init_pool()
	var all_ids := CardDB.get_all_ids()
	for id in all_ids:
		assert_gt(_pool.get_remaining(id), 0,
			"%s 초기 잔여 > 0" % id)


func test_init_pool_tier_sizes() -> void:
	## 기본값: T1=22, T2=18, T3=15, T4=13, T5=11
	_pool.init_pool()
	var expected := {1: 22, 2: 18, 3: 15, 4: 13, 5: 11}
	for id in CardDB.get_all_ids():
		var tmpl := CardDB.get_template(id)
		var tier: int = tmpl.get("tier", 1)
		assert_eq(_pool.get_remaining(id), expected[tier],
			"%s (T%d) 초기 = %d" % [id, tier, expected[tier]])


func test_init_pool_custom_sizes() -> void:
	_pool.init_pool({1: 10, 2: 8, 3: 6, 4: 4, 5: 2})
	for id in CardDB.get_all_ids():
		var tmpl := CardDB.get_template(id)
		var tier: int = tmpl.get("tier", 1)
		var expected_map := {1: 10, 2: 8, 3: 6, 4: 4, 5: 2}
		assert_eq(_pool.get_remaining(id), expected_map[tier],
			"%s 커스텀 크기" % id)


func test_init_pool_resets_existing() -> void:
	_pool.init_pool()
	_pool.draw("sp_assembly")
	_pool.init_pool()  # 재초기화
	assert_eq(_pool.get_remaining("sp_assembly"), 22,
		"재초기화 후 원래 크기 복원")


# ================================================================
# draw
# ================================================================

func test_draw_decrements() -> void:
	_pool.init_pool()
	var before: int = _pool.get_remaining("sp_assembly")
	var ok: bool = _pool.draw("sp_assembly")
	assert_true(ok, "draw 성공")
	assert_eq(_pool.get_remaining("sp_assembly"), before - 1, "1 감소")


func test_draw_to_zero() -> void:
	_pool.init_pool({1: 2, 2: 2, 3: 2, 4: 2, 5: 2})
	_pool.draw("sp_assembly")
	_pool.draw("sp_assembly")
	assert_eq(_pool.get_remaining("sp_assembly"), 0, "0까지 감소")


func test_draw_empty_returns_false() -> void:
	_pool.init_pool({1: 1, 2: 1, 3: 1, 4: 1, 5: 1})
	_pool.draw("sp_assembly")
	var ok: bool = _pool.draw("sp_assembly")
	assert_false(ok, "잔여 0 → draw 실패")
	assert_eq(_pool.get_remaining("sp_assembly"), 0, "음수 안 됨")


func test_draw_unknown_card_returns_false() -> void:
	_pool.init_pool()
	var ok: bool = _pool.draw("nonexistent_card")
	assert_false(ok, "미등록 카드 draw 실패")


# ================================================================
# return_cards
# ================================================================

func test_return_cards_increments() -> void:
	_pool.init_pool()
	_pool.draw("sp_assembly")
	_pool.draw("sp_assembly")
	_pool.return_cards("sp_assembly", 2)
	assert_eq(_pool.get_remaining("sp_assembly"), 22, "반환 후 원래 수량")


func test_return_cards_star2_returns_3() -> void:
	## ★2 판매 시 3장 반환
	_pool.init_pool()
	for _i in 3:
		_pool.draw("sp_assembly")
	assert_eq(_pool.get_remaining("sp_assembly"), 19, "3장 뽑은 후")
	_pool.return_cards("sp_assembly", 3)
	assert_eq(_pool.get_remaining("sp_assembly"), 22, "3장 반환")


func test_return_cards_star3_returns_9() -> void:
	## ★3 판매 시 9장 반환
	_pool.init_pool()
	for _i in 9:
		_pool.draw("sp_assembly")
	assert_eq(_pool.get_remaining("sp_assembly"), 13, "9장 뽑은 후")
	_pool.return_cards("sp_assembly", 9)
	assert_eq(_pool.get_remaining("sp_assembly"), 22, "9장 반환")


func test_return_cards_does_not_exceed_initial() -> void:
	## 초기 수량 초과 반환 방지
	_pool.init_pool()
	_pool.return_cards("sp_assembly", 5)
	assert_eq(_pool.get_remaining("sp_assembly"), 22,
		"초기값 초과 불가")


# ================================================================
# available_of_tier
# ================================================================

func test_available_of_tier_all_initially() -> void:
	_pool.init_pool()
	var t1_all: Array[String] = _pool.available_of_tier(1)
	# CardDB에 T1이 12종 있으므로 12종 모두 반환
	var expected_count := 0
	for id in CardDB.get_all_ids():
		if CardDB.get_template(id).get("tier", 0) == 1:
			expected_count += 1
	assert_eq(t1_all.size(), expected_count,
		"T1 전체 카드 사용 가능")


func test_available_of_tier_excludes_depleted() -> void:
	_pool.init_pool({1: 1, 2: 1, 3: 1, 4: 1, 5: 1})
	_pool.draw("sp_assembly")  # T1 카드 1장 → 0
	var t1: Array[String] = _pool.available_of_tier(1)
	assert_false(t1.has("sp_assembly"), "고갈된 카드 제외")


func test_available_of_tier_empty_when_all_depleted() -> void:
	_pool.init_pool({1: 1, 2: 1, 3: 1, 4: 1, 5: 1})
	# T1 전부 고갈
	for id in CardDB.get_all_ids():
		if CardDB.get_template(id).get("tier", 0) == 1:
			_pool.draw(id)
	var t1: Array[String] = _pool.available_of_tier(1)
	assert_eq(t1.size(), 0, "T1 전체 고갈 → 빈 배열")


# ================================================================
# get_remaining
# ================================================================

func test_get_remaining_unknown_returns_zero() -> void:
	_pool.init_pool()
	assert_eq(_pool.get_remaining("nonexistent"), 0, "미등록 = 0")


# ================================================================
# 가중 뽑기용 helpers
# ================================================================

func test_get_weighted_candidates() -> void:
	## available_of_tier 결과를 가중치 배열과 함께 사용할 수 있는지 확인
	_pool.init_pool()
	_pool.draw("sp_assembly")
	var candidates: Array[String] = _pool.available_of_tier(1)
	assert_true(candidates.has("sp_assembly"), "잔여 > 0이면 포함")
	# 잔여량 기반 가중치 사용 가능
	var weight: int = _pool.get_remaining("sp_assembly")
	assert_eq(weight, 21, "21장 남음 → 가중치 21")
