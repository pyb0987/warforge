extends GutTest
## ne_pawnbroker (T1 전당포) REROLL trigger 통합 테스트.
## chain_engine.process_reroll_triggers + game_state.apply_levelup_discount 검증.


func _board_with(card_id: String, star: int) -> Array:
	var c: CardInstance = CardInstance.create(card_id)
	for _s in star - 1:
		c.evolve_star()
	return [c]


# ================================================================
# REROLL trigger: levelup_discount action
# ================================================================


func test_pawnbroker_star1_reroll_emits_discount_signal() -> void:
	## ★1: chance=0.5, amount=1. seed=42 첫 randf 가 0.5 미만이면 +1 신호.
	## 결정성 RNG 로 신호 누적이 amount 단위인지 검증.
	var engine := ChainEngine.new()
	engine.set_seed(42)
	var board := _board_with("ne_pawnbroker", 1)
	var total: int = 0
	for _i in 50:  # 통계적 분포 검증
		var r: Dictionary = engine.process_reroll_triggers(board)
		total += int(r.get("levelup_discount", 0))
	# 50회 중 평균 25회 발동 (50% chance) × amount 1 = 25.
	# 결정성 RNG 라 정확값 일치할 필요는 없지만 5~45 범위 안전.
	assert_gt(total, 5, "★1 50% chance — 누적 ≥ 5")
	assert_lt(total, 45, "★1 50% chance — 누적 ≤ 45")


func test_pawnbroker_star3_reroll_always_discount_2() -> void:
	## ★3: chance=1.0, amount=2. 매 리롤마다 정확히 +2.
	var engine := ChainEngine.new()
	engine.set_seed(42)
	var board := _board_with("ne_pawnbroker", 3)
	var r: Dictionary = engine.process_reroll_triggers(board)
	assert_eq(r.get("levelup_discount", 0), 2, "★3 첫 리롤 → -2 확정")
	r = engine.process_reroll_triggers(board)
	assert_eq(r.get("levelup_discount", 0), 2, "★3 두 번째 리롤 → -2 확정")


func test_pawnbroker_max_act_minus1_no_cap() -> void:
	## max_act=-1: 무제한 발동. ★3 10회 리롤 → 모두 발동.
	var engine := ChainEngine.new()
	engine.set_seed(42)
	var board := _board_with("ne_pawnbroker", 3)
	var total := 0
	for _i in 10:
		var r: Dictionary = engine.process_reroll_triggers(board)
		total += int(r.get("levelup_discount", 0))
	assert_eq(total, 20, "★3 10회 리롤 = 20 누적 인하 (상한 없음)")


# ================================================================
# game_state.apply_levelup_discount(amount) 적용
# ================================================================


func test_apply_levelup_discount_amount_subtracts() -> void:
	var gs := GameState.new()
	gs.shop_level = 1  # next levelup → T2 (5g)
	gs.levelup_current_cost = 5
	gs.apply_levelup_discount(2)
	assert_eq(gs.levelup_current_cost, 3, "5 - 2 = 3")


func test_apply_levelup_discount_floors_at_zero() -> void:
	## 가격은 0이 최저 (음수 안 됨).
	var gs := GameState.new()
	gs.shop_level = 1
	gs.levelup_current_cost = 1
	gs.apply_levelup_discount(5)
	assert_eq(gs.levelup_current_cost, 0, "1 - 5 = 0 (floor)")


func test_apply_levelup_discount_default_amount_one() -> void:
	## default 매개변수 1 — 자연 감가 caller 호환.
	var gs := GameState.new()
	gs.shop_level = 1
	gs.levelup_current_cost = 5
	gs.apply_levelup_discount()
	assert_eq(gs.levelup_current_cost, 4, "default amount 1 (자연 감가)")
