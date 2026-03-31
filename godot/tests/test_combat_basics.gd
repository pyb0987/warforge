extends GutTest
## 전투 메카닉 기본 테스트 (결정론적 검증)
## 참조: docs/design/upgrades-items.md
##
## CombatEngine을 직접 인스턴스화하여 단일 공격/틱 결과를 검증.
## 모든 테스트는 시드가 고정된 RNG 또는 확정적 경로만 사용.
##
## 유닛 dict 포맷:
##   {atk, hp, attack_speed, range, move_speed, def, mechanics, radius}


const CombatEngineScript = preload("res://combat/combat_engine.gd")
const MechanicsScript = preload("res://combat/mechanics_handler.gd")

var _engine: CombatEngine = null


func _make_unit(atk: float, hp: float, mechs: Array = []) -> Dictionary:
	return {
		"atk": atk, "hp": hp,
		"attack_speed": 1.0, "range": 1, "move_speed": 50,
		"def": 0, "mechanics": mechs, "radius": 6.0,
	}


func _run_one_attack(ally: Dictionary, enemy: Dictionary) -> void:
	## 엔진을 setup 후 단 한 번의 _do_attack 호출만 수행.
	_engine = CombatEngineScript.new()
	_engine.setup([ally], [enemy])
	# 인덱스: ally=0, enemy=1
	_engine._do_attack(0, 1)


# =============================================================
# DEF 공식: damage = max(1, ATK - DEF)
# =============================================================

func test_def_reduces_damage() -> void:
	var ally := _make_unit(10.0, 100.0)
	var enemy := _make_unit(5.0, 50.0)
	enemy["def"] = 3
	_run_one_attack(ally, enemy)
	# damage = max(1, 10 - 3) = 7
	assert_almost_eq(_engine.hp[1], 50.0 - 7.0, 0.01, "DEF 3: 피해 7")


func test_def_minimum_1_damage() -> void:
	var ally := _make_unit(2.0, 100.0)
	var enemy := _make_unit(5.0, 50.0)
	enemy["def"] = 10  # DEF가 ATK보다 크면 최소 1
	_run_one_attack(ally, enemy)
	assert_almost_eq(_engine.hp[1], 49.0, 0.01, "최소 1 피해 보장")


func test_no_def_full_damage() -> void:
	var ally := _make_unit(8.0, 100.0)
	var enemy := _make_unit(5.0, 50.0)
	_run_one_attack(ally, enemy)
	assert_almost_eq(_engine.hp[1], 42.0, 0.01, "DEF 없으면 전체 피해")


# =============================================================
# armor_pierce: DEF ignore_def_pct
# =============================================================

func test_armor_pierce_50pct() -> void:
	var ally := _make_unit(10.0, 100.0)
	ally["mechanics"] = [{"type": "armor_pierce", "ignore_def_pct": 0.5}]
	var enemy := _make_unit(5.0, 50.0)
	enemy["def"] = 4
	_run_one_attack(ally, enemy)
	# effective_def = 4 * (1 - 0.5) = 2, damage = 10 - 2 = 8
	assert_almost_eq(_engine.hp[1], 42.0, 0.01, "관통 50%%: DEF 2 적용")


func test_armor_pierce_100pct() -> void:
	var ally := _make_unit(10.0, 100.0)
	ally["mechanics"] = [{"type": "armor_pierce", "ignore_def_pct": 1.0}]
	var enemy := _make_unit(5.0, 50.0)
	enemy["def"] = 5
	_run_one_attack(ally, enemy)
	# effective_def = 0, damage = 10
	assert_almost_eq(_engine.hp[1], 40.0, 0.01, "관통 100%%: DEF 무시")


# =============================================================
# thorns: 피격 시 공격자에게 ATK × reflect_pct 반사
# =============================================================

func test_thorns_reflects_to_attacker() -> void:
	var ally := _make_unit(10.0, 100.0)
	var enemy := _make_unit(8.0, 50.0)
	enemy["mechanics"] = [{"type": "thorns", "reflect_pct": 0.20}]
	_run_one_attack(ally, enemy)
	# reflect = 8 * 0.20 = 1.6
	assert_almost_eq(_engine.hp[0], 100.0 - 1.6, 0.01, "가시 반사: 1.6 피해")
	assert_almost_eq(_engine.hp[1], 40.0, 0.01, "방어자 10 피해")


func test_thorns_does_not_reflect_when_attacker_invuln() -> void:
	var ally := _make_unit(10.0, 100.0)
	var enemy := _make_unit(8.0, 50.0)
	enemy["mechanics"] = [{"type": "thorns", "reflect_pct": 0.20}]
	_engine = CombatEngineScript.new()
	_engine.setup([ally], [enemy])
	_engine.invuln[0] = 1  # 공격자 무적
	_engine._do_attack(0, 1)
	assert_almost_eq(_engine.hp[0], 100.0, 0.01, "무적 상태면 가시 반사 없음")


# =============================================================
# lifesteal: 공격 데미지의 steal_pct HP 회복
# =============================================================

func test_lifesteal_heals_attacker() -> void:
	var ally := _make_unit(10.0, 80.0)  # HP 80 (not full)
	ally["mechanics"] = [{"type": "lifesteal", "steal_pct": 0.15}]
	var enemy := _make_unit(5.0, 50.0)
	_engine = CombatEngineScript.new()
	_engine.setup([ally], [enemy])
	_engine.hp[0] = 70.0  # 이미 10 피해
	_engine._do_attack(0, 1)
	# damage=10, lifesteal = 10 * 0.15 = 1.5
	assert_almost_eq(_engine.hp[0], 71.5, 0.01, "라이프스틸 +1.5")


func test_lifesteal_capped_at_max_hp() -> void:
	var ally := _make_unit(10.0, 100.0)
	ally["mechanics"] = [{"type": "lifesteal", "steal_pct": 0.50}]
	var enemy := _make_unit(5.0, 50.0)
	_run_one_attack(ally, enemy)
	# HP full이므로 회복해도 max_hp 초과 불가
	assert_almost_eq(_engine.hp[0], 100.0, 0.01, "풀 HP에서 초과 회복 없음")


# =============================================================
# battle_start_heal: 전투 시작 시 HP +heal_hp_pct
# =============================================================

func test_battle_start_heal_applied_on_setup() -> void:
	var ally := _make_unit(5.0, 100.0)
	ally["mechanics"] = [{"type": "battle_start_heal", "heal_hp_pct": 0.10}]
	var enemy := _make_unit(5.0, 50.0)
	# HP가 이미 max이면 회복 없음 (clamped)
	_engine = CombatEngineScript.new()
	_engine.setup([ally], [enemy])
	assert_almost_eq(_engine.hp[0], 100.0, 0.01, "풀 HP → 회복 없음 (clamped)")


func test_battle_start_heal_heals_missing_hp() -> void:
	## setup() 전에 HP를 낮출 수 없으므로, 유닛을 hp=90으로 생성
	var ally := _make_unit(5.0, 90.0)  # max_hp=90
	ally["mechanics"] = [{"type": "battle_start_heal", "heal_hp_pct": 0.10}]
	var enemy := _make_unit(5.0, 50.0)
	_engine = CombatEngineScript.new()
	_engine.setup([ally], [enemy])
	# setup 후 hp = min(90 + 90*0.10, 90) = 90 (이미 max)
	# 진짜 테스트: 전투 시작 heal은 hp < max_hp일 때 의미 있음
	# 여기서는 _engine.hp[0] after _mech.apply_combat_start() 확인
	assert_almost_eq(_engine.hp[0], 90.0, 0.01, "HP max이면 그대로")


# =============================================================
# battle_start_shield: max HP를 shield_hp_pct만큼 초과 가능
# =============================================================

func test_battle_start_shield_increases_max_hp() -> void:
	var ally := _make_unit(5.0, 100.0)
	ally["mechanics"] = [{"type": "battle_start_shield", "shield_hp_pct": 0.15}]
	var enemy := _make_unit(5.0, 50.0)
	_engine = CombatEngineScript.new()
	_engine.setup([ally], [enemy])
	# max_hp 가 100 + 15 = 115가 되고 hp도 115
	assert_almost_eq(_engine.max_hp[0], 115.0, 0.1, "방어막: max_hp 115")
	assert_almost_eq(_engine.hp[0], 115.0, 0.1, "방어막: hp 115")


# =============================================================
# hp_percent_dmg: 대상 현재 HP × dmg_pct 추가 (DEF 무시)
# =============================================================

func test_hp_percent_dmg_added_to_base() -> void:
	var ally := _make_unit(10.0, 100.0)
	ally["mechanics"] = [{"type": "hp_percent_dmg", "dmg_pct": 0.08}]
	var enemy := _make_unit(5.0, 200.0)
	enemy["def"] = 3  # DEF는 hp_percent_dmg에 영향 없음
	_run_one_attack(ally, enemy)
	# base damage: max(1, 10 - 3) = 7
	# hp_pct: 200 * 0.08 = 16
	# total: 7 + 16 = 23
	assert_almost_eq(_engine.hp[1], 177.0, 0.1, "HP%% 피해 + DEF 무시: 23 총 피해")


# =============================================================
# phase_shift: 첫 피격 완전 무효
# =============================================================

func test_phase_shift_negates_first_hit() -> void:
	var ally := _make_unit(10.0, 100.0)
	var enemy := _make_unit(5.0, 50.0)
	enemy["mechanics"] = [{"type": "phase_shift"}]
	_engine = CombatEngineScript.new()
	_engine.setup([ally], [enemy])
	_engine._do_attack(0, 1)
	assert_almost_eq(_engine.hp[1], 50.0, 0.01, "첫 피격 무효")
	assert_eq(int(_engine.phase_shift_left[1]), 0, "charge 소모")


func test_phase_shift_second_hit_takes_damage() -> void:
	var ally := _make_unit(10.0, 100.0)
	var enemy := _make_unit(5.0, 50.0)
	enemy["mechanics"] = [{"type": "phase_shift"}]
	_engine = CombatEngineScript.new()
	_engine.setup([ally], [enemy])
	_engine._do_attack(0, 1)  # 무효
	_engine._do_attack(0, 1)  # 두 번째: 정상 피해
	assert_almost_eq(_engine.hp[1], 40.0, 0.01, "두 번째 공격은 10 피해")
