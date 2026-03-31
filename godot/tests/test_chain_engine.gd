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
