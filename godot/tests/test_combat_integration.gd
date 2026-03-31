extends GutTest
## CombatEngine 전투 통합 테스트
## 참조: combat_engine.gd, mechanics_handler.gd, handoff.md P5
##
## 기본 전투 / 메카닉(slow_aura, fission, regen, berserk, soul_harvest) 검증.


const CombatEngineScript = preload("res://combat/combat_engine.gd")

var _engine: CombatEngine = null


func before_each() -> void:
	_engine = CombatEngineScript.new()


func _make_unit(u_atk: float, u_hp: float, mechs: Array = [], def: float = 0.0) -> Dictionary:
	return {"atk": u_atk, "hp": u_hp, "attack_speed": 1.0, "range": 1,
			"move_speed": 3, "def": def, "mechanics": mechs, "radius": 6.0}


func _run_to_end() -> int:
	var ticks: int = 0
	while ticks < 6000:
		var ongoing: bool = _engine.tick()
		ticks += 1
		if not ongoing:
			break
	return ticks


# ================================================================
# 기본 전투
# ================================================================

func test_stronger_unit_wins() -> void:
	_engine.setup([_make_unit(100, 500)], [_make_unit(1, 1)])
	_run_to_end()
	assert_eq(_engine.alive[0], 1, "강한 아군 생존")
	assert_eq(_engine.alive[1], 0, "약한 적군 사망")


func test_weaker_unit_loses() -> void:
	_engine.setup([_make_unit(1, 1)], [_make_unit(100, 500)])
	_run_to_end()
	assert_eq(_engine.alive[0], 0, "약한 아군 사망")
	assert_eq(_engine.alive[1], 1, "강한 적군 생존")


func test_combat_terminates_before_max_ticks() -> void:
	_engine.setup([_make_unit(10, 100)], [_make_unit(10, 100)])
	var ticks: int = _run_to_end()
	assert_lt(ticks, 6000, "최대 틱 전에 종료")


func test_team_assignment_correct() -> void:
	_engine.setup([_make_unit(1, 100)], [_make_unit(1, 100)])
	assert_eq(_engine.team[0], 1, "idx0 = ally (team=1)")
	assert_eq(_engine.team[1], 0, "idx1 = enemy (team=0)")


# ================================================================
# 다수 vs 소수
# ================================================================

func test_multiple_allies_vs_one_enemy() -> void:
	var allies: Array = [_make_unit(10, 200), _make_unit(10, 200), _make_unit(10, 200)]
	var enemies: Array = [_make_unit(1, 10)]
	_engine.setup(allies, enemies)
	_run_to_end()
	# 3 allies survive, 1 enemy dead
	for i in 3:
		assert_eq(_engine.alive[i], 1, "아군 %d 생존" % i)
	assert_eq(_engine.alive[3], 0, "적군 사망")


# ================================================================
# slow_aura
# ================================================================

func test_slow_aura_sets_slow_factor() -> void:
	## ally에 slow_aura 30% 부착 → range 이내 적에게 slow_factor < 1.0
	## range=1 → 32px. 초기 배치: ally(80,80), enemy(920,80) — 먼 거리이므로
	## 가까이 붙을 때까지 tick 여러 번 돌림
	var mechs: Array = [{"type": "slow_aura", "slow_pct": 0.30}]
	_engine.setup([_make_unit(1, 9999, mechs)], [_make_unit(1, 9999)])
	# 유닛들이 접근할 때까지 충분히 tick
	for _i in 200:
		_engine.tick()
	# 접근 후 slow_factor 확인 — 범위 이내면 < 1.0
	var enemy_idx: int = 1
	assert_eq(_engine.alive[enemy_idx], 1, "적 생존 확인")
	assert_lt(_engine.slow_factor[enemy_idx], 1.0, "slow_aura → slow_factor < 1.0")


# ================================================================
# fission
# ================================================================

func test_fission_clones_survive_after_death() -> void:
	## fission 유닛 사망 → 클론 2기 생존
	var mechs: Array = [{"type": "fission", "clone_count": 2}]
	_engine.setup([_make_unit(1, 1, mechs)], [_make_unit(100, 9999)])
	# _base_count = 2, fission extra = 2, total count = 4
	# Clone slots: idx 2, 3
	assert_eq(_engine._base_count, 2, "base_count=2")
	# 전투 진행 → ally(idx0) 사망 → 클론 생성
	for _i in 200:
		_engine.tick()
		if _engine.alive[0] == 0:
			break
	assert_eq(_engine.alive[0], 0, "원본 사망")
	# 클론이 하나 이상 alive
	var clones_alive: int = 0
	for i in range(2, _engine.count):
		if _engine.alive[i] == 1 and _engine.is_clone[i] == 1:
			clones_alive += 1
	assert_gt(clones_alive, 0, "클론 1기 이상 생존")


# ================================================================
# regen
# ================================================================

func test_regen_heals_over_time() -> void:
	## regen: interval 3초, heal 10% maxHP
	var mechs: Array = [{"type": "regen", "interval_sec": 3.0, "heal_hp_pct": 0.10}]
	_engine.setup([_make_unit(1, 1000, mechs)], [_make_unit(1, 9999)])
	# 수동으로 HP 낮춤
	_engine.hp[0] = 500.0
	# 3초 = 60 ticks at 20fps, 넉넉히 65 ticks
	for _i in 65:
		_engine.tick()
	# 10% of 1000 = 100 회복 → 500 + 100 = 600 이상
	assert_gt(_engine.hp[0], 500.0, "regen → HP 회복")


# ================================================================
# berserk
# ================================================================

func test_berserk_activates_below_30pct() -> void:
	## HP를 29%로 낮춘 후 공격받으면 berserk_active 발동
	var mechs: Array = [{"type": "berserk", "hp_threshold": 0.30, "atk_mult": 2.0, "as_mult": 2.0}]
	_engine.setup([_make_unit(1, 1000, mechs)], [_make_unit(5, 9999)])
	# HP를 30% 직전으로 설정
	_engine.hp[0] = 301.0
	# tick → 적이 공격하면 HP 감소 → 300 이하 → berserk 발동
	for _i in 200:
		_engine.tick()
		if _engine.berserk_active[0] == 1:
			break
	assert_eq(_engine.berserk_active[0], 1, "HP ≤30% → berserk 발동")


# ================================================================
# soul_harvest
# ================================================================

func test_soul_harvest_stacks_on_kill() -> void:
	## soul_harvest 유닛이 kill 후 soul_atk_bonus > 0
	var mechs: Array = [{"type": "soul_harvest", "kill_atk_pct": 0.05}]
	_engine.setup([_make_unit(100, 9999, mechs)], [_make_unit(1, 1)])
	_run_to_end()
	assert_gt(_engine.soul_atk_bonus[0], 0.0, "kill 후 soul_atk_bonus > 0")
	assert_eq(_engine.soul_kills[0], 1, "kill count = 1")
