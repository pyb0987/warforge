extends GutTest
## GUT tests for boss reward system — 27종 보상 데이터 + 적용 로직 검증.

var state: GameState
var rng: RandomNumberGenerator


func before_each() -> void:
	state = GameState.new()
	rng = RandomNumberGenerator.new()
	rng.seed = 42


# ================================================================
# 인프라: 데이터 27종 존재 + 풀 조회
# ================================================================

func test_all_27_rewards_exist() -> void:
	var all_ids := BossRewardDB.get_all_ids()
	assert_eq(all_ids.size(), 27, "보상 27종 등록")


func test_pool_r4_has_9() -> void:
	var pool := BossRewardDB.get_pool(4)
	assert_eq(pool.size(), 9, "R4 풀 9개")


func test_pool_r8_has_9() -> void:
	var pool := BossRewardDB.get_pool(8)
	assert_eq(pool.size(), 9, "R8 풀 9개")


func test_pool_r12_has_9() -> void:
	var pool := BossRewardDB.get_pool(12)
	assert_eq(pool.size(), 9, "R12 풀 9개")


func test_pool_invalid_returns_empty() -> void:
	assert_true(BossRewardDB.get_pool(5).is_empty(), "존재하지 않는 보스 → 빈 풀")


func test_each_reward_has_required_fields() -> void:
	for id in BossRewardDB.get_all_ids():
		var data: Dictionary = BossRewardDB.get_data(id)
		assert_true(data.has("name"), "%s has name" % id)
		assert_true(data.has("icon"), "%s has icon" % id)
		assert_true(data.has("desc"), "%s has desc" % id)
		assert_true(data.has("boss_tier"), "%s has boss_tier" % id)
		assert_true(data.has("type"), "%s has type" % id)
		assert_true(data.has("needs_target"), "%s has needs_target" % id)


func test_roll_choices_returns_correct_count() -> void:
	var choices := BossRewardDB.roll_choices(4, 4, rng)
	assert_eq(choices.size(), 4, "4개 선택지")


func test_roll_choices_no_duplicates() -> void:
	for _i in 20:
		var choices := BossRewardDB.roll_choices(4, 4, rng)
		var seen := {}
		for c in choices:
			assert_false(seen.has(c), "중복 없음: %s" % c)
			seen[c] = true


func test_roll_choices_golden_die_6() -> void:
	var choices := BossRewardDB.roll_choices(8, 6, rng)
	assert_eq(choices.size(), 6, "황금 주사위: 6개 선택지")


func test_has_reward_query() -> void:
	assert_false(BossReward.has_reward(state, "r4_3"))
	state.boss_rewards.append("r4_3")
	assert_true(BossReward.has_reward(state, "r4_3"))


# ================================================================
# R4 보상 적용
# ================================================================

func test_r4_1_star_evolve_plus_terazin() -> void:
	## 긴급 보급: 카드 1장 ★승급 + 4 테라진
	var card := CardInstance.create("sp_assembly")
	assert_not_null(card)
	state.board[0] = card
	state.terazin = 0
	BossReward.apply_with_target("r4_1", state, card, rng)
	assert_eq(card.star_level, 2, "★1→★2")
	assert_eq(state.terazin, 4, "+4 테라진")


func test_r4_2_t3_shop_plus_gold() -> void:
	## 용병단 초청: +10 골드 (상점 갱신은 UI 레벨)
	state.gold = 5
	BossReward.apply_no_target("r4_2", state, rng)
	assert_eq(state.gold, 15, "+10 골드")


func test_r4_3_permanent_chain_reaction() -> void:
	## 연쇄 반응로: 영구 보상 등록
	BossReward.apply_no_target("r4_3", state, rng)
	assert_true(BossReward.has_reward(state, "r4_3"))


func test_r4_4_permanent_double_reroll() -> void:
	## 이중 리롤: 영구 보상 등록
	BossReward.apply_no_target("r4_4", state, rng)
	assert_true(BossReward.has_reward(state, "r4_4"))


func test_r4_5_permanent_enhance_amp() -> void:
	## 강화 증폭기: 영구 보상 등록
	BossReward.apply_no_target("r4_5", state, rng)
	assert_true(BossReward.has_reward(state, "r4_5"))


func test_r4_6_permanent_auto_conscript() -> void:
	## 자동 징집: 영구 보상 등록
	BossReward.apply_no_target("r4_6", state, rng)
	assert_true(BossReward.has_reward(state, "r4_6"))


func test_r4_7_elite_awakening() -> void:
	## 정예 각성: ATK +30%, HP +30%
	var card := CardInstance.create("sp_assembly")
	assert_not_null(card)
	var atk_before := card.get_total_atk()
	var hp_before := card.get_total_hp()
	BossReward.apply_with_target("r4_7", state, card, rng)
	assert_gt(card.get_total_atk(), atk_before * 1.29, "ATK +30%")
	assert_gt(card.get_total_hp(), hp_before * 1.29, "HP +30%")


func test_r4_8_emergency_reinforcement() -> void:
	## 비상 증원: 유닛 +5기
	var card := CardInstance.create("sp_assembly")
	assert_not_null(card)
	var units_before := card.get_total_units()
	BossReward.apply_with_target("r4_8", state, card, rng)
	assert_eq(card.get_total_units(), units_before + 5, "+5기")


func test_r4_9_expand_bench() -> void:
	## 확장 벤치: 벤치 +2칸
	var before := state.bench.size()
	BossReward.apply_no_target("r4_9", state, rng)
	assert_eq(state.bench.size(), before + 2, "벤치 +2")


# ================================================================
# R8 보상 적용
# ================================================================

func test_r8_1_star_evolve_needs_target() -> void:
	## 대규모 징집: ★승급 (에픽 업그레이드는 UI 레벨에서 처리)
	var card := CardInstance.create("sp_assembly")
	assert_not_null(card)
	BossReward.apply_with_target("r8_1", state, card, rng)
	assert_eq(card.star_level, 2, "★승급")


func test_r8_2_war_fund() -> void:
	## 전쟁 기금: 15골드 + 8 테라진
	state.gold = 0
	state.terazin = 0
	BossReward.apply_no_target("r8_2", state, rng)
	assert_eq(state.gold, 15, "+15g")
	assert_eq(state.terazin, 8, "+8t")


func test_r8_3_permanent_overload_engine() -> void:
	## 과부하 엔진: 영구
	BossReward.apply_no_target("r8_3", state, rng)
	assert_true(BossReward.has_reward(state, "r8_3"))


func test_r8_4_permanent_loot_recovery() -> void:
	## 전리품 회수: 영구
	BossReward.apply_no_target("r8_4", state, rng)
	assert_true(BossReward.has_reward(state, "r8_4"))


func test_r8_5_permanent_aoe_enhance() -> void:
	## 광역 강화장: 영구
	BossReward.apply_no_target("r8_5", state, rng)
	assert_true(BossReward.has_reward(state, "r8_5"))


func test_r8_6_permanent_victory_will() -> void:
	## 승전 의지: 영구
	BossReward.apply_no_target("r8_6", state, rng)
	assert_true(BossReward.has_reward(state, "r8_6"))


func test_r8_7_gene_enhance() -> void:
	## 유전자 강화: 유닛 2배 + 레어 업글
	var card := CardInstance.create("sp_assembly")
	assert_not_null(card)
	var units_before := card.get_total_units()
	BossReward.apply_with_target("r8_7", state, card, rng)
	assert_eq(card.get_total_units(), units_before * 2, "유닛 2배")
	assert_eq(card.upgrades.size(), 1, "레어 업글 1개 부착")


func test_r8_8_mass_reinforcement() -> void:
	## 일괄 증원: 전체 카드 +3기
	var c1 := CardInstance.create("sp_assembly")
	var c2 := CardInstance.create("sp_workshop")
	assert_not_null(c1)
	assert_not_null(c2)
	state.board[0] = c1
	state.board[1] = c2
	var u1 := c1.get_total_units()
	var u2 := c2.get_total_units()
	BossReward.apply_no_target("r8_8", state, rng)
	assert_eq(c1.get_total_units(), u1 + 3, "카드1 +3기")
	assert_eq(c2.get_total_units(), u2 + 3, "카드2 +3기")


func test_r8_9_expand_field() -> void:
	## 전선 확장: 필드 +1칸
	var before := state.field_slots
	BossReward.apply_no_target("r8_9", state, rng)
	assert_eq(state.field_slots, before + 1, "필드 +1")


# ================================================================
# R12 보상 적용
# ================================================================

func test_r12_1_ultimate_evolve() -> void:
	## 궁극 진화: 카드 ★승급 (2장은 game_manager에서 2회 호출)
	var card := CardInstance.create("sp_assembly")
	assert_not_null(card)
	BossReward.apply_with_target("r12_1", state, card, rng)
	assert_eq(card.star_level, 2, "★승급")


func test_r12_2_legacy_of_empire() -> void:
	## 제국의 유산: 전체 ATK+20% HP+20% + 15t
	var c1 := CardInstance.create("sp_assembly")
	assert_not_null(c1)
	state.board[0] = c1
	state.terazin = 0
	var atk_before := c1.get_total_atk()
	BossReward.apply_no_target("r12_2", state, rng)
	assert_gt(c1.get_total_atk(), atk_before * 1.19, "ATK +20%")
	assert_eq(state.terazin, 15, "+15t")


func test_r12_3_permanent_overload_chain() -> void:
	## 과부하 연쇄: 영구
	BossReward.apply_no_target("r12_3", state, rng)
	assert_true(BossReward.has_reward(state, "r12_3"))


func test_r12_4_permanent_double_merge() -> void:
	## 이중 합성: 영구
	BossReward.apply_no_target("r12_4", state, rng)
	assert_true(BossReward.has_reward(state, "r12_4"))


func test_r12_5_permanent_battlefield_echo() -> void:
	## 전장의 메아리: 영구
	BossReward.apply_no_target("r12_5", state, rng)
	assert_true(BossReward.has_reward(state, "r12_5"))


func test_r12_6_permanent_quantity_law() -> void:
	## 물량의 법칙: 영구
	BossReward.apply_no_target("r12_6", state, rng)
	assert_true(BossReward.has_reward(state, "r12_6"))


func test_r12_7_divine_strike() -> void:
	## 신의 일격: ATK ×2 + 에픽 업글
	var card := CardInstance.create("sp_assembly")
	assert_not_null(card)
	var atk_before := card.get_total_atk()
	BossReward.apply_with_target("r12_7", state, card, rng)
	assert_almost_eq(card.get_total_atk(), atk_before * 2.0, 1.0, "ATK ×2")
	assert_eq(card.upgrades.size(), 1, "에픽 업글 1개 부착")


func test_r12_8_legion_clone() -> void:
	## 군단 복제: 유닛 3배
	var card := CardInstance.create("sp_assembly")
	assert_not_null(card)
	var units_before := card.get_total_units()
	BossReward.apply_with_target("r12_8", state, card, rng)
	assert_eq(card.get_total_units(), units_before * 3, "유닛 3배")


func test_r12_9_dimension_rift() -> void:
	## 차원 균열: 필드+1 + 전체 업글슬롯+1
	var card := CardInstance.create("sp_assembly")
	assert_not_null(card)
	state.board[0] = card
	var slots_before_field := state.field_slots
	var slots_before := card.get_max_upgrade_slots()
	BossReward.apply_no_target("r12_9", state, rng)
	assert_eq(state.field_slots, slots_before_field + 1, "필드 +1")
	assert_eq(card.get_max_upgrade_slots(), slots_before + 1, "업글슬롯 +1")


# ================================================================
# 영구 보상 효과 쿼리
# ================================================================

func test_get_activation_bonus_none() -> void:
	assert_eq(BossReward.get_activation_bonus(state), 0)


func test_get_activation_bonus_r8_3() -> void:
	## 과부하 엔진: +1
	state.boss_rewards.append("r8_3")
	assert_eq(BossReward.get_activation_bonus(state), 1)


func test_get_activation_bonus_r12_3() -> void:
	## 과부하 연쇄: +2
	state.boss_rewards.append("r12_3")
	assert_eq(BossReward.get_activation_bonus(state), 2)


func test_get_activation_bonus_stacks() -> void:
	## 과부하 엔진 + 과부하 연쇄 = +3
	state.boss_rewards.append("r8_3")
	state.boss_rewards.append("r12_3")
	assert_eq(BossReward.get_activation_bonus(state), 3)


func test_get_enhance_amp_none() -> void:
	assert_almost_eq(BossReward.get_enhance_amp(state), 1.0, 0.001)


func test_get_enhance_amp_r4_5() -> void:
	## 강화 증폭기: ×1.5
	state.boss_rewards.append("r4_5")
	assert_almost_eq(BossReward.get_enhance_amp(state), 1.5, 0.001)


func test_get_settlement_gold_bonus_none() -> void:
	assert_eq(BossReward.get_settlement_gold_bonus(state, true), 0)
	assert_eq(BossReward.get_settlement_gold_bonus(state, false), 0)


func test_get_settlement_gold_bonus_r8_4_win() -> void:
	## 전리품 회수: 승리 +3g
	state.boss_rewards.append("r8_4")
	assert_eq(BossReward.get_settlement_gold_bonus(state, true), 3)


func test_get_settlement_terazin_bonus_r8_4_loss() -> void:
	## 전리품 회수: 패배 +2t
	state.boss_rewards.append("r8_4")
	assert_eq(BossReward.get_settlement_terazin_bonus(state, false), 2)


func test_get_shop_size_bonus_none() -> void:
	assert_eq(BossReward.get_shop_size_bonus(state), 0)


func test_get_shop_size_bonus_r4_4() -> void:
	## 상점 확장: +1 (6→7)
	state.boss_rewards.append("r4_4")
	assert_eq(BossReward.get_shop_size_bonus(state), 1)
