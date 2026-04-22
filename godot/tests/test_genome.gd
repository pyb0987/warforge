extends GutTest
## Genome 로드/검증 테스트.

const GenomeScript = preload("res://sim/genome.gd")


func test_load_default_genome() -> void:
	var g: RefCounted = GenomeScript.load_file("res://sim/default_genome.json")
	assert_not_null(g, "default genome 로드 성공")


func test_default_target_cp_length() -> void:
	# 2026-04-22: target_cp_per_round 대체 (enemy_cp_curve deprecated).
	var g = GenomeScript.load_file("res://sim/default_genome.json")
	assert_eq(g.target_cp_per_round.size(), 15, "target_cp 15라운드")


func test_default_target_cp_geometric() -> void:
	# Default: geometric 100 → 100000 over 15 rounds.
	var g = GenomeScript.load_file("res://sim/default_genome.json")
	assert_almost_eq(g.target_cp_per_round[0], 100.0, 1.0, "R1 = 100")
	assert_almost_eq(g.target_cp_per_round[14], 100000.0, 100.0, "R15 = 100000")
	# Monotonic
	for i in range(1, 15):
		assert_gte(g.target_cp_per_round[i], g.target_cp_per_round[i-1], "monotonic at R%d" % (i+1))


func test_default_economy() -> void:
	var g = GenomeScript.load_file("res://sim/default_genome.json")
	assert_eq(g.economy.reroll_cost, 1, "리롤 비용 1g")
	assert_eq(g.economy.interest_per_5g, 1, "이자 5g당 1")
	assert_eq(g.economy.max_interest, 2, "최대 이자 2")
	assert_eq(g.economy.terazin_win, 2, "승리 테라진 +2")
	assert_eq(g.economy.terazin_lose, 1, "패배 테라진 +1")


func test_default_base_income() -> void:
	var g = GenomeScript.load_file("res://sim/default_genome.json")
	assert_eq(g.economy.base_income.size(), 15, "소득 15라운드")
	assert_eq(g.economy.base_income[0], 5, "R1 소득 5g")
	assert_eq(g.economy.base_income[5], 6, "R6 소득 6g")
	assert_eq(g.economy.base_income[10], 7, "R11 소득 7g")


func test_default_activation_caps_empty() -> void:
	var g = GenomeScript.load_file("res://sim/default_genome.json")
	assert_eq(g.activation_caps.size(), 0, "기본값은 빈 dict")


func test_get_cp_mult_returns_ratio() -> void:
	var g = GenomeScript.load_file("res://sim/default_genome.json")
	var ratio: float = g.get_cp_scale(1)
	assert_almost_eq(ratio, 1.0, 0.01, "기본 genome은 스케일 1.0")
	ratio = g.get_cp_scale(15)
	assert_almost_eq(ratio, 1.0, 0.01, "R15도 스케일 1.0")


func test_get_activation_cap_fallback() -> void:
	var g = GenomeScript.load_file("res://sim/default_genome.json")
	assert_eq(g.get_activation_cap("sp_assembly"), -1, "빈 caps → -1")


func test_get_activation_cap_override() -> void:
	var g = GenomeScript.load_file("res://sim/default_genome.json")
	g.activation_caps["sp_assembly"] = 3
	assert_eq(g.get_activation_cap("sp_assembly"), 3, "오버라이드 적용")


func test_invalid_file_returns_null() -> void:
	var g = GenomeScript.load_file("res://sim/nonexistent.json")
	assert_null(g, "존재하지 않는 파일 → null")
