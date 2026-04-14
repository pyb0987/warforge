extends GutTest
## Evaluator 7축 평가 테스트.

const EvalScript = preload("res://sim/evaluator.gd")
const RunnerScript = preload("res://sim/headless_runner.gd")
const GenomeScript = preload("res://sim/genome.gd")


# ================================================================
# 실제 시뮬 데이터로 평가
# ================================================================

func test_evaluate_returns_all_axes() -> void:
	var genome = GenomeScript.load_file("res://sim/default_genome.json")
	var results: Array = []
	# 3 strategies × 2 runs each (최소한의 데이터)
	for strat in ["soft_steampunk", "soft_druid", "aggressive"]:
		for seed_val in [42, 43]:
			var runner = RunnerScript.new(genome, strat, seed_val)
			results.append(runner.run())

	var score: Dictionary = EvalScript.evaluate(results)
	assert_has(score, "board_utilization")
	assert_has(score, "activation_utilization")
	assert_has(score, "win_rate_band")
	assert_has(score, "tipping_point_quality")
	assert_has(score, "dominance_moment")
	assert_has(score, "theme_ratio_variance")
	assert_has(score, "card_coverage")
	assert_has(score, "weighted_score")


func test_scores_are_bounded() -> void:
	var genome = GenomeScript.load_file("res://sim/default_genome.json")
	var results: Array = []
	for strat in ["adaptive", "aggressive"]:
		for seed_val in [10, 20]:
			results.append(RunnerScript.new(genome, strat, seed_val).run())

	var score: Dictionary = EvalScript.evaluate(results)
	for key in ["board_utilization", "activation_utilization", "win_rate_band",
			"tipping_point_quality", "dominance_moment",
			"theme_ratio_variance", "card_coverage", "emotional_arc"]:
		assert_gte(score[key], 0.0, "%s >= 0" % key)
		assert_lte(score[key], 1.0, "%s <= 1" % key)


func test_weighted_score_is_weighted_sum() -> void:
	var genome = GenomeScript.load_file("res://sim/default_genome.json")
	var results: Array = []
	for strat in ["adaptive", "economy"]:
		results.append(RunnerScript.new(genome, strat, 42).run())

	var score: Dictionary = EvalScript.evaluate(results)
	var expected: float = (
		score.board_utilization * 0.12 +
		score.activation_utilization * 0.08 +
		score.win_rate_band * 0.13 +
		score.tipping_point_quality * 0.17 +
		score.dominance_moment * 0.12 +
		score.theme_ratio_variance * 0.13 +
		score.card_coverage * 0.10 +
		score.emotional_arc * 0.05 +
		score.loss_resilience * 0.10
	)
	assert_almost_eq(score.weighted_score, expected, 0.001, "가중합 일치")


# ================================================================
# 개별 축 단위 테스트 (합성 데이터)
# ================================================================

func test_gini_uniform_is_zero() -> void:
	# 모든 카드 CP가 동일 → Gini = 0 → utilization = 1.0
	var cps := [100.0, 100.0, 100.0, 100.0]
	var gini: float = EvalScript._calc_gini(cps)
	assert_almost_eq(gini, 0.0, 0.01, "균등 CP → Gini 0")


func test_gini_extreme_is_high() -> void:
	# 한 카드가 모든 CP → Gini ≈ 0.75
	var cps := [0.0, 0.0, 0.0, 400.0]
	var gini: float = EvalScript._calc_gini(cps)
	assert_gt(gini, 0.5, "극단 불균등 → Gini 높음")


func test_win_rate_in_band() -> void:
	# 클리어율 7.5% = 목표 중심 → 높은 점수
	var score: float = EvalScript._score_win_rate_band(0.075, 0.03)
	assert_gt(score, 0.5, "7.5% 클리어율 목표 내 → 높은 점수")


func test_win_rate_out_of_band() -> void:
	# 클리어율 50% = 목표 외 → 낮은 점수
	var score: float = EvalScript._score_win_rate_band(0.50, 0.05)
	assert_lt(score, 0.3, "50% 클리어율 목표 외 → 낮은 점수")
