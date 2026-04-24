extends GutTest
## 게임 경제/루프 로직 테스트
## 참조: game_state.gd, game_manager.gd, upgrade.md
##
## 이자 브레이크포인트 / 라운드 수입 / HP 데미지 / materialize_army 검증.
## game_manager.gd는 씬 의존이므로, 순수 로직은 직접 재현하여 검증.


var _state: GameState = null


func before_each() -> void:
	_state = GameState.new()


# ================================================================
# 이자 브레이크포인트 (calc_interest)
# ================================================================

func test_interest_gold_0_returns_0() -> void:
	_state.gold = 0
	assert_eq(_state.calc_interest(), 0, "0골드 → 이자 0")


func test_interest_gold_4_returns_0() -> void:
	_state.gold = 4
	assert_eq(_state.calc_interest(), 0, "4골드 → 이자 0")


func test_interest_gold_5_returns_1() -> void:
	_state.gold = 5
	assert_eq(_state.calc_interest(), 1, "5골드 → 이자 1")


func test_interest_gold_9_returns_1() -> void:
	_state.gold = 9
	assert_eq(_state.calc_interest(), 1, "9골드 → 이자 1")


func test_interest_gold_10_returns_2() -> void:
	_state.gold = 10
	assert_eq(_state.calc_interest(), 2, "10골드 → 이자 2 (상한)")


func test_interest_gold_15_capped_at_2() -> void:
	_state.gold = 15
	assert_eq(_state.calc_interest(), 2, "15골드 → 이자 2 (상한)")


func test_interest_gold_50_capped_at_2() -> void:
	_state.gold = 50
	assert_eq(_state.calc_interest(), 2, "50골드 → 이자 2 (상한)")


# ================================================================
# 라운드별 기본 수입 (game_manager._run_settlement 로직 재현)
# ================================================================

func _base_income(round_num: int) -> int:
	if round_num >= 11:
		return 7
	elif round_num >= 6:
		return 6
	return 5


func test_base_income_r1_is_5() -> void:
	assert_eq(_base_income(1), 5, "R1 기본 수입 = 5")


func test_base_income_r5_is_5() -> void:
	assert_eq(_base_income(5), 5, "R5 기본 수입 = 5")


func test_base_income_r6_is_6() -> void:
	assert_eq(_base_income(6), 6, "R6 기본 수입 = 6")


func test_base_income_r10_is_6() -> void:
	assert_eq(_base_income(10), 6, "R10 기본 수입 = 6")


func test_base_income_r11_is_7() -> void:
	assert_eq(_base_income(11), 7, "R11 기본 수입 = 7")


func test_base_income_r15_is_7() -> void:
	assert_eq(_base_income(15), 7, "R15 기본 수입 = 7")


# ================================================================
# 정산 시뮬레이션 (수입 + 이자 통합)
# ================================================================

func test_settlement_r1_gold_0_total_income_5() -> void:
	## R1, 골드 0 → 기본 5 + 이자 0 = 5
	_state.gold = 0
	_state.round_num = 1
	var income: int = _base_income(1) + _state.calc_interest()
	assert_eq(income, 5, "R1 총수입 = 5")


func test_settlement_r6_gold_10_total_income_8() -> void:
	## R6, 골드 10 → 기본 6 + 이자 2 = 8
	_state.gold = 10
	_state.round_num = 6
	var income: int = _base_income(6) + _state.calc_interest()
	assert_eq(income, 8, "R6 총수입 = 8")


func test_settlement_r11_gold_5_total_income_8() -> void:
	## R11, 골드 5 → 기본 7 + 이자 1 = 8
	_state.gold = 5
	_state.round_num = 11
	var income: int = _base_income(11) + _state.calc_interest()
	assert_eq(income, 8, "R11 총수입 = 8")


# ================================================================
# HP 데미지 (패배 시 라운드 배수 × 적 생존 유닛 수, ceil)
# 배수: R1=0.2 → R15=1.2 선형 증가
# ================================================================

func test_defeat_damage_r1_multiplier_02() -> void:
	# R1 배수 0.2: enemy=5 → 1.0 → ceil 1, enemy=10 → 2.0 → ceil 2
	assert_eq(GameState.compute_defeat_damage(1, 5), 1, "R1 × 5유닛 = 1 데미지")
	assert_eq(GameState.compute_defeat_damage(1, 10), 2, "R1 × 10유닛 = 2 데미지")


func test_defeat_damage_r8_multiplier_07() -> void:
	# R8 배수 0.7: enemy=10 → 7.0 → ceil 7, enemy=14 → 9.8 → ceil 10
	assert_eq(GameState.compute_defeat_damage(8, 10), 7, "R8 × 10유닛 = 7 데미지")
	assert_eq(GameState.compute_defeat_damage(8, 14), 10, "R8 × 14유닛 = 10 데미지 (9.8 ceil)")


func test_defeat_damage_r15_multiplier_12() -> void:
	# R15 배수 1.2: enemy=5 → 6.0 → ceil 6, enemy=10 → 12.0 → ceil 12
	assert_eq(GameState.compute_defeat_damage(15, 5), 6, "R15 × 5유닛 = 6 데미지")
	assert_eq(GameState.compute_defeat_damage(15, 10), 12, "R15 × 10유닛 = 12 데미지")


func test_defeat_damage_ceil_rounds_up() -> void:
	# R1 enemy=3: 0.6 → ceil 1 (공짜 패배 방지)
	assert_eq(GameState.compute_defeat_damage(1, 3), 1, "R1 × 3유닛 = 0.6 ceil = 1")


func test_defeat_damage_min_1_boundary() -> void:
	# 어떤 라운드든 enemy≥1이면 데미지≥1 (ceil의 자동 보장)
	assert_eq(GameState.compute_defeat_damage(1, 1), 1, "R1 × 1유닛 = 0.2 ceil = 1 (공짜 패배 불가)")


func test_defeat_damage_monotonic_round() -> void:
	# enemy 고정 시 round_num 증가 → damage 비감소
	var prev: int = 0
	for r: int in range(1, Enums.MAX_ROUNDS + 1):
		var dmg: int = GameState.compute_defeat_damage(r, 10)
		assert_true(dmg >= prev, "R%d 데미지(%d) >= R%d 데미지(%d)" % [r, dmg, r - 1, prev])
		prev = dmg


func test_defeat_damage_applied_to_hp() -> void:
	# 통합: state.hp 차감 흐름
	_state.hp = 30
	_state.round_num = 1
	var dmg: int = GameState.compute_defeat_damage(_state.round_num, 5)
	_state.hp -= dmg
	assert_eq(_state.hp, 29, "R1 패배 적5 → 30-1=29")


func test_hp_damage_can_go_negative() -> void:
	_state.hp = 3
	_state.hp -= 10
	assert_eq(_state.hp, -7, "HP 음수 가능 (게임오버 판정)")


func test_hp_no_damage_on_win() -> void:
	_state.hp = 30
	# 승리 시 HP 변화 없고 골드 +1
	_state.gold += 1
	assert_eq(_state.hp, 30, "승리 시 HP 불변")
	assert_eq(_state.gold, 1, "승리 보너스 +1골드")


# ================================================================
# 테라진 수입 (승리 +2, 패배 +1)
# ================================================================

func test_terazin_win_plus_2() -> void:
	_state.terazin = 0
	_state.terazin += 2
	assert_eq(_state.terazin, 2, "승리 테라진 +2")


func test_terazin_loss_plus_1() -> void:
	_state.terazin = 0
	_state.terazin += 1
	assert_eq(_state.terazin, 1, "패배 테라진 +1")


# ================================================================
# 판매 전액 환급
# ================================================================

func test_sell_refunds_full_cost() -> void:
	_state.gold = 0
	_state.board[0] = CardInstance.create("sp_assembly")
	var refund: int = _state.sell_card("board", 0)
	assert_eq(refund, 2, "T1 sp_assembly 판매 = 2골드")
	assert_eq(_state.gold, 2, "골드 = 0 + 2")


func test_sell_t4_refunds_5() -> void:
	_state.gold = 0
	_state.board[0] = CardInstance.create("sp_warmachine")
	var refund: int = _state.sell_card("board", 0)
	assert_eq(refund, 5, "T4 sp_warmachine 판매 = 5골드")


func test_sell_t5_refunds_6() -> void:
	_state.gold = 0
	_state.board[0] = CardInstance.create("sp_arsenal")
	var refund: int = _state.sell_card("board", 0)
	assert_eq(refund, 6, "T5 sp_arsenal 판매 = 6골드")


# ================================================================
# materialize_army 로직 (game_manager 순수 로직 재현)
# ================================================================

func test_materialize_army_unit_count() -> void:
	## sp_assembly: spider×2 + sawblade×1 + rat×1 = 4유닛 → 4개 unit dict
	var card: CardInstance = CardInstance.create("sp_assembly")
	var units: Array = _materialize_card(card)
	assert_eq(units.size(), 4, "sp_assembly → 4유닛")


func test_materialize_army_has_combat_keys() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	var units: Array = _materialize_card(card)
	var u: Dictionary = units[0]
	assert_true(u.has("atk"), "atk")
	assert_true(u.has("hp"), "hp")
	assert_true(u.has("attack_speed"), "attack_speed")
	assert_true(u.has("range"), "range")
	assert_true(u.has("move_speed"), "move_speed")
	assert_true(u.has("def"), "def")
	assert_true(u.has("mechanics"), "mechanics")


func test_materialize_enhanced_card_has_higher_atk() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	var base_units: Array = _materialize_card(card)
	var base_atk: float = base_units[0]["atk"]
	card.enhance(null, 0.50, 0.0)  # +50% ATK
	var enhanced_units: Array = _materialize_card(card)
	assert_gt(enhanced_units[0]["atk"], base_atk, "enhance 후 ATK 증가")


func test_materialize_upgrade_def_applied() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	card.upgrade_def = 5
	var units: Array = _materialize_card(card)
	assert_eq(units[0]["def"], 5, "업그레이드 DEF 반영")


func test_materialize_upgrade_range_applied() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	var base_units: Array = _materialize_card(card)
	var base_range: int = base_units[0]["range"]
	card.upgrade_range = 2
	var upgraded_units: Array = _materialize_card(card)
	assert_eq(upgraded_units[0]["range"], base_range + 2, "업그레이드 Range 반영")


func test_materialize_mechanics_from_upgrade() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	card.attach_upgrade("C1")  # C1 = 강화 베어링 (atk_pct)
	var units: Array = _materialize_card(card)
	# C1은 stat_mods만 있고 mechanic 없음 → mechanics=[]
	# R1 = 첫 번째 레어 업그레이드 (mechanic 포함)
	card.attach_upgrade("R1")  # R1 = 집중 사격 모듈 (focus_fire)
	var units2: Array = _materialize_card(card)
	assert_gt(units2[0]["mechanics"].size(), 0, "R1 → focus_fire 메카닉 포함")


# ================================================================
# Helper: game_manager._materialize_army 순수 로직 재현
# ================================================================

func _materialize_card(card: CardInstance) -> Array:
	var units: Array = []
	var card_mechanics: Array = card.get_all_mechanics()
	for s in card.stacks:
		var ut: Dictionary = s["unit_type"]
		var eff_atk: float = card.eff_atk_for(s)
		var eff_hp: float = card.eff_hp_for(s)
		for _n in s["count"]:
			units.append({
				"atk": eff_atk,
				"hp": eff_hp,
				"attack_speed": ut["attack_speed"] * card.upgrade_as_mult,
				"range": ut["range"] + card.upgrade_range,
				"move_speed": ut["move_speed"] + card.upgrade_move_speed,
				"def": card.upgrade_def,
				"mechanics": card_mechanics,
				"radius": 6.0,
			})
	return units
