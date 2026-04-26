extends GutTest
## ★합성 시스템 테스트
## 참조: game_state.gd try_merge, card_instance.gd evolve_star/multiply_stats
##
## ★1×3→★2 / ★2×3→★3 / 유닛 흡수 / 스탯 보너스 / 실패 케이스 검증.


var _state: GameState = null


func before_each() -> void:
	_state = GameState.new()


# ================================================================
# try_merge 기본 성공
# ================================================================

func test_merge_3_star1_returns_star2() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_assembly")
	_state.board[2] = CardInstance.create("sp_assembly")
	var steps: Array = _state.try_merge("sp_assembly")
	assert_eq(steps.size(), 1, "3장 → 합성 성공")
	assert_eq(steps[0]["old_star"], 1, "이전 ★1")
	assert_eq(steps[0]["new_star"], 2, "합성 후 ★2")


func test_merge_survivor_is_first_copy() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_assembly")
	_state.board[2] = CardInstance.create("sp_assembly")
	var first_card: CardInstance = _state.board[0]
	var steps: Array = _state.try_merge("sp_assembly")
	assert_eq(steps[0]["card"], first_card, "첫 번째 카드가 생존자")


func test_merge_removes_2_donors() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_assembly")
	_state.board[2] = CardInstance.create("sp_assembly")
	_state.try_merge("sp_assembly")
	assert_eq(_state.board[1], null, "두 번째 슬롯 비워짐")
	assert_eq(_state.board[2], null, "세 번째 슬롯 비워짐")
	assert_ne(_state.board[0], null, "생존자 유지")


func test_merge_absorbs_donor_units() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_assembly")
	_state.board[2] = CardInstance.create("sp_assembly")
	var units_one: int = _state.board[0].get_total_units()
	_state.try_merge("sp_assembly")
	# 3장의 유닛이 1장에 합산
	assert_eq(_state.board[0].get_total_units(), units_one * 3, "유닛 3배 흡수")


# ================================================================
# ★1→★2 보너스: multiply_stats(0.30)
# ================================================================

func test_star2_merge_absorbs_units_no_stat_bonus() -> void:
	# 2026-04-20: 합성 ×1.30 스탯 보너스 제거 (사용자 의도 외). 유닛 흡수(3배)만 적용.
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_assembly")
	_state.board[2] = CardInstance.create("sp_assembly")
	var atk_before: float = _state.board[0].get_total_atk()
	_state.try_merge("sp_assembly")
	# ★2 유닛 흡수(3배)만 — 스탯 배수 없음 → ATK = base_atk * 3
	var expected: float = atk_before * 3.0
	assert_almost_eq(_state.board[0].get_total_atk(), expected, expected * 0.01, "★2 유닛 3배 (스탯 배수 없음)")


# ================================================================
# ★2→★3 합성
# ================================================================

func test_merge_3_star2_returns_star3() -> void:
	for i in 3:
		var card: CardInstance = CardInstance.create("sp_assembly")
		card.evolve_star()  # ★1→★2
		_state.board[i] = card
	var steps: Array = _state.try_merge("sp_assembly")
	assert_eq(steps.size(), 1, "★2 ×3 → 합성 성공")
	assert_eq(steps[0]["old_star"], 2, "이전 ★2")
	assert_eq(steps[0]["new_star"], 3, "합성 후 ★3")


func test_star3_merge_no_extra_multiplier() -> void:
	## ★2→★3은 multiply_stats 보너스 없음 (old_star==1일 때만)
	for i in 3:
		var card: CardInstance = CardInstance.create("sp_assembly")
		card.evolve_star()
		_state.board[i] = card
	var atk_before: float = _state.board[0].get_total_atk()
	var units_one: int = _state.board[0].get_total_units()
	_state.try_merge("sp_assembly")
	# 유닛 3배 흡수만, multiply_stats 없음
	var expected: float = atk_before * float(units_one * 3) / float(units_one)
	assert_almost_eq(_state.board[0].get_total_atk(), expected, expected * 0.01, "★3 ATK = 유닛 흡수만")


# ================================================================
# 실패 케이스
# ================================================================

func test_merge_fails_with_only_2_copies() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_assembly")
	var steps: Array = _state.try_merge("sp_assembly")
	assert_eq(steps.size(), 0, "2장 → 합성 불가")


func test_merge_fails_with_different_cards() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_workshop")
	_state.board[2] = CardInstance.create("sp_furnace")
	var steps: Array = _state.try_merge("sp_assembly")
	assert_eq(steps.size(), 0, "다른 카드 → 합성 불가")


func test_merge_fails_with_mixed_star_levels() -> void:
	## ★1 ×2 + ★2 ×1 → 같은 ★ 3장이 아니므로 합성 불가
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_assembly")
	var star2: CardInstance = CardInstance.create("sp_assembly")
	star2.evolve_star()
	_state.board[2] = star2
	var steps: Array = _state.try_merge("sp_assembly")
	# ★1이 2장뿐 → 합성 불가
	assert_eq(steps.size(), 0, "★1×2 + ★2×1 → 합성 불가")


func test_merge_no_cards_returns_empty() -> void:
	var steps: Array = _state.try_merge("sp_assembly")
	assert_eq(steps.size(), 0, "카드 없음 → 빈 배열")


# ================================================================
# 보드+벤치 교차 합성
# ================================================================

func test_merge_across_board_and_bench() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.bench[0] = CardInstance.create("sp_assembly")
	_state.bench[1] = CardInstance.create("sp_assembly")
	var steps: Array = _state.try_merge("sp_assembly")
	assert_eq(steps.size(), 1, "보드1 + 벤치2 = 3장 → 합성 성공")
	assert_eq(steps[0]["new_star"], 2, "★2")


func test_merge_donors_removed_from_bench() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.bench[0] = CardInstance.create("sp_assembly")
	_state.bench[1] = CardInstance.create("sp_assembly")
	_state.try_merge("sp_assembly")
	assert_eq(_state.bench[0], null, "벤치 도너 1 제거")
	assert_eq(_state.bench[1], null, "벤치 도너 2 제거")


# ================================================================
# evolve_star 개별 검증
# ================================================================

func test_evolve_star_increments_level() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	assert_eq(card.star_level, 1, "초기 ★1")
	card.evolve_star()
	assert_eq(card.star_level, 2, "진화 후 ★2")
	card.evolve_star()
	assert_eq(card.star_level, 3, "진화 후 ★3")


func test_evolve_star_capped_at_3() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	card.evolve_star()  # ★2
	card.evolve_star()  # ★3
	card.evolve_star()  # 여전히 ★3
	assert_eq(card.star_level, 3, "★3 초과 불가")


func test_evolve_star_resets_threshold_fired() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	card.threshold_fired = true
	card.evolve_star()
	assert_false(card.threshold_fired, "진화 시 threshold 리셋")


# ================================================================
# 업그레이드 누적 + survivor 선정 (R5 OBS-011 회귀)
# ================================================================
## R5 시나리오: rare 보너스로 부착된 R6 재생프로토콜이 ★2→★3 캐스케이드 시
## donor 카드에 있어 소멸하던 버그. donor 의 업그레이드는 모두 survivor 에 흡수되고,
## survivor 는 "업그레이드 수 최대 → 동점 시 leftmost(보드→벤치)" 로 선정돼야 함.

func test_merge_survivor_picks_card_with_most_upgrades() -> void:
	## board[0]=0 upg, board[1]=1 upg, board[2]=0 upg → survivor 는 board[1]
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_assembly")
	_state.board[2] = CardInstance.create("sp_assembly")
	_state.board[1].attach_upgrade("R1")
	var winner: CardInstance = _state.board[1]
	var steps: Array = _state.try_merge("sp_assembly")
	assert_eq(steps[0]["card"], winner, "업그레이드 보유 카드가 survivor")
	assert_eq(winner.upgrades.size(), 1, "survivor 의 기존 업그레이드 유지")


func test_merge_survivor_tie_picks_leftmost_board_then_bench() -> void:
	## 보드 1장 + 벤치 2장, 모두 업그레이드 0 → 보드 leftmost 가 survivor
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.bench[0] = CardInstance.create("sp_assembly")
	_state.bench[1] = CardInstance.create("sp_assembly")
	var board_card: CardInstance = _state.board[0]
	var steps: Array = _state.try_merge("sp_assembly")
	assert_eq(steps[0]["card"], board_card, "동점 시 보드 leftmost 우선")


func test_merge_absorbs_donor_upgrades() -> void:
	## donor 2장이 각각 1개씩 업그레이드 보유 → survivor 에 3개 모두 흡수
	## R5 OBS-011 회귀 핵심 케이스 (R6 재생프로토콜 소멸 방지)
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_assembly")
	_state.board[2] = CardInstance.create("sp_assembly")
	_state.board[0].attach_upgrade("C1")
	_state.board[1].attach_upgrade("R1")
	_state.board[2].attach_upgrade("C1")
	_state.try_merge("sp_assembly")
	# survivor 는 board[0] (가장 많은 업그레이드 동점 → leftmost)
	assert_eq(_state.board[0].upgrades.size(), 3, "donor 업그레이드 모두 흡수")


func test_merge_upgrade_overflow_truncates_at_max_slots() -> void:
	## survivor 4 + donor1 1 + donor2 1 = 6 → 5 슬롯 상한, 1개 truncate
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_assembly")
	_state.board[2] = CardInstance.create("sp_assembly")
	for _i in 4:
		_state.board[0].attach_upgrade("C1")
	_state.board[1].attach_upgrade("R1")
	_state.board[2].attach_upgrade("C1")
	_state.try_merge("sp_assembly")
	var max_slots: int = _state.board[0].get_max_upgrade_slots()
	assert_eq(_state.board[0].upgrades.size(), max_slots, "5 슬롯 상한 truncate")


# ================================================================
# 캐스케이드 머지 — steps 배열 반환 + 중간 보상 (OBS-047)
# ================================================================

func test_try_merge_returns_array() -> void:
	## try_merge()는 Array[Dictionary]를 반환해야 함
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_assembly")
	_state.board[2] = CardInstance.create("sp_assembly")
	var steps: Array = _state.try_merge("sp_assembly")
	assert_eq(steps.size(), 1, "단일 머지 → steps 1개")
	assert_eq(steps[0]["old_star"], 1)
	assert_eq(steps[0]["new_star"], 2)


func test_try_merge_no_merge_returns_empty_array() -> void:
	var steps: Array = _state.try_merge("sp_assembly")
	assert_eq(steps.size(), 0, "머지 불가 → 빈 배열")


func test_try_merge_cascade_returns_2_steps() -> void:
	## ★2×2(보드) + ★1×3(벤치) → step1: ★1→★2, step2: ★2→★3
	for i in 2:
		var s2: CardInstance = CardInstance.create("sp_assembly")
		s2.evolve_star()
		_state.board[i] = s2
	for i in 3:
		_state.bench[i] = CardInstance.create("sp_assembly")
	var steps: Array = _state.try_merge("sp_assembly")
	assert_eq(steps.size(), 2, "캐스케이드 → steps 2개")
	assert_eq(steps[0]["old_star"], 1, "step1: ★1→★2")
	assert_eq(steps[0]["new_star"], 2)
	assert_eq(steps[1]["old_star"], 2, "step2: ★2→★3")
	assert_eq(steps[1]["new_star"], 3)


func test_try_merge_cascade_step1_has_star2_for_reward() -> void:
	## 캐스케이드 step1이 old_star=1, new_star=2이므로 레어 업그레이드 보상 대상
	for i in 2:
		var s2: CardInstance = CardInstance.create("sp_assembly")
		s2.evolve_star()
		_state.board[i] = s2
	for i in 3:
		_state.bench[i] = CardInstance.create("sp_assembly")
	var steps: Array = _state.try_merge("sp_assembly")
	# step1이 ★1→★2이므로 build_phase에서 레어 업그레이드 팝업 트리거 가능
	assert_true(steps.size() >= 1, "최소 1 step")
	var has_star2_step := false
	for step in steps:
		if step["old_star"] == 1 and step["new_star"] == 2:
			has_star2_step = true
			break
	assert_true(has_star2_step, "캐스케이드에 ★1→★2 step 존재 (레어 보상 대상)")


func test_merge_cascade_preserves_upgrades_through_star3() -> void:
	## R5 정확 시나리오: ★1×3 머지 → rare 부착 → ★2×3 캐스케이드 → ★3
	## 캐스케이드 후에도 모든 rare 업그레이드 유지 (R6 재생프로토콜 소멸 방지)
	for i in 9:
		_state.bench[i % 8] = null  # safety
	# 9장 ★1 배치 (벤치 8 + 보드 1) — 캐스케이드로 ★3까지 가야 함
	_state.board[0] = CardInstance.create("sp_assembly")
	for i in 8:
		_state.bench[i] = CardInstance.create("sp_assembly")
	# 모든 카드에 rare 업그레이드 1개씩
	_state.board[0].attach_upgrade("R1")
	for i in 8:
		_state.bench[i].attach_upgrade("R1")
	var steps: Array = _state.try_merge("sp_assembly")
	assert_true(steps.size() > 0, "캐스케이드 머지 성공")
	assert_eq(steps.back().get("new_star", -1), 3, "캐스케이드로 ★3 도달")
	# survivor 의 업그레이드 수 == min(9, max_slots)
	var survivor: CardInstance = steps.back()["card"]
	var max_slots: int = survivor.get_max_upgrade_slots()
	assert_eq(survivor.upgrades.size(), mini(9, max_slots), "캐스케이드 통해 모든 업그레이드 흡수 (5 상한)")


# ================================================================
# 합성 정책 v2 (2026-04-26): 도너 stat 보존
# ----------------------------------------------------------------
# 정책 표:
#   유닛/업그레이드/체인강화/나무/theme_state 그룹A: 합산
#   stack mult / upgrade_as_mult: 곱셈 누적
#   upgrade_def/range/move_speed/shield_hp_pct: 합산
#   tenure / rank / unit_cap_bonus / upgrade_slot_bonus: max
#   activations_used: 0 리셋
#   threshold_fired: false (evolve_star가 처리, 검증)
#   theme_state 그룹B (pending_epic_upgrade, high_rank_applied), is_omni_theme: OR
#   theme_state 그룹C/D: survivor 유지 (검증 생략)
# ================================================================

func _three_assembly() -> Array:
	var arr: Array = []
	for i in 3:
		var c := CardInstance.create("sp_assembly")
		_state.board[i] = c
		arr.append(c)
	return arr


# --- 체인강화 (growth_atk_pct/hp_pct, tag_growth_*) — 합산 ---

func test_merge_sums_growth_atk_pct() -> void:
	var cs := _three_assembly()
	cs[0].growth_atk_pct = 0.10
	cs[1].growth_atk_pct = 0.20
	cs[2].growth_atk_pct = 0.30
	_state.try_merge("sp_assembly")
	assert_almost_eq(_state.board[0].growth_atk_pct, 0.60, 0.001, "growth_atk_pct 합산")


func test_merge_sums_growth_hp_pct() -> void:
	var cs := _three_assembly()
	cs[0].growth_hp_pct = 0.05
	cs[1].growth_hp_pct = 0.15
	cs[2].growth_hp_pct = 0.10
	_state.try_merge("sp_assembly")
	assert_almost_eq(_state.board[0].growth_hp_pct, 0.30, 0.001, "growth_hp_pct 합산")


func test_merge_sums_tag_growth_per_tag() -> void:
	var cs := _three_assembly()
	cs[0].tag_growth_atk = {"기계": 0.10}
	cs[1].tag_growth_atk = {"기계": 0.20, "대형": 0.05}
	cs[2].tag_growth_atk = {"대형": 0.10}
	_state.try_merge("sp_assembly")
	var s: CardInstance = _state.board[0]
	assert_almost_eq(s.tag_growth_atk.get("기계", 0.0), 0.30, 0.001, "기계 태그 합산")
	assert_almost_eq(s.tag_growth_atk.get("대형", 0.0), 0.15, 0.001, "대형 태그 합산")


# --- stack mult (upgrade_atk_mult/hp_mult) — 곱셈 누적 ---

func test_merge_multiplies_stack_atk_mult() -> void:
	var cs := _three_assembly()
	for s in cs[0].stacks: s["upgrade_atk_mult"] = 1.30
	for s in cs[1].stacks: s["upgrade_atk_mult"] = 1.20
	for s in cs[2].stacks: s["upgrade_atk_mult"] = 1.10
	_state.try_merge("sp_assembly")
	# 1.30 * 1.20 * 1.10 = 1.716
	for s in _state.board[0].stacks:
		assert_almost_eq(s["upgrade_atk_mult"], 1.716, 0.001, "stack atk_mult 곱셈 누적")


func test_merge_multiplies_stack_hp_mult() -> void:
	var cs := _three_assembly()
	for s in cs[0].stacks: s["upgrade_hp_mult"] = 1.20
	for s in cs[1].stacks: s["upgrade_hp_mult"] = 1.10
	for s in cs[2].stacks: s["upgrade_hp_mult"] = 1.10
	_state.try_merge("sp_assembly")
	# 1.20 * 1.10 * 1.10 = 1.452
	for s in _state.board[0].stacks:
		assert_almost_eq(s["upgrade_hp_mult"], 1.452, 0.001, "stack hp_mult 곱셈 누적")


# --- 업그레이드 stat (def/range/ms 가산, as_mult 곱셈) ---

func test_merge_sums_upgrade_def_range_ms() -> void:
	var cs := _three_assembly()
	cs[0].upgrade_def = 1; cs[0].upgrade_range = 0; cs[0].upgrade_move_speed = 0
	cs[1].upgrade_def = 2; cs[1].upgrade_range = 1; cs[1].upgrade_move_speed = 1
	cs[2].upgrade_def = 0; cs[2].upgrade_range = 2; cs[2].upgrade_move_speed = 0
	_state.try_merge("sp_assembly")
	var s: CardInstance = _state.board[0]
	assert_eq(s.upgrade_def, 3, "upgrade_def 합산")
	assert_eq(s.upgrade_range, 3, "upgrade_range 합산")
	assert_eq(s.upgrade_move_speed, 1, "upgrade_move_speed 합산")


func test_merge_multiplies_upgrade_as_mult() -> void:
	var cs := _three_assembly()
	cs[0].upgrade_as_mult = 0.90
	cs[1].upgrade_as_mult = 0.80
	cs[2].upgrade_as_mult = 1.00
	_state.try_merge("sp_assembly")
	# 0.90 * 0.80 * 1.00 = 0.72
	assert_almost_eq(_state.board[0].upgrade_as_mult, 0.72, 0.001, "upgrade_as_mult 곱셈 누적")


func test_merge_sums_shield_hp_pct() -> void:
	var cs := _three_assembly()
	cs[0].shield_hp_pct = 0.10
	cs[1].shield_hp_pct = 0.20
	cs[2].shield_hp_pct = 0.05
	_state.try_merge("sp_assembly")
	assert_almost_eq(_state.board[0].shield_hp_pct, 0.35, 0.001, "shield_hp_pct 합산")


# --- 진행도/등급 (tenure, rank, unit_cap_bonus, upgrade_slot_bonus) — max ---

func test_merge_takes_max_tenure() -> void:
	var cs := _three_assembly()
	cs[0].tenure = 3
	cs[1].tenure = 7
	cs[2].tenure = 5
	_state.try_merge("sp_assembly")
	assert_eq(_state.board[0].tenure, 7, "tenure max")


func test_merge_takes_max_rank_in_theme_state() -> void:
	var cs := _three_assembly()
	cs[0].theme_state["rank"] = 2
	cs[1].theme_state["rank"] = 8
	cs[2].theme_state["rank"] = 5
	_state.try_merge("sp_assembly")
	assert_eq(_state.board[0].theme_state.get("rank", 0), 8, "rank max")


func test_merge_takes_max_unit_cap_bonus() -> void:
	var cs := _three_assembly()
	cs[0].unit_cap_bonus = 0
	cs[1].unit_cap_bonus = 5
	cs[2].unit_cap_bonus = 2
	_state.try_merge("sp_assembly")
	assert_eq(_state.board[0].unit_cap_bonus, 5, "unit_cap_bonus max")


func test_merge_takes_max_upgrade_slot_bonus() -> void:
	var cs := _three_assembly()
	cs[0].upgrade_slot_bonus = 1
	cs[1].upgrade_slot_bonus = 0
	cs[2].upgrade_slot_bonus = 0
	_state.try_merge("sp_assembly")
	assert_eq(_state.board[0].upgrade_slot_bonus, 1, "upgrade_slot_bonus max")


# --- theme_state 그룹A 합산 ---

func test_merge_sums_theme_state_group_a() -> void:
	var cs := _three_assembly()
	for c in cs:
		c.theme_state["trees"] = 0
	cs[0].theme_state["trees"] = 5
	cs[1].theme_state["trees"] = 3
	cs[2].theme_state["trees"] = 2
	cs[0].theme_state["manufacture_counter"] = 4
	cs[1].theme_state["manufacture_counter"] = 1
	cs[2].theme_state["attack_stack_pct"] = 0.10
	cs[1].theme_state["attack_stack_pct"] = 0.05
	cs[0].theme_state["range_bonus"] = 1
	cs[2].theme_state["range_bonus"] = 2
	_state.try_merge("sp_assembly")
	var ts: Dictionary = _state.board[0].theme_state
	assert_eq(ts.get("trees", 0), 10, "trees 합산")
	assert_eq(ts.get("manufacture_counter", 0), 5, "manufacture_counter 합산")
	assert_almost_eq(ts.get("attack_stack_pct", 0.0), 0.15, 0.001, "attack_stack_pct 합산")
	assert_eq(ts.get("range_bonus", 0), 3, "range_bonus 합산")


# --- theme_state 그룹B (OR) ---

func test_merge_or_pending_epic_upgrade() -> void:
	var cs := _three_assembly()
	cs[1].theme_state["pending_epic_upgrade"] = true
	_state.try_merge("sp_assembly")
	assert_true(_state.board[0].theme_state.get("pending_epic_upgrade", false),
		"donor 1장이 true → survivor true (OR)")


func test_merge_or_high_rank_applied() -> void:
	var cs := _three_assembly()
	cs[2].theme_state["high_rank_applied"] = true
	_state.try_merge("sp_assembly")
	assert_true(_state.board[0].theme_state.get("high_rank_applied", false),
		"donor 1장이 true → survivor true (OR)")


# --- is_omni_theme OR ---

func test_merge_or_is_omni_theme() -> void:
	var cs := _three_assembly()
	cs[1].is_omni_theme = true
	_state.try_merge("sp_assembly")
	assert_true(_state.board[0].is_omni_theme,
		"donor 1장이 omni → survivor omni (OR)")


# --- activations_used 0 리셋 ---

func test_merge_resets_activations_used_to_zero() -> void:
	var cs := _three_assembly()
	cs[0].activations_used = 2
	cs[1].activations_used = 1
	cs[2].activations_used = 3
	_state.try_merge("sp_assembly")
	assert_eq(_state.board[0].activations_used, 0,
		"합성 후 activations_used = 0 (다음 발동 가능)")


# --- threshold_fired false (evolve_star 동작 확인) ---

func test_merge_resets_threshold_fired_via_evolve_star() -> void:
	var cs := _three_assembly()
	cs[0].threshold_fired = true
	cs[1].threshold_fired = true
	cs[2].threshold_fired = true
	_state.try_merge("sp_assembly")
	assert_false(_state.board[0].threshold_fired,
		"evolve_star가 threshold_fired를 false로 리셋")


# --- stack mult floor는 표시 시점에만 적용 (내부는 full precision) ---

func test_merge_stack_mult_keeps_full_precision_internally() -> void:
	## floor(0.01)은 UI 표시 시점에만. 내부 stack mult는 부동소수점 그대로.
	var cs := _three_assembly()
	for s in cs[0].stacks: s["upgrade_atk_mult"] = 1.33
	for s in cs[1].stacks: s["upgrade_atk_mult"] = 1.27
	for s in cs[2].stacks: s["upgrade_atk_mult"] = 1.19
	_state.try_merge("sp_assembly")
	# 1.33 * 1.27 * 1.19 = 2.010029 — 내부 full precision 유지
	for s in _state.board[0].stacks:
		assert_almost_eq(s["upgrade_atk_mult"], 2.010029, 0.0001,
			"stack mult full precision (UI floor 분리)")


# ================================================================
# 세계수 [고유효과] — unique_*_mult 분리 + max 합성 정책
# ----------------------------------------------------------------
# dr_world 매 RS 곱셈 누적이 합성 시 폭발(예: ★3 캐스케이드 ×100+)하지
# 않도록, 세계수 발 mult는 별도 unique_*_mult 필드에 분리하고 합성 시
# max로 합친다. 다른 입력원(% 업그레이드, 보스, 커맨더)은 기존 곱셈 그대로.
# ================================================================

func test_merge_takes_max_unique_atk_mult_per_stack() -> void:
	var cs := _three_assembly()
	for s in cs[0].stacks: s["unique_atk_mult"] = 1.30
	for s in cs[1].stacks: s["unique_atk_mult"] = 1.80
	for s in cs[2].stacks: s["unique_atk_mult"] = 1.50
	_state.try_merge("sp_assembly")
	# max(1.30, 1.80, 1.50) = 1.80 — 합성 시 max
	for s in _state.board[0].stacks:
		assert_almost_eq(s["unique_atk_mult"], 1.80, 0.0001,
			"unique_atk_mult max 합성")


func test_merge_takes_max_unique_hp_mult_per_stack() -> void:
	var cs := _three_assembly()
	for s in cs[0].stacks: s["unique_hp_mult"] = 1.10
	for s in cs[1].stacks: s["unique_hp_mult"] = 1.40
	for s in cs[2].stacks: s["unique_hp_mult"] = 1.20
	_state.try_merge("sp_assembly")
	for s in _state.board[0].stacks:
		assert_almost_eq(s["unique_hp_mult"], 1.40, 0.0001,
			"unique_hp_mult max 합성")


func test_merge_takes_min_unique_as_mult() -> void:
	## AS 값은 시간 단위 — 작을수록 빠름. min이 "가장 빠른 도너 보존" 의미.
	## ATK/HP unique mult는 max (큰 값이 강함), AS만 min — semantic 정합.
	var cs := _three_assembly()
	cs[0].unique_as_mult = 0.90
	cs[1].unique_as_mult = 0.70  # 가장 빠른 도너
	cs[2].unique_as_mult = 0.85
	_state.try_merge("sp_assembly")
	# min(0.90, 0.70, 0.85) = 0.70 — 가장 빠른 보존
	assert_almost_eq(_state.board[0].unique_as_mult, 0.70, 0.0001,
		"unique_as_mult min 합성 (AS 작을수록 빠름)")


func test_multiply_unique_stats_writes_to_unique_field_only() -> void:
	## multiply_unique_stats 호출은 unique_*_mult에만 적용,
	## upgrade_*_mult는 영향받지 않음.
	var card := CardInstance.create("sp_assembly")
	var upg_before: float = card.stacks[0]["upgrade_atk_mult"]
	card.multiply_unique_stats(0.30, 0.20)
	assert_almost_eq(card.stacks[0]["unique_atk_mult"], 1.30, 0.0001,
		"unique_atk_mult ×1.30")
	assert_almost_eq(card.stacks[0]["unique_hp_mult"], 1.20, 0.0001,
		"unique_hp_mult ×1.20")
	assert_eq(card.stacks[0]["upgrade_atk_mult"], upg_before,
		"upgrade_atk_mult 영향 없음")


func test_eff_atk_combines_upgrade_and_unique_mults() -> void:
	## eff_atk_for = base * (1+growth) * upgrade_mult * unique_mult * temp
	var card := CardInstance.create("sp_assembly")
	card.stacks[0]["upgrade_atk_mult"] = 1.50
	card.stacks[0]["unique_atk_mult"] = 1.20
	var base: float = card.stacks[0]["unit_type"]["atk"]
	# Layer1 growth = 0, temp = 1.0
	var expected: float = base * 1.50 * 1.20
	assert_almost_eq(card.eff_atk_for(card.stacks[0]), expected, 0.001,
		"eff_atk = base × upgrade_mult × unique_mult")


# ================================================================
# fresh_ref policy (2026-04-26): 신규 카드 유닛 흡수 skip
# ----------------------------------------------------------------
# 신규 생성된 카드를 try_merge에 fresh_ref 인자로 전달하면:
#   - 도너 참여 시 유닛 흡수 제외 (3장 중 1장 fresh → 결과 2장분량)
#   - survivor 선정: (업그레이드 max → non-fresh 우선 → leftmost) 3-tier
#   - 캐스케이드: fresh 포함 step의 survivor도 다음 step에서 fresh 추적
# fresh_ref=null (default): 기존 3장 흡수 동작 유지 (회귀 보호).
# 카드 필드(is_fresh) 도입 안 함 — 호출 인자로만 전달 (로컬 스코프).
# ================================================================

func test_fresh_donor_units_skipped_two_thirds() -> void:
	## 3장 중 1장이 fresh → 도너 유닛 흡수에서 제외 = 2장분량
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_assembly")
	_state.board[2] = CardInstance.create("sp_assembly")
	var fresh: CardInstance = _state.board[2]
	var units_one: int = _state.board[0].get_total_units()
	_state.try_merge("sp_assembly", fresh)
	# survivor 선정: 모두 동률이지만 fresh 후순위 → board[0] (leftmost non-fresh)
	# survivor own (units_one) + non-fresh donor (units_one) + fresh donor (skip 0) = 2 * units_one
	assert_eq(_state.board[0].get_total_units(), units_one * 2,
		"fresh 도너 유닛 미흡수 → 2장분량")


func test_fresh_ref_null_keeps_3x_legacy_absorption() -> void:
	## fresh_ref 미전달 시 기존 3배 흡수 동작 보존 (회귀 보호)
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_assembly")
	_state.board[2] = CardInstance.create("sp_assembly")
	var units_one: int = _state.board[0].get_total_units()
	_state.try_merge("sp_assembly")
	assert_eq(_state.board[0].get_total_units(), units_one * 3,
		"fresh_ref 없음 → 기존 3장 흡수 (legacy)")


func test_fresh_survivor_prefers_non_fresh_when_upgrades_tied() -> void:
	## 업그레이드 동률 (모두 0) + 1장이 fresh → fresh가 survivor가 아님
	_state.board[0] = CardInstance.create("sp_assembly")  # leftmost, fresh
	_state.board[1] = CardInstance.create("sp_assembly")
	_state.board[2] = CardInstance.create("sp_assembly")
	var fresh: CardInstance = _state.board[0]
	var steps: Array = _state.try_merge("sp_assembly", fresh)
	# leftmost(board[0])가 fresh → tier2 (non-fresh 우선)에 따라 다음 후보(board[1])가 survivor
	assert_ne(steps[0]["card"], fresh, "fresh survivor 회피 (non-fresh 우선)")


func test_fresh_survivor_kept_when_uniquely_most_upgrades() -> void:
	## fresh가 유일한 upgrade 보유 → 업그레이드 우선이 더 강함, fresh가 survivor
	## 이 경우 fresh own units 유지 (skip은 donor에만)
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_assembly")
	_state.board[2] = CardInstance.create("sp_assembly")
	var fresh: CardInstance = _state.board[0]
	fresh.attach_upgrade("R1")
	var units_one: int = _state.board[0].get_total_units()
	var steps: Array = _state.try_merge("sp_assembly", fresh)
	assert_eq(steps[0]["card"], fresh, "fresh가 upgrade 유일 보유 → fresh survivor")
	# survivor own + 2 non-fresh donors = 3 * units_one (fresh 자기 유닛은 유지)
	assert_eq(steps[0]["card"].get_total_units(), units_one * 3,
		"fresh survivor own units 유지 (skip은 donor만)")


func test_fresh_propagates_through_cascade_to_star3() -> void:
	## 2 non-fresh ★2 + 3 ★1 (1 fresh) → cascade ★1→★2→★3
	## ★1 base = 4u (sp_assembly).
	## step1 (★1×3 with 1 fresh): non-fresh survivor 4u + 1 non-fresh donor 4u + fresh skip
	##   = 8u ★2, 결과는 fresh-tagged (cascade propagation)
	## step2 (★2×3, 1 fresh from step1): non-fresh survivor 4u + non-fresh donor 4u + fresh skip
	##   = 8u ★3
	var s2_a := CardInstance.create("sp_assembly")
	s2_a.evolve_star()
	var s2_b := CardInstance.create("sp_assembly")
	s2_b.evolve_star()
	_state.board[0] = s2_a
	_state.board[1] = s2_b
	_state.bench[0] = CardInstance.create("sp_assembly")
	_state.bench[1] = CardInstance.create("sp_assembly")
	_state.bench[2] = CardInstance.create("sp_assembly")
	var fresh: CardInstance = _state.bench[2]
	var base_units: int = _state.bench[0].get_total_units()  # ★1 base = 4

	var steps: Array = _state.try_merge("sp_assembly", fresh)
	assert_eq(steps.size(), 2, "캐스케이드 2 steps")
	assert_eq(steps[1]["new_star"], 3, "★3 도달")
	# 최종 ★3: 2 ★2 worth = 2 * base_units (fresh propagation으로 cascade ★2 도너 skip)
	assert_eq(steps[1]["card"].get_total_units(), base_units * 2,
		"★3 = 2장분량 ★2 (fresh propagation)")


func test_fresh_no_propagation_means_full_3x_at_step2() -> void:
	## 위 테스트의 대조: fresh propagation이 없는 경우(fresh_ref=null)
	## step2에서 cascade ★2 도너도 정상 흡수 → ★3 = 3 ★2 worth
	var s2_a := CardInstance.create("sp_assembly")
	s2_a.evolve_star()
	var s2_b := CardInstance.create("sp_assembly")
	s2_b.evolve_star()
	_state.board[0] = s2_a
	_state.board[1] = s2_b
	_state.bench[0] = CardInstance.create("sp_assembly")
	_state.bench[1] = CardInstance.create("sp_assembly")
	_state.bench[2] = CardInstance.create("sp_assembly")
	var base_units: int = _state.bench[0].get_total_units()

	var steps: Array = _state.try_merge("sp_assembly")  # fresh_ref 미전달
	# step1: 3*base ★2 cascade. step2: cascade ★2 (3*base) + 2 ★2 base = 5*base ★3
	assert_eq(steps[1]["card"].get_total_units(), base_units * 5,
		"fresh_ref 없음 → step1 3*base + step2의 다른 ★2 2*base = 5*base")


func test_fresh_only_applies_when_in_picked_three() -> void:
	## 4장 ★1 (board 1 + bench 3) — 첫 3장(board[0] + bench[0,1])만 합성에 픽
	## fresh가 4번째(bench[2])에 있어 픽되지 않음 → fresh skip 미적용 → 3배 흡수
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.bench[0] = CardInstance.create("sp_assembly")
	_state.bench[1] = CardInstance.create("sp_assembly")
	_state.bench[2] = CardInstance.create("sp_assembly")
	var fresh: CardInstance = _state.bench[2]  # 픽되지 않을 위치
	var units_one: int = _state.board[0].get_total_units()
	_state.try_merge("sp_assembly", fresh)
	assert_eq(_state.board[0].get_total_units(), units_one * 3,
		"fresh가 픽 안 된 경우 → 정상 3배 흡수")


# ================================================================
# spawn_card funnel (2026-04-26): 단일 진입점
# ----------------------------------------------------------------
# 모든 신규 카드 spawn은 GameState.spawn_card()를 통해야 함.
# 내부적으로 CardInstance.create + add_to_bench + try_merge(fresh_ref=card).
# 클론(시스템 생성) 경로는 GameState.add_clone()를 사용 — try_merge 호출 안 함.
# ================================================================

func test_spawn_card_creates_and_benches() -> void:
	## spawn_card는 카드 생성 후 벤치에 추가
	var result: Dictionary = _state.spawn_card("sp_assembly")
	assert_true(result.has("card"), "result에 card 키")
	assert_ne(result["card"], null, "card 생성 성공")
	# 벤치 어딘가에 있어야 함
	var found := false
	for c in _state.bench:
		if c == result["card"]:
			found = true
			break
	assert_true(found, "벤치에 추가됨")


func test_spawn_card_with_two_existing_triggers_fresh_merge() -> void:
	## 벤치에 2 ★1 → spawn 1 ★1 (fresh) → 자동 합성, 2장분량 흡수
	_state.bench[0] = CardInstance.create("sp_assembly")
	_state.bench[1] = CardInstance.create("sp_assembly")
	var units_one: int = _state.bench[0].get_total_units()

	var result: Dictionary = _state.spawn_card("sp_assembly")
	var merge_steps: Array = result["merge_steps"]
	assert_eq(merge_steps.size(), 1, "auto-merge 발생")
	assert_eq(merge_steps[0]["new_star"], 2, "★2 도달")
	# fresh skip → 2장분량
	assert_eq(merge_steps[0]["card"].get_total_units(), units_one * 2,
		"spawn_card는 fresh_ref로 전달 → 2장분량 흡수")


func test_spawn_card_no_merge_returns_empty_steps() -> void:
	## 같은 카드 없으면 merge 없이 벤치 추가만
	var result: Dictionary = _state.spawn_card("sp_assembly")
	assert_eq((result["merge_steps"] as Array).size(), 0,
		"동일 카드 없음 → merge 없음")
	assert_ne(result["card"], null, "카드는 정상 생성")


func test_spawn_card_bench_full_signals_via_bench_idx() -> void:
	## 벤치가 가득 찬 경우 result["bench_idx"] == -1로 신호 (호출자가 처리)
	for i in _state.bench.size():
		_state.bench[i] = CardInstance.create("sp_workshop")  # 다른 카드로 채움
	var result: Dictionary = _state.spawn_card("sp_assembly")
	assert_eq(result.get("bench_idx", 0), -1, "벤치 풀 → bench_idx = -1")
	assert_eq((result.get("merge_steps", []) as Array).size(), 0,
		"벤치 풀 → merge 미시도")


func test_add_clone_creates_without_merge() -> void:
	## add_clone (클론 경로)은 try_merge 호출 안 함
	_state.bench[0] = CardInstance.create("sp_assembly")
	_state.bench[1] = CardInstance.create("sp_assembly")
	var clone: CardInstance = _state.add_clone("sp_assembly")
	assert_ne(clone, null, "클론 생성")
	# 3장 ★1이 모였지만 add_clone은 merge 미트리거 → 모두 ★1로 남음
	var star1_count := 0
	for c in _state.bench:
		if c != null and c.template_id == "sp_assembly" and c.star_level == 1:
			star1_count += 1
	assert_eq(star1_count, 3, "add_clone은 auto-merge 안 함 → ★1 3장 유지")
