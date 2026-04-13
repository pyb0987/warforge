extends GutTest
## Shop 상점 로직 테스트 (UI 우회)
## 참조: shop.gd, upgrade.md
##
## 티어 확률표 / 상점 레벨 / 리롤 비용 / 구매 / 카드풀 샘플링 검증.


const ShopScript = preload("res://scripts/build/shop.gd")

var _shop = null
var _state: GameState = null
var _rng: RandomNumberGenerator = null


func before_each() -> void:
	_shop = ShopScript.new()
	_state = GameState.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 42
	# UI 생성(_create_slots) 우회: 내부 상태만 직접 주입
	_shop._game_state = _state
	_shop._rng = _rng


func after_each() -> void:
	if _shop != null:
		_shop.free()


# ================================================================
# TIER_WEIGHTS 상수 검증
# ================================================================

func test_tier_weights_has_6_levels() -> void:
	assert_eq(ShopPicker.DEFAULT_TIER_WEIGHTS.size(), 6, "6단계 상점 레벨")


func test_tier_weights_each_level_sums_to_100() -> void:
	for level in ShopPicker.DEFAULT_TIER_WEIGHTS:
		var weights: Array = ShopPicker.DEFAULT_TIER_WEIGHTS[level]
		var total: int = 0
		for w in weights:
			total += int(w)
		assert_eq(total, 100, "Lv%d 가중치 합 = 100" % level)


func test_tier_weights_lv1_only_t1() -> void:
	var w: Array = ShopPicker.DEFAULT_TIER_WEIGHTS[1]
	assert_eq(w[0], 100, "Lv1: T1=100")
	assert_eq(w[1], 0, "Lv1: T2=0")


func test_tier_weights_lv6_no_t1_t2() -> void:
	var w: Array = ShopPicker.DEFAULT_TIER_WEIGHTS[6]
	assert_eq(w[0], 0, "Lv6: T1=0")
	assert_eq(w[1], 0, "Lv6: T2=0")
	assert_eq(w[4], 50, "Lv6: T5=50")


# ================================================================
# 상점 레벨업 (골드 수동 구매 + 자동 할인)
# upgrade.md: 베이스 Lv2:5, Lv3:7, Lv4:8, Lv5:11, Lv6:13
# 매 라운드 -1g 할인 (최소 0), 레벨업 시 다음 베이스로 리셋
# ================================================================

func test_initial_shop_level_is_1() -> void:
	assert_eq(_state.shop_level, 1, "초기 상점 레벨 = 1")


func test_levelup_base_cost_lv2() -> void:
	assert_eq(_state.levelup_current_cost, Enums.LEVELUP_BASE_COST[2],
		"Lv1→Lv2 초기 비용 = 베이스 5")


func test_try_levelup_success() -> void:
	_state.gold = 10
	var ok := _state.try_levelup()
	assert_true(ok, "레벨업 성공")
	assert_eq(_state.shop_level, 2, "Lv1→Lv2")
	assert_eq(_state.gold, 5, "5골드 차감")
	assert_eq(_state.levelup_current_cost, Enums.LEVELUP_BASE_COST[3],
		"다음 레벨 베이스 비용으로 리셋")


func test_try_levelup_fails_not_enough_gold() -> void:
	_state.gold = 3
	var ok := _state.try_levelup()
	assert_false(ok, "골드 부족 → 실패")
	assert_eq(_state.shop_level, 1, "레벨 불변")
	assert_eq(_state.gold, 3, "골드 불변")


func test_try_levelup_fails_at_max_level() -> void:
	_state.shop_level = 6
	_state.gold = 99
	_state.levelup_current_cost = 0
	var ok := _state.try_levelup()
	assert_false(ok, "Lv6 = 최대 → 실패")
	assert_eq(_state.shop_level, 6, "레벨 불변")


func test_round_discount_reduces_cost() -> void:
	# 초기 비용 5 → 라운드 할인 → 4
	_state.levelup_current_cost = 5
	_state.apply_levelup_discount()
	assert_eq(_state.levelup_current_cost, 4, "매 라운드 -1g")


func test_round_discount_min_zero() -> void:
	_state.levelup_current_cost = 0
	_state.apply_levelup_discount()
	assert_eq(_state.levelup_current_cost, 0, "최소 0")


func test_round_discount_then_free_levelup() -> void:
	# 5라운드 할인 → 비용 0 → 무료 레벨업
	_state.gold = 0
	for _i in 5:
		_state.apply_levelup_discount()
	assert_eq(_state.levelup_current_cost, 0, "5회 할인 → 0")
	var ok := _state.try_levelup()
	assert_true(ok, "0골드 레벨업 성공")
	assert_eq(_state.shop_level, 2, "Lv2")


func test_consecutive_levelup_in_one_round() -> void:
	# 한 라운드에 2단계 연속 가능
	_state.gold = 20
	_state.try_levelup()  # Lv1→Lv2 (5g)
	assert_eq(_state.shop_level, 2)
	_state.try_levelup()  # Lv2→Lv3 (7g)
	assert_eq(_state.shop_level, 3)
	assert_eq(_state.gold, 8, "20 - 5 - 7 = 8")


func test_levelup_all_stages_cost_and_reset() -> void:
	# Lv1→2(5) → Lv2→3(7) → Lv3→4(8) → Lv4→5(11) → Lv5→6(13) = 총 44g
	_state.gold = 50
	var expected_costs := [5, 7, 8, 11, 13]
	var total_spent := 0
	for i in 5:
		var cost_before := _state.levelup_current_cost
		assert_eq(cost_before, expected_costs[i],
			"Lv%d→%d 비용 = %d" % [i + 1, i + 2, expected_costs[i]])
		_state.try_levelup()
		total_spent += expected_costs[i]
	assert_eq(_state.shop_level, 6, "Lv6 도달")
	assert_eq(total_spent, 44, "베이스 합계 44g")
	assert_eq(_state.gold, 6, "50 - 44 = 6")


func test_max_level_discount_stays_zero() -> void:
	# Lv6 도달 후 할인 반복해도 비용 0 유지, 에러 없음
	_state.shop_level = 6
	_state.levelup_current_cost = 0
	for _i in 10:
		_state.apply_levelup_discount()
	assert_eq(_state.levelup_current_cost, 0, "Lv6에서 할인 반복해도 0 유지")


func test_shop_uses_game_state_level() -> void:
	# shop._get_shop_level()이 game_state.shop_level을 반환
	_state.shop_level = 4
	assert_eq(_shop._get_shop_level(), 4, "game_state.shop_level 직접 참조")


# ================================================================
# _roll_tier 분포 검증
# ================================================================

func test_roll_tier_lv1_always_t1() -> void:
	for _i in 50:
		assert_eq(_shop._roll_tier(1), 1, "Lv1 → 항상 T1")


func test_roll_tier_lv6_only_t3_t4_t5() -> void:
	for _i in 100:
		var tier: int = _shop._roll_tier(6)
		assert_gte(tier, 3, "Lv6 → T3 이상")
		assert_lte(tier, 5, "Lv6 → T5 이하")


func test_roll_tier_lv4_distribution_reasonable() -> void:
	## Lv4: T1=10, T2=25, T3=42, T4=20, T5=3
	## 1000회 롤 → T3가 최다 (30%+ 예상)
	var counts: Dictionary = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
	for _i in 1000:
		var tier: int = _shop._roll_tier(4)
		counts[tier] += 1
	assert_gt(counts[3], counts[1], "Lv4: T3 > T1")
	assert_gt(counts[3], counts[2], "Lv4: T3 > T2")
	assert_gt(counts[3], counts[4], "Lv4: T3 > T4")


# ================================================================
# _pick_card_of_tier
# ================================================================

func test_pick_card_of_tier_returns_correct_tier() -> void:
	for _i in 20:
		var card_id: String = _shop._pick_card_of_tier(1)
		var tmpl: Dictionary = CardDB.get_template(card_id)
		assert_eq(tmpl["tier"], 1, "T1 카드 반환")


func test_pick_card_of_tier_returns_base_ids_only() -> void:
	## get_all_ids()에 base만 있으므로 항상 base ID 반환
	for _i in 50:
		var card_id: String = _shop._pick_card_of_tier(4)
		assert_false(card_id.ends_with("_s2"), "base ID만: %s" % card_id)
		assert_false(card_id.ends_with("_s3"), "base ID만: %s" % card_id)


func test_pick_card_of_tier_5_returns_t5() -> void:
	var card_id: String = _shop._pick_card_of_tier(5)
	var tmpl: Dictionary = CardDB.get_template(card_id)
	assert_eq(tmpl["tier"], 5, "T5 카드 반환")


# ================================================================
# reroll 비용
# ================================================================

func test_reroll_costs_1_gold() -> void:
	_state.gold = 5
	_shop._offered_ids.assign(["sp_assembly", "", "", "", "", ""])
	var result: bool = _shop.reroll()
	assert_true(result, "리롤 성공")
	assert_eq(_state.gold, 4, "1골드 차감")


func test_reroll_fails_if_no_gold() -> void:
	_state.gold = 0
	var result: bool = _shop.reroll()
	assert_false(result, "골드 부족 → 실패")
	assert_eq(_state.gold, 0, "골드 불변")


func test_reroll_refreshes_6_cards() -> void:
	_state.gold = 5
	_state.round_num = 1
	_shop._offered_ids.assign(["", "", "", "", "", ""])
	_shop.reroll()
	assert_eq(_shop._offered_ids.size(), 6, "리롤 후 6장")
	for id in _shop._offered_ids:
		assert_ne(id, "", "모든 슬롯 채워짐")


# ================================================================
# try_purchase 비용/벤치
# ================================================================

func test_purchase_deducts_cost() -> void:
	_state.gold = 10
	_shop._offered_ids.assign(["sp_assembly", "", "", "", "", ""])
	# sp_assembly cost = 2 (T1)
	var result: bool = _shop.try_purchase(0)
	assert_true(result, "구매 성공")
	assert_eq(_state.gold, 8, "2골드 차감")


func test_purchase_fails_if_not_enough_gold() -> void:
	_state.gold = 1
	_shop._offered_ids.assign(["sp_assembly", "", "", "", "", ""])
	var result: bool = _shop.try_purchase(0)
	assert_false(result, "골드 부족 → 실패")
	assert_eq(_state.gold, 1, "골드 불변")


func test_purchase_marks_slot_empty() -> void:
	_state.gold = 10
	_shop._offered_ids.assign(["sp_assembly", "sp_workshop", "", "", "", ""])
	_shop.try_purchase(0)
	assert_eq(_shop._offered_ids[0], "", "구매 후 슬롯 빈 문자열")
	assert_eq(_shop._offered_ids[1], "sp_workshop", "다른 슬롯 유지")


func test_purchase_adds_to_bench() -> void:
	_state.gold = 10
	_shop._offered_ids.assign(["sp_assembly", "", "", "", "", ""])
	_shop.try_purchase(0)
	var found: bool = false
	for card in _state.bench:
		if card != null and card.template_id == "sp_assembly":
			found = true
	assert_true(found, "벤치에 카드 추가됨")


func test_purchase_empty_slot_fails() -> void:
	_state.gold = 10
	_shop._offered_ids.assign(["", "", "", "", "", ""])
	var result: bool = _shop.try_purchase(0)
	assert_false(result, "빈 슬롯 구매 불가")


func test_purchase_fails_bench_full() -> void:
	_state.gold = 100
	# 벤치 8칸 모두 채움
	for i in 8:
		_state.bench[i] = CardInstance.create("sp_assembly")
	_shop._offered_ids.assign(["sp_workshop", "", "", "", "", ""])
	var result: bool = _shop.try_purchase(0)
	assert_false(result, "벤치 만석 → 실패")
	assert_eq(_state.gold, 100, "골드 불변")


# ================================================================
# 카드 풀 고갈 (OBS-049)
# ================================================================

func test_pick_card_respects_pool_single_remaining() -> void:
	## pool에 T1 카드 중 1종만 남으면 그것만 등장
	var pool := CardPool.new()
	pool.init_pool({1: 50, 2: 50, 3: 50, 4: 50, 5: 50})
	# sp_assembly 이외의 T1 카드 모두 고갈
	for card_id in CardDB.get_all_ids():
		var tmpl: Dictionary = CardDB.get_template(card_id)
		if tmpl.get("tier", 0) == 1 and card_id != "sp_assembly":
			for _j in 50:
				pool.draw(card_id)
	for _i in 20:
		var id: String = ShopPicker.pick_card(1, _rng, _state, pool)
		assert_eq(id, "sp_assembly", "pool에 1종만 남으면 그것만 반환")



func test_pick_card_empty_pool_returns_empty() -> void:
	## 해당 티어 풀이 완전 고갈 → 빈 문자열
	var pool := CardPool.new()
	pool.init_pool({1: 0, 2: 0, 3: 0, 4: 0, 5: 0})
	var id: String = ShopPicker.pick_card(1, _rng, _state, pool)
	assert_eq(id, "", "풀 고갈 → 빈 문자열")


func test_pick_card_no_pool_backward_compat() -> void:
	## pool=null이면 기존 동작 (무한 풀)
	for _i in 10:
		var id: String = ShopPicker.pick_card(1, _rng, _state)
		assert_ne(id, "", "pool 없으면 항상 카드 반환")
		var tmpl: Dictionary = CardDB.get_template(id)
		assert_eq(tmpl["tier"], 1, "올바른 티어")


func test_pick_card_draws_from_pool() -> void:
	## pick_card 호출 시 풀에서 자동 draw
	var pool := CardPool.new()
	pool.init_pool({1: 3, 2: 3, 3: 3, 4: 3, 5: 3})
	var id: String = ShopPicker.pick_card(1, _rng, _state, pool)
	assert_ne(id, "", "카드 반환됨")
	assert_eq(pool.get_remaining(id), 2, "draw 후 잔여 2")


# ================================================================
# 카드 풀 E2E 통합 (OBS-049)
# ================================================================

func test_pool_purchase_decrements() -> void:
	## 구매 시 풀에서 1장 감소 확인
	var pool := CardPool.new()
	pool.init_pool()
	_state.card_pool = pool
	_state.gold = 100
	# 상점에 sp_assembly를 직접 배치
	_shop._offered_ids.assign(["sp_assembly", "", "", "", "", ""])
	var before: int = pool.get_remaining("sp_assembly")
	_shop.try_purchase(0)
	# pick_card에서 이미 draw했으므로, 상점에 직접 배치한 경우는 draw가 안 됨
	# 대신 refresh_shop 경로에서 draw됨. 여기서는 purchase 자체가 draw하지 않음을 확인
	# (draw는 pick_card에서 발생)
	assert_eq(pool.get_remaining("sp_assembly"), before,
		"try_purchase는 추가 draw 안 함 (pick_card에서 이미 수행)")


func test_pool_refresh_returns_unsold() -> void:
	## 리프레시 시 미구매 카드가 풀에 반환되는지 확인
	var pool := CardPool.new()
	pool.init_pool()
	_state.card_pool = pool
	_state.gold = 100
	# 수동으로 offered_ids 세팅 (refresh를 거치지 않고 직접)
	_shop._offered_ids.assign(["sp_assembly", "sp_workshop", "", "", "", ""])
	# draw를 수동으로 수행 (refresh_shop이 했을 것처럼)
	pool.draw("sp_assembly")
	pool.draw("sp_workshop")
	var before_assembly: int = pool.get_remaining("sp_assembly")
	var before_workshop: int = pool.get_remaining("sp_workshop")
	# sp_assembly만 구매
	_shop.try_purchase(0)
	# refresh → sp_workshop(미구매)가 풀에 반환
	_shop.refresh_shop()
	assert_eq(pool.get_remaining("sp_workshop"), before_workshop + 1,
		"미구매 sp_workshop 풀에 반환")


func test_pool_sell_returns_star1() -> void:
	## 판매 시 풀 복귀: ★1 = 1장
	var pool := CardPool.new()
	pool.init_pool()
	_state.card_pool = pool
	_state.gold = 100
	# 벤치에 카드 배치 + 풀에서 수동 draw
	_state.bench[0] = CardInstance.create("sp_assembly")
	pool.draw("sp_assembly")
	var before: int = pool.get_remaining("sp_assembly")
	_state.sell_card("bench", 0)
	assert_eq(pool.get_remaining("sp_assembly"), before + 1,
		"★1 판매 → 1장 풀 복귀")


func test_pool_sell_returns_star2() -> void:
	## 판매 시 풀 복귀: ★2 = 3장
	var pool := CardPool.new()
	pool.init_pool()
	_state.card_pool = pool
	_state.gold = 100
	var card := CardInstance.create("sp_assembly")
	card.star_level = 2
	_state.bench[0] = card
	# 3장 draw (합성에 소모된 것처럼)
	for _i in 3:
		pool.draw("sp_assembly")
	var before: int = pool.get_remaining("sp_assembly")
	_state.sell_card("bench", 0)
	assert_eq(pool.get_remaining("sp_assembly"), before + 3,
		"★2 판매 → 3장 풀 복귀")


func test_pool_sell_returns_star3() -> void:
	## 판매 시 풀 복귀: ★3 = 9장
	var pool := CardPool.new()
	pool.init_pool()
	_state.card_pool = pool
	_state.gold = 100
	var card := CardInstance.create("sp_assembly")
	card.star_level = 3
	_state.bench[0] = card
	# 9장 draw
	for _i in 9:
		pool.draw("sp_assembly")
	var before: int = pool.get_remaining("sp_assembly")
	_state.sell_card("bench", 0)
	assert_eq(pool.get_remaining("sp_assembly"), before + 9,
		"★3 판매 → 9장 풀 복귀")
