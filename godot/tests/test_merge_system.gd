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
