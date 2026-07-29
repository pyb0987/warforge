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


func _count_min_tier(ids: Array, min_tier: int) -> int:
	var count := 0
	for id in ids:
		if String(id) == "":
			continue
		var tmpl: Dictionary = CardDB.get_template(String(id))
		if int(tmpl.get("tier", 0)) >= min_tier:
			count += 1
	return count


func _connect_reroll_triggers(engine: ChainEngine) -> void:
	_shop.set_reroll_trigger_callback(func():
		var result: Dictionary = engine.process_reroll_triggers(_state.get_active_board())
		_state.terazin += int(result.get("terazin", 0))
		_state.gold += int(result.get("gold", 0))
		var levelup_discount: int = int(result.get("levelup_discount", 0))
		if levelup_discount > 0:
			_state.apply_levelup_discount(levelup_discount)
		return result
	)


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


func test_collector_first_shop_guarantees_four_t2_plus() -> void:
	_state.commander_type = Enums.CommanderType.COLLECTOR
	_state.round_num = 1
	_shop.refresh_shop()

	assert_gte(_count_min_tier(_shop.offered_ids, 2), 4,
		"수집가 첫 상점 → T2+ 4장 이상")
	assert_true(_state.commander_state.get("collector_start_shop_used", false),
		"첫 상점 보장 사용 플래그 기록")


func test_collector_start_shop_guarantee_only_once() -> void:
	_state.commander_type = Enums.CommanderType.COLLECTOR
	_state.round_num = 1
	_shop.refresh_shop()
	_shop.refresh_shop()

	assert_eq(_count_min_tier(_shop.offered_ids, 2), 0,
		"두 번째 R1 refresh는 Lv1 기본 T1 상점")


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


func test_two_faced_coin_slot_costs_reflect_discount_and_markup() -> void:
	_state.talisman_type = Enums.TalismanType.TWO_FACED_COIN
	_shop.offered_ids.assign(["sp_assembly", "sp_assembly", "sp_assembly"])
	_shop._coin_slots = {"discount_idx": 0, "markup_idx": 1}

	assert_eq(_shop.get_slot_cost(0), 1, "할인 슬롯은 2g → 1g")
	assert_eq(_shop.get_slot_cost(1), 3, "할증 슬롯은 2g → 3g")
	assert_eq(_shop.get_slot_cost(2), 2, "그 외 슬롯은 기본가")


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


func test_difficulty_6_refreshes_4_cards() -> void:
	_state.difficulty = 6
	_shop.refresh_shop()
	assert_eq(_shop.offered_ids.size(), 4, "D6 상점 4장")


func test_difficulty_6_reroll_costs_2_gold() -> void:
	_state.difficulty = 6
	_shop.refresh_shop()
	var gold_before: int = _state.gold
	var result: bool = _shop.reroll()
	assert_true(result, "리롤 성공")
	assert_eq(_state.gold, gold_before - 2, "D6 리롤 2골드")


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


func test_pending_free_reroll_consumes_before_gold() -> void:
	_state.pending_free_rerolls = 1
	_shop.refresh_shop()
	var gold_before: int = _state.gold

	var result: bool = _shop.reroll()

	assert_true(result, "무료 리롤 성공")
	assert_eq(_state.pending_free_rerolls, 0, "pending 무료 리롤 1회 소비")
	assert_eq(_state.gold, gold_before, "무료 리롤은 골드 미차감")
	assert_eq(_state.round_rerolls, 1, "무료 리롤도 라운드 리롤 수 증가")
	assert_true(_shop.last_reroll_was_free, "마지막 리롤 free flag 기록")
	assert_eq(_shop.last_reroll_cost, 0, "무료 리롤 비용 0")


func test_pending_free_reroll_fires_on_reroll_triggers() -> void:
	var engine := ChainEngine.new()
	engine.set_seed(42)
	_state.board[0] = CardInstance.create("sp_interest")
	_state.gold = 0
	_state.pending_free_rerolls = 1
	_connect_reroll_triggers(engine)
	_shop.refresh_shop()
	var units_before: int = (_state.board[0] as CardInstance).get_total_units()

	var result: bool = _shop.reroll()

	assert_true(result, "무료 리롤 성공")
	assert_eq((_state.board[0] as CardInstance).get_total_units(), units_before + 1,
		"무료 리롤도 ON_REROLL 유닛 추가 발동")
	assert_true(_shop.last_reroll_trigger_result.has("events"),
		"무료 리롤 trigger 결과 저장")


func test_reroll_triggers_on_reroll_card_effects() -> void:
	var engine := ChainEngine.new()
	engine.set_seed(42)
	_state.board[0] = CardInstance.create("sp_interest")
	_connect_reroll_triggers(engine)
	_shop.refresh_shop()
	var units_before: int = (_state.board[0] as CardInstance).get_total_units()

	var result: bool = _shop.reroll()

	assert_true(result, "리롤 성공")
	assert_eq((_state.board[0] as CardInstance).get_total_units(), units_before + 1,
		"sim 리롤 → ON_REROLL 유닛 추가")
	assert_true(_shop.last_reroll_trigger_result.has("events"),
		"리롤 trigger 결과 저장")


func test_reroll_applies_levelup_discount_from_on_reroll() -> void:
	var engine := ChainEngine.new()
	engine.set_seed(42)
	var pawn := CardInstance.create("ne_pawnbroker")
	pawn.evolve_star()
	pawn.evolve_star()
	_state.board[0] = pawn
	_state.levelup_current_cost = 5
	_connect_reroll_triggers(engine)
	_shop.refresh_shop()

	var result: bool = _shop.reroll()

	assert_true(result, "리롤 성공")
	assert_eq(_state.levelup_current_cost, 3, "전당포 ★3 리롤 → 레벨업 비용 -2")
	assert_eq(_shop.last_reroll_trigger_result.get("levelup_discount", 0), 2)


func test_failed_reroll_does_not_fire_trigger_callback() -> void:
	var called := [0]
	_shop.set_reroll_trigger_callback(func():
		called[0] += 1
		return {"gold": 99}
	)
	_state.gold = 0
	_shop.refresh_shop()

	var result: bool = _shop.reroll()

	assert_false(result, "골드 부족 → 리롤 실패")
	assert_eq(called[0], 0, "실패 리롤은 ON_REROLL 미발동")
	assert_eq(_shop.last_reroll_trigger_result, {})


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
