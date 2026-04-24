class_name Evaluator
extends RefCounted
## Fixed evaluator for autoresearch. Computes 9-axis score from simulation results.
## IMMUTABLE — do not modify during autoresearch (without explicit user authorization).

## Axis weights (v9 — 2026-04-22: win_rate_band + emotional_arc 통합 → per_round_wr_match).
## 변경 사유: target_wr_curve.json이 진실 소스가 되면서, 두 축이 각각 다른 기준으로 평가하던
## "WR이 맞나"와 "라운드별 흐름이 맞나"가 하나의 per-round WR 매칭 신호로 수렴.
## 가중치 0.13 + 0.05 = 0.18을 신축으로 이전.
const WEIGHTS := {
	"board_utilization": 0.12,
	"activation_utilization": 0.08,
	"per_round_wr_match": 0.18,
	"tipping_point_quality": 0.17,
	"dominance_moment": 0.12,
	"theme_ratio_variance": 0.13,
	"card_coverage": 0.10,
	"loss_resilience": 0.10,
}

## Per-round WR match — segment-based Gaussian scoring.
## target_wr는 target_wr_curve.json에서 런타임 로드 (evaluator 클래스 로드 시 1회).
## σ_pp는 각 segment의 noise floor 고려값 (binomial SE × 1.5).
const TARGET_CURVE_PATH := "res://sim/target_wr_curve.json"
const WR_MATCH_SIGMA_PP := {
	"early": 5.0,   # R1-R8  (n≈140, SE~2.5pp)
	"mid":   8.0,   # R9-R12 (n≈80, SE~5pp)
	"late": 12.0,   # R13-R15 (n≈30, SE~9pp)
}
const MIN_SAMPLES_PER_ROUND := 10  # 소표본 라운드는 점수 계산에서 제외

## CP margin gate for board_utilization.
const MARGIN_LO := 0.2
const MARGIN_HI := 2.0

## Tipping threshold: CP must increase 50%+ from previous round.
const TIPPING_THRESHOLD := 0.5

## Card coverage: count cards appearing in 10%+ of runs.
const COVERAGE_THRESHOLD := 0.10


## Evaluate a batch of simulation results. Returns score dictionary.
## results: Array[Dictionary] from HeadlessRunner.run()
static func evaluate(results: Array) -> Dictionary:
	var scores := {}
	scores["board_utilization"] = _eval_board_utilization(results)
	scores["activation_utilization"] = _eval_activation_utilization(results)
	scores["per_round_wr_match"] = _eval_per_round_wr_match(results)
	scores["tipping_point_quality"] = _eval_tipping_point(results)
	scores["dominance_moment"] = _eval_dominance_moment(results)
	scores["theme_ratio_variance"] = _eval_theme_ratio_variance(results)
	scores["card_coverage"] = _eval_card_coverage(results)
	scores["loss_resilience"] = _eval_loss_resilience(results)

	# Weighted sum
	var ws := 0.0
	for key in WEIGHTS:
		ws += scores[key] * WEIGHTS[key]
	scores["weighted_score"] = ws

	return scores


# ================================================================
# Axis 1: board_utilization — CP Gini, margin-gated
# ================================================================

static func _eval_board_utilization(results: Array) -> float:
	var gini_sum := 0.0
	var count := 0
	for r in results:
		for rd in r.round_data:
			if not rd.battle_won:
				continue
			# Margin gate: only count rounds where victory margin is in range
			var ally: int = rd.ally_survived
			var enemy: int = rd.enemy_survived
			var total_player: int = rd.total_player_units
			if total_player == 0:
				continue
			var survival_ratio: float = float(ally) / total_player
			if survival_ratio < MARGIN_LO or survival_ratio > MARGIN_HI:
				continue
			var cps: Array = rd.card_cps
			if cps.size() < 2:
				continue
			gini_sum += _calc_gini(cps)
			count += 1
	if count == 0:
		return 0.5  # No data, neutral
	# Lower Gini = more equal = better. Score = 1 - avg_gini.
	return clampf(1.0 - gini_sum / count, 0.0, 1.0)


## Gini coefficient for an array of values.
static func _calc_gini(values: Array) -> float:
	var n: int = values.size()
	if n < 2:
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	if total <= 0.0:
		return 0.0
	var sum_diff := 0.0
	for i in n:
		for j in n:
			sum_diff += absf(values[i] - values[j])
	return sum_diff / (2.0 * n * total)


# ================================================================
# Axis 2: activation_utilization — avg(used / cap)
# ================================================================

static func _eval_activation_utilization(results: Array) -> float:
	var util_sum := 0.0
	var count := 0
	for r in results:
		for rd in r.round_data:
			var total_act: int = rd.total_activations
			var max_act: int = rd.get("max_activations", 0)
			if max_act <= 0:
				continue
			# Direct ratio: activations_used / max_activations across all cards
			# Ideal: 0.4-0.8 utilization (not too low, not maxed out)
			var util: float = clampf(float(total_act) / max_act, 0.0, 1.0)
			util_sum += util
			count += 1
	if count == 0:
		return 0.5
	var avg: float = util_sum / count
	# Best score at utilization ~0.6 (not too low, not maxed)
	return clampf(1.0 - absf(avg - 0.6) * 2.5, 0.0, 1.0)


# ================================================================
# Axis 3: per_round_wr_match — design curve matching (2026-04-22)
# ================================================================
##
## target_wr_curve.json (R0/R4/R8/R12/R15 앵커 → 15-round cumulative survival)
## 으로부터 per-round target WR을 도출하고, 측정 WR과의 오차를 segment별
## Gaussian으로 채점. 이전 win_rate_band + emotional_arc 두 축을 대체.
##
## Segment 기반 이유: 후반 라운드는 도달자 적어 noise floor 높음. σ를 segment별로
## 조정하지 않으면 후반 soft fail이 전반 hard fail과 동점 점수로 나와 gradient 혼탁.
##
## Formula (per round):
##   score_r = exp(-((actual_wr[r] - target_wr[r])/100 / sigma_pp[segment])^2 / 2)
##   (Gaussian, σ is in percentage points)
## Final = mean(score_r) across rounds with totals[r] >= MIN_SAMPLES_PER_ROUND.
##
## target_wr는 evaluator 클래스 로드 시 1회 로드 (static cache). 런 중 불변.
static var _target_wr: Array = _load_target_wr()


static func _load_target_wr() -> Array:
	var file := FileAccess.open(TARGET_CURVE_PATH, FileAccess.READ)
	if file == null:
		push_error("Evaluator: target_wr_curve.json not found at %s — per_round_wr_match disabled" % TARGET_CURVE_PATH)
		return []
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("Evaluator: target_wr_curve.json parse failed")
		return []
	var data: Dictionary = json.data
	var anchors: Dictionary = data.get("survival_anchors", {})
	var rounds: Array = anchors.get("rounds", [])
	var values: Array = anchors.get("values", [])
	if rounds.size() != values.size() or rounds.size() < 2:
		push_error("Evaluator: invalid survival_anchors")
		return []
	# Geometric interpolation: expand anchors → 15-round cumulative survival
	var survival: Array = []
	survival.resize(16)
	survival[0] = 1.0
	for seg in range(rounds.size() - 1):
		var r_start: int = rounds[seg]
		var r_end: int = rounds[seg + 1]
		var v_start: float = values[seg]
		var v_end: float = values[seg + 1]
		var per_round_clear: float = pow(v_end / v_start, 1.0 / (r_end - r_start))
		for r in range(r_start + 1, r_end + 1):
			survival[r] = survival[r - 1] * per_round_clear
	# Survival → target_wr (ratio)
	var target_wr: Array = []
	var prev: float = 1.0
	for r in range(1, 16):
		target_wr.append(survival[r] / prev if prev > 0.0 else 0.0)
		prev = survival[r]
	return target_wr


static func _segment_of(round_index: int) -> String:
	# round_index is 0-indexed (0 = R1, 14 = R15)
	if round_index < 8:
		return "early"
	if round_index < 12:
		return "mid"
	return "late"


static func _eval_per_round_wr_match(results: Array) -> float:
	if _target_wr.is_empty():
		return 0.5  # curve not loaded — neutral score
	# Aggregate per-round wins/totals
	var wins: Array = []
	var totals: Array = []
	wins.resize(15)
	totals.resize(15)
	for i in 15:
		wins[i] = 0
		totals[i] = 0
	for r in results:
		for rd in r.round_data:
			var rn: int = int(rd.round_num) - 1
			if rn >= 0 and rn < 15:
				totals[rn] += 1
				if rd.battle_won:
					wins[rn] += 1
	# Score per round (only those with enough samples)
	var score_sum: float = 0.0
	var count: int = 0
	for rn in 15:
		if totals[rn] < MIN_SAMPLES_PER_ROUND:
			continue
		var actual_wr: float = float(wins[rn]) / totals[rn]
		var target_wr: float = float(_target_wr[rn])
		var seg: String = _segment_of(rn)
		var sigma_pp: float = WR_MATCH_SIGMA_PP[seg]
		var dist_pp: float = (actual_wr - target_wr) * 100.0
		var score: float = exp(-dist_pp * dist_pp / (2.0 * sigma_pp * sigma_pp))
		score_sum += score
		count += 1
	if count == 0:
		return 0.0
	return clampf(score_sum / count, 0.0, 1.0)


# ================================================================
# Axis 4: tipping_point_quality — max impact_ratio × defeat prerequisite × merge bonus
# ================================================================

static func _eval_tipping_point(results: Array) -> float:
	var scores: Array = []
	for r in results:
		var rd_arr: Array = r.round_data
		if rd_arr.size() < 4:
			scores.append(0.0)
			continue

		# Find tipping rounds: CP increase > 50% from previous
		var best_impact := 0.0
		var has_prior_defeat := false
		var merge_rounds: Dictionary = {}
		for me in r.merge_events:
			merge_rounds[me.round] = true

		for i in range(1, rd_arr.size()):
			var prev_cp := _total_cp(rd_arr[i - 1])
			var curr_cp := _total_cp(rd_arr[i])
			if prev_cp <= 0.0:
				continue
			var growth: float = (curr_cp - prev_cp) / prev_cp
			if growth < TIPPING_THRESHOLD:
				continue

			# Check defeat prerequisite: at least 1 loss before this round
			has_prior_defeat = false
			for j in range(0, i):
				if not rd_arr[j].battle_won:
					has_prior_defeat = true
					break
			if not has_prior_defeat:
				continue

			# Impact ratio: avg margin after / avg margin before
			var before_margin := _avg_margin(rd_arr, maxi(0, i - 3), i)
			var after_margin := _avg_margin(rd_arr, i, mini(rd_arr.size(), i + 3))
			if before_margin <= 0.0:
				before_margin = 0.01  # Prevent division by zero
			var impact: float = after_margin / before_margin

			# Merge bonus
			var round_num: int = rd_arr[i].round_num
			if merge_rounds.has(round_num):
				impact *= 1.5

			best_impact = maxf(best_impact, impact)

		# Normalize: impact 3.0+ = perfect score
		scores.append(clampf(best_impact / 3.0, 0.0, 1.0))

	if scores.is_empty():
		return 0.0
	var total := 0.0
	for s in scores:
		total += s
	return total / scores.size()


## Sum of all card CPs in a round.
static func _total_cp(rd: Dictionary) -> float:
	var total := 0.0
	for cp in rd.card_cps:
		total += cp
	return total


## Average "margin" across a range of rounds. Margin = ally_survived - enemy_survived.
static func _avg_margin(rd_arr: Array, from: int, to: int) -> float:
	var total := 0.0
	var count := 0
	for i in range(from, to):
		if i >= 0 and i < rd_arr.size():
			total += rd_arr[i].ally_survived - rd_arr[i].enemy_survived
			count += 1
	return total / count if count > 0 else 0.0


# ================================================================
# Axis 5: dominance_moment — max(survival_ratio × elimination_ratio)
# ================================================================

static func _eval_dominance_moment(results: Array) -> float:
	var scores: Array = []
	for r in results:
		var best := 0.0
		for rd in r.round_data:
			if not rd.battle_won:
				continue
			var total_units: int = rd.total_player_units
			var survived: int = rd.ally_survived
			var enemy_total: int = rd.total_enemy_units
			var enemy_survived: int = rd.enemy_survived
			if total_units == 0 or enemy_total == 0:
				continue
			var survival_ratio: float = float(survived) / total_units
			var elimination_ratio: float = float(enemy_total - enemy_survived) / enemy_total
			var dominance: float = survival_ratio * elimination_ratio
			best = maxf(best, dominance)
		scores.append(best)

	if scores.is_empty():
		return 0.0
	var total := 0.0
	for s in scores:
		total += s
	return total / scores.size()


# ================================================================
# Axis 6: theme_ratio_variance — within-AI variance of theme vectors
# ================================================================

static func _eval_theme_ratio_variance(results: Array) -> float:
	# Group results by strategy
	var by_strat: Dictionary = {}
	for r in results:
		var s: String = r.strategy
		if not by_strat.has(s):
			by_strat[s] = []
		# Theme ratio vector from final deck
		var vec := _theme_vector(r.final_deck)
		by_strat[s].append(vec)

	# Compute within-strategy variance, average across strategies
	var var_sum := 0.0
	var strat_count := 0
	for strat in by_strat:
		var vecs: Array = by_strat[strat]
		if vecs.size() < 2:
			continue
		var variance: float = _vec_variance(vecs)
		var_sum += variance
		strat_count += 1

	if strat_count == 0:
		return 0.0
	var avg_var: float = var_sum / strat_count
	# Normalize: variance 0.1+ = good diversity
	return clampf(avg_var / 0.1, 0.0, 1.0)


## Extract theme ratio vector [s%, d%, p%, m%] from final deck.
static func _theme_vector(deck: Array) -> Array:
	var counts := [0.0, 0.0, 0.0, 0.0]  # S, D, P, M
	var total := 0.0
	for entry in deck:
		var theme: int = entry.get("theme", 0)
		match theme:
			Enums.CardTheme.STEAMPUNK: counts[0] += 1.0
			Enums.CardTheme.DRUID: counts[1] += 1.0
			Enums.CardTheme.PREDATOR: counts[2] += 1.0
			Enums.CardTheme.MILITARY: counts[3] += 1.0
			_: pass  # Neutral excluded
		total += 1.0
	if total <= 0.0:
		return [0.25, 0.25, 0.25, 0.25]
	# Count only theme cards for normalization
	var theme_total: float = counts[0] + counts[1] + counts[2] + counts[3]
	if theme_total <= 0.0:
		return [0.25, 0.25, 0.25, 0.25]
	return [counts[0] / theme_total, counts[1] / theme_total,
			counts[2] / theme_total, counts[3] / theme_total]


## Average element-wise variance across a set of 4D vectors.
static func _vec_variance(vecs: Array) -> float:
	if vecs.size() < 2:
		return 0.0
	var n: int = vecs.size()
	var dim := 4
	var total_var := 0.0
	for d in dim:
		var mean := 0.0
		for v in vecs:
			mean += v[d]
		mean /= n
		var var_d := 0.0
		for v in vecs:
			var diff: float = v[d] - mean
			var_d += diff * diff
		var_d /= n
		total_var += var_d
	return total_var / dim


# ================================================================
# Axis 7: card_coverage — min(per-theme avg usage rate)
# ================================================================

static func _eval_card_coverage(results: Array) -> float:
	# Count card appearances across all runs
	var card_runs: Dictionary = {}  # card_id → number of runs it appeared in
	var total_runs: int = results.size()
	if total_runs == 0:
		return 0.0

	for r in results:
		var seen: Dictionary = {}
		for entry in r.final_deck:
			seen[entry.card_id] = true
		# Also count from purchase log
		for card_id in r.purchase_log:
			seen[card_id] = true
		for card_id in seen:
			card_runs[card_id] = card_runs.get(card_id, 0) + 1

	# Per-theme coverage: mean(usage_rate) for each theme's 10 cards
	var theme_coverages: Array = []
	for theme in [Enums.CardTheme.STEAMPUNK, Enums.CardTheme.DRUID,
			Enums.CardTheme.PREDATOR, Enums.CardTheme.MILITARY]:
		var theme_ids: Array = CardDB.get_ids_by_theme(theme)
		if theme_ids.is_empty():
			continue
		var rate_sum := 0.0
		for card_id in theme_ids:
			var runs_with: int = card_runs.get(card_id, 0)
			rate_sum += float(runs_with) / total_runs
		theme_coverages.append(rate_sum / theme_ids.size())

	if theme_coverages.is_empty():
		return 0.0
	# Min coverage across themes
	var min_cov: float = theme_coverages[0]
	for c in theme_coverages:
		min_cov = minf(min_cov, c)
	return clampf(min_cov, 0.0, 1.0)


# ================================================================
# Axis 8: loss_resilience — final HP normalized (close losses > stomps)
# ================================================================
## 2026-04-22: emotional_arc 축 제거 — per_round_wr_match로 통합됨.
## ARC_SEGMENTS(4-segment in/out band)는 target_wr_curve의 segment별 Gaussian
## σ로 대체됨 (continuous gradient, cliff 없음).
##
## Rationale (Pragmatist 2026-04-07):
## avg_hp 데이터는 batch_runner.gd에서 수집되지만 8축 evaluator가 무시.
## R3에서 -20 HP로 패배 vs R14에서 -2 HP로 패배는 완전히 다른 게임이지만
## win_rate_band/emotional_arc는 둘 다 "0/10 패배"로 동일 처리.
## 이 축은 final_hp를 [0, 1]로 normalize하여 close loss와 stomp를 구분.
##
## Formula: resilience = clamp((final_hp + 30) / 60, 0, 1)
##   HP= 30 (full health win): 1.00
##   HP= 10 (close win):       0.67
##   HP=  0 (last-stand win):  0.50
##   HP= -1 (very close loss): 0.483
##   HP=-10 (close loss):      0.33
##   HP=-20 (decisive loss):   0.17
##   HP=-30 (stomped):         0.00
static func _eval_loss_resilience(results: Array) -> float:
	if results.is_empty():
		return 0.5
	var total := 0.0
	for r in results:
		var hp: float = float(r.get("final_hp", 0))
		var resilience: float = clampf((hp + 30.0) / 60.0, 0.0, 1.0)
		total += resilience
	return total / results.size()
