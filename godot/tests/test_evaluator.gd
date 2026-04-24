extends GutTest
## Evaluator 8축 평가 테스트 (2026-04-22: per_round_wr_match 신축 반영).

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
	assert_has(score, "per_round_wr_match")
	assert_has(score, "tipping_point_quality")
	assert_has(score, "dominance_moment")
	assert_has(score, "theme_ratio_variance")
	assert_has(score, "card_coverage")
	assert_has(score, "loss_resilience")
	assert_has(score, "weighted_score")
	# 제거된 축은 존재하지 않아야
	assert_false(score.has("win_rate_band"), "win_rate_band 제거됨")
	assert_false(score.has("emotional_arc"), "emotional_arc 제거됨")


func test_scores_are_bounded() -> void:
	var genome = GenomeScript.load_file("res://sim/default_genome.json")
	var results: Array = []
	for strat in ["adaptive", "aggressive"]:
		for seed_val in [10, 20]:
			results.append(RunnerScript.new(genome, strat, seed_val).run())

	var score: Dictionary = EvalScript.evaluate(results)
	for key in ["board_utilization", "activation_utilization", "per_round_wr_match",
			"tipping_point_quality", "dominance_moment",
			"theme_ratio_variance", "card_coverage", "loss_resilience"]:
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
		score.per_round_wr_match * 0.18 +
		score.tipping_point_quality * 0.17 +
		score.dominance_moment * 0.12 +
		score.theme_ratio_variance * 0.13 +
		score.card_coverage * 0.10 +
		score.loss_resilience * 0.10
	)
	assert_almost_eq(score.weighted_score, expected, 0.001, "가중합 일치")


# ================================================================
# 개별 축 단위 테스트
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


# ================================================================
# per_round_wr_match — target curve 로드 및 segment 분기
# ================================================================

func test_target_wr_loaded() -> void:
	# 정적 캐시가 로드되어 있어야
	assert_eq(EvalScript._target_wr.size(), 15, "target_wr 15 entries")
	# R1 target ≈ 94.6% (anchor R0=1.0, R4=0.80, (0.80)^0.25)
	assert_almost_eq(float(EvalScript._target_wr[0]), 0.9457, 0.005, "R1 target ~94.6%")
	# R15 target ≈ 65.4% ((0.07/0.25)^(1/3))
	assert_almost_eq(float(EvalScript._target_wr[14]), 0.6542, 0.005, "R15 target ~65.4%")


func test_segment_of_early() -> void:
	for r in range(8):  # R1..R8 (0-indexed 0..7)
		assert_eq(EvalScript._segment_of(r), "early", "R%d early" % (r + 1))


func test_segment_of_mid() -> void:
	for r in range(8, 12):  # R9..R12
		assert_eq(EvalScript._segment_of(r), "mid", "R%d mid" % (r + 1))


func test_segment_of_late() -> void:
	for r in range(12, 15):  # R13..R15
		assert_eq(EvalScript._segment_of(r), "late", "R%d late" % (r + 1))


func test_per_round_wr_match_empty_returns_zero() -> void:
	var score: float = EvalScript._eval_per_round_wr_match([])
	assert_eq(score, 0.0, "빈 results → 0")


func test_per_round_wr_match_perfect_hit() -> void:
	# 조작된 results: n=100 per round, 각 라운드 wins = round(target_wr * 100)
	# 이로써 측정 WR이 target_wr에 ≤1pp 오차로 접근.
	var fake_results: Array = []
	var n: int = 100
	for i in n:
		var rd_arr: Array = []
		for rn in range(1, 16):
			var t_wr: float = float(EvalScript._target_wr[rn - 1])
			var won: bool = float(i) < t_wr * n
			rd_arr.append({"round_num": rn, "battle_won": won})
		fake_results.append({"round_data": rd_arr})
	var score: float = EvalScript._eval_per_round_wr_match(fake_results)
	# n=100 이면 round 단위 오차 ≤ 1pp << σ(5/8/12) → 거의 1.0
	assert_gt(score, 0.95, "target_wr 정밀 매칭 → ~1.0 점수")


func test_per_round_wr_match_far_from_target_early() -> void:
	# R1-R8 모두 WR 0% — early target ~90%+, sigma 5pp → 극히 낮은 점수
	var fake_results: Array = []
	for i in 100:
		var rd_arr: Array = []
		for rn in range(1, 16):
			rd_arr.append({"round_num": rn, "battle_won": false})
		fake_results.append({"round_data": rd_arr})
	var score: float = EvalScript._eval_per_round_wr_match(fake_results)
	assert_lt(score, 0.1, "모든 라운드 WR 0% → 낮은 점수")
