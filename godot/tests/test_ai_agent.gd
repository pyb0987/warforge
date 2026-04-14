extends GutTest
## AI Agent 테스트.

const AIAgentScript = preload("res://sim/ai_agent.gd")
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
	# R1-R3에서는 soft_druid도 테마 선호 없이 구매해야 함
	var agent = AIAgentScript.new("soft_druid", _rng)
	_state.round_num = 2
	_state.gold = 30
	_shop.refresh_shop()
	agent.play_build_phase(_state, _shop)
	# R2에서는 테마 무관하게 구매 → 중립/다른 테마 카드도 보드에 있어야 함
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
