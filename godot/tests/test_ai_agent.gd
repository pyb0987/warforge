extends GutTest
## AI Agent 테스트.

const AIAgentScript = preload("res://sim/ai_agent.gd")
const AITracerScript = preload("res://sim/ai_tracer.gd")
const ShopLogicScript = preload("res://sim/shop_logic.gd")

var _state: GameState = null
var _shop: RefCounted = null
var _rng: RandomNumberGenerator = null


func before_each() -> void:
	_state = GameState.new()
	_state.gold = 20
	_state.terazin = 5
	_state.shop_level = 1
	_state.round_num = 1
	_rng = RandomNumberGenerator.new()
	_rng.seed = 42
	_shop = ShopLogicScript.new()
	_shop.setup(_state, _rng)
	_shop.refresh_shop()


# ================================================================
# 전략 목록
# ================================================================

func test_strategy_names() -> void:
	var names: Array = AIAgentScript.STRATEGY_NAMES
	assert_eq(names.size(), 7, "7종 전략")
	assert_has(names, "soft_steampunk", "소프트 스팀펑크 전략 존재")
	assert_has(names, "soft_druid", "소프트 드루이드 전략 존재")
	assert_has(names, "soft_predator", "소프트 포식종 전략 존재")
	assert_has(names, "soft_military", "소프트 군대 전략 존재")
	assert_has(names, "adaptive", "적응형 전략 존재")
	assert_has(names, "economy", "경제 전략 존재")
	assert_has(names, "aggressive", "어그로 전략 존재")


# ================================================================
# 기본 동작
# ================================================================

func test_agent_creation() -> void:
	var agent = AIAgentScript.new("soft_steampunk", _rng)
	assert_not_null(agent, "에이전트 생성")


func test_trace_records_levelup_decision() -> void:
	var agent = AIAgentScript.new("soft_druid", _rng)
	var tracer = AITracerScript.new()
	tracer.enabled = true
	agent.set_tracer(tracer)
	_state.round_num = 3
	_state.shop_level = 1
	_state.levelup_current_cost = 5
	_state.gold = 20

	assert_true(agent._try_levelup(_state), "레벨업 성공")
	assert_eq(tracer.events.size(), 1, "레벨업 trace 1건")
	var ev: Dictionary = tracer.events[0]
	assert_eq(ev["t"], "levelup", "trace type")
	assert_eq(ev["round"], 3, "라운드 기록")
	assert_eq(ev["from_level"], 1, "이전 상점 레벨")
	assert_eq(ev["to_level"], 2, "이후 상점 레벨")
	assert_eq(ev["cost"], 5, "지불 비용")
	assert_eq(ev["gold_before"], 20, "지불 전 골드")
	assert_eq(ev["gold_after"], 15, "지불 후 골드")


func test_play_build_phase_spends_gold() -> void:
	var agent = AIAgentScript.new("aggressive", _rng)
	var gold_before: int = _state.gold
	agent.play_build_phase(_state, _shop)
	# aggressive는 가능한 한 많이 구매 → 골드 감소
	assert_lt(_state.gold, gold_before, "빌드 페이즈 후 골드 감소")


func test_play_build_phase_adds_cards() -> void:
	var agent = AIAgentScript.new("aggressive", _rng)
	var board_before: int = _state.board_count()
	var bench_count_before := 0
	for c in _state.bench:
		if c != null:
			bench_count_before += 1
	agent.play_build_phase(_state, _shop)
	var board_after: int = _state.board_count()
	var bench_count_after := 0
	for c in _state.bench:
		if c != null:
			bench_count_after += 1
	var total_before: int = board_before + bench_count_before
	var total_after: int = board_after + bench_count_after
	assert_gt(total_after, total_before, "카드 추가됨")


func test_agent_moves_bench_to_board() -> void:
	# 보드 비어있고 벤치에 카드 → 에이전트가 보드로 이동해야
	var agent = AIAgentScript.new("soft_steampunk", _rng)
	agent.play_build_phase(_state, _shop)
	assert_gt(_state.board_count(), 0, "보드에 카드 배치됨")


func test_agent_does_not_exceed_gold() -> void:
	var agent = AIAgentScript.new("economy", _rng)
	agent.play_build_phase(_state, _shop)
	assert_gte(_state.gold, 0, "골드가 음수가 되지 않음")


func test_sell_for_upgrade_does_not_sell_board_when_bench_full() -> void:
	var agent = AIAgentScript.new("soft_steampunk", _rng)
	_state.round_num = 11
	_state.field_slots = 6
	_state.board[0] = CardInstance.create("sp_global_workshop")
	for i in _state.bench.size():
		_state.bench[i] = CardInstance.create("pr_nest")

	var board_before := _state.board_count()
	var ok: bool = agent._sell_weakest_for_upgrade(_state, 999.0)

	assert_true(ok, "벤치 카드는 하나 팔 수 있어야 함")
	assert_eq(_state.board_count(), board_before, "구매 공간 확보는 보드를 팔지 않음")


func test_sell_for_upgrade_uses_bench_even_when_bench_cards_are_high_value() -> void:
	var agent = AIAgentScript.new("soft_steampunk", _rng)
	_state.round_num = 11
	_state.shop_level = 5
	_state.board[0] = CardInstance.create("sp_workshop")
	_state.board[1] = CardInstance.create("sp_circulator")
	for i in _state.bench.size():
		_state.bench[i] = CardInstance.create("sp_arsenal")

	var board_before := _state.board_count()
	var ok: bool = agent._sell_weakest_for_upgrade(_state, 999.0)

	assert_true(ok, "높은 점수 구매라면 고가치 벤치 카드도 공간 확보에 사용할 수 있음")
	assert_eq(_state.board_count(), board_before, "고가치 카드가 있어도 보드는 팔지 않음")


# ================================================================
# 테마 선호
# ================================================================

func test_steampunk_prefers_steampunk() -> void:
	_state.shop_level = 3  # T1-T3 접근
	_state.gold = 50
	_state.round_num = 5  # R5: soft-commit 활성
	_shop.refresh_shop()
	var agent = AIAgentScript.new("soft_steampunk", _rng)
	agent.play_build_phase(_state, _shop)
	# 보드+벤치에 스팀펑크 카드가 하나라도 있어야
	var has_steampunk := false
	for card in _state.board:
		if card != null:
			var tmpl: Dictionary = CardDB.get_template((card as CardInstance).get_base_id())
			if tmpl.get("theme", -1) == Enums.CardTheme.STEAMPUNK:
				has_steampunk = true
	for card in _state.bench:
		if card != null:
			var tmpl: Dictionary = CardDB.get_template((card as CardInstance).get_base_id())
			if tmpl.get("theme", -1) == Enums.CardTheme.STEAMPUNK:
				has_steampunk = true
	assert_true(has_steampunk, "소프트 스팀펑크 → R5+에서 스팀펑크 카드 존재")


# ================================================================
# 경제 전략
# ================================================================

func test_economy_buys_cards_first() -> void:
	_state.gold = 10
	_state.shop_level = 1  # levelup cost to lv2 = 5g
	var agent = AIAgentScript.new("economy", _rng)
	agent.play_build_phase(_state, _shop)
	# v3 economy: 카드 먼저 구매, 이자용 골드 보존
	var card_count := _state.board_count()
	for b in _state.bench:
		if b != null:
			card_count += 1
	assert_gte(card_count, 1, "경제 전략 → 카드 구매 우선")


# ================================================================
# 결정론
# ================================================================

func test_deterministic() -> void:
	var agent1 = AIAgentScript.new("adaptive", RandomNumberGenerator.new())
	agent1._rng.seed = 99
	var state1 := GameState.new()
	state1.gold = 20
	state1.shop_level = 1
	state1.round_num = 1
	var rng1 := RandomNumberGenerator.new()
	rng1.seed = 99
	var shop1 := ShopLogicScript.new()
	shop1.setup(state1, rng1)
	shop1.refresh_shop()
	agent1.play_build_phase(state1, shop1)
	var gold1: int = state1.gold
	var board1: int = state1.board_count()

	var agent2 = AIAgentScript.new("adaptive", RandomNumberGenerator.new())
	agent2._rng.seed = 99
	var state2 := GameState.new()
	state2.gold = 20
	state2.shop_level = 1
	state2.round_num = 1
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 99
	var shop2 := ShopLogicScript.new()
	shop2.setup(state2, rng2)
	shop2.refresh_shop()
	agent2.play_build_phase(state2, shop2)

	assert_eq(state2.gold, gold1, "같은 시드 → 같은 골드")
	assert_eq(state2.board_count(), board1, "같은 시드 → 같은 보드")


# ================================================================
# 소프트 커밋 동작
# ================================================================

func test_soft_theme_no_preference_before_r4() -> void:
	# R1-R3 soft_druid buys without a theme preference.
	var agent = AIAgentScript.new("soft_druid", _rng)
	_state.round_num = 2
	_state.gold = 30
	_shop.refresh_shop()
	agent.play_build_phase(_state, _shop)
	var total_cards := _state.board_count()
	for c in _state.bench:
		if c != null:
			total_cards += 1
	assert_gt(total_cards, 0, "R2에서도 카드 구매")


func test_soft_theme_commits_after_r4() -> void:
	# R5에서는 soft_steampunk가 스팀펑크를 선호해야 함
	var agent = AIAgentScript.new("soft_steampunk", _rng)
	_state.round_num = 5
	_state.shop_level = 3
	_state.gold = 50
	_shop.refresh_shop()
	agent.play_build_phase(_state, _shop)
	assert_gt(_state.board_count(), 0, "R5에서 카드 배치")


func test_adaptive_buys_cards() -> void:
	var agent = AIAgentScript.new("adaptive", _rng)
	_state.gold = 20
	agent.play_build_phase(_state, _shop)
	assert_gt(_state.board_count(), 0, "적응형 전략 카드 구매")


func test_ai_uses_effective_coin_price_for_affordability() -> void:
	var agent = AIAgentScript.new("adaptive", _rng)
	_state.gold = 2
	_state.talisman_type = Enums.TalismanType.TWO_FACED_COIN
	_shop.offered_ids.assign(["sp_assembly", "sp_assembly", "", "", "", ""])
	_shop._coin_slots = {"discount_idx": 2, "markup_idx": 0}

	var bought: bool = agent._try_buy_best(_state, _shop, -1)

	assert_true(bought, "할증으로 살 수 없는 1번 슬롯 대신 살 수 있는 2번 슬롯 구매")
	assert_eq(_shop.offered_ids[0], "sp_assembly", "할증 슬롯은 유지")
	assert_eq(_shop.offered_ids[1], "", "정상가 슬롯 구매")
	assert_eq(_state.gold, 0, "실제 가격 2골드 차감")


func test_transition_board_protects_druid_critical_infrastructure() -> void:
	var agent = AIAgentScript.new("soft_druid", _rng)
	_state.round_num = 8
	_state.field_slots = 6
	_state.board[0] = CardInstance.create("dr_lifebeat")
	_state.board[1] = CardInstance.create("ne_merchant")

	agent._transition_board(_state)

	assert_not_null(_state.board[0], "드루이드 핵심 기초 카드는 정리 대상 아님")
	assert_eq((_state.board[0] as CardInstance).get_base_id(), "dr_lifebeat")
	assert_null(_state.board[1], "약한 비핵심 카드는 정리 가능")


func test_theme_conversion_promotes_path_card_over_off_theme() -> void:
	var agent = AIAgentScript.new("soft_druid", _rng)
	_state.round_num = 7
	_state.field_slots = 6
	_state.board[0] = CardInstance.create("dr_cradle")
	_state.board[1] = CardInstance.create("dr_lifebeat")
	_state.board[2] = CardInstance.create("pr_farm")
	_state.board[3] = CardInstance.create("sp_workshop")
	_state.board[4] = CardInstance.create("ne_earth_echo")
	_state.board[5] = CardInstance.create("ne_ruins")
	_state.bench[0] = CardInstance.create("dr_origin")

	agent._promote_committed_theme_bench(_state)

	assert_null(_state.bench[0], "드루이드 경로 카드가 벤치에 남지 않음")
	assert_true(_has_board_card("dr_origin"), "드루이드 경로 카드를 활성 보드로 승격")
	assert_false(_has_board_card("pr_farm"), "약한 오프테마 카드를 우선 교체")


func test_theme_conversion_keeps_neutral_glue_before_late_game() -> void:
	var agent = AIAgentScript.new("soft_predator", _rng)
	_state.round_num = 7
	_state.field_slots = 6
	_state.board[0] = CardInstance.create("pr_farm")
	_state.board[1] = CardInstance.create("pr_swarm_sense")
	_state.board[2] = CardInstance.create("ne_earth_echo")
	_state.board[3] = CardInstance.create("ne_wild_pulse")
	_state.board[4] = CardInstance.create("ne_pawnbroker")
	_state.board[5] = CardInstance.create("ne_ruins")
	_state.bench[0] = CardInstance.create("pr_nest")

	agent._promote_committed_theme_bench(_state)

	assert_not_null(_state.bench[0], "R7에는 중립 글루만 남은 보드를 억지 교체하지 않음")
	assert_true(_has_board_card("ne_earth_echo"), "중립 체인 기반은 보존")


func test_druid_path_lag_relaxes_interest_reserve() -> void:
	var agent = AIAgentScript.new("soft_druid", _rng)
	_state.round_num = 9
	_state.board[0] = CardInstance.create("dr_cradle")
	_state.board[1] = CardInstance.create("dr_lifebeat")
	_state.board[2] = CardInstance.create("dr_origin")
	_state.board[3] = CardInstance.create("dr_prune")
	var board_ids := {
		"dr_cradle": true,
		"dr_lifebeat": true,
		"dr_origin": true,
		"dr_prune": true,
	}

	var result: Dictionary = agent._apply_path_phase_urgency(_state, board_ids, 5, 10)

	assert_gt(result["max_rerolls"], 5, "payoff lag가 크면 추가 리롤 예산 확보")
	assert_eq(result["gold_reserve"], 3, "R9 payoff lag에서는 이자 보존보다 경로 추구 우선")
	assert_gte(result["phase_lag"], 0.5, "경로 lag 진단값 포함")


func test_steampunk_path_lag_caps_pre_payoff_reroll_urgency() -> void:
	var agent = AIAgentScript.new("soft_steampunk", _rng)
	var board_ids := {
		"sp_furnace": true,
		"sp_workshop": true,
	}

	_state.round_num = 9
	_state.shop_level = 3
	var before_lv4: Dictionary = agent._apply_path_phase_urgency(
		_state, board_ids, 5, 10)

	assert_eq(before_lv4["max_rerolls"], 7, "T4 접근 전에는 저티어 리롤 추격을 제한")
	assert_eq(before_lv4["gold_reserve"], 10, "T4 접근 전에는 이자 보존을 완화하지 않음")
	assert_gte(before_lv4["phase_lag"], 0.5, "lag는 기록하되 행동 보너스는 제한")

	_state.round_num = 8
	_state.shop_level = 4
	var before_payoff_round: Dictionary = agent._apply_path_phase_urgency(
		_state, board_ids, 5, 10)

	assert_eq(before_payoff_round["max_rerolls"], 7, "R9 payoff 창 전에는 리롤 보너스 제한")
	assert_eq(before_payoff_round["gold_reserve"], 10, "R9 전에는 reserve 완화 없음")


func test_steampunk_path_lag_applies_at_lv4_payoff_window() -> void:
	var agent = AIAgentScript.new("soft_steampunk", _rng)
	_state.round_num = 9
	_state.shop_level = 4
	var board_ids := {
		"sp_furnace": true,
		"sp_workshop": true,
	}

	var result: Dictionary = agent._apply_path_phase_urgency(_state, board_ids, 5, 10)

	assert_gt(result["max_rerolls"], 5, "T4 payoff 창에서는 경로 lag 리롤 보너스 적용")
	assert_eq(result["gold_reserve"], 3, "T4 payoff 창에서는 reserve 완화 적용")
	assert_gte(result["phase_lag"], 0.5, "경로 lag 진단값 포함")


func test_druid_path_lag_forces_scheduled_level_access() -> void:
	var agent = AIAgentScript.new("soft_druid", _rng)
	_state.round_num = 9
	_state.shop_level = 2
	_state.levelup_current_cost = 7
	var board_ids := {
		"dr_cradle": true,
		"dr_lifebeat": true,
		"dr_origin": true,
		"dr_prune": true,
	}
	var phase_lag: float = agent._build_path.get_current_phase_lag(
		"soft_druid", board_ids, _state.round_num)

	assert_true(agent._should_force_path_tier_access(_state, 5, phase_lag),
		"R9 payoff lag should override Druid slow-roll and pursue scheduled tiers")


func test_druid_path_lag_dampens_low_tier_duplicate_merges() -> void:
	var agent = AIAgentScript.new("soft_druid", _rng)
	_state.round_num = 9
	_state.board[0] = CardInstance.create("dr_cradle")
	_state.board[1] = CardInstance.create("dr_lifebeat")
	_state.board[2] = CardInstance.create("dr_origin")
	_state.board[3] = CardInstance.create("dr_prune")
	_state.bench[0] = CardInstance.create("dr_cradle")
	var board_ids := {
		"dr_cradle": true,
		"dr_lifebeat": true,
		"dr_origin": true,
		"dr_prune": true,
	}

	assert_true(agent._should_dampen_path_lag_duplicate(_state, "dr_cradle", 1, board_ids),
		"missing payoff should damp extra low-tier duplicate merges")
	assert_false(agent._should_dampen_path_lag_duplicate(_state, "dr_spore_cloud", 3, board_ids),
		"current payoff card should not be damped")


func test_druid_path_lag_holds_non_priority_purchase() -> void:
	var agent = AIAgentScript.new("soft_druid", _rng)
	_state.round_num = 9
	var board_ids := {
		"dr_cradle": true,
		"dr_lifebeat": true,
		"dr_origin": true,
		"dr_prune": true,
	}

	assert_true(agent._should_hold_for_path_lag_purchase(
		_state, "ne_council", CardDB.get_template("ne_council"), board_ids),
		"payoff lag should save gold instead of buying neutral filler")
	assert_true(agent._should_hold_for_path_lag_purchase(
		_state, "dr_grace", CardDB.get_template("dr_grace"), board_ids),
		"non-priority Druid cards should not distract from missing payoff")


func test_druid_path_lag_allows_priority_purchase() -> void:
	var agent = AIAgentScript.new("soft_druid", _rng)
	_state.round_num = 9
	var board_ids := {
		"dr_cradle": true,
		"dr_lifebeat": true,
		"dr_origin": true,
		"dr_prune": true,
	}

	assert_false(agent._should_hold_for_path_lag_purchase(
		_state, "dr_spore_cloud", CardDB.get_template("dr_spore_cloud"), board_ids),
		"current payoff remains buyable")
	assert_false(agent._should_hold_for_path_lag_purchase(
		_state, "dr_wt_root", CardDB.get_template("dr_wt_root"), board_ids),
		"missing critical infrastructure remains buyable")


func test_druid_path_focus_prevents_payoff_swap_out() -> void:
	var agent = AIAgentScript.new("soft_druid", _rng)
	_state.round_num = 10
	_state.board[0] = CardInstance.create("dr_cradle")
	_state.board[1] = CardInstance.create("dr_lifebeat")
	_state.board[2] = CardInstance.create("dr_deep")
	var outgoing := CardInstance.create("dr_spore_cloud")
	var incoming := CardInstance.create("dr_wt_root")
	_state.board[3] = outgoing
	_state.bench[0] = incoming

	assert_true(agent._should_skip_path_focus_swap(_state, outgoing, incoming),
		"current payoff should stay active instead of being replaced by non-focus engine")


func test_druid_path_focus_allows_duplicate_payoff_swap() -> void:
	var agent = AIAgentScript.new("soft_druid", _rng)
	_state.round_num = 10
	_state.field_slots = 5
	_state.board[0] = CardInstance.create("dr_cradle")
	_state.board[1] = CardInstance.create("dr_lifebeat")
	_state.board[2] = CardInstance.create("dr_deep")
	_state.board[3] = CardInstance.create("dr_wrath")
	var outgoing := CardInstance.create("dr_wrath")
	var incoming := CardInstance.create("dr_wt_root")
	_state.board[4] = outgoing
	_state.bench[0] = incoming

	assert_false(agent._should_skip_path_focus_swap(_state, outgoing, incoming),
		"extra payoff copy can be replaced by a useful Druid engine card")


func test_promote_bench_executes_board_eval_swap() -> void:
	var agent = AIAgentScript.new("soft_steampunk", _rng)
	_state.round_num = 10
	_state.field_slots = 1
	_state.board[0] = CardInstance.create("ne_ruins")
	_state.bench[0] = CardInstance.create("sp_charger")

	agent._promote_bench(_state)

	assert_true(_has_board_card("sp_charger"), "strong bench card should replace weak board card")
	assert_null(_state.bench[0], "promoted card leaves bench")


func test_non_druid_strategy_still_executes_generic_swap() -> void:
	var agent = AIAgentScript.new("soft_predator", _rng)
	_state.round_num = 2
	_state.field_slots = 1
	_state.board[0] = CardInstance.create("dr_lifebeat")
	_state.bench[0] = CardInstance.create("ne_wild_pulse")

	agent._promote_bench(_state)

	assert_true(_has_board_card("ne_wild_pulse"), "non-Druid strategies keep generic swaps")


func test_druid_identity_guard_blocks_moderate_non_druid_swap() -> void:
	var agent = AIAgentScript.new("soft_druid", _rng)
	_state.round_num = 3
	_state.field_slots = 2
	_state.board[0] = CardInstance.create("dr_cradle")
	_state.board[1] = CardInstance.create("dr_lifebeat")
	var outgoing := _state.board[1] as CardInstance
	var incoming := CardInstance.create("ne_merchant")

	assert_true(agent._should_skip_druid_identity_swap(_state, outgoing, incoming),
		"early Druid identity should not be erased by a moderate generic swap")


func test_druid_identity_guard_allows_extra_represented_foundation() -> void:
	var agent = AIAgentScript.new("soft_druid", _rng)
	_state.round_num = 3
	_state.field_slots = 3
	_state.board[0] = CardInstance.create("dr_cradle")
	_state.board[1] = CardInstance.create("dr_lifebeat")
	_state.board[2] = CardInstance.create("dr_lifebeat")
	var outgoing := _state.board[1] as CardInstance
	var incoming := CardInstance.create("ne_merchant")

	assert_false(agent._should_skip_druid_identity_swap(_state, outgoing, incoming),
		"extra active copy is not protected by identity guard")


func test_druid_identity_guard_protects_current_engine_focus() -> void:
	var agent = AIAgentScript.new("soft_druid", _rng)
	_state.round_num = 8
	_state.field_slots = 4
	_state.board[0] = CardInstance.create("dr_cradle")
	_state.board[1] = CardInstance.create("dr_lifebeat")
	_state.board[2] = CardInstance.create("dr_origin")
	_state.board[3] = CardInstance.create("ne_earth_echo")
	var outgoing := _state.board[2] as CardInstance
	var incoming := CardInstance.create("ne_merchant")

	assert_true(agent._should_skip_druid_identity_swap(_state, outgoing, incoming),
		"current Druid engine focus should stay active through setup window")


func test_druid_path_focus_promotes_current_payoff_from_bench() -> void:
	var agent = AIAgentScript.new("soft_druid", _rng)
	_state.round_num = 9
	_state.field_slots = 6
	_state.board[0] = CardInstance.create("dr_cradle")
	_state.board[1] = CardInstance.create("dr_lifebeat")
	_state.board[2] = CardInstance.create("dr_origin")
	_state.board[3] = CardInstance.create("dr_prune")
	_state.board[4] = CardInstance.create("ne_earth_echo")
	_state.board[5] = CardInstance.create("pr_farm")
	_state.bench[0] = CardInstance.create("dr_spore_cloud")

	agent._promote_path_focus_bench(_state)

	assert_null(_state.bench[0], "current Druid payoff should leave bench")
	assert_true(_has_board_card("dr_spore_cloud"), "current Druid payoff should become active")
	assert_false(_has_board_card("pr_farm"), "off-theme filler is preferred replacement")


func test_druid_path_focus_ignores_cards_outside_field_slots() -> void:
	var agent = AIAgentScript.new("soft_druid", _rng)
	_state.round_num = 9
	_state.field_slots = 4
	_state.board[0] = CardInstance.create("dr_cradle")
	_state.board[1] = CardInstance.create("dr_lifebeat")
	_state.board[2] = CardInstance.create("dr_origin")
	_state.board[3] = CardInstance.create("pr_farm")
	_state.board[4] = CardInstance.create("dr_spore_cloud")
	_state.bench[0] = CardInstance.create("dr_spore_cloud")

	agent._promote_path_focus_bench(_state)

	assert_null(_state.bench[0], "bench payoff should be promoted when only inactive copy exists")
	assert_true(_has_active_board_card("dr_spore_cloud"), "payoff should be inside usable field slots")


func test_druid_path_focus_promotes_payoff_over_engine_body() -> void:
	var agent = AIAgentScript.new("soft_druid", _rng)
	_state.round_num = 9
	_state.field_slots = 4
	_state.board[0] = CardInstance.create("dr_cradle")
	_state.board[1] = CardInstance.create("dr_lifebeat")
	_state.board[2] = CardInstance.create("dr_origin")
	_state.board[3] = CardInstance.create("dr_wt_root")
	_state.bench[0] = CardInstance.create("dr_spore_cloud")

	agent._promote_path_focus_bench(_state)

	assert_true(_has_board_card("dr_spore_cloud"),
		"payoff phase should activate a missing payoff even over a valuable Druid body")
	assert_null(_state.bench[0], "payoff card leaves bench")


func test_druid_grace_is_not_late_power_sentinel() -> void:
	var agent = AIAgentScript.new("soft_druid", _rng)
	var capstone_cards: Array = agent._STRATEGY_CONFIG["soft_druid"]["capstone_cards"]

	assert_false("dr_grace" in capstone_cards, "은혜는 경제 카드이지 late-power 충족 조건 아님")
	assert_true("dr_wrath" in capstone_cards, "태고의 분노는 드루이드 late-power 추구 대상")
	assert_true("dr_world" in capstone_cards, "세계수는 드루이드 late-power 추구 대상")
	assert_false("dr_wt_root" in capstone_cards, "뿌리는 엔진 카드이지 late-power 충족 조건 아님")


func test_druid_core_cards_use_shared_payoffs_not_branch_infrastructure() -> void:
	var agent = AIAgentScript.new("soft_druid", _rng)
	var core_cards: Array = agent._STRATEGY_CONFIG["soft_druid"]["core_cards"]

	assert_has(core_cards, "dr_grace", "공유 전환 카드 우선")
	assert_has(core_cards, "dr_spore_cloud", "공유 payoff 카드 우선")
	assert_has(core_cards, "dr_wrath", "공유/정원형 payoff 카드 우선")
	assert_false("dr_deep" in core_cards, "세계수 분기 카드에 전역 core 보너스 금지")
	assert_false("dr_wt_root" in core_cards, "세계수 엔진 카드에 전역 core 보너스 금지")
	assert_false("dr_world" in core_cards, "T5 세계수를 전역 core 보너스로 강제하지 않음")


func test_druid_garden_scores_shared_payoff_above_world_tree_anti_core() -> void:
	var agent = AIAgentScript.new("soft_druid", _rng)
	_state.round_num = 9
	_state.shop_level = 4
	_state.board[0] = CardInstance.create("dr_cradle")
	_state.board[1] = CardInstance.create("dr_lifebeat")
	_state.board[2] = CardInstance.create("dr_origin")
	_state.board[3] = CardInstance.create("dr_prune")

	var spore_score: float = agent._score_card(
		"dr_spore_cloud", CardDB.get_template("dr_spore_cloud"),
		Enums.CardTheme.DRUID, _state)
	var root_score: float = agent._score_card(
		"dr_wt_root", CardDB.get_template("dr_wt_root"),
		Enums.CardTheme.DRUID, _state)

	assert_gt(spore_score, root_score,
		"정원형 확정 후에는 공유 payoff가 세계수 anti 엔진보다 우선되어야 함")


func test_trace_theme_metrics_counts_commitment() -> void:
	var agent = AIAgentScript.new("soft_druid", _rng)
	_state.board[0] = CardInstance.create("dr_cradle")
	_state.board[1] = CardInstance.create("ne_earth_echo")
	_state.board[2] = CardInstance.create("sp_workshop")
	_state.bench[0] = CardInstance.create("dr_lifebeat")

	var metrics: Dictionary = agent._trace_theme_metrics(_state, Enums.CardTheme.DRUID)

	assert_eq(metrics["preferred_theme_name"], "druid")
	assert_eq(metrics["board_total"], 3)
	assert_eq(metrics["board_theme"], 1)
	assert_eq(metrics["board_neutral"], 1)
	assert_eq(metrics["board_off_theme"], 1)
	assert_almost_eq(metrics["board_theme_ratio"], 1.0 / 3.0, 0.001)
	assert_eq(metrics["bench_theme"], 1)


func _has_board_card(card_id: String) -> bool:
	for card in _state.board:
		if card != null and (card as CardInstance).get_base_id() == card_id:
			return true
	return false


func _has_active_board_card(card_id: String) -> bool:
	for i in _state.field_slots:
		if i >= _state.board.size():
			break
		var card = _state.board[i]
		if card != null and (card as CardInstance).get_base_id() == card_id:
			return true
	return false
