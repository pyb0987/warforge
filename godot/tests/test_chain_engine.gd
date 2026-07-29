extends GutTest
## ChainEngine BFS 성장 체인 테스트
## 참조: chain_engine.gd, handoff.md P3
##
## RS 발동 / 좌→우 순서 / BFS 연쇄 / 활성화 상한 / 안전 장치를 검증.


var _engine: ChainEngine = null


func before_each() -> void:
	_engine = ChainEngine.new()
	_engine.set_seed(42)


# ================================================================
# Helper
# ================================================================

func _make_board(ids: Array) -> Array:
	var board: Array = []
	for id in ids:
		board.append(CardInstance.create(id))
	return board


# ================================================================
# 기본 발동
# ================================================================

func test_round_start_fires_and_spawns() -> void:
	## sp_assembly(RS): spawn right_adj → 단독이면 자기 자신에겐 spawn 안 함
	## 단독 배치 시 right_adj 타겟 없음 → spawn 안 됨. 하지만 RS 카드라 chain_count += 1
	var board: Array = _make_board(["sp_assembly", "sp_assembly"])
	var units_before: int = (board[1] as CardInstance).get_total_units()
	_engine.run_growth_chain(board)
	# board[0]의 spawn("right_adj") → board[1]에 +1
	assert_gt((board[1] as CardInstance).get_total_units(), units_before, "right_adj spawn → 유닛 증가")


func test_chain_count_at_least_1() -> void:
	var board: Array = _make_board(["sp_assembly"])
	var result: Dictionary = _engine.run_growth_chain(board)
	assert_gte(result["chain_count"], 1, "RS 카드 1장 → chain_count >= 1")


func test_tenure_increments_after_run() -> void:
	var board: Array = _make_board(["sp_assembly"])
	_engine.run_growth_chain(board)
	assert_eq((board[0] as CardInstance).tenure, 1, "run 후 tenure=1")


func test_returns_required_keys() -> void:
	var board: Array = _make_board(["sp_assembly"])
	var result: Dictionary = _engine.run_growth_chain(board)
	assert_true(result.has("chain_count"), "chain_count 키")
	assert_true(result.has("gold_earned"), "gold_earned 키")
	assert_true(result.has("terazin_earned"), "terazin_earned 키")


# ================================================================
# 좌→우 순서
# ================================================================

func test_left_fires_before_right() -> void:
	## board=[sp_assembly, sp_furnace]
	## sp_assembly(idx0) spawn right_adj → board[1] 유닛 증가
	var board: Array = _make_board(["sp_assembly", "sp_furnace"])
	var furnace_before: int = (board[1] as CardInstance).get_total_units()
	_engine.run_growth_chain(board)
	assert_gt((board[1] as CardInstance).get_total_units(), furnace_before, "좌측 assembly가 우측 furnace에 spawn")


func test_rightmost_no_right_adj_spawn() -> void:
	## sp_assembly 단독 → right_adj 타겟 없음 → 자기 자신에는 spawn 안 됨
	var board: Array = _make_board(["sp_assembly"])
	var units_before: int = (board[0] as CardInstance).get_total_units()
	_engine.run_growth_chain(board)
	# sp_assembly의 spawn target은 "right_adj"이므로 단독 시 타겟 없음
	assert_eq((board[0] as CardInstance).get_total_units(), units_before, "단독 → right_adj 없어 유닛 불변")


# ================================================================
# BFS 연쇄
# ================================================================

func test_on_event_reacts_to_manufacture() -> void:
	## sp_assembly(RS) → MANUFACTURE 이벤트 → sp_workshop(OE) 반응 → enhance event_target
	## sp_assembly spawn right_adj → target_idx=1(workshop). workshop enhance event_target(idx=1)
	var board: Array = _make_board(["sp_assembly", "sp_workshop"])
	var workshop_atk_before: float = (board[1] as CardInstance).get_total_atk()
	var result: Dictionary = _engine.run_growth_chain(board)
	assert_gte(result["chain_count"], 2, "RS + OE 반응 = 최소 2 chain")
	# workshop이 자기 자신(event_target=1)에 enhance(gear, 0.05) → gear 유닛 ATK 증가
	assert_gt((board[1] as CardInstance).get_total_atk(), workshop_atk_before, "workshop ATK 증가")


func test_on_event_does_not_fire_without_event() -> void:
	## sp_workshop 단독 → OE 카드는 이벤트 없으면 반응 없음
	var board: Array = _make_board(["sp_workshop"])
	var result: Dictionary = _engine.run_growth_chain(board)
	assert_eq(result["chain_count"], 0, "OE 단독 → chain 0")


# ================================================================
# 활성화 상한
# ================================================================

func test_max_activations_2_respected() -> void:
	## sp_assembly×3 + sp_workshop → MANUFACTURE 이벤트 3개, workshop은 2번만
	var board: Array = _make_board(["sp_assembly", "sp_assembly", "sp_assembly", "sp_workshop"])
	_engine.run_growth_chain(board)
	assert_eq((board[3] as CardInstance).activations_used, 2, "max_act=2 → 2회만 반응")


func test_activations_reset_second_run() -> void:
	var board: Array = _make_board(["sp_assembly", "sp_workshop"])
	_engine.run_growth_chain(board)
	var used_after_first: int = (board[1] as CardInstance).activations_used
	assert_eq(used_after_first, 1, "1회 run: assembly 1개 → workshop 1회 반응")
	# 2회 run → reset_round() 먼저 호출 → activations_used=0에서 다시 시작
	_engine.run_growth_chain(board)
	assert_eq((board[1] as CardInstance).activations_used, 1, "2회차에도 정확히 1회 반응")


# ================================================================
# BS 카드는 chain_count 미포함
# ================================================================

func test_battle_start_card_not_counted_in_chain() -> void:
	## sp_barrier(BATTLE_START) → growth chain에서 발동 안 함
	var board: Array = _make_board(["sp_barrier"])
	var result: Dictionary = _engine.run_growth_chain(board)
	assert_eq(result["chain_count"], 0, "BS 카드 → chain 0")


func test_theme_system_routes_by_base_theme_after_transform() -> void:
	## ne_masquerade 등으로 theme이 바뀌어도 impl 소유권은 원본 카드 시스템에 남아야 함.
	var card: CardInstance = CardInstance.create("dr_cradle")
	card.template["theme"] = Enums.CardTheme.STEAMPUNK
	card.theme_state["trees"] = 5
	var atk_before: float = card.get_total_atk()
	_engine.process_battle_start([card])
	assert_almost_eq(card.get_total_atk(), atk_before * 1.25, 0.01,
		"변환된 dr_cradle도 DruidSystem BS 공통 보너스 적용")


func test_druid_spore_debuff_applies_to_enemy_attack_interval() -> void:
	var card: CardInstance = CardInstance.create("dr_spore_cloud")
	card.theme_state["trees"] = 5
	var board: Array = [card]
	_engine.process_battle_start(board)
	var enemies: Array = [{
		"atk": 10.0, "hp": 100.0, "attack_speed": 1.0,
		"range": 1, "move_speed": 1, "def": 0, "mechanics": [],
	}]

	var debuffs: Dictionary = _engine.apply_enemy_battle_debuffs(board, enemies)

	assert_almost_eq(debuffs["as_pct"], 0.225, 0.001,
		"★1 포자 구름 AS 디버프 수집")
	assert_almost_eq(float(enemies[0]["attack_speed"]), 1.0 / (1.0 - 0.225), 0.001,
		"AS 감소 → 적 공격 간격 증가")
	assert_almost_eq(float(enemies[0]["atk"]), 10.0, 0.001,
		"★1 포자 구름은 ATK 디버프 없음")


func test_druid_spore_star2_debuff_applies_to_enemy_atk_and_as() -> void:
	var card: CardInstance = CardInstance.create("dr_spore_cloud")
	card.evolve_star()
	card.theme_state["trees"] = 5
	var board: Array = [card]
	_engine.process_battle_start(board)
	var enemies: Array = [{
		"atk": 20.0, "hp": 100.0, "attack_speed": 2.0,
		"range": 1, "move_speed": 1, "def": 0, "mechanics": [],
	}]

	var debuffs: Dictionary = _engine.apply_enemy_battle_debuffs(board, enemies)

	assert_almost_eq(debuffs["atk_pct"], 0.3, 0.001,
		"★2 포자 구름 ATK 디버프 수집")
	assert_almost_eq(debuffs["as_pct"], 0.3, 0.001,
		"★2 포자 구름 AS 디버프 수집")
	assert_almost_eq(float(enemies[0]["atk"]), 14.0, 0.001,
		"ATK 감소 → 적 피해 감소")
	assert_almost_eq(float(enemies[0]["attack_speed"]), 2.0 / (1.0 - 0.3), 0.001,
		"AS 감소 → 적 공격 간격 증가")


func test_druid_grace_star3_post_combat_grants_pending_free_reroll() -> void:
	var grace: CardInstance = CardInstance.create("dr_grace")
	grace.evolve_star()
	grace.evolve_star()
	var granted := [0]
	_engine.pending_free_reroll_callback = func(n: int):
		granted[0] += n

	var result: Dictionary = _engine.process_post_combat([grace], true)

	assert_eq(result.get("free_rerolls", 0), 1, "★3 숲의 은혜 PC → free reroll 1")
	assert_eq(granted[0], 1, "post-combat free reroll callback fired")


# ================================================================
# 안전 장치
# ================================================================

func test_no_infinite_loop() -> void:
	var board: Array = _make_board(["sp_assembly", "sp_workshop"])
	var result: Dictionary = _engine.run_growth_chain(board)
	assert_lt(result["chain_count"], 200, "무한루프 방지")


# ================================================================
# 특수 케이스
# ================================================================

func test_empty_board_returns_zero_chain() -> void:
	var result: Dictionary = _engine.run_growth_chain([])
	assert_eq(result["chain_count"], 0, "빈 보드 → chain 0")


func test_single_on_event_card_no_fire() -> void:
	## ne_wanderers(OE) 단독 → 이벤트 없으므로 발동 안 함
	var board: Array = _make_board(["ne_wanderers"])
	var result: Dictionary = _engine.run_growth_chain(board)
	assert_eq(result["chain_count"], 0, "OE 단독 → chain 0")


# ================================================================
# require_other_card
# ================================================================

func test_sp_line_requires_other_card_for_manufacture() -> void:
	## sp_line (OE, require_other=true): 자신이 방출한 이벤트에는 자신이 반응 안 함
	## sp_line 단독 → OE 리스너이므로 RS에서 발동 안 함 → chain 0
	var board: Array = _make_board(["sp_line"])
	var result: Dictionary = _engine.run_growth_chain(board)
	assert_eq(result["chain_count"], 0, "sp_line 단독 → OE이므로 chain 0")


# ================================================================
# gold / terazin 반환
# ================================================================

func test_gold_earned_in_result() -> void:
	var board: Array = _make_board(["sp_assembly"])
	var result: Dictionary = _engine.run_growth_chain(board)
	assert_gte(result["gold_earned"], 0, "gold_earned >= 0")


func test_terazin_earned_in_result() -> void:
	var board: Array = _make_board(["sp_assembly"])
	var result: Dictionary = _engine.run_growth_chain(board)
	assert_gte(result["terazin_earned"], 0, "terazin_earned >= 0")
