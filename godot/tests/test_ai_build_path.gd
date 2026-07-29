extends GutTest
## Tests for AIBuildPath — theme-specific build path detection and scoring.

const BuildPath = preload("res://sim/ai_build_path.gd")
var bp


func before_each() -> void:
	bp = BuildPath.new()


# ================================================================
# Phase boundary tests
# ================================================================

func test_phase_foundation() -> void:
	for r in [1, 2, 3, 4]:
		assert_eq(BuildPath.get_phase(r), BuildPath.FOUNDATION,
			"R%d = FOUNDATION" % r)

func test_phase_engine() -> void:
	for r in [5, 6, 7, 8]:
		assert_eq(BuildPath.get_phase(r), BuildPath.ENGINE,
			"R%d = ENGINE" % r)

func test_phase_payoff() -> void:
	for r in [9, 10, 11]:
		assert_eq(BuildPath.get_phase(r), BuildPath.PAYOFF,
			"R%d = PAYOFF" % r)

func test_phase_capstone() -> void:
	for r in [12, 13, 14, 15]:
		assert_eq(BuildPath.get_phase(r), BuildPath.CAPSTONE,
			"R%d = CAPSTONE" % r)


# ================================================================
# Detection tests
# ================================================================

func test_detect_steampunk_spread() -> void:
	var board := {"sp_assembly": true, "sp_workshop": true}
	var path: Dictionary = bp.detect_build_path("soft_steampunk", board)
	assert_eq(path.get("id", ""), "steampunk_spread",
		"sp_assembly → spread path")

func test_detect_steampunk_focus() -> void:
	var board := {"sp_furnace": true, "sp_workshop": true}
	var path: Dictionary = bp.detect_build_path("soft_steampunk", board)
	assert_eq(path.get("id", ""), "steampunk_focus",
		"sp_furnace → focus path")

func test_detect_druid_world_tree() -> void:
	var board := {"dr_cradle": true, "dr_deep": true}
	var path: Dictionary = bp.detect_build_path("soft_druid", board)
	assert_eq(path.get("id", ""), "druid_world_tree",
		"dr_deep → world tree path")

func test_detect_druid_garden() -> void:
	var board := {"dr_cradle": true, "dr_origin": true, "dr_prune": true}
	var path: Dictionary = bp.detect_build_path("soft_druid", board)
	assert_eq(path.get("id", ""), "druid_garden",
		"dr_origin + dr_prune → garden path")

func test_druid_foundation_only_keeps_branch_open() -> void:
	var board := {"dr_cradle": true, "dr_lifebeat": true}
	var path: Dictionary = bp.detect_build_path("soft_druid", board)
	assert_true(path.is_empty(),
		"공유 기초 카드만 있으면 드루이드 분기 미확정")

func test_detect_predator_swarm() -> void:
	var board := {"pr_nest": true, "pr_farm": true, "pr_swarm_sense": true}
	var path: Dictionary = bp.detect_build_path("soft_predator", board)
	assert_eq(path.get("id", ""), "predator_swarm",
		"pr_farm → swarm path")

func test_detect_predator_evolution() -> void:
	var board := {"pr_nest": true, "pr_molt": true, "pr_harvest": true}
	var path: Dictionary = bp.detect_build_path("soft_predator", board)
	assert_eq(path.get("id", ""), "predator_evolution",
		"pr_molt + pr_harvest → evolution path")

func test_detect_military_elite() -> void:
	var board := {"ml_barracks": true, "ml_academy": true}
	var path: Dictionary = bp.detect_build_path("soft_military", board)
	assert_eq(path.get("id", ""), "military_elite",
		"ml_barracks → elite path")

func test_detect_military_mass() -> void:
	var board := {"ml_outpost": true, "ml_conscript": true}
	var path: Dictionary = bp.detect_build_path("soft_military", board)
	assert_eq(path.get("id", ""), "military_mass",
		"ml_outpost → mass path")

func test_detect_empty_board_returns_empty() -> void:
	var board := {}
	var path: Dictionary = bp.detect_build_path("soft_steampunk", board)
	assert_true(path.is_empty(), "빈 보드 → 빈 경로")

func test_detect_non_theme_strategy_returns_empty() -> void:
	var board := {"sp_assembly": true, "sp_furnace": true}
	var path: Dictionary = bp.detect_build_path("economy", board)
	assert_true(path.is_empty(), "economy 전략 → 빈 경로")

func test_detect_conflict_picks_stronger() -> void:
	# Both branch cards present, but sp_line is in spread's engine
	var board := {"sp_assembly": true, "sp_furnace": true, "sp_line": true}
	var path: Dictionary = bp.detect_build_path("soft_steampunk", board)
	assert_eq(path.get("id", ""), "steampunk_spread",
		"sp_assembly + sp_line(spread engine) > sp_furnace alone")


# ================================================================
# Score modifier tests
# ================================================================

func test_missing_engine_card_bonus() -> void:
	var board := {"sp_assembly": true, "sp_workshop": true}
	var path: Dictionary = bp.detect_build_path("soft_steampunk", board)
	# R6 = ENGINE phase. sp_circulator is in engine list, not on board.
	var mod: float = bp.score_card_modifier("sp_circulator", path, board, 6)
	assert_gt(mod, 15.0, "엔진 빈칸 카드 → 높은 보너스")

func test_owned_engine_card_no_gap_bonus() -> void:
	var board := {"sp_assembly": true, "sp_workshop": true, "sp_circulator": true}
	var path: Dictionary = bp.detect_build_path("soft_steampunk", board)
	# sp_circulator already on board → no "missing" bonus
	var mod: float = bp.score_card_modifier("sp_circulator", path, board, 6)
	assert_lt(mod, 15.0, "이미 보유한 엔진 카드 → 빈칸 보너스 ��음")

func test_anti_card_penalty() -> void:
	var board := {"sp_assembly": true, "sp_workshop": true}
	var path: Dictionary = bp.detect_build_path("soft_steampunk", board)
	# sp_furnace is anti for spread path
	var mod: float = bp.score_card_modifier("sp_furnace", path, board, 3)
	assert_lt(mod, 0.0, "anti 카드 → 음수 수정자")

func test_steampunk_branch_lock_anti_penalty_is_strong() -> void:
	var spread_board := {"sp_assembly": true, "sp_workshop": true}
	var spread_path: Dictionary = bp.detect_build_path("soft_steampunk", spread_board)
	var focus_starter_mod: float = bp.score_card_modifier(
		"sp_furnace", spread_path, spread_board, 3)
	assert_lte(focus_starter_mod, -36.0,
		"spread lock should strongly reject focus starter")

	var focus_board := {"sp_furnace": true, "sp_workshop": true}
	var focus_path: Dictionary = bp.detect_build_path("soft_steampunk", focus_board)
	var spread_starter_mod: float = bp.score_card_modifier(
		"sp_assembly", focus_path, focus_board, 3)
	assert_lte(spread_starter_mod, -36.0,
		"focus lock should strongly reject spread starter")

func test_druid_anti_card_penalty_remains_soft() -> void:
	var board := {"dr_cradle": true, "dr_deep": true}
	var path: Dictionary = bp.detect_build_path("soft_druid", board)
	var mod: float = bp.score_card_modifier("dr_origin", path, board, 3)
	assert_gt(mod, -20.0,
		"druid branch choice remains a soft preference")

func test_druid_branch_card_enables_soft_anti_penalty() -> void:
	var board := {"dr_cradle": true, "dr_deep": true}
	var path: Dictionary = bp.detect_build_path("soft_druid", board)
	assert_eq(path.get("id", ""), "druid_world_tree",
		"분기 카드 보유 시 세계수형 확정")

	var mod: float = bp.score_card_modifier("dr_origin", path, board, 5)

	assert_lt(mod, 0.0, "확정 후 정원형 anti 카드에는 소프트 페널티")

func test_strategy_modifier_seeds_druid_branch_before_detection() -> void:
	var board := {"dr_cradle": true, "dr_lifebeat": true}
	var path: Dictionary = bp.detect_build_path("soft_druid", board)
	assert_true(path.is_empty(), "기초 카드만으로는 드루이드 분기 확정 안 함")

	var origin_mod: float = bp.score_strategy_card_modifier(
		"dr_origin", "soft_druid", board, 6)
	var deep_mod: float = bp.score_strategy_card_modifier(
		"dr_deep", "soft_druid", board, 6)

	assert_gt(origin_mod, 20.0, "정원형 분기/엔진 카드를 cold-start에서 추구")
	assert_gt(deep_mod, 20.0, "세계수형 분기/엔진 카드도 cold-start에서 추구")

func test_strategy_modifier_does_not_apply_anti_before_detection() -> void:
	var board := {"dr_cradle": true, "dr_lifebeat": true}

	var origin_mod: float = bp.score_strategy_card_modifier(
		"dr_origin", "soft_druid", board, 6)

	assert_gte(origin_mod, 0.0, "분기 전에는 반대 경로 anti 페널티로 억누르지 않음")

func test_path_progress_reports_phase_completion() -> void:
	var board := {"dr_cradle": true, "dr_lifebeat": true, "dr_origin": true}
	var progress: Array = bp.get_path_progress("soft_druid", board, 5)

	assert_eq(progress.size(), 2, "드루이드 두 경로의 진행도를 보고")
	var garden := {}
	for row in progress:
		if row.get("id", "") == "druid_garden":
			garden = row
			break

	assert_false(garden.is_empty(), "정원형 진행도 존재")
	assert_eq(garden.get("current_phase", ""), "engine")
	assert_eq(garden.get("foundation_owned", 0), 2)
	assert_eq(garden.get("foundation_total", 0), 2)
	assert_eq(garden.get("engine_owned", 0), 1)
	assert_eq(garden.get("engine_total", 0), 3)

func test_current_phase_lag_reports_missing_payoff() -> void:
	var board := {
		"dr_cradle": true,
		"dr_lifebeat": true,
		"dr_origin": true,
		"dr_prune": true,
	}

	var lag: float = bp.get_current_phase_lag("soft_druid", board, 9)

	assert_almost_eq(lag, 1.0, 0.001, "R9 payoff phase에서 payoff 0/2 → lag 1.0")


func test_current_phase_lag_improves_with_payoff_card() -> void:
	var board := {
		"dr_cradle": true,
		"dr_lifebeat": true,
		"dr_origin": true,
		"dr_prune": true,
		"dr_spore_cloud": true,
	}

	var lag: float = bp.get_current_phase_lag("soft_druid", board, 9)

	assert_almost_eq(lag, 0.5, 0.001, "R9 payoff phase에서 payoff 1/2 → lag 0.5")


func test_phase_card_focus_reports_current_and_next_cards() -> void:
	var board := {
		"dr_cradle": true,
		"dr_lifebeat": true,
		"dr_origin": true,
		"dr_prune": true,
	}

	var focus: Dictionary = bp.get_phase_card_focus("soft_druid", board, 9)

	assert_eq(focus.get("path_id", ""), "druid_garden")
	assert_eq(focus.get("current_phase", ""), "payoff")
	assert_true("dr_spore_cloud" in focus.get("current", []),
		"R9 current phase should focus Druid payoff")
	assert_true("dr_wrath" in focus.get("focus", []),
		"next capstone card remains in focus")


func test_next_phase_prep_bonus() -> void:
	var board := {"sp_assembly": true, "sp_workshop": true}
	var path: Dictionary = bp.detect_build_path("soft_steampunk", board)
	# R3 = FOUNDATION. sp_circulator is ENGINE phase → next phase prep
	var mod: float = bp.score_card_modifier("sp_circulator", path, board, 3)
	assert_gt(mod, 5.0, "다음 페이즈 카드 → 선행 보너스")

func test_capstone_urgency() -> void:
	var board := {"sp_assembly": true, "sp_workshop": true,
		"sp_circulator": true, "sp_line": true}
	var path: Dictionary = bp.detect_build_path("soft_steampunk", board)
	# R11 = PAYOFF. sp_warmachine is capstone, not on board.
	var mod: float = bp.score_card_modifier("sp_warmachine", path, board, 11)
	assert_gt(mod, 20.0, "캡스톤 긴급 → 높은 보너스")

func test_shared_card_bonus() -> void:
	var board := {"sp_assembly": true, "sp_workshop": true}
	var path: Dictionary = bp.detect_build_path("soft_steampunk", board)
	var mod: float = bp.score_card_modifier("sp_interest", path, board, 5)
	assert_gt(mod, 0.0, "shared 카드 → 양수 보너스")

func test_completion_acceleration() -> void:
	# All foundation cards owned → engine card gets acceleration bonus
	var board := {"sp_assembly": true, "sp_workshop": true}
	var path: Dictionary = bp.detect_build_path("soft_steampunk", board)
	# R4 = still FOUNDATION, but all foundation cards owned → acceleration
	var mod: float = bp.score_card_modifier("sp_circulator", path, board, 4)
	# Should include both next-phase prep AND acceleration
	assert_gt(mod, 12.0, "페이즈 완성 + 다음 페이즈 카드 → 가속 보너스")

func test_unrelated_card_zero_modifier() -> void:
	var board := {"sp_assembly": true, "sp_workshop": true}
	var path: Dictionary = bp.detect_build_path("soft_steampunk", board)
	# A druid card on a steampunk path → no modifier from build path
	var mod: float = bp.score_card_modifier("dr_cradle", path, board, 5)
	assert_eq(mod, 0.0, "��관한 카드 → 수정자 0")


# ================================================================
# Card value modifier tests
# ================================================================

func test_engine_card_protected() -> void:
	var board := {"sp_assembly": true, "sp_workshop": true}
	var path: Dictionary = bp.detect_build_path("soft_steampunk", board)
	var mod: float = bp.card_value_modifier("sp_assembly", path, board, 5)
	assert_gt(mod, 10.0, "엔진 인프라 카드 → 판매 보호")

func test_anti_card_sell_encouraged() -> void:
	var board := {"sp_assembly": true, "sp_furnace": true}
	var path: Dictionary = bp.detect_build_path("soft_steampunk", board)
	var mod: float = bp.card_value_modifier("sp_furnace", path, board, 5)
	assert_lt(mod, 0.0, "anti 카드 → 판매 유도 (음수 가치)")


# ================================================================
# Data integrity
# ================================================================

func test_all_path_card_ids_exist_in_carddb() -> void:
	var all_ids: Array = bp.get_all_card_ids()
	for cid in all_ids:
		var tmpl := CardDB.get_template(cid)
		assert_false(tmpl.is_empty(),
			"CardDB에 '%s' 존재해야 함" % cid)
