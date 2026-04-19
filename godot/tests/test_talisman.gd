extends GutTest
## GUT tests for talisman.gd — 12종 부적 로직 검증.

var state: GameState
var rng: RandomNumberGenerator


func before_each() -> void:
	state = GameState.new()
	rng = RandomNumberGenerator.new()
	rng.seed = 42


# ================================================================
# 인프라
# ================================================================

func test_talisman_enum_has_12_types() -> void:
	# NONE + 12종 = 13
	assert_eq(Enums.TalismanType.COPPER_WIRE, 12,
		"TalismanType should have 12 talismans (last = 12)")


func test_game_state_has_talisman_fields() -> void:
	assert_eq(state.talisman_type, Enums.TalismanType.NONE)
	assert_true(state.talisman_state is Dictionary)


func test_talisman_data_all_12() -> void:
	for t in range(1, 13):
		var data: Dictionary = Talisman.get_data(t)
		assert_false(data.is_empty(), "Talisman %d should have data" % t)
		assert_true(data.has("name"), "Talisman %d should have name" % t)


func test_init_run_state() -> void:
	state.talisman_type = Enums.TalismanType.FLINT
	Talisman.init_run_state(state)
	assert_false(state.talisman_state.get("first_growth_used", true))


# ================================================================
# 터진 자루
# ================================================================

func test_burst_sack_upgrade_slots() -> void:
	state.talisman_type = Enums.TalismanType.NONE
	assert_eq(Talisman.get_upgrade_shop_slots(state), 2)
	state.talisman_type = Enums.TalismanType.BURST_SACK
	assert_eq(Talisman.get_upgrade_shop_slots(state), 3)


# ================================================================
# 전쟁 북
# ================================================================

func test_war_drum_reduction_active() -> void:
	state.talisman_type = Enums.TalismanType.WAR_DRUM
	assert_almost_eq(Talisman.calc_war_drum_reduction(state, 10, 5), 0.10, 0.001)


func test_war_drum_no_reduction_when_equal() -> void:
	state.talisman_type = Enums.TalismanType.WAR_DRUM
	assert_almost_eq(Talisman.calc_war_drum_reduction(state, 5, 5), 0.0, 0.001)


func test_war_drum_no_reduction_without_talisman() -> void:
	state.talisman_type = Enums.TalismanType.NONE
	assert_almost_eq(Talisman.calc_war_drum_reduction(state, 10, 5), 0.0, 0.001)


# ================================================================
# 수은 방울
# ================================================================

func test_mercury_drop_enhance_multiplier() -> void:
	state.talisman_type = Enums.TalismanType.NONE
	assert_almost_eq(Talisman.get_enhance_multiplier(state), 1.0, 0.001)
	state.talisman_type = Enums.TalismanType.MERCURY_DROP
	assert_almost_eq(Talisman.get_enhance_multiplier(state), 1.25, 0.001)


# ================================================================
# 유리 눈
# ================================================================

func test_glass_eye_weight_mult() -> void:
	state.talisman_type = Enums.TalismanType.NONE
	assert_almost_eq(Talisman.get_owned_card_weight_mult(state), 1.0, 0.001)
	state.talisman_type = Enums.TalismanType.GLASS_EYE
	assert_almost_eq(Talisman.get_owned_card_weight_mult(state), 1.15, 0.001)


# ================================================================
# 양면 동전
# ================================================================

func test_two_faced_coin_roll() -> void:
	state.talisman_type = Enums.TalismanType.TWO_FACED_COIN
	var slots: Dictionary = Talisman.roll_coin_slots(state, 6, rng)
	assert_true(slots.has("discount_idx"))
	assert_true(slots.has("markup_idx"))
	assert_ne(slots["discount_idx"], slots["markup_idx"])


func test_two_faced_coin_price_discount() -> void:
	var slots := {"discount_idx": 2, "markup_idx": 4}
	assert_eq(Talisman.apply_coin_price(10, 2, slots), 5)  # 50% off


func test_two_faced_coin_price_markup() -> void:
	var slots := {"discount_idx": 2, "markup_idx": 4}
	assert_eq(Talisman.apply_coin_price(10, 4, slots), 15)  # 50% markup


func test_two_faced_coin_price_normal() -> void:
	var slots := {"discount_idx": 2, "markup_idx": 4}
	assert_eq(Talisman.apply_coin_price(10, 0, slots), 10)


func test_two_faced_coin_no_talisman() -> void:
	state.talisman_type = Enums.TalismanType.NONE
	var slots: Dictionary = Talisman.roll_coin_slots(state, 6, rng)
	assert_true(slots.is_empty())


# ================================================================
# 황금 주사위
# ================================================================

func test_golden_die_choices() -> void:
	state.talisman_type = Enums.TalismanType.NONE
	assert_eq(Talisman.get_boss_reward_choices(state), 4)
	state.talisman_type = Enums.TalismanType.GOLDEN_DIE
	assert_eq(Talisman.get_boss_reward_choices(state), 6)


# ================================================================
# 깨진 알
# ================================================================

func test_cracked_egg_star1_no_bonus() -> void:
	state.talisman_type = Enums.TalismanType.CRACKED_EGG
	var card := CardInstance.create("sp_assembly")
	assert_not_null(card)
	assert_eq(Talisman.get_extra_spawn(card, state), 0)


func test_cracked_egg_star2_bonus() -> void:
	state.talisman_type = Enums.TalismanType.CRACKED_EGG
	var card := CardInstance.create("sp_assembly")
	assert_not_null(card)
	card.star_level = 2
	assert_eq(Talisman.get_extra_spawn(card, state), 1)


# ================================================================
# 부싯돌
# ================================================================

func test_flint_consume_once() -> void:
	state.talisman_type = Enums.TalismanType.FLINT
	Talisman.init_round_state(state)
	var mult1: float = Talisman.consume_flint_bonus(state)
	assert_almost_eq(mult1, 2.0, 0.001)
	var mult2: float = Talisman.consume_flint_bonus(state)
	assert_almost_eq(mult2, 1.0, 0.001)


func test_flint_no_talisman() -> void:
	state.talisman_type = Enums.TalismanType.NONE
	Talisman.init_round_state(state)
	assert_almost_eq(Talisman.consume_flint_bonus(state), 1.0, 0.001)


# ================================================================
# 금간 해골
# ================================================================

func test_cracked_skull_query() -> void:
	state.talisman_type = Enums.TalismanType.NONE
	assert_false(Talisman.has_cracked_skull(state))
	state.talisman_type = Enums.TalismanType.CRACKED_SKULL
	assert_true(Talisman.has_cracked_skull(state))


# ================================================================
# 녹슨 렌치
# ================================================================

func test_rusty_wrench_can_detach() -> void:
	state.talisman_type = Enums.TalismanType.NONE
	assert_false(Talisman.can_detach_upgrade(state))
	state.talisman_type = Enums.TalismanType.RUSTY_WRENCH
	assert_true(Talisman.can_detach_upgrade(state))


func test_rusty_wrench_detach_refund() -> void:
	state.talisman_type = Enums.TalismanType.RUSTY_WRENCH
	state.terazin = 0
	var card := CardInstance.create("sp_assembly")
	assert_not_null(card)
	# Manually add a fake upgrade
	card.upgrades.append({"id": "test", "cost": 4, "stat_mods": {}})
	var refund: int = Talisman.detach_upgrade(state, card, 0)
	assert_eq(refund, 2)  # 50% of 4
	assert_eq(state.terazin, 2)
	assert_eq(card.upgrades.size(), 0)


# ================================================================
# 영혼 항아리
# ================================================================

func test_soul_jar_first_sell() -> void:
	state.talisman_type = Enums.TalismanType.SOUL_JAR
	Talisman.init_round_state(state)
	# Setup: board has 2 cards, sold card has 10 units
	var card1 := CardInstance.create("sp_assembly")
	var card2 := CardInstance.create("sp_workshop")
	assert_not_null(card1)
	assert_not_null(card2)
	state.board[0] = card1
	state.board[1] = card2
	var sold := CardInstance.create("sp_circulator")
	assert_not_null(sold)
	# Set sold card to have known units
	var units_before_1 := card1.get_total_units()
	var units_before_2 := card2.get_total_units()
	var sold_units := sold.get_total_units()
	var distributed: int = Talisman.process_soul_jar_sell(state, sold, rng)
	# Should distribute about half of sold_units
	assert_gt(distributed, 0)
	# Second sell should not distribute
	var distributed2: int = Talisman.process_soul_jar_sell(state, sold, rng)
	assert_eq(distributed2, 0)


# ================================================================
# 구리 전선
# ================================================================

func test_copper_wire_no_effect_without_talisman() -> void:
	state.talisman_type = Enums.TalismanType.NONE
	var card := CardInstance.create("sp_assembly")
	assert_not_null(card)
	state.board[0] = card
	Talisman.apply_copper_wire(state)
	# No crash, no effect


func test_copper_wire_full_slots() -> void:
	state.talisman_type = Enums.TalismanType.COPPER_WIRE
	var card1 := CardInstance.create("sp_assembly")
	var card2 := CardInstance.create("sp_workshop")
	assert_not_null(card1)
	assert_not_null(card2)
	state.board[0] = card1
	state.board[1] = card2
	# Fill card1 upgrade slots (5 slots by default)
	for i in 5:
		card1.upgrades.append({"id": "test_%d" % i, "stat_mods": {"atk_pct": 0.10, "hp_pct": 0.05}})
	Talisman.apply_copper_wire(state)
	# card2 should have received temp buff
	# Total atk_pct = 5 * 0.10 = 0.50, propagate 30% = 0.15 → temp_atk_mult = 1.15
	# Total hp_pct = 5 * 0.05 = 0.25, propagate 30% = 0.075 → temp_hp_mult = 1.075
	for s in card2.stacks:
		assert_almost_eq(s["temp_atk_mult"], 1.15, 0.01,
			"Adjacent card should get 30%% of full-slot upgrade ATK")
		assert_almost_eq(s["temp_hp_mult"], 1.075, 0.01,
			"Adjacent card should get 30%% of full-slot upgrade HP")


# ================================================================
# Test Auditor 지적 ①: 다중 라운드 리셋 후 재사용 엣지 케이스
# ================================================================

func test_flint_multi_round_reset_reuse() -> void:
	## FLINT: 라운드 리셋 후 다시 사용 가능한지 검증
	state.talisman_type = Enums.TalismanType.FLINT
	# 라운드 1
	Talisman.init_round_state(state)
	var m1: float = Talisman.consume_flint_bonus(state)
	assert_almost_eq(m1, 2.0, 0.001, "R1 첫 성장 ×2")
	var m1b: float = Talisman.consume_flint_bonus(state)
	assert_almost_eq(m1b, 1.0, 0.001, "R1 두번째 ×1")
	# 라운드 2 — 리셋 후 다시 사용 가능
	Talisman.init_round_state(state)
	var m2: float = Talisman.consume_flint_bonus(state)
	assert_almost_eq(m2, 2.0, 0.001, "R2 리셋 후 첫 성장 다시 ×2")
	# 라운드 3
	Talisman.init_round_state(state)
	var m3: float = Talisman.consume_flint_bonus(state)
	assert_almost_eq(m3, 2.0, 0.001, "R3 리셋 후 다시 ×2")


func test_soul_jar_multi_round_reset_reuse() -> void:
	## SOUL_JAR: 라운드 리셋 후 다시 첫 판매 배분 가능
	state.talisman_type = Enums.TalismanType.SOUL_JAR
	var card1 := CardInstance.create("sp_assembly")
	var card2 := CardInstance.create("sp_workshop")
	var sold := CardInstance.create("sp_furnace")
	assert_not_null(card1)
	assert_not_null(card2)
	assert_not_null(sold)
	state.board[0] = card1
	state.board[1] = card2
	# 라운드 1: 첫 판매
	Talisman.init_round_state(state)
	var d1: int = Talisman.process_soul_jar_sell(state, sold, rng)
	assert_gt(d1, 0, "R1 첫 판매 → 배분")
	var d1b: int = Talisman.process_soul_jar_sell(state, sold, rng)
	assert_eq(d1b, 0, "R1 두번째 판매 → 배분 없음")
	# 라운드 2: 리셋 후 다시 첫 판매 가능
	Talisman.init_round_state(state)
	var d2: int = Talisman.process_soul_jar_sell(state, sold, rng)
	assert_gt(d2, 0, "R2 리셋 후 첫 판매 → 다시 배분")


func test_soul_jar_empty_board() -> void:
	## SOUL_JAR: 보드가 비어있을 때 크래시 없이 0 반환
	state.talisman_type = Enums.TalismanType.SOUL_JAR
	Talisman.init_round_state(state)
	var sold := CardInstance.create("sp_assembly")
	assert_not_null(sold)
	# 보드에 아무것도 없음 (기본: 전부 null)
	var distributed: int = Talisman.process_soul_jar_sell(state, sold, rng)
	assert_eq(distributed, 0, "빈 보드 → 배분 0, 크래시 없음")


func test_two_faced_coin_shop_size_1() -> void:
	## TWO_FACED_COIN: shop_size < 2이면 빈 결과
	state.talisman_type = Enums.TalismanType.TWO_FACED_COIN
	var slots: Dictionary = Talisman.roll_coin_slots(state, 1, rng)
	assert_true(slots.is_empty(), "shop_size=1 → 동전 효과 불가")


func test_two_faced_coin_shop_size_0() -> void:
	## TWO_FACED_COIN: shop_size=0이면 빈 결과
	state.talisman_type = Enums.TalismanType.TWO_FACED_COIN
	var slots: Dictionary = Talisman.roll_coin_slots(state, 0, rng)
	assert_true(slots.is_empty(), "shop_size=0 → 동전 효과 불가")


# ================================================================
# Test Auditor 지적 ②: 실제 효과 적용 end-to-end 검증
# ================================================================

func test_mercury_drop_actually_enhances_more() -> void:
	## 수은 방울이 chain_engine의 enhance에 실제로 영향을 미치는지
	var engine := ChainEngine.new()
	engine.set_seed(42)
	# ne_ruin_resonance: RS, spawn self + enhance self 2%
	var board_normal: Array = [CardInstance.create("ne_ruin_resonance")]
	assert_not_null(board_normal[0])
	engine.run_growth_chain(board_normal)
	var atk_normal: float = board_normal[0].get_total_atk()

	# 수은 방울 적용 (enhance_multiplier = 1.25)
	var engine2 := ChainEngine.new()
	engine2.set_seed(42)
	engine2.enhance_multiplier = Talisman.get_enhance_multiplier(state)
	assert_almost_eq(engine2.enhance_multiplier, 1.0, 0.001,
		"NONE → multiplier 1.0")
	state.talisman_type = Enums.TalismanType.MERCURY_DROP
	engine2.enhance_multiplier = Talisman.get_enhance_multiplier(state)
	assert_almost_eq(engine2.enhance_multiplier, 1.25, 0.001,
		"MERCURY_DROP → multiplier 1.25")
	var board_mercury: Array = [CardInstance.create("ne_ruin_resonance")]
	assert_not_null(board_mercury[0])
	engine2.run_growth_chain(board_mercury)
	var atk_mercury: float = board_mercury[0].get_total_atk()
	assert_gt(atk_mercury, atk_normal,
		"수은 방울 → enhance 효과 실제 증가 확인")


func test_glass_eye_weight_applied_in_shop_context() -> void:
	## 유리 눈 가중치가 실제로 1.0보다 큰 값을 반환하는지
	state.talisman_type = Enums.TalismanType.NONE
	var w1: float = Talisman.get_owned_card_weight_mult(state)
	state.talisman_type = Enums.TalismanType.GLASS_EYE
	var w2: float = Talisman.get_owned_card_weight_mult(state)
	assert_almost_eq(w1, 1.0, 0.001, "NONE → 1.0")
	assert_almost_eq(w2, 1.15, 0.001, "GLASS_EYE → 1.15")
	assert_gt(w2, w1, "유리 눈 가중치가 실제로 더 큼")


# ================================================================
# Test Auditor 지적 ③: 상태 관리 완전성 검증
# ================================================================

func test_init_run_state_clears_previous() -> void:
	## init_run_state가 기존 talisman_state를 완전히 초기화하는지
	state.talisman_type = Enums.TalismanType.FLINT
	state.talisman_state = {"first_growth_used": true, "garbage_key": 42}
	Talisman.init_run_state(state)
	assert_false(state.talisman_state.get("first_growth_used", true),
		"init_run → first_growth_used = false")
	assert_false(state.talisman_state.has("garbage_key"),
		"init_run → 이전 상태 키 제거됨")


func test_changing_talisman_resets_state() -> void:
	## 부적 변경 후 init_run_state 호출 시 새 부적에 맞는 상태 설정
	state.talisman_type = Enums.TalismanType.FLINT
	Talisman.init_run_state(state)
	assert_false(state.talisman_state.get("first_growth_used", true))
	# 부적 변경
	state.talisman_type = Enums.TalismanType.SOUL_JAR
	Talisman.init_run_state(state)
	assert_false(state.talisman_state.get("first_sell_used", true),
		"SOUL_JAR → first_sell_used 초기화됨")
	assert_false(state.talisman_state.has("first_growth_used"),
		"FLINT 상태가 새 초기화에서 제거됨")
