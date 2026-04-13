extends GutTest
## 커맨더 7종 시스템 테스트 (RED → GREEN)
## 참조: docs/design/commanders.md (확정)
##
## 구조: Commander (데이터/쿼리) + GameState (커맨더 상태) + 각 시스템 훅
## Commander는 autoload Node — 테스트에서는 preload로 인스턴스 생성.

const CommanderScript = preload("res://core/commander.gd")

var _state: GameState = null
var _rng: RandomNumberGenerator = null
var _chain: ChainEngine = null
var _cmd: Node = null


func before_each() -> void:
	_state = GameState.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 42
	_chain = ChainEngine.new()
	_chain.set_seed(42)
	_cmd = CommanderScript.new()


func after_each() -> void:
	if _cmd != null:
		_cmd.free()


# ================================================================
# Commander 데이터 정의 검증
# ================================================================

func test_commander_enum_has_8_values() -> void:
	## NONE + 7종 = 8
	assert_eq(Enums.CommanderType.size(), 8, "NONE + 7종 커맨더")


func test_commander_data_exists_for_all_types() -> void:
	for type_val in Enums.CommanderType.values():
		if type_val == Enums.CommanderType.NONE:
			continue
		var data: Dictionary = _cmd.get_data(type_val)
		assert_false(data.is_empty(), "커맨더 %d 데이터 존재" % type_val)
		assert_has(data, "name", "커맨더 %d에 name 필드" % type_val)


# ================================================================
# 🎲 도박꾼
# ================================================================

func test_gambler_start_gold_bonus() -> void:
	## 시작 골드 +3
	_state.commander_type = Enums.CommanderType.GAMBLER
	_cmd.apply_start_bonus(_state, _rng)
	assert_eq(_state.gold, 3, "도박꾼 시작 골드 보너스 +3")


func test_gambler_reroll_50_percent_free() -> void:
	## 리롤 시 50% 확률로 무료
	_state.commander_type = Enums.CommanderType.GAMBLER
	_state.gold = 100

	var free_count := 0
	for i in 200:
		if _cmd.is_reroll_free(_state, _rng):
			free_count += 1

	# 200회 중 50%±15% 범위 (70~130 무료)
	assert_gt(free_count, 60, "무료 리롤 60회 이상")
	assert_lt(free_count, 140, "무료 리롤 140회 미만")


func test_gambler_merge_refund() -> void:
	## ★합성 시 합성에 사용된 카드의 구매 비용 합계의 50% 골드 환급
	_state.commander_type = Enums.CommanderType.GAMBLER
	_state.gold = 50

	# sp_assembly는 T1, cost=2. 3장 합성 → 비용 합 = 6 → 50% = 3
	for i in 3:
		var card := CardInstance.create("sp_assembly")
		if i < 2:
			_state.bench[i] = card
		else:
			_state.board[0] = card

	var steps := _state.try_merge("sp_assembly")
	assert_true(steps.size() > 0, "합성 성공")

	var refund: int = _cmd.calc_merge_refund(_state, steps.back())
	_state.gold += refund

	# cost=2 × 3장 = 6, 50% = 3
	assert_eq(refund, 3, "합성 환급 = 구매비용합 6 × 50% = 3")


# ================================================================
# 🌱 양성가
# ================================================================

func test_breeder_start_units_plus_2() -> void:
	## 시작 카드 각각에 유닛 +2
	_state.commander_type = Enums.CommanderType.BREEDER
	var card := CardInstance.create("sp_assembly")
	_state.board[0] = card
	var units_before := card.get_total_units()

	_cmd.apply_start_bonus(_state, _rng)
	assert_eq(card.get_total_units(), units_before + 2,
		"양성가 시작 카드 유닛 +2")


func test_breeder_unit_cap_80() -> void:
	## 카드당 유닛 상한 +20 (60→80)
	_state.commander_type = Enums.CommanderType.BREEDER
	var card := CardInstance.create("sp_assembly")
	card.unit_cap_bonus = _cmd.get_unit_cap_bonus(_state)

	assert_eq(card.get_unit_cap(), 80, "양성가 유닛 상한 80")


func test_breeder_bonus_spawn_30_percent() -> void:
	## 유닛 추가 시 30% 확률로 1기 동시 생성 (이벤트 미방출)
	## cap 도달 전 50회만 테스트 (시작 3유닛 + ~65 = cap 80 전)
	_state.commander_type = Enums.CommanderType.BREEDER
	var card := CardInstance.create("sp_assembly")
	card.unit_cap_bonus = 20

	var bonus_count := 0
	var trials := 50
	for i in trials:
		var units_before := card.get_total_units()
		card.spawn_random_with_bonus(_rng, 0.3)
		var added := card.get_total_units() - units_before
		if added > 1:
			bonus_count += 1

	# 50회 중 30%±20% 범위 (5~25 보너스)
	assert_gt(bonus_count, 4, "보너스 유닛 4회 이상 (50회 × 30%)")
	assert_lt(bonus_count, 30, "보너스 유닛 30회 미만")


func test_breeder_default_no_bonus() -> void:
	## 커맨더 NONE일 때 unit_cap_bonus = 0
	assert_eq(_cmd.get_unit_cap_bonus(_state), 0, "기본 유닛 상한 보너스 0")


# ================================================================
# ⚒️ 단조사
# ================================================================

func test_smith_upgrade_slot_6() -> void:
	## 업그레이드 슬롯 +1 (5→6)
	_state.commander_type = Enums.CommanderType.SMITH
	var card := CardInstance.create("sp_assembly")
	card.upgrade_slot_bonus = _cmd.get_upgrade_slot_bonus(_state)

	assert_eq(card.get_max_upgrade_slots(), 6, "단조사 업그레이드 슬롯 6")


func test_smith_common_cost_discount() -> void:
	## 커먼 업그레이드 비용 -1 테라진 (4→3)
	_state.commander_type = Enums.CommanderType.SMITH
	var discount: int = _cmd.get_common_upgrade_discount(_state)
	assert_eq(discount, 1, "단조사 커먼 할인 -1t")


func test_smith_default_no_discount() -> void:
	assert_eq(_cmd.get_common_upgrade_discount(_state), 0, "기본 커먼 할인 0")


# ================================================================
# 📐 전략가
# ================================================================

func test_strategist_field_7() -> void:
	## 필드 시작 크기 +1 (6→7)
	_state.commander_type = Enums.CommanderType.STRATEGIST
	var bonus: int = _cmd.get_field_size_bonus(_state)
	assert_eq(bonus, 1, "전략가 필드 보너스 +1")


func test_strategist_adjacency_range_2() -> void:
	## 인접 효과 범위 2칸 확장
	_state.commander_type = Enums.CommanderType.STRATEGIST
	var adj_range: int = _cmd.get_adjacency_range(_state)
	assert_eq(adj_range, 2, "전략가 인접 범위 2칸")


func test_default_adjacency_range_1() -> void:
	assert_eq(_cmd.get_adjacency_range(_state), 1, "기본 인접 범위 1칸")


func test_strategist_swap_preserves_tenure() -> void:
	## 영웅 능력: 카드 2장 교환 시 tenure 유지
	_state.commander_type = Enums.CommanderType.STRATEGIST
	var card_a := CardInstance.create("sp_assembly")
	card_a.tenure = 5
	var card_b := CardInstance.create("sp_workshop")
	card_b.tenure = 3

	_state.board[0] = card_a
	_state.board[1] = card_b

	var ok: bool = _cmd.hero_swap(_state, 0, 1)
	assert_true(ok, "영웅 교환 성공")
	assert_eq(_state.board[0], card_b, "위치 교환됨")
	assert_eq(_state.board[1], card_a, "위치 교환됨")
	assert_eq(card_a.tenure, 5, "tenure A 유지")
	assert_eq(card_b.tenure, 3, "tenure B 유지")


func test_strategist_swap_once_per_build() -> void:
	## 빌드 페이즈당 1회 제한
	_state.commander_type = Enums.CommanderType.STRATEGIST
	var card_a := CardInstance.create("sp_assembly")
	var card_b := CardInstance.create("sp_workshop")
	_state.board[0] = card_a
	_state.board[1] = card_b

	assert_true(_cmd.hero_swap(_state, 0, 1), "1회 성공")
	assert_false(_cmd.hero_swap(_state, 0, 1), "2회 실패")


# ================================================================
# 📚 수집가
# ================================================================

func test_collector_unique_atk_bonus() -> void:
	## 서로 다른 카드 종류 1개당 전체 아군 ATK +4%
	_state.commander_type = Enums.CommanderType.COLLECTOR

	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_workshop")
	_state.board[2] = CardInstance.create("ne_wanderers")

	var bonus: float = _cmd.calc_collector_atk_bonus(_state)
	# 3종 × 4% = 12%
	assert_almost_eq(bonus, 0.12, 0.001, "3종 × 4% = 12%")


func test_collector_terazin_at_5_types() -> void:
	## 5종+ → 매 라운드 +1 테라진
	_state.commander_type = Enums.CommanderType.COLLECTOR

	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_workshop")
	_state.board[2] = CardInstance.create("ne_wanderers")
	_state.board[3] = CardInstance.create("ne_earth_echo")
	_state.board[4] = CardInstance.create("ne_mana_crystal")

	var terazin: int = _cmd.calc_settlement_terazin(_state)
	assert_eq(terazin, 1, "5종 이상 → +1 테라진")


func test_collector_no_terazin_under_5() -> void:
	_state.commander_type = Enums.CommanderType.COLLECTOR
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("sp_workshop")

	var terazin: int = _cmd.calc_settlement_terazin(_state)
	assert_eq(terazin, 0, "5종 미만 → 테라진 0")


# ================================================================
# ⚔️ 약탈자
# ================================================================

func test_raider_start_atk_boost() -> void:
	## 시작 카드 전투 스탯 ATK +20% (영구)
	_state.commander_type = Enums.CommanderType.RAIDER
	var card := CardInstance.create("sp_assembly")
	_state.board[0] = card

	var atk_before := card.get_total_atk()
	_cmd.apply_start_bonus(_state, _rng)
	var atk_after := card.get_total_atk()

	assert_almost_eq(atk_after, atk_before * 1.2, 0.01,
		"약탈자 시작 ATK +20%")


func test_raider_win_gold_bonus() -> void:
	## 전투 승리 시 추가 +2 골드
	_state.commander_type = Enums.CommanderType.RAIDER
	var bonus: int = _cmd.calc_battle_win_gold(_state)
	assert_eq(bonus, 2, "약탈자 승리 +2골드")


func test_raider_no_bonus_on_loss() -> void:
	_state.commander_type = Enums.CommanderType.NONE
	var bonus: int = _cmd.calc_battle_win_gold(_state)
	assert_eq(bonus, 0, "기본 승리 보너스 0")


func test_raider_3_wins_free_upgrade() -> void:
	## 3승 누적마다 무료 커먼 업그레이드 획득
	_state.commander_type = Enums.CommanderType.RAIDER
	_state.commander_state["win_count"] = 2

	# 3번째 승리
	_state.commander_state["win_count"] += 1
	var should_grant: bool = _cmd.check_raider_upgrade(_state)
	assert_true(should_grant, "3승 도달 → 업그레이드 획득")

	# 카운터 리셋 확인
	assert_eq(_state.commander_state["win_count"], 0, "카운터 리셋")


func test_raider_no_upgrade_at_2_wins() -> void:
	_state.commander_type = Enums.CommanderType.RAIDER
	_state.commander_state["win_count"] = 2
	var should_grant: bool = _cmd.check_raider_upgrade(_state)
	assert_false(should_grant, "2승에선 업그레이드 없음")


# ================================================================
# 💰 연금술사
# ================================================================

func test_alchemist_round_terazin() -> void:
	## 매 라운드 +1 테라진
	_state.commander_type = Enums.CommanderType.ALCHEMIST
	var bonus: int = _cmd.calc_settlement_terazin(_state)
	assert_eq(bonus, 1, "연금술사 매 라운드 +1 테라진")


func test_alchemist_epic_in_shop() -> void:
	## 에픽 업그레이드가 상점에 등장 가능
	_state.commander_type = Enums.CommanderType.ALCHEMIST
	assert_true(_cmd.can_shop_epic(_state), "연금술사 에픽 상점 가능")


func test_default_no_epic_in_shop() -> void:
	assert_false(_cmd.can_shop_epic(_state), "기본 에픽 상점 불가")


# ================================================================
# 커맨더 NONE — 기존 동작 보존
# ================================================================

func test_none_no_start_bonus() -> void:
	_state.gold = 0
	_cmd.apply_start_bonus(_state, _rng)
	assert_eq(_state.gold, 0, "NONE: 골드 변화 없음")


func test_none_reroll_never_free() -> void:
	_state.commander_type = Enums.CommanderType.NONE
	for i in 50:
		assert_false(_cmd.is_reroll_free(_state, _rng),
			"NONE: 리롤 무료 없음")


func test_none_unit_cap_60() -> void:
	var card := CardInstance.create("sp_assembly")
	assert_eq(card.get_unit_cap(), 60, "기본 유닛 상한 60")


func test_none_upgrade_slots_5() -> void:
	var card := CardInstance.create("sp_assembly")
	assert_eq(card.get_max_upgrade_slots(), 5, "기본 업그레이드 슬롯 5")


# ================================================================
# commander_state 초기화 + apply_card_bonuses
# ================================================================

func test_commander_state_initialized_on_start() -> void:
	## apply_start_bonus 호출 시 hero_used, win_count 초기화
	_cmd.apply_start_bonus(_state, _rng)
	assert_true(_state.commander_state.has("hero_used"), "hero_used 키 존재")
	assert_true(_state.commander_state.has("win_count"), "win_count 키 존재")
	assert_false(_state.commander_state["hero_used"], "hero_used 초기값 false")
	assert_eq(_state.commander_state["win_count"], 0, "win_count 초기값 0")


func test_apply_card_bonuses_breeder() -> void:
	## 양성가: 카드 보너스 적용 (unit_cap +20, upgrade_slot 0)
	_state.commander_type = Enums.CommanderType.BREEDER
	var card := CardInstance.create("sp_assembly")
	_cmd.apply_card_bonuses(_state, card)
	assert_eq(card.unit_cap_bonus, 20, "양성가 unit_cap_bonus = 20")
	assert_eq(card.upgrade_slot_bonus, 0, "양성가 upgrade_slot_bonus = 0")


func test_apply_card_bonuses_smith() -> void:
	## 단조사: 카드 보너스 적용 (unit_cap 0, upgrade_slot +1)
	_state.commander_type = Enums.CommanderType.SMITH
	var card := CardInstance.create("sp_assembly")
	_cmd.apply_card_bonuses(_state, card)
	assert_eq(card.unit_cap_bonus, 0, "단조사 unit_cap_bonus = 0")
	assert_eq(card.upgrade_slot_bonus, 1, "단조사 upgrade_slot_bonus = 1")
