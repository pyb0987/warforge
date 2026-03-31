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
	assert_eq(ShopScript.TIER_WEIGHTS.size(), 6, "6단계 상점 레벨")


func test_tier_weights_each_level_sums_to_100() -> void:
	for level in ShopScript.TIER_WEIGHTS:
		var weights: Dictionary = ShopScript.TIER_WEIGHTS[level]
		var total: int = 0
		for t in weights:
			total += weights[t]
		assert_eq(total, 100, "Lv%d 가중치 합 = 100" % level)


func test_tier_weights_lv1_only_t1() -> void:
	var w: Dictionary = ShopScript.TIER_WEIGHTS[1]
	assert_eq(w[1], 100, "Lv1: T1=100")
	assert_eq(w[2], 0, "Lv1: T2=0")


func test_tier_weights_lv6_no_t1_t2() -> void:
	var w: Dictionary = ShopScript.TIER_WEIGHTS[6]
	assert_eq(w[1], 0, "Lv6: T1=0")
	assert_eq(w[2], 0, "Lv6: T2=0")
	assert_eq(w[5], 50, "Lv6: T5=50")


# ================================================================
# _get_shop_level (라운드 기반)
# ================================================================

func test_shop_level_r1_is_1() -> void:
	_state.round_num = 1
	assert_eq(_shop._get_shop_level(), 1, "R1 → Lv1")


func test_shop_level_r3_is_2() -> void:
	_state.round_num = 3
	assert_eq(_shop._get_shop_level(), 2, "R3 → Lv2")


func test_shop_level_r5_is_3() -> void:
	_state.round_num = 5
	assert_eq(_shop._get_shop_level(), 3, "R5 → Lv3")


func test_shop_level_r7_is_4() -> void:
	_state.round_num = 7
	assert_eq(_shop._get_shop_level(), 4, "R7 → Lv4")


func test_shop_level_r9_is_5() -> void:
	_state.round_num = 9
	assert_eq(_shop._get_shop_level(), 5, "R9 → Lv5")


func test_shop_level_r12_is_6() -> void:
	_state.round_num = 12
	assert_eq(_shop._get_shop_level(), 6, "R12 → Lv6")


func test_shop_level_r2_still_1() -> void:
	_state.round_num = 2
	assert_eq(_shop._get_shop_level(), 1, "R2 → 아직 Lv1")


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


func test_pick_card_of_tier_excludes_s2() -> void:
	for _i in 50:
		var card_id: String = _shop._pick_card_of_tier(4)
		assert_false(card_id.ends_with("_s2"), "_s2 접미사 제외: %s" % card_id)


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
