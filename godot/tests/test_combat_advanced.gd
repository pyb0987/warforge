extends GutTest
## 전투 메카닉 고급 테스트 (조건부/누적 메카닉)
## 참조: docs/design/upgrades-items.md
##
## focus_fire, berserk, immortal_core, soul_harvest, fission,
## chain_discharge, chain_explosion, regen, slow_aura, tactical_retreat


const CombatEngineScript = preload("res://combat/combat_engine.gd")

var _engine: CombatEngine = null


func _make_unit(atk: float, hp: float, mechs: Array = [], def: int = 0) -> Dictionary:
	return {
		"atk": atk, "hp": hp,
		"attack_speed": 1.0, "range": 1, "move_speed": 50,
		"def": def, "mechanics": mechs, "radius": 6.0,
	}


# =============================================================
# focus_fire: 동일 대상 연속 공격 시 ATK +10% 누적
# =============================================================

func test_focus_fire_stacks_on_same_target() -> void:
	var ally := _make_unit(10.0, 100.0, [{"type": "focus_fire", "stack_atk_pct": 0.10}])
	var enemy := _make_unit(5.0, 500.0)
	_engine = CombatEngineScript.new()
	_engine.setup([ally], [enemy])

	_engine._do_attack(0, 1)  # 스택 0 → damage = 10
	_engine._do_attack(0, 1)  # 스택 1 → damage = 10 * 1.10 = 11
	_engine._do_attack(0, 1)  # 스택 2 → damage = 10 * 1.20 = 12
	# 총 피해: 10 + 11 + 12 = 33
	assert_almost_eq(_engine.hp[1], 467.0, 0.5, "focus_fire 3연속: 33 누적 피해")


func test_focus_fire_resets_on_new_target() -> void:
	## 적 2명을 앞에 두고 대상 변경 시 스택 리셋 확인
	var ally := _make_unit(10.0, 100.0, [{"type": "focus_fire", "stack_atk_pct": 0.10}])
	var enemy1 := _make_unit(5.0, 200.0)
	var enemy2 := _make_unit(5.0, 200.0)
	_engine = CombatEngineScript.new()
	_engine.setup([ally], [enemy1, enemy2])

	_engine._do_attack(0, 1)  # target=1, stack=0, dmg=10
	_engine._do_attack(0, 1)  # target=1, stack=1, dmg=11
	# 대상 변경
	_engine._do_attack(0, 2)  # target=2, stack reset=0, dmg=10
	assert_almost_eq(_engine.hp[2], 190.0, 0.5, "대상 변경 후 스택 0: 10 피해")


# =============================================================
# berserk: HP 30% 이하 시 ATK×2, 공격속도×2
# =============================================================

func test_berserk_triggers_at_threshold() -> void:
	var ally := _make_unit(5.0, 100.0)
	var enemy := _make_unit(100.0, 200.0, [{"type": "berserk", "hp_threshold": 0.30, "atk_mult": 2.0, "as_mult": 2.0}])
	_engine = CombatEngineScript.new()
	_engine.setup([ally], [enemy])

	# 피해를 주어 HP를 29%로 낮춤 (200 * 0.30 = 60, 29% = 58)
	_engine.hp[1] = 58.0
	_engine._do_attack(0, 1)  # 이 공격에서 threshold 체크 발동
	assert_eq(int(_engine.berserk_active[1]), 1, "광폭화 발동")


func test_berserk_doubles_atk_on_next_attack() -> void:
	var ally1 := _make_unit(5.0, 500.0)
	var enemy := _make_unit(10.0, 200.0, [{"type": "berserk", "hp_threshold": 0.30, "atk_mult": 2.0, "as_mult": 2.0}])
	_engine = CombatEngineScript.new()
	_engine.setup([ally1], [enemy])

	# 광폭화 수동 활성화
	_engine.berserk_active[1] = 1
	var ally_hp_before := _engine.hp[0]
	_engine._do_attack(1, 0)  # 적이 아군 공격: ATK 10 * 2 = 20
	assert_almost_eq(_engine.hp[0], ally_hp_before - 20.0, 0.5, "광폭화 ATK×2: 20 피해")


# =============================================================
# immortal_core: 치명타 시 HP 1 생존 + 3초 무적
# =============================================================

func test_immortal_core_survives_lethal() -> void:
	var ally := _make_unit(1000.0, 100.0)  # 즉사 공격
	var enemy := _make_unit(5.0, 50.0, [{"type": "immortal_core"}])
	_engine = CombatEngineScript.new()
	_engine.setup([ally], [enemy])
	_engine._do_attack(0, 1)
	assert_eq(int(_engine.alive[1]), 1, "불멸의 핵: 생존")
	assert_almost_eq(_engine.hp[1], 1.0, 0.01, "HP 1로 생존")
	assert_eq(int(_engine.invuln[1]), 1, "무적 상태")
	assert_eq(int(_engine.immortal_left[1]), 0, "charge 소모")


func test_immortal_core_only_once() -> void:
	var ally := _make_unit(1000.0, 100.0)
	var enemy := _make_unit(5.0, 50.0, [{"type": "immortal_core"}])
	_engine = CombatEngineScript.new()
	_engine.setup([ally], [enemy])
	_engine._do_attack(0, 1)  # 첫 번째: 생존
	_engine.invuln[1] = 0    # 무적 수동 해제 (두 번째 공격 테스트용)
	_engine._do_attack(0, 1)  # 두 번째: immortal_left=0이므로 사망
	assert_eq(int(_engine.alive[1]), 0, "두 번째는 사망")


# =============================================================
# soul_harvest: 처치 시 ATK +5% 누적, 10킬 → AS ×1.5
# =============================================================

func test_soul_harvest_stacks_on_kill() -> void:
	var ally := _make_unit(100.0, 100.0, [{"type": "soul_harvest", "kill_atk_pct": 0.05}])
	var enemy1 := _make_unit(1.0, 50.0)
	var enemy2 := _make_unit(1.0, 50.0)
	_engine = CombatEngineScript.new()
	_engine.setup([ally], [enemy1, enemy2])

	_engine._do_attack(0, 1)  # kill → +5% ATK bonus
	assert_almost_eq(_engine.soul_atk_bonus[0], 0.05, 0.001, "첫 킬: +5% 누적")
	_engine._do_attack(0, 2)  # kill → +5% more
	assert_almost_eq(_engine.soul_atk_bonus[0], 0.10, 0.001, "두 번째 킬: +10% 누적")


func test_soul_harvest_10kills_bonus_as() -> void:
	var ally := _make_unit(100.0, 100.0, [{"type": "soul_harvest", "kill_atk_pct": 0.05}])
	var enemies: Array = []
	for i in 10:
		enemies.append(_make_unit(1.0, 1.0))  # 즉사 적
	_engine = CombatEngineScript.new()
	_engine.setup([ally], enemies)

	var base_as := _engine.attack_speed[0]
	for i in 10:
		if _engine.alive[1 + i] == 1:
			_engine._do_attack(0, 1 + i)
	assert_eq(_engine.soul_kills[0], 10, "10킬 달성")
	assert_almost_eq(_engine.attack_speed[0], base_as / 1.5, base_as * 0.01, "10킬: AS ×1.5 (interval ÷1.5)")


# =============================================================
# fission: 사망 시 2기 복제 (HP 50%, ATK 50%)
# =============================================================

func test_fission_spawns_clones_on_death() -> void:
	var ally := _make_unit(1000.0, 100.0)
	var enemy := _make_unit(5.0, 50.0, [{"type": "fission", "clone_count": 2}])
	_engine = CombatEngineScript.new()
	_engine.setup([ally], [enemy])

	# 사전 할당된 클론 슬롯 수 확인
	assert_eq(_engine.count, 4, "기본 2 + 클론 슬롯 2 = 4")
	assert_eq(int(_engine.alive[2]), 0, "클론 슬롯 초기 사망 상태")

	_engine._do_attack(0, 1)  # 적 처치 → fission 발동
	assert_eq(int(_engine.alive[1]), 0, "원본 사망")
	assert_eq(int(_engine.alive[2]), 1, "클론1 생존")
	assert_eq(int(_engine.alive[3]), 1, "클론2 생존")


func test_fission_clone_stats_halved() -> void:
	var ally := _make_unit(1000.0, 100.0)
	var enemy := _make_unit(10.0, 60.0, [{"type": "fission", "clone_count": 2}])
	_engine = CombatEngineScript.new()
	_engine.setup([ally], [enemy])
	_engine._do_attack(0, 1)

	assert_almost_eq(_engine.hp[2], 30.0, 0.1, "클론 HP: 60 * 0.5 = 30")
	assert_almost_eq(_engine.atk[2], 5.0, 0.1, "클론 ATK: 10 * 0.5 = 5")


func test_fission_clone_cannot_refission() -> void:
	var ally := _make_unit(1000.0, 100.0)
	var enemy := _make_unit(10.0, 60.0, [{"type": "fission", "clone_count": 2}])
	_engine = CombatEngineScript.new()
	_engine.setup([ally], [enemy])
	_engine._do_attack(0, 1)  # fission 발동 → 클론 2기

	# 클론의 mechanics는 비어있어야 함
	assert_eq(_engine.mechanics[2].size(), 0, "클론에 메카닉 없음")
	assert_eq(int(_engine.is_clone[2]), 1, "클론 플래그")


# =============================================================
# chain_discharge: 처치 시 주변 적에게 ATK 30% 데미지
# =============================================================

func test_chain_discharge_damages_nearby_on_kill() -> void:
	var ally := _make_unit(100.0, 100.0, [{"type": "chain_discharge", "chain_dmg_pct": 0.30}])
	var enemy1 := _make_unit(5.0, 50.0)
	var enemy2 := _make_unit(5.0, 50.0)
	_engine = CombatEngineScript.new()
	_engine.setup([ally], [enemy1, enemy2])

	# enemy2를 enemy1 옆에 배치
	_engine.pos[2] = _engine.pos[1] + Vector2(10.0, 0.0)  # 10px 거리 (RANGE_SCALE=32px 이내)
	_engine._do_attack(0, 1)  # enemy1 처치 → chain_discharge

	# chain_dmg = 100 * 0.30 = 30
	assert_almost_eq(_engine.hp[2], 20.0, 1.0, "chain_discharge: 30 피해")


# =============================================================
# critical: 15% 확률, ×2.5 (결정론적 테스트: 크리 강제)
# =============================================================

func test_critical_multiplies_damage_when_rolled() -> void:
	var ally := _make_unit(10.0, 100.0, [{"type": "critical", "crit_chance": 1.0, "crit_mult": 2.5}])
	var enemy := _make_unit(5.0, 100.0)
	_engine = CombatEngineScript.new()
	_engine.setup([ally], [enemy])
	_engine._do_attack(0, 1)
	# crit_chance=100% → damage = 10 * 2.5 = 25
	assert_almost_eq(_engine.hp[1], 75.0, 0.1, "크리티컬 100%%: 25 피해")


func test_no_critical_when_chance_zero() -> void:
	var ally := _make_unit(10.0, 100.0, [{"type": "critical", "crit_chance": 0.0, "crit_mult": 2.5}])
	var enemy := _make_unit(5.0, 100.0)
	_engine = CombatEngineScript.new()
	_engine.setup([ally], [enemy])
	_engine._do_attack(0, 1)
	assert_almost_eq(_engine.hp[1], 90.0, 0.1, "크리 확률 0%%: 10 피해")


# =============================================================
# splash: 주변 적 50% 피해
# =============================================================

func test_splash_damages_nearby_enemies() -> void:
	var ally := _make_unit(10.0, 100.0, [{"type": "splash", "splash_pct": 0.50}])
	var enemy1 := _make_unit(5.0, 100.0)
	var enemy2 := _make_unit(5.0, 100.0)
	_engine = CombatEngineScript.new()
	_engine.setup([ally], [enemy1, enemy2])

	# enemy2를 enemy1 바로 옆에 배치 (RANGE_SCALE = 32px)
	_engine.pos[2] = _engine.pos[1] + Vector2(10.0, 0.0)
	_engine._do_attack(0, 1)
	# enemy1: 10 피해, enemy2: 10 * 0.5 = 5 스플래시
	assert_almost_eq(_engine.hp[1], 90.0, 0.1, "주공격: 10 피해")
	assert_almost_eq(_engine.hp[2], 95.0, 0.1, "스플래시: 5 피해")
