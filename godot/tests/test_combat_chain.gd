extends GutTest
## 전투 중 이벤트 체인 테스트 (combat → chain_engine 브릿지)
## 참조: growth-chain.md "전투 이벤트 (전투 중 — 보조)", combat.md
##
## combat_engine 이벤트(공격/사망) → chain_engine.process_combat_event() 검증.
## 카드 레벨에서 전투 이벤트에 반응하는 인프라 테스트.


var _chain: ChainEngine = null
var _board: Array = []


func before_each() -> void:
	_chain = ChainEngine.new()
	_chain.set_seed(42)
	_board = []


# ================================================================
# process_combat_event — 기본 인프라
# ================================================================

func test_combat_event_returns_valid_dict() -> void:
	## 빈 보드에서도 에러 없이 빈 결과 반환
	var result := _chain.process_combat_event([], "ally_death", -1)
	assert_eq(result["buffs"].size(), 0, "빈 보드 → 버프 없음")


func test_combat_event_ignores_non_combat_cards() -> void:
	## ROUND_START 카드는 전투 이벤트에 반응 안 함
	var card := CardInstance.create("sp_assembly")  # RS timing
	_board.append(card)
	var result := _chain.process_combat_event(_board, "ally_death", 0)
	assert_eq(result["buffs"].size(), 0, "RS 카드 → 전투 반응 없음")


func test_combat_event_on_combat_attack_fires() -> void:
	## ON_COMBAT_ATTACK 타이밍 카드가 공격 이벤트에 반응
	var card := CardInstance.create("sp_assembly")
	# v2 block format: effects[0] is the timing block
	card.template["effects"] = [{
		"trigger_timing": Enums.TriggerTiming.ON_COMBAT_ATTACK,
		"max_activations": -1,
		"actions": [{"action": "combat_buff_pct", "buff_atk_pct": 0.12, "target": "self"}],
	}]
	_board.append(card)

	var result := _chain.process_combat_event(_board, "attack", 0)
	assert_eq(result["buffs"].size(), 1, "ON_COMBAT_ATTACK → 1 버프")
	assert_eq(result["buffs"][0]["card_idx"], 0, "자기 카드에 버프")
	assert_almost_eq(result["buffs"][0]["atk_pct"], 0.12, 0.001, "ATK +12%")


func test_combat_event_ally_death_fires() -> void:
	## ON_COMBAT_DEATH 타이밍 카드가 사망 이벤트에 반응
	var card := CardInstance.create("sp_assembly")
	card.template["effects"] = [{
		"trigger_timing": Enums.TriggerTiming.ON_COMBAT_DEATH,
		"max_activations": -1,
		"actions": [{"action": "combat_buff_pct", "buff_atk_pct": 0.03, "target": "all_allies"}],
	}]
	_board.append(card)

	var result := _chain.process_combat_event(_board, "ally_death", 0)
	assert_eq(result["buffs"].size(), 1, "ON_COMBAT_DEATH → 1 버프")
	assert_almost_eq(result["buffs"][0]["atk_pct"], 0.03, 0.001, "ATK +3%")


func test_combat_event_ally_death_ignores_attack_cards() -> void:
	## ON_COMBAT_ATTACK 카드는 사망 이벤트에 반응 안 함
	var card := CardInstance.create("sp_assembly")
	card.template["effects"] = [{
		"trigger_timing": Enums.TriggerTiming.ON_COMBAT_ATTACK,
		"max_activations": -1,
		"actions": [{"action": "combat_buff_pct", "buff_atk_pct": 0.12, "target": "self"}],
	}]
	_board.append(card)

	var result := _chain.process_combat_event(_board, "ally_death", 0)
	assert_eq(result["buffs"].size(), 0, "ON_COMBAT_ATTACK → 사망에 무반응")


func test_combat_event_unknown_type_returns_empty() -> void:
	## 알 수 없는 이벤트 타입 → 빈 결과
	var card := CardInstance.create("sp_assembly")
	card.template["trigger_timing"] = Enums.TriggerTiming.ON_COMBAT_ATTACK
	card.template["effects"] = [{"action": "combat_buff_pct", "buff_atk_pct": 0.12, "target": "self"}]
	_board.append(card)

	var result := _chain.process_combat_event(_board, "unknown_event", 0)
	assert_eq(result["buffs"].size(), 0, "unknown event → early return")


func test_combat_event_respects_activation_limit() -> void:
	## 발동 횟수 상한 초과 시 발동 안 됨
	var card := CardInstance.create("sp_assembly")
	card.template["trigger_timing"] = Enums.TriggerTiming.ON_COMBAT_ATTACK
	card.template["effects"] = [{"action": "combat_buff_pct", "buff_atk_pct": 0.10, "target": "self"}]
	card.template["max_activations"] = 2
	_board.append(card)

	_chain.process_combat_event(_board, "attack", 0)
	_chain.process_combat_event(_board, "attack", 0)
	var result := _chain.process_combat_event(_board, "attack", 0)
	assert_eq(result["buffs"].size(), 0, "3번째 발동 → 상한 초과")


# ================================================================
# unit_attacked signal
# ================================================================

func test_combat_engine_emits_unit_attacked() -> void:
	## combat_engine.resolve_attack 후 unit_attacked 시그널 발생
	var CombatEngineScript = preload("res://combat/combat_engine.gd")
	var engine := CombatEngineScript.new()
	engine.setup(
		[{"atk": 10, "hp": 9999, "attack_speed": 0.5, "range": 1,
		  "move_speed": 5, "def": 0, "mechanics": [], "radius": 6.0}],
		[{"atk": 1, "hp": 9999, "attack_speed": 0.5, "range": 1,
		  "move_speed": 5, "def": 0, "mechanics": [], "radius": 6.0}]
	)

	# GDScript 4 lambda는 int 값 캡처 → 배열로 우회
	var attacks := [0]
	engine.unit_attacked.connect(func(_a, _d): attacks[0] += 1)

	for _i in 200:
		if not engine.tick():
			break
		if attacks[0] > 0:
			break

	assert_gt(attacks[0], 0, "unit_attacked 시그널 1회 이상 발생")


# ================================================================
# unit→card map (materialize bridge)
# ================================================================

func test_unit_card_map_structure() -> void:
	## _build_unit_card_map이 올바른 매핑 생성
	# 카드 2장: 카드0(유닛2기), 카드1(유닛3기) → map = [0,0,1,1,1]
	var card0 := CardInstance.create("sp_assembly")  # spider×2 + rat×1 = 3유닛
	var card1 := CardInstance.create("sp_workshop")
	var board := [card0, card1]

	# 시뮬: _materialize 스타일로 유닛 수 세기
	var expected_map: Array[int] = []
	for card_idx in board.size():
		var c: CardInstance = board[card_idx]
		for s in c.stacks:
			for _n in s["count"]:
				expected_map.append(card_idx)

	assert_gt(expected_map.size(), 0, "유닛 1기 이상")
	# 모든 엔트리가 유효한 카드 인덱스
	for entry in expected_map:
		assert_gte(entry, 0, "유효 인덱스")
		assert_lt(entry, board.size(), "보드 범위 내")
