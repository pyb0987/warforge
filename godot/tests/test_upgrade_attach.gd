extends GutTest
## 업그레이드 부착 로직 테스트
## 참조: DESIGN.md § 업그레이드 시스템, memory/project_upgrade_system.md
##
## - 5슬롯 상한
## - stat_mods 라우팅 (atk_pct/hp_pct → multiply_stats, def/range/ms → additive, as_mult → multiplicative)
## - can_attach_upgrade() 경계값


var _card: CardInstance = null


func before_each() -> void:
	# sp_assembly: 스팀펑크 T1, 간단한 카드로 부착 테스트
	_card = CardInstance.create("sp_assembly")
	assert_not_null(_card, "sp_assembly 카드 생성 실패")


# --- 슬롯 상한 ---

func test_can_attach_when_empty() -> void:
	assert_true(_card.can_attach_upgrade(), "빈 슬롯에는 부착 가능")


func test_max_5_slots() -> void:
	# 5개까지 부착 가능
	for i in 5:
		assert_true(_card.attach_upgrade("C1"), "슬롯 %d 부착 가능" % (i + 1))
	assert_false(_card.can_attach_upgrade(), "5개 부착 후 슬롯 없음")
	assert_false(_card.attach_upgrade("C2"), "5개 이후 부착 실패")


func test_upgrades_array_length() -> void:
	_card.attach_upgrade("C1")
	_card.attach_upgrade("C2")
	assert_eq(_card.upgrades.size(), 2, "upgrades 배열 길이 일치")


# --- stat_mods 라우팅: atk_pct/hp_pct → multiply_stats ---

func test_atk_pct_applied_via_multiply_stats() -> void:
	var base_atk: float = _card.get_total_atk()
	_card.attach_upgrade("C1")  # ATK +15%
	var new_atk: float = _card.get_total_atk()
	assert_almost_eq(new_atk, base_atk * 1.15, base_atk * 0.01,
		"ATK +15%% 적용: %f → %f" % [base_atk, new_atk])


func test_hp_pct_applied_via_multiply_stats() -> void:
	var base_hp: float = _card.get_total_hp()
	_card.attach_upgrade("C2")  # HP +15%
	var new_hp: float = _card.get_total_hp()
	assert_almost_eq(new_hp, base_hp * 1.15, base_hp * 0.01,
		"HP +15%% 적용: %f → %f" % [base_hp, new_hp])


# --- stat_mods 라우팅: def/range/move_speed → additive 필드 ---

func test_def_additive() -> void:
	assert_eq(_card.upgrade_def, 0, "초기 DEF 0")
	_card.attach_upgrade("C3")  # DEF +1
	assert_eq(_card.upgrade_def, 1, "DEF +1 적용")
	_card.attach_upgrade("C3")  # DEF +1 again
	assert_eq(_card.upgrade_def, 2, "DEF 누적: +2")


func test_range_additive() -> void:
	assert_eq(_card.upgrade_range, 0, "초기 Range 0")
	_card.attach_upgrade("C4")  # Range +1
	assert_eq(_card.upgrade_range, 1, "Range +1 적용")


func test_move_speed_additive() -> void:
	assert_eq(_card.upgrade_move_speed, 0, "초기 MS 0")
	_card.attach_upgrade("C5")  # MS +15
	assert_eq(_card.upgrade_move_speed, 15, "MS +15 적용")


# --- stat_mods 라우팅: as_mult → multiplicative ---

func test_as_mult_multiplicative() -> void:
	assert_almost_eq(_card.upgrade_as_mult, 1.0, 0.001, "초기 AS mult 1.0")
	_card.attach_upgrade("C6")  # AS interval ×0.85
	assert_almost_eq(_card.upgrade_as_mult, 0.85, 0.001, "AS ×0.85 적용")


func test_as_mult_stacks_multiplicatively() -> void:
	_card.attach_upgrade("C6")  # ×0.85
	_card.attach_upgrade("C6")  # ×0.85 again
	assert_almost_eq(_card.upgrade_as_mult, 0.85 * 0.85, 0.001, "AS 중첩: 0.85²")


# --- mechanics 저장 ---

func test_mechanics_stored_in_upgrades_array() -> void:
	_card.attach_upgrade("C7")  # thorns
	assert_eq(_card.upgrades.size(), 1)
	var stored_mechanics: Array = _card.upgrades[0].get("mechanics", [])
	assert_eq(stored_mechanics.size(), 1, "mechanics 배열에 1개")
	assert_eq(stored_mechanics[0].get("type", ""), "thorns")


func test_has_mechanic_returns_true() -> void:
	_card.attach_upgrade("C7")  # thorns
	assert_true(_card.has_mechanic("thorns"))
	assert_false(_card.has_mechanic("lifesteal"))


func test_get_all_mechanics_flat() -> void:
	_card.attach_upgrade("C7")  # thorns (1 mechanic)
	_card.attach_upgrade("C8")  # battle_start_heal (1 mechanic)
	var all_mechs := _card.get_all_mechanics()
	assert_eq(all_mechs.size(), 2, "2개 메카닉 플랫 리스트")


# --- 유효하지 않은 ID ---

func test_invalid_upgrade_id_returns_false() -> void:
	assert_false(_card.attach_upgrade("nonexistent"), "유효하지 않은 ID는 부착 실패")
	assert_eq(_card.upgrades.size(), 0, "upgrades 배열 변화 없음")
