extends GutTest
## AI Theme Scorer 테스트 — theme_state 기반 스코어링 검증.

const ThemeScorerScript = preload("res://sim/ai_theme_scorer.gd")
const GenomeScript = preload("res://sim/genome.gd")


# ================================================================
# Helpers
# ================================================================

func _make_card(card_id: String, theme: int, tier: int = 1, star: int = 1) -> CardInstance:
	var card := CardInstance.new()
	card.template_id = card_id
	card.template = {"id": card_id, "theme": theme, "tier": tier}
	card.star_level = star
	return card


func _make_card_with_trees(card_id: String, trees: int, star: int = 1) -> CardInstance:
	var card := _make_card(card_id, Enums.CardTheme.DRUID, 1, star)
	card.theme_state["trees"] = trees
	return card


func _make_card_with_rank(card_id: String, rank: int, star: int = 1) -> CardInstance:
	var card := _make_card(card_id, Enums.CardTheme.MILITARY, 1, star)
	card.theme_state["rank"] = rank
	card.theme_state["rank_triggers"] = {}
	return card


func _make_card_with_counter(card_id: String, counter_key: String, counter_val: int, star: int = 1) -> CardInstance:
	var card := _make_card(card_id, Enums.CardTheme.STEAMPUNK, 4, star)
	card.theme_state[counter_key] = counter_val
	return card


func _make_genome(overrides: Dictionary = {}) -> RefCounted:
	var g := GenomeScript.new()
	for k in overrides:
		g.ai_params[k] = overrides[k]
	return g


# ================================================================
# card_value_bonus — 드루이드 나무
# ================================================================

func test_druid_trees_increase_value() -> void:
	var scorer := ThemeScorerScript.new()
	var card_0 := _make_card_with_trees("dr_deep", 0)
	var card_10 := _make_card_with_trees("dr_deep", 10)
	var genome := _make_genome()

	var bonus_0: float = scorer.card_value_bonus(card_0, [], genome)
	var bonus_10: float = scorer.card_value_bonus(card_10, [], genome)

	assert_gt(bonus_10, bonus_0, "나무 10개 카드가 0개보다 높은 가치")
	# tree_value_per 기본값 2.0 → 10 * 2.0 = +20 차이
	assert_almost_eq(bonus_10 - bonus_0, 20.0, 1.0, "나무 10개 ≈ +20 가치")


func test_druid_trees_scaled_by_param() -> void:
	var scorer := ThemeScorerScript.new()
	var card := _make_card_with_trees("dr_cradle", 5)
	var genome_low := _make_genome({"tree_value_per": 1.0})
	var genome_high := _make_genome({"tree_value_per": 4.0})

	var bonus_low: float = scorer.card_value_bonus(card, [], genome_low)
	var bonus_high: float = scorer.card_value_bonus(card, [], genome_high)

	assert_gt(bonus_high, bonus_low, "tree_value_per가 높으면 보너스 증가")


# ================================================================
# card_value_bonus — 군대 랭크
# ================================================================

func test_military_rank_increases_value() -> void:
	var scorer := ThemeScorerScript.new()
	var card_0 := _make_card_with_rank("ml_barracks", 0)
	var card_7 := _make_card_with_rank("ml_barracks", 7)
	var genome := _make_genome()

	var bonus_0: float = scorer.card_value_bonus(card_0, [], genome)
	var bonus_7: float = scorer.card_value_bonus(card_7, [], genome)

	assert_gt(bonus_7, bonus_0, "랭크 7 카드가 0보다 높은 가치")


func test_military_near_threshold_bonus() -> void:
	var scorer := ThemeScorerScript.new()
	# ml_barracks thresholds: 3, 5, 8. Rank 2 is 1 away from 3.
	var card_near := _make_card_with_rank("ml_barracks", 2)
	var card_far := _make_card_with_rank("ml_barracks", 0)
	var genome := _make_genome()

	var bonus_near: float = scorer.card_value_bonus(card_near, [], genome)
	var bonus_far: float = scorer.card_value_bonus(card_far, [], genome)

	# Near-threshold should get extra bonus beyond just rank*value_per
	var rank_diff: float = 2.0 * genome.get_ai_param("rank_value_per")
	var actual_diff: float = bonus_near - bonus_far
	assert_gt(actual_diff, rank_diff, "임계 근접 보너스가 랭크 차이 이상")


# ================================================================
# card_value_bonus — 스팀펑크 카운터
# ================================================================

func test_steampunk_counter_near_threshold() -> void:
	var scorer := ThemeScorerScript.new()
	# sp_charger manufacture_counter near 10 threshold
	var card_near := _make_card_with_counter("sp_charger", "manufacture_counter", 8)
	var card_far := _make_card_with_counter("sp_charger", "manufacture_counter", 2)
	var genome := _make_genome()

	var bonus_near: float = scorer.card_value_bonus(card_near, [], genome)
	var bonus_far: float = scorer.card_value_bonus(card_far, [], genome)

	assert_gt(bonus_near, bonus_far, "카운터 8/10이 2/10보다 높은 가치")


# ================================================================
# card_value_bonus — theme_state_weight 글로벌 배율
# ================================================================

func test_theme_state_weight_scales_all() -> void:
	var scorer := ThemeScorerScript.new()
	var card := _make_card_with_trees("dr_deep", 10)
	var genome_1x := _make_genome({"theme_state_weight": 1.0})
	var genome_2x := _make_genome({"theme_state_weight": 2.0})

	var bonus_1x: float = scorer.card_value_bonus(card, [], genome_1x)
	var bonus_2x: float = scorer.card_value_bonus(card, [], genome_2x)

	assert_almost_eq(bonus_2x, bonus_1x * 2.0, 0.5, "weight 2x ≈ 보너스 2배")


# ================================================================
# card_value_bonus — 비테마 카드는 보너스 0
# ================================================================

func test_neutral_card_no_bonus() -> void:
	var scorer := ThemeScorerScript.new()
	var card := _make_card("nt_merchant", Enums.CardTheme.NEUTRAL)
	var genome := _make_genome()

	var bonus: float = scorer.card_value_bonus(card, [], genome)
	assert_eq(bonus, 0.0, "중립 카드는 테마 보너스 없음")


# ================================================================
# score_buy_bonus — 드루이드 유닛캡 근접 페널티
# ================================================================

func _make_druid_card_with_units(card_id: String, units: int, star: int = 1) -> CardInstance:
	var c := _make_card(card_id, Enums.CardTheme.DRUID, 1, star)
	c.stacks = [{"unit_type": {"id": "dr_treant"}, "count": units,
		"upgrade_atk_mult": 1.0, "upgrade_hp_mult": 1.0,
		"temp_atk": 0.0, "temp_atk_mult": 1.0, "temp_hp_mult": 1.0}]
	return c


func test_druid_no_penalty_without_dr_world() -> void:
	# 버그 수정(2026-04-18): dr_world 없으면 total druid units 기반 페널티 없음.
	# dr_world unit_cap은 자신(dr_world)만 대상.
	var scorer := ThemeScorerScript.new()
	var genome := _make_genome()

	var board_cards: Array = []
	for i in 3:
		board_cards.append(_make_druid_card_with_units("dr_cradle", 6))  # 총 18기

	var tmpl := {"id": "dr_earth", "theme": Enums.CardTheme.DRUID, "tier": 2}
	var bonus: float = scorer.score_buy_bonus("dr_earth", tmpl, Enums.CardTheme.DRUID, board_cards, genome)

	assert_gte(bonus, 0.0, "dr_world 없으면 유닛 수 상관없이 페널티 없음")


func test_druid_penalty_with_dr_world_near_cap() -> void:
	# dr_world ★1 (cap=20), 자신의 unit count에 따라 페널티 스케일.
	# 캡 근접(19) vs 여유(5) 비교 — payoff 보너스는 양쪽 동일하므로 순수 페널티 차이 검증.
	var scorer := ThemeScorerScript.new()
	var genome := _make_genome()

	var tmpl := {"id": "dr_cradle", "theme": Enums.CardTheme.DRUID, "tier": 1}

	var bonus_near: float = scorer.score_buy_bonus("dr_cradle", tmpl, Enums.CardTheme.DRUID,
		[_make_druid_card_with_units("dr_world", 19, 1)], genome)
	var bonus_far: float = scorer.score_buy_bonus("dr_cradle", tmpl, Enums.CardTheme.DRUID,
		[_make_druid_card_with_units("dr_world", 5, 1)], genome)

	assert_lt(bonus_near, bonus_far, "dr_world 자기 유닛이 cap 근접할수록 페널티 ↑")


# ================================================================
# score_buy_bonus — 군대 트레이닝 시너지
# ================================================================

func test_military_training_synergy() -> void:
	var scorer := ThemeScorerScript.new()
	var genome := _make_genome()

	# Board has ml_academy → buying training cards is more valuable
	var board_with_academy: Array = [_make_card("ml_academy", Enums.CardTheme.MILITARY, 2)]
	var board_without: Array = [_make_card("ml_supply", Enums.CardTheme.MILITARY, 2)]

	var tmpl := {"id": "ml_barracks", "theme": Enums.CardTheme.MILITARY, "tier": 1}

	var bonus_with: float = scorer.score_buy_bonus("ml_barracks", tmpl, Enums.CardTheme.MILITARY, board_with_academy, genome)
	var bonus_without: float = scorer.score_buy_bonus("ml_barracks", tmpl, Enums.CardTheme.MILITARY, board_without, genome)

	assert_gt(bonus_with, bonus_without, "ml_academy 보유 시 트레이닝 카드 구매 보너스")


# ================================================================
# score_buy_bonus — 크로스 체인 보너스 (CHAIN_PAIRS 기반)
# ================================================================

func test_military_factory_prefers_conscript_emitter() -> void:
	var scorer := ThemeScorerScript.new()
	var genome := _make_genome()

	# ml_factory는 CO 이벤트 listener. 보드에 factory가 있으면 CO emitter(ml_conscript) 구매 우선.
	var board_with_factory: Array = [_make_card("ml_factory", Enums.CardTheme.MILITARY, 4)]
	var board_neutral: Array = [_make_card("ml_supply", Enums.CardTheme.MILITARY, 2)]
	var tmpl := {"id": "ml_conscript", "theme": Enums.CardTheme.MILITARY, "tier": 1}

	var with_f: float = scorer.score_buy_bonus("ml_conscript", tmpl, Enums.CardTheme.MILITARY, board_with_factory, genome)
	var without_f: float = scorer.score_buy_bonus("ml_conscript", tmpl, Enums.CardTheme.MILITARY, board_neutral, genome)

	assert_gt(with_f, without_f, "ml_factory 보유 시 ml_conscript 구매 보너스 (CO 체인 완성)")


func test_military_emitter_prefers_listener() -> void:
	var scorer := ThemeScorerScript.new()
	var genome := _make_genome()

	# 보드에 ml_barracks(TR emitter)만 있을 때 ml_academy(TR listener) 구매에 보너스.
	var board_emitter_only: Array = [_make_card("ml_barracks", Enums.CardTheme.MILITARY, 1)]
	var board_neutral: Array = [_make_card("ml_supply", Enums.CardTheme.MILITARY, 2)]
	var tmpl := {"id": "ml_academy", "theme": Enums.CardTheme.MILITARY, "tier": 2}

	var with_e: float = scorer.score_buy_bonus("ml_academy", tmpl, Enums.CardTheme.MILITARY, board_emitter_only, genome)
	var without_e: float = scorer.score_buy_bonus("ml_academy", tmpl, Enums.CardTheme.MILITARY, board_neutral, genome)

	assert_gt(with_e, without_e, "ml_barracks(TR emitter) 보유 시 ml_academy 구매 보너스")


# ================================================================
# card_value_bonus — enhanced_count 기반 ml_assault/ml_tactical 가치
# ================================================================

func _make_military_card_with_enhanced(card_id: String, enhanced_units: int) -> CardInstance:
	var card := _make_card(card_id, Enums.CardTheme.MILITARY, 3)
	card.theme_state["rank"] = 0
	card.theme_state["rank_triggers"] = {}
	if enhanced_units > 0:
		card.stacks = [{
			"unit_type": {"id": "ml_recruit_enhanced", "tags": PackedStringArray(["enhanced"])},
			"count": enhanced_units,
			"upgrade_atk_mult": 1.0, "upgrade_hp_mult": 1.0,
			"temp_atk": 0.0, "temp_atk_mult": 1.0, "temp_hp_mult": 1.0,
		}]
	return card


func test_military_assault_gains_value_from_enhanced_units() -> void:
	var scorer := ThemeScorerScript.new()
	var assault := _make_card_with_rank("ml_assault", 0)
	var genome := _make_genome()

	# 빈 보드 vs enhanced 유닛 많은 보드
	var board_empty: Array = [assault]
	var enhanced_provider := _make_military_card_with_enhanced("ml_conscript", 6)
	var board_with_enhanced: Array = [assault, enhanced_provider]

	var bonus_empty: float = scorer.card_value_bonus(assault, board_empty, genome)
	var bonus_full: float = scorer.card_value_bonus(assault, board_with_enhanced, genome)

	assert_gt(bonus_full, bonus_empty, "보드에 enhanced 유닛이 많을수록 ml_assault 가치 상승")


func test_military_non_assault_unaffected_by_enhanced() -> void:
	var scorer := ThemeScorerScript.new()
	var supply := _make_card_with_rank("ml_supply", 0)  # assault/tactical 아님
	var genome := _make_genome()

	var board_empty: Array = [supply]
	var enhanced_provider := _make_military_card_with_enhanced("ml_conscript", 6)
	var board_with_enhanced: Array = [supply, enhanced_provider]

	var bonus_empty: float = scorer.card_value_bonus(supply, board_empty, genome)
	var bonus_full: float = scorer.card_value_bonus(supply, board_with_enhanced, genome)

	assert_almost_eq(bonus_full, bonus_empty, 0.01, "assault/tactical 아닌 군대 카드는 enhanced 보너스 없음")


# ================================================================
# card_value_bonus — 드루이드 나무 임계 근접 보너스
# ================================================================

func test_druid_deep_near_tree_threshold() -> void:
	# dr_deep ★1 tree_bonus thresh=10. 나무 9개 → 임박 보너스 발생.
	var scorer := ThemeScorerScript.new()
	var card_near := _make_card_with_trees("dr_deep", 9, 1)
	var card_far := _make_card_with_trees("dr_deep", 2, 1)
	var genome := _make_genome()

	var bonus_near: float = scorer.card_value_bonus(card_near, [], genome)
	var bonus_far: float = scorer.card_value_bonus(card_far, [], genome)

	var tree_diff: float = (9 - 2) * genome.get_ai_param("tree_value_per")
	assert_gt(bonus_near - bonus_far, tree_diff, "임계 근접 보너스가 나무 차이 이상")


func test_druid_wt_root_dual_threshold() -> void:
	# dr_wt_root ★2 thresholds=[3, 6]. 나무 5개 → 6 임계 근접.
	var scorer := ThemeScorerScript.new()
	var card_near := _make_card_with_trees("dr_wt_root", 5, 2)
	var card_far := _make_card_with_trees("dr_wt_root", 1, 2)  # 3 이미 미달, 거리=2
	var genome := _make_genome()

	var bonus_near: float = scorer.card_value_bonus(card_near, [], genome)
	var bonus_far: float = scorer.card_value_bonus(card_far, [], genome)
	# 둘 다 근접 (1→3 distance 2, 5→6 distance 1). 가까운 쪽이 더 큰 보너스.
	assert_gt(bonus_near, bonus_far, "가장 가까운 미달 임계까지 distance 작을수록 큰 보너스")


# ================================================================
# score_buy_bonus — 드루이드 payoff-producer 시너지
# ================================================================

func test_druid_payoff_boosts_producer() -> void:
	# 보드에 payoff 카드(dr_deep) 있음 → producer(dr_cradle) 구매 보너스.
	var scorer := ThemeScorerScript.new()
	var genome := _make_genome()

	var board_payoff: Array = [_make_card("dr_deep", Enums.CardTheme.DRUID, 3)]
	var board_empty: Array = []

	var tmpl := {"id": "dr_cradle", "theme": Enums.CardTheme.DRUID, "tier": 1}

	var with_p: float = scorer.score_buy_bonus("dr_cradle", tmpl, Enums.CardTheme.DRUID, board_payoff, genome)
	var without_p: float = scorer.score_buy_bonus("dr_cradle", tmpl, Enums.CardTheme.DRUID, board_empty, genome)

	assert_gt(with_p, without_p, "payoff 보유 시 tree producer 구매 보너스")
