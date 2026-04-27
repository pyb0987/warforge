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


func test_r4_2_gold_grant() -> void:
	## 긴급 자금: +12 골드
	state.gold = 5
	BossReward.apply_no_target("r4_2", state, rng)
	assert_eq(state.gold, 17, "+12 골드")


func test_r4_3_permanent_chain_reaction() -> void:
	## 연쇄 반응로: 영구 보상 등록
	BossReward.apply_no_target("r4_3", state, rng)
	assert_true(BossReward.has_reward(state, "r4_3"))


func test_r4_4_shop_expansion() -> void:
	## 상점 확장: 영구 보상 등록 + 즉시 5회 무료 리롤 예약
	BossReward.apply_no_target("r4_4", state, rng)
	assert_true(BossReward.has_reward(state, "r4_4"))
	assert_eq(state.r4_4_initial_rerolls, 5, "즉시 5회 예약")


func test_r4_4_round_start_consumes_initial_then_one_per_round() -> void:
	## 첫 라운드 시작: +5 (즉시) + 1 (영구) = 6, 이후 매 라운드 +1
	BossReward.apply_no_target("r4_4", state, rng)
	var first := BossReward.consume_round_start_free_rerolls(state)
	assert_eq(first, 6, "첫 라운드: 5 + 1")
	var second := BossReward.consume_round_start_free_rerolls(state)
	assert_eq(second, 1, "다음 라운드: 1")
	var third := BossReward.consume_round_start_free_rerolls(state)
	assert_eq(third, 1, "또 다음 라운드: 1")


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


func test_r4_8_random_t4_t3_grant() -> void:
	## 보급 호송: 랜덤 T4 1장 + T3 1장 획득. 벤치 만석 시 못 받음.
	## 빈 벤치(8칸) → 두 장 다 받음
	var bench_before := 0
	for slot in state.bench:
		if slot != null:
			bench_before += 1
	BossReward.apply_no_target("r4_8", state, rng)
	var bench_after := 0
	var t4_found := false
	var t3_found := false
	for slot in state.bench:
		if slot != null:
			bench_after += 1
			var tier: int = CardDB.get_template(slot.get_base_id()).get("tier", 0)
			if tier == 4:
				t4_found = true
			elif tier == 3:
				t3_found = true
	assert_eq(bench_after - bench_before, 2, "벤치에 2장 추가")
	assert_true(t4_found, "T4 카드 1장")
	assert_true(t3_found, "T3 카드 1장")


func test_r4_8_bench_full_no_grant() -> void:
	## 벤치 만석이면 아무 카드도 못 받음
	for i in state.bench.size():
		state.bench[i] = CardInstance.create("sp_assembly")
	var occupied := state.bench.size()
	BossReward.apply_no_target("r4_8", state, rng)
	var still_occupied := 0
	for slot in state.bench:
		if slot != null:
			still_occupied += 1
	assert_eq(still_occupied, occupied, "벤치 만석 → 추가 없음")


func test_r4_8_bench_one_slot_only_t4() -> void:
	## 벤치 1칸만 비었을 때: T4 우선 획득, T3는 못 받음
	for i in range(1, state.bench.size()):
		state.bench[i] = CardInstance.create("sp_assembly")
	BossReward.apply_no_target("r4_8", state, rng)
	var added: CardInstance = state.bench[0]
	assert_not_null(added, "T4 1장 추가")
	if added != null:
		var tier: int = CardDB.get_template(added.get_base_id()).get("tier", 0)
		assert_eq(tier, 4, "추가된 카드는 T4")


func test_r4_9_expand_bench() -> void:
	## 확장 벤치: 벤치 +2칸
	var before := state.bench.size()
	BossReward.apply_no_target("r4_9", state, rng)
	assert_eq(state.bench.size(), before + 2, "벤치 +2")


# ================================================================
# R8 보상 적용
# ================================================================

func test_r8_1_star_evolve_with_rare_upgrade() -> void:
	## 대규모 징집: ★승급 + 레어 업글 1개 부착
	var card := CardInstance.create("sp_assembly")
	assert_not_null(card)
	BossReward.apply_with_target("r8_1", state, card, rng)
	assert_eq(card.star_level, 2, "★승급")
	assert_eq(card.upgrades.size(), 1, "레어 업글 1개 부착")


func test_r8_2_war_fund() -> void:
	## 전쟁 기금: 18골드 + 4 테라진
	state.gold = 0
	state.terazin = 0
	BossReward.apply_no_target("r8_2", state, rng)
	assert_eq(state.gold, 18, "+18g")
	assert_eq(state.terazin, 4, "+4t")


func test_r8_3_permanent_artisan_refund() -> void:
	## 장인의 회수: 영구 (★ 합성 시 티어 비용 환급)
	BossReward.apply_no_target("r8_3", state, rng)
	assert_true(BossReward.has_reward(state, "r8_3"))


func test_r8_4_permanent_unlimited_interest() -> void:
	## 무한 금고: 영구 (이자 cap 무제한)
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


func test_r8_7_gene_enhance_epic_only() -> void:
	## 유전자 강화: 에픽 업글 1개만 부착
	var card := CardInstance.create("sp_assembly")
	assert_not_null(card)
	var units_before := card.get_total_units()
	BossReward.apply_with_target("r8_7", state, card, rng)
	assert_eq(card.get_total_units(), units_before, "유닛 수 변화 없음")
	assert_eq(card.upgrades.size(), 1, "에픽 업글 1개 부착")


func test_r8_8_permanent_def_bonus() -> void:
	## 방어선 구축: 영구 (전체 카드 DEF +2)
	BossReward.apply_no_target("r8_8", state, rng)
	assert_true(BossReward.has_reward(state, "r8_8"))


func test_r8_9_sets_r13_bonus_pending() -> void:
	## 전선 확장: R13 전투 승리 시 R12 보상 추가 (1회 한정 flag 설정)
	assert_false(state.r8_9_bonus_pending, "초기 false")
	BossReward.apply_no_target("r8_9", state, rng)
	assert_true(state.r8_9_bonus_pending, "flag 설정")


func test_consume_r8_9_bonus_one_shot() -> void:
	## 한 번만 소비 후 flag 클리어
	state.r8_9_bonus_pending = true
	assert_true(BossReward.consume_r8_9_bonus(state), "1회 트리거")
	assert_false(BossReward.consume_r8_9_bonus(state), "재호출 시 false")
	assert_false(state.r8_9_bonus_pending, "flag 클리어")


func test_consume_r8_9_bonus_no_reward() -> void:
	## 보상 안 받았으면 false
	assert_false(BossReward.consume_r8_9_bonus(state))


# ================================================================
# R12 보상 적용
# ================================================================

func test_r12_1_two_stage_evolve() -> void:
	## 궁극 진화: step 1 = ★2→★3, step 2 = ★1→★2 (game_manager에서 step 전달)
	## step 1: ★2 카드만 ★3 승급 (★1 카드 전달 시 효과 무시)
	var c1 := CardInstance.create("sp_assembly")
	assert_not_null(c1)
	c1.evolve_star()  # ★1 → ★2
	BossReward.apply_with_target("r12_1", state, c1, rng, 1)
	assert_eq(c1.star_level, 3, "step 1: ★2 → ★3")
	## step 2: ★1 카드만 ★2 승급 (★3 카드 전달 시 효과 무시)
	var c2 := CardInstance.create("sp_workshop")
	assert_not_null(c2)
	BossReward.apply_with_target("r12_1", state, c2, rng, 2)
	assert_eq(c2.star_level, 2, "step 2: ★1 → ★2")
	## step 1에 ★1 카드 전달 시 효과 무시
	var c3 := CardInstance.create("sp_furnace")
	assert_not_null(c3)
	BossReward.apply_with_target("r12_1", state, c3, rng, 1)
	assert_eq(c3.star_level, 1, "step 1에 ★1 전달 → 효과 무시")
	## step 2에 ★3 카드 전달 시 효과 무시 (★1→★3 직행 방지)
	BossReward.apply_with_target("r12_1", state, c1, rng, 2)
	assert_eq(c1.star_level, 3, "step 2에 ★3 전달 → 효과 무시")


func test_r12_2_legacy_of_empire() -> void:
	## 제국의 유산: 전체 ATK+25% HP+25%
	var c1 := CardInstance.create("sp_assembly")
	assert_not_null(c1)
	state.board[0] = c1
	var atk_before := c1.get_total_atk()
	BossReward.apply_no_target("r12_2", state, rng)
	assert_gt(c1.get_total_atk(), atk_before * 1.24, "ATK +25%")


func test_r12_3_permanent_overload_chain() -> void:
	## 과부하 연쇄: 영구
	BossReward.apply_no_target("r12_3", state, rng)
	assert_true(BossReward.has_reward(state, "r12_3"))


func test_r12_4_shop_mega_expansion() -> void:
	## 상점 대확장: 영구 (상점 슬롯 +2 + 매턴 리롤 +2)
	BossReward.apply_no_target("r12_4", state, rng)
	assert_true(BossReward.has_reward(state, "r12_4"))
	assert_eq(BossReward.get_shop_size_bonus(state), 2, "상점 슬롯 +2")
	assert_eq(BossReward.consume_round_start_free_rerolls(state), 2, "매턴 리롤 +2")


func test_r12_5_permanent_five_color_legion() -> void:
	## 오색 군단: 영구
	BossReward.apply_no_target("r12_5", state, rng)
	assert_true(BossReward.has_reward(state, "r12_5"))


func test_count_board_themes_basic() -> void:
	## 보드 distinct 테마 개수 (중립 포함)
	var c1 := CardInstance.create("sp_assembly")
	var c2 := CardInstance.create("sp_workshop")
	assert_not_null(c1)
	assert_not_null(c2)
	state.board[0] = c1
	state.board[1] = c2
	# 둘 다 스팀펑크 → 1테마
	assert_eq(BossReward.count_board_themes(state), 1, "스팀펑크만 = 1테마")


func test_r12_6_permanent_quantity_law() -> void:
	## 물량의 법칙: 영구
	BossReward.apply_no_target("r12_6", state, rng)
	assert_true(BossReward.has_reward(state, "r12_6"))


func test_r12_7_divine_strike_epic_plus_rare() -> void:
	## 신의 일격: 에픽 + 레어 업글 1개씩 부착 (ATK×2 폐기)
	var card := CardInstance.create("sp_assembly")
	assert_not_null(card)
	var units_before := card.get_total_units()
	BossReward.apply_with_target("r12_7", state, card, rng)
	assert_eq(card.get_total_units(), units_before, "유닛 변화 없음")
	assert_eq(card.upgrades.size(), 2, "에픽 + 레어 = 2개 부착")


func test_r12_8_warrior_soul_revive_pool() -> void:
	## 전사의 영혼: 영구 (보드 부활 풀 20기, 100% HP)
	BossReward.apply_no_target("r12_8", state, rng)
	assert_true(BossReward.has_reward(state, "r12_8"))
	assert_eq(BossReward.get_revive_pool_size(state), 20, "풀 크기 20")


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


func test_get_activation_bonus_r12_3() -> void:
	## 과부하 연쇄: +1 (너프 후)
	state.boss_rewards.append("r12_3")
	assert_eq(BossReward.get_activation_bonus(state), 1)


func test_get_def_bonus_none() -> void:
	assert_eq(BossReward.get_def_bonus(state), 0)


func test_get_def_bonus_r8_8() -> void:
	## 방어선 구축: DEF +2
	state.boss_rewards.append("r8_8")
	assert_eq(BossReward.get_def_bonus(state), 2)


func test_get_merge_refund_none() -> void:
	assert_eq(BossReward.get_merge_refund(state, 4), 0)


func test_get_merge_refund_r8_3() -> void:
	## 장인의 회수: 합성 대상 티어 비용 환급
	state.boss_rewards.append("r8_3")
	assert_eq(BossReward.get_merge_refund(state, 1), 2, "T1 → 2g")
	assert_eq(BossReward.get_merge_refund(state, 4), 5, "T4 → 5g")
	assert_eq(BossReward.get_merge_refund(state, 5), 6, "T5 → 6g")


func test_is_interest_uncapped_none() -> void:
	assert_false(BossReward.is_interest_uncapped(state))


func test_is_interest_uncapped_r8_4() -> void:
	## 무한 금고: 이자 cap 우회
	state.boss_rewards.append("r8_4")
	assert_true(BossReward.is_interest_uncapped(state))


func test_get_enhance_amp_none() -> void:
	assert_almost_eq(BossReward.get_enhance_amp(state), 1.0, 0.001)


func test_get_enhance_amp_r4_5() -> void:
	## 강화 증폭기: ×1.2
	state.boss_rewards.append("r4_5")
	assert_almost_eq(BossReward.get_enhance_amp(state), 1.2, 0.001)


func test_consume_round_start_free_rerolls_none() -> void:
	assert_eq(BossReward.consume_round_start_free_rerolls(state), 0)


func test_round_start_rerolls_r4_4_plus_r12_4() -> void:
	## 두 보상 동시 보유: +1 (r4_4) + +2 (r12_4) = 3
	state.boss_rewards.append("r4_4")
	state.boss_rewards.append("r12_4")
	assert_eq(BossReward.consume_round_start_free_rerolls(state), 3)


func test_get_shop_size_bonus_r12_4() -> void:
	## 상점 대확장: +2
	state.boss_rewards.append("r12_4")
	assert_eq(BossReward.get_shop_size_bonus(state), 2)


func test_get_revive_pool_size_none() -> void:
	assert_eq(BossReward.get_revive_pool_size(state), 0)


# ================================================================
# 통합 검증 — 보스 보상 효과가 실제 시스템 경로에 적용되는지
# ================================================================

func test_r8_4_calc_interest_uncaps_above_max() -> void:
	## r8_4 무한 금고: gold=50일 때 일반 cap=4 → 우회 시 10
	state.gold = 50
	state.interest_per_5g = 1
	state.max_interest = 4
	## 일반 (보상 미보유): cap 4 적용
	assert_eq(state.calc_interest(), 4, "기본: cap 4")
	## r8_4 보유: cap 우회 → 10
	state.boss_rewards.append("r8_4")
	assert_eq(state.calc_interest(), 10, "r8_4: cap 우회")


func test_r8_4_calc_interest_below_cap_no_change() -> void:
	## gold=10 → raw 2, cap 4. r8_4 보유 무관 (raw < cap)
	state.gold = 10
	state.interest_per_5g = 1
	state.max_interest = 4
	state.boss_rewards.append("r8_4")
	assert_eq(state.calc_interest(), 2, "raw < cap → 우회 동일")


func test_r8_8_def_bonus_combines_with_upgrade_def() -> void:
	## r8_8 보유 + 업글로 추가 DEF 부여 시 둘이 합산되어 materialize에 반영되는지
	## 직접 materialize 호출 어려우므로 helper 합산 검증 (game_manager.gd:401에서 c.upgrade_def + bonus)
	var card := CardInstance.create("sp_assembly")
	assert_not_null(card)
	card.upgrade_def = 1
	## 보상 미보유: bonus = 0 → 총 def = 1
	assert_eq(card.upgrade_def + BossReward.get_def_bonus(state), 1, "upgrade_def 단독 = 1")
	## 보상 보유: bonus = 2 → 총 def = 3
	state.boss_rewards.append("r8_8")
	assert_eq(card.upgrade_def + BossReward.get_def_bonus(state), 3, "+r8_8 = 3")


func test_r12_5_theme_count_buff_application() -> void:
	## r12_5 오색 군단: 보드 테마 개수 × 10% buff 매 라운드 갱신.
	## game_manager._run_chain의 hook을 직접 시뮬: buff 적용 → ATK 변화 검증
	var c1 := CardInstance.create("sp_assembly")
	var c2 := CardInstance.create("sp_workshop")
	assert_not_null(c1)
	assert_not_null(c2)
	state.board[0] = c1
	state.board[1] = c2
	state.boss_rewards.append("r12_5")
	## 단일 테마 (둘 다 스팀펑크) → 1테마 → ×1.10
	var theme_count: int = BossReward.count_board_themes(state)
	assert_eq(theme_count, 1, "1테마")
	var atk_before := c1.get_total_atk()
	var mult: float = 1.0 + 0.10 * theme_count
	c1.temp_mult_buff(mult, mult)
	assert_almost_eq(c1.get_total_atk(), atk_before * 1.10, 0.5, "ATK ×1.10")
	## 리셋 후 다시 보드 변경 (c2 → 다른 테마로 가정 시 갱신 가능 검증은 어려우므로 reset만 검증)
	c1.clear_temp_buffs()
	assert_almost_eq(c1.get_total_atk(), atk_before, 0.5, "리셋 후 원복")


func test_r12_8_revive_pool_persists_alive_after_kill() -> void:
	## r12_8 보드 부활 풀: combat_engine에 풀 주입 + kill_unit 호출 → alive 유지
	var CombatEngineScript = load("res://combat/combat_engine.gd")
	var engine = CombatEngineScript.new()
	engine.headless = true
	## ally 1유닛 (HP 100) vs enemy 1유닛 (ATK 1000)
	var ally_units = [{"atk": 10.0, "hp": 100.0, "attack_speed": 1.0,
		"range": 32.0, "move_speed": 2.0, "def": 0.0, "mechanics": []}]
	var enemy_units = [{"atk": 1000.0, "hp": 100.0, "attack_speed": 1.0,
		"range": 32.0, "move_speed": 2.0, "def": 0.0, "mechanics": []}]
	engine.setup(ally_units, enemy_units)
	## board_revive_pool 주입 (보스 보상 r12_8 가정)
	engine.board_revive_pool = 1
	## 아군 0번에 1000 데미지 강제 (kill_unit 직접 호출 → 부활 처리 path)
	engine.alive[0] = 1
	engine.hp[0] = 1.0
	engine.kill_unit(0)
	## 풀 1 → 0으로 소비, alive=1 유지, hp=max_hp 복원
	assert_eq(engine.board_revive_pool, 0, "풀 1 소비 → 0")
	assert_eq(engine.alive[0], 1, "alive 유지")
	assert_almost_eq(engine.hp[0], engine.max_hp[0], 0.001, "100% HP 복원")


func test_r12_8_revive_pool_depleted_unit_dies() -> void:
	## 풀 0이면 부활 안 됨, alive = 0
	var CombatEngineScript = load("res://combat/combat_engine.gd")
	var engine = CombatEngineScript.new()
	engine.headless = true
	var ally_units = [{"atk": 10.0, "hp": 100.0, "attack_speed": 1.0,
		"range": 32.0, "move_speed": 2.0, "def": 0.0, "mechanics": []}]
	var enemy_units = [{"atk": 1000.0, "hp": 100.0, "attack_speed": 1.0,
		"range": 32.0, "move_speed": 2.0, "def": 0.0, "mechanics": []}]
	engine.setup(ally_units, enemy_units)
	engine.board_revive_pool = 0
	engine.kill_unit(0)
	assert_eq(engine.alive[0], 0, "풀 0 → 사망")


func test_r12_8_revive_pool_resets_each_setup() -> void:
	## setup 호출 시 board_revive_pool = 0으로 초기화 (caller 재주입 필요)
	var CombatEngineScript = load("res://combat/combat_engine.gd")
	var engine = CombatEngineScript.new()
	engine.headless = true
	engine.board_revive_pool = 5  # 직전 전투 잔여
	var ally_units = [{"atk": 10.0, "hp": 100.0, "attack_speed": 1.0,
		"range": 32.0, "move_speed": 2.0, "def": 0.0, "mechanics": []}]
	var enemy_units = [{"atk": 1000.0, "hp": 100.0, "attack_speed": 1.0,
		"range": 32.0, "move_speed": 2.0, "def": 0.0, "mechanics": []}]
	engine.setup(ally_units, enemy_units)
	assert_eq(engine.board_revive_pool, 0, "setup 시 0으로 reset")
