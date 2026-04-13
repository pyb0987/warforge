extends GutTest
## ShopLogic (RefCounted) 테스트.

const ShopLogicScript = preload("res://sim/shop_logic.gd")

var _shop: RefCounted = null
var _state: GameState = null
var _rng: RandomNumberGenerator = null


func before_each() -> void:
	_state = GameState.new()
	_state.gold = 20
	_state.terazin = 5
	_state.shop_level = 1
	_rng = RandomNumberGenerator.new()
	_rng.seed = 42
	_shop = ShopLogicScript.new()
	_shop.setup(_state, _rng)


func test_refresh_generates_cards() -> void:
	_shop.refresh_shop()
	assert_eq(_shop.offered_ids.size(), 6, "기본 상점 6장")
	for id in _shop.offered_ids:
		assert_ne(id, "", "빈 ID 없음")


func test_refresh_tier1_only_at_level1() -> void:
	_shop.refresh_shop()
	for id in _shop.offered_ids:
		var tmpl := CardDB.get_template(id)
		assert_eq(tmpl.get("tier", 0), 1, "레벨1 → T1만")


func test_refresh_higher_tiers_at_level4() -> void:
	_state.shop_level = 4
	_shop.refresh_shop()
	var has_high_tier := false
	for id in _shop.offered_ids:
		var tmpl := CardDB.get_template(id)
		if tmpl.get("tier", 0) >= 3:
			has_high_tier = true
	assert_true(has_high_tier, "레벨4 → T3+ 카드 존재")


func test_purchase_success() -> void:
	_shop.refresh_shop()
	var card_id: String = _shop.offered_ids[0]
	var cost: int = CardDB.get_template(card_id).get("cost", 99)
	var gold_before: int = _state.gold
	var result: bool = _shop.try_purchase(0)
	assert_true(result, "구매 성공")
	assert_eq(_state.gold, gold_before - cost, "골드 차감")
	assert_eq(_shop.offered_ids[0], "", "슬롯 비움")


func test_purchase_adds_to_bench() -> void:
	_shop.refresh_shop()
	_shop.try_purchase(0)
	var bench_has_card := false
	for card in _state.bench:
		if card != null:
			bench_has_card = true
			break
	assert_true(bench_has_card, "벤치에 카드 추가됨")


func test_purchase_not_enough_gold() -> void:
	_state.gold = 0
	_shop.refresh_shop()
	var result: bool = _shop.try_purchase(0)
	assert_false(result, "골드 부족 → 실패")


func test_purchase_bench_full() -> void:
	for i in Enums.MAX_BENCH_SLOTS:
		_state.bench[i] = CardInstance.create("sp_assembly")
	_shop.refresh_shop()
	var result: bool = _shop.try_purchase(0)
	assert_false(result, "벤치 풀 → 실패")


func test_purchase_empty_slot() -> void:
	_shop.refresh_shop()
	_shop.try_purchase(0)
	var result: bool = _shop.try_purchase(0)
	assert_false(result, "빈 슬롯 → 실패")


func test_reroll_costs_gold() -> void:
	_shop.refresh_shop()
	var gold_before: int = _state.gold
	var result: bool = _shop.reroll()
	assert_true(result, "리롤 성공")
	assert_eq(_state.gold, gold_before - Enums.REROLL_COST, "리롤 비용 차감")


func test_reroll_changes_cards() -> void:
	_shop.refresh_shop()
	var old_ids: Array = _shop.offered_ids.duplicate()
	_shop.reroll()
	var changed := false
	for i in old_ids.size():
		if i < _shop.offered_ids.size() and old_ids[i] != _shop.offered_ids[i]:
			changed = true
			break
	assert_true(changed, "리롤 후 카드 변경")


func test_reroll_not_enough_gold() -> void:
	_state.gold = 0
	_shop.refresh_shop()
	var result: bool = _shop.reroll()
	assert_false(result, "골드 부족 → 리롤 실패")


func test_auto_merge_on_purchase() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.bench[0] = CardInstance.create("sp_assembly")
	_shop.offered_ids.clear()
	_shop.offered_ids.append_array(["sp_assembly", "", "", "", "", ""] as Array[String])
	var ok: bool = _shop.try_purchase(0)
	assert_true(ok, "구매 성공")
	# try_merge가 성공하면 board[0]이 ★2가 됨
	var card: CardInstance = _state.board[0]
	assert_not_null(card, "보드에 카드 존재")
	if card != null:
		assert_eq(card.star_level, 2, "★2로 진화")


func test_deterministic_with_same_seed() -> void:
	_shop.refresh_shop()
	var ids_1: Array = _shop.offered_ids.duplicate()

	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 42
	var shop2 := ShopLogicScript.new()
	shop2.setup(_state, rng2)
	shop2.refresh_shop()
	var ids_2: Array = shop2.offered_ids.duplicate()

	assert_eq(ids_1, ids_2, "같은 시드 → 같은 카드")
