extends GutTest
## EnemyDB 적 생성 시스템 테스트
## 참조: enemy_db.gd, combat.md
##
## 라운드별 스케일링 / 프리셋 구성 / 보스 라운드 검증.


const EnemyDBScript = preload("res://core/data/enemy_db.gd")

var _rng: RandomNumberGenerator = null


func before_each() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = 42


# ================================================================
# _round_mult 스케일링 공식
# ================================================================

func test_round_mult_r1_is_1() -> void:
	assert_almost_eq(EnemyDBScript._round_mult(1), 1.0, 0.001, "R1=1.0")


func test_round_mult_r5() -> void:
	# 1.0 + (5-1)*0.2 + max(0, 5-8)*0.1 = 1.0 + 0.8 + 0 = 1.8
	assert_almost_eq(EnemyDBScript._round_mult(5), 1.8, 0.001, "R5=1.8")


func test_round_mult_r8() -> void:
	# 1.0 + (8-1)*0.2 + max(0, 8-8)*0.1 = 1.0 + 1.4 + 0 = 2.4
	assert_almost_eq(EnemyDBScript._round_mult(8), 2.4, 0.001, "R8=2.4")


func test_round_mult_r10() -> void:
	# 1.0 + (10-1)*0.2 + max(0, 10-8)*0.1 = 1.0 + 1.8 + 0.2 = 3.0
	assert_almost_eq(EnemyDBScript._round_mult(10), 3.0, 0.001, "R10=3.0")


func test_round_mult_r15() -> void:
	# 1.0 + (15-1)*0.2 + max(0, 15-8)*0.1 = 1.0 + 2.8 + 0.7 = 4.5
	assert_almost_eq(EnemyDBScript._round_mult(15), 4.5, 0.001, "R15=4.5")


func test_round_mult_increases_monotonically() -> void:
	var prev: float = 0.0
	for r in range(1, 16):
		var m: float = EnemyDBScript._round_mult(r)
		assert_gt(m, prev, "R%d > R%d" % [r, r - 1])
		prev = m


# ================================================================
# generate() 기본
# ================================================================

func test_generate_returns_nonempty_array() -> void:
	var units: Array = EnemyDBScript.generate(1, _rng)
	assert_gt(units.size(), 0, "R1 유닛 1기 이상")


func test_generate_unit_has_required_keys() -> void:
	var units: Array = EnemyDBScript.generate(1, _rng)
	var u: Dictionary = units[0]
	assert_true(u.has("atk"), "atk 키")
	assert_true(u.has("hp"), "hp 키")
	assert_true(u.has("attack_speed"), "attack_speed 키")
	assert_true(u.has("range"), "range 키")
	assert_true(u.has("move_speed"), "move_speed 키")


func test_generate_units_grow_with_rounds() -> void:
	var r1: Array = EnemyDBScript.generate(1, _rng)
	_rng.seed = 42
	var r10: Array = EnemyDBScript.generate(10, _rng)
	# 평균 ATK가 R10 > R1
	var avg_r1: float = 0.0
	for u in r1:
		avg_r1 += u["atk"]
	avg_r1 /= r1.size()
	var avg_r10: float = 0.0
	for u in r10:
		avg_r10 += u["atk"]
	avg_r10 /= r10.size()
	assert_gt(avg_r10, avg_r1, "R10 평균 ATK > R1")


func test_generate_more_units_later_rounds() -> void:
	var r1: Array = EnemyDBScript.generate(1, _rng)
	_rng.seed = 42
	var r15: Array = EnemyDBScript.generate(15, _rng)
	assert_gt(r15.size(), r1.size(), "R15 유닛 수 > R1")


# ================================================================
# 보스 라운드
# ================================================================

func test_boss_r4_is_swarm() -> void:
	assert_eq(EnemyDBScript._boss_preset(4), EnemyDBScript.Preset.SWARM, "R4=SWARM")


func test_boss_r8_is_heavy() -> void:
	assert_eq(EnemyDBScript._boss_preset(8), EnemyDBScript.Preset.HEAVY, "R8=HEAVY")


func test_boss_r12_is_sniper() -> void:
	assert_eq(EnemyDBScript._boss_preset(12), EnemyDBScript.Preset.SNIPER, "R12=SNIPER")


func test_boss_r15_is_balanced() -> void:
	assert_eq(EnemyDBScript._boss_preset(15), EnemyDBScript.Preset.BALANCED, "R15=BALANCED")


func test_boss_round_has_130_stat_boost() -> void:
	## 보스 라운드(R4)는 ×1.3 추가 적용
	## 비보스(R3)와 보스(R4) 비교: 같은 프리셋이면 보스가 1.3배
	var r4: Array = EnemyDBScript.generate(4, _rng)
	# R4 mult = _round_mult(4) * 1.3 = (1.0+0.6) * 1.3 = 2.08
	# swarm base atk=2.0 → 2.0 * 2.08 = 4.16
	var expected_atk: float = 2.0 * EnemyDBScript._round_mult(4) * 1.3
	assert_almost_eq(r4[0]["atk"], expected_atk, 0.01, "R4 swarm atk = base×mult×1.3")


func test_non_boss_round_no_130_boost() -> void:
	## R3은 비보스 → ×1.3 없음. 단 프리셋은 랜덤이므로 스탯으로 간접 확인
	_rng.seed = 100  # 프리셋 랜덤 → 어떤 프리셋이든 1.3배 없음
	var r3: Array = EnemyDBScript.generate(3, _rng)
	var mult: float = EnemyDBScript._round_mult(3)
	# 모든 유닛의 atk이 base*mult 이하 (1.3배 미적용)
	for u in r3:
		# 가장 높은 base_atk = sniper 6.0. 최대 atk = 6.0 * mult
		assert_lte(u["atk"], 6.0 * mult + 0.01, "비보스 atk ≤ base×mult")


# ================================================================
# 프리셋별 유닛 수 공식
# ================================================================

func test_swarm_preset_unit_count_r1() -> void:
	## SWARM R1: swarm=int(8+1*2.5)=10, ranged=int(2+1*0.5)=2 → 12
	_rng.seed = 42
	# 강제 SWARM: boss R4 사용
	var units: Array = EnemyDBScript.generate(4, _rng)
	var n_expected: int = int(8 + 4 * 2.5) + int(2 + 4 * 0.5)  # 18 + 4 = 22
	assert_eq(units.size(), n_expected, "R4 SWARM 유닛 수 = %d" % n_expected)


func test_heavy_preset_unit_count_r8() -> void:
	## HEAVY R8: heavy=int(3+8*0.8)=9, melee=int(4+8*1.0)=12, ranged=int(2+8*0.5)=6 → 27
	var units: Array = EnemyDBScript.generate(8, _rng)
	var n_expected: int = int(3 + 8 * 0.8) + int(4 + 8 * 1.0) + int(2 + 8 * 0.5)
	assert_eq(units.size(), n_expected, "R8 HEAVY 유닛 수 = %d" % n_expected)
