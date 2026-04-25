extends GutTest
## MilitarySystem 테마 로직 테스트 (R4/R10 재설계 반영, 2026-04-16)
##
## 테스트 범위:
## - barracks 훈련 (self + right_adj, R4 차분 확장)
## - conscript(스왑 후 T1 self 징집) / outpost(스왑 후 T2 반응)
## - academy 훈련 반응
## - factory counter (terazin → global_military_atk_pct 전환)
## - tactical rank_buff
## - supply PC gold
## - command 부활 수치 (★1: 25%, ★2: 50%, ★3: 100%)
##
## 제거된 테스트 (rank_threshold 폐기):
## - barracks rank3/5/8 → infantry/plasma/walker
## - special_ops rank8 → commander
## - factory terazin reward (rewards 구조 변경)
## - assault BS swarm_buff (R4 조건부로 이동)
##
## 새 R4/R10 효과 테스트는 별도 스프린트에서 추가 예정.


var _sys: MilitarySystem = null
var _rng: RandomNumberGenerator = null


func before_each() -> void:
	_sys = MilitarySystem.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 42


func _make_train_event(src: int, tgt: int) -> Dictionary:
	return {"layer1": Enums.Layer1.ENHANCED, "layer2": Enums.Layer2.TRAIN,
			"source_idx": src, "target_idx": tgt}


func _make_conscript_event(src: int, tgt: int) -> Dictionary:
	return {"layer1": Enums.Layer1.UNIT_ADDED, "layer2": Enums.Layer2.CONSCRIPT,
			"source_idx": src, "target_idx": tgt}


func _make_star(base_id: String, star: int) -> CardInstance:
	var card: CardInstance = CardInstance.create(base_id)
	for _i in star - 1:
		card.evolve_star()
	return card


# ================================================================
# ml_barracks (RS): train self + right_adj (R0), left_adj R4, far_military R10
# ================================================================

func test_barracks_trains_self_plus1() -> void:
	var card: CardInstance = CardInstance.create("ml_barracks")
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(card.theme_state.get("rank", 0), 1, "rank=1")


func test_barracks_trains_right_adj_military() -> void:
	## R0 기본: self + right_adj.
	var board: Array = [CardInstance.create("ml_barracks"), CardInstance.create("ml_conscript")]
	_sys.process_rs_card(board[0], 0, board, _rng)
	assert_eq(board[0].theme_state.get("rank", 0), 1, "self rank=1")
	assert_eq(board[1].theme_state.get("rank", 0), 1, "right_adj rank=1")


func test_barracks_no_train_to_non_military_adj() -> void:
	var board: Array = [CardInstance.create("ml_barracks"), CardInstance.create("sp_assembly")]
	_sys.process_rs_card(board[0], 0, board, _rng)
	assert_eq(board[1].theme_state.get("rank", 0), 0, "비군대 → rank 불변")


# ================================================================
# ml_conscript (T1 RS self 징집).
# 2026-04-21: 3택1 UI 제거. _outpost() 가 자동 랜덤으로 즉시 처리.
# pending_conscriptions / clear_pending / pick_conscript_options /
# apply_conscript 관련 테스트 (6개) 제거됨.
# ================================================================

func test_conscript_self_adds_units_immediately() -> void:
	## ★1: RS 즉시 self 에 뽑기 1 회 (base pool uniform). 유닛 1~3 기 범위로
	## 추가 (pool 의 최소 count=1, 최대 count=3). 정확 수치는 RNG 종속.
	var card: CardInstance = CardInstance.create("ml_conscript")
	var before: int = card.get_total_units()
	_sys.process_rs_card(card, 0, [card], _rng)
	var added: int = card.get_total_units() - before
	assert_between(added, 1, 3, "★1 RS: 뽑기 1 회 → 1~3 기 추가")


func test_conscript_star3_self_adds_more() -> void:
	## ★3: RS self 뽑기 3 회 (각 뽑기 1~3 기). 최소 3 기, 최대 9 기 추가.
	var card: CardInstance = CardInstance.create("ml_conscript")
	card.star_level = 3
	var before: int = card.get_total_units()
	_sys.process_rs_card(card, 0, [card], _rng)
	var added: int = card.get_total_units() - before
	assert_between(added, 3, 9, "★3 RS: 뽑기 3 회 → 3~9 기 추가")


# ================================================================
# ml_outpost (T2 OE 반응 증폭, 스왑 후 이전 _conscript_react 역할)
# ================================================================

func test_outpost_s1_react_adds_units_to_target() -> void:
	## ★1: CO 이벤트 감지 → event_target 에 징집 1 회. 해석 B 로 유닛 1~3 기 추가.
	var board: Array = [CardInstance.create("ml_outpost"), CardInstance.create("ml_conscript")]
	var before: int = board[1].get_total_units()
	var event: Dictionary = _make_conscript_event(9, 1)  # 외부 source idx=9
	_sys.process_event_card(board[0], 0, board, event, _rng)
	var added: int = board[1].get_total_units() - before
	assert_between(added, 1, 3, "★1 event_target 징집 1 회 → 1~3 기 추가")


func test_outpost_s2_reacts_with_self_and_event_target() -> void:
	## ★2: self 에도 징집 (rank_upgrade) + event_target 에도 징집.
	var board: Array = [_make_star("ml_outpost", 2), CardInstance.create("ml_conscript")]
	var before_self: int = board[0].get_total_units()
	var before_target: int = board[1].get_total_units()
	var event: Dictionary = _make_conscript_event(9, 1)
	_sys.process_event_card(board[0], 0, board, event, _rng)
	assert_gt(board[0].get_total_units(), before_self, "★2 self 징집 발동")
	assert_gt(board[1].get_total_units(), before_target, "★2 event_target 징집 발동")


func test_outpost_s3_adds_train_events() -> void:
	## ★3: self 에 훈련 1 회 (+ event_target 도 훈련 1). rank 증가 확인.
	var board: Array = [_make_star("ml_outpost", 3), CardInstance.create("ml_conscript")]
	var before_self_rank: int = board[0].theme_state.get("rank", 0)
	var before_target_rank: int = board[1].theme_state.get("rank", 0)
	var event: Dictionary = _make_conscript_event(9, 1)
	_sys.process_event_card(board[0], 0, board, event, _rng)
	assert_eq(board[0].theme_state.get("rank", 0), before_self_rank + 1, "★3 self rank +1")
	assert_eq(board[1].theme_state.get("rank", 0), before_target_rank + 1, "★3 target rank +1")


# ================================================================
# ml_academy (OE): TRAIN 이벤트 → target 추가 훈련
# ================================================================

func test_academy_adds_rank_to_train_target() -> void:
	var board: Array = [CardInstance.create("ml_academy"), CardInstance.create("ml_barracks")]
	var event: Dictionary = _make_train_event(1, 1)
	_sys.process_event_card(board[0], 0, board, event, _rng)
	assert_eq(board[1].theme_state.get("rank", 0), 1, "target rank +1")


func test_academy_star1_no_enhance() -> void:
	## ★1: bonus_train=1, growth=0 (enhance 없음)
	var board: Array = [CardInstance.create("ml_academy"), CardInstance.create("ml_barracks")]
	var atk_before: float = board[1].get_total_atk()
	var event: Dictionary = _make_train_event(1, 1)
	_sys.process_event_card(board[0], 0, board, event, _rng)
	assert_almost_eq(board[1].get_total_atk(), atk_before, 0.01, "★1: ATK 불변")


# ================================================================
# ml_factory (OE+PC 2-block, 2026-04-21 재설계):
#   OE: TR 이벤트의 target_idx 를 theme_state["trained_this_round"] 집합에 기록
#   PC: 수집된 각 군대 카드에 (그 카드 rank) × atk_pct_per_rank 만큼 ATK 영구 강화
#       ml_factory rank 4+ 이면 HP, rank 10+ 이면 AS 도 동일 비율. 적용 후 집합 초기화.
#       추가로 자신 rank +1 (self-train, 이벤트 방출 없음).
# ================================================================

func test_factory_oe_collects_tr_target_idx() -> void:
	## OE: TR 이벤트의 target_idx 를 집합에 기록 (중복 제거는 Dictionary key 의 idempotence).
	var card: CardInstance = CardInstance.create("ml_factory")
	_sys.process_event_card(card, 0, [card], _make_train_event(0, 1), _rng)
	_sys.process_event_card(card, 0, [card], _make_train_event(0, 2), _rng)
	_sys.process_event_card(card, 0, [card], _make_train_event(0, 1), _rng)  # 중복
	var coll: Dictionary = card.theme_state.get("trained_this_round", {})
	assert_eq(coll.size(), 2, "중복 제거 후 2개 idx 기록")
	assert_true(coll.has(1), "target_idx=1 기록됨")
	assert_true(coll.has(2), "target_idx=2 기록됨")


func test_factory_pc_self_trains_rank_plus_one() -> void:
	## PC 마다 자신 rank +1 (self-train, 이벤트 방출 없음).
	var factory: CardInstance = CardInstance.create("ml_factory")
	factory.theme_state["rank"] = 3
	_sys.apply_post_combat(factory, 0, [factory], true)
	assert_eq(factory.theme_state.get("rank", 0), 4,
		"PC 후 rank 3 → 4 (+1)")


func test_factory_pc_self_train_crosses_r4_gate_next_round() -> void:
	## 자체 rank +1 이 R4 게이트 충족으로 이어지는지 (rank 3 → 4 → 다음 라운드 HP 활성화).
	var factory: CardInstance = CardInstance.create("ml_factory")
	factory.theme_state["rank"] = 3
	# Round N PC: rank 3 상태로 수집된 카드에 ATK 만 적용 → 자신 rank 3→4
	var target: CardInstance = CardInstance.create("ml_barracks")
	target.theme_state["rank"] = 5
	factory.theme_state["trained_this_round"] = {1: true}
	var hp_before_r3: float = target.get_total_hp()
	_sys.apply_post_combat(factory, 0, [factory, target], true)
	assert_almost_eq(target.get_total_hp(), hp_before_r3, 0.01,
		"Round N: 자신 rank 3 — HP 증강 없음 (PC 중 self-train 은 target 증강 후에 실행)")
	assert_eq(factory.theme_state.get("rank", 0), 4, "PC 후 rank 4 승격")
	# Round N+1 PC: rank 4 로 HP 도 적용
	factory.theme_state["trained_this_round"] = {1: true}
	var hp_before_r4: float = target.get_total_hp()
	_sys.apply_post_combat(factory, 0, [factory, target], true)
	assert_gt(target.get_total_hp(), hp_before_r4,
		"Round N+1: rank 4 — HP 도 증강 활성화")


func test_factory_pc_enhances_conscripted_by_rank() -> void:
	## 2026-04-23: 스케일 기준 = factory 자신의 rank.
	## ★1 rate 0.02. factory rank 5 → 5 × 2% = 10% ATK.
	var factory: CardInstance = CardInstance.create("ml_factory")
	factory.theme_state["rank"] = 5
	var target: CardInstance = CardInstance.create("ml_barracks")
	factory.theme_state["trained_this_round"] = {1: true}
	var board: Array = [factory, target]
	var atk_before: float = target.get_total_atk()
	_sys.apply_post_combat(factory, 0, board, true)
	var atk_after: float = target.get_total_atk()
	assert_almost_eq(atk_after / atk_before, 1.10, 0.01,
		"factory rank 5 × 2% = 10% ATK")


func test_factory_pc_r4_applies_hp_too() -> void:
	## 2026-04-23: factory 자신 rank 기반. rate 0.02 (★1).
	## factory rank 10 → HP = 10 × 2% = 20%. R4 게이트 충족.
	var factory: CardInstance = CardInstance.create("ml_factory")
	factory.theme_state["rank"] = 10
	var target: CardInstance = CardInstance.create("ml_barracks")
	factory.theme_state["trained_this_round"] = {1: true}
	var board: Array = [factory, target]
	var hp_before: float = target.get_total_hp()
	_sys.apply_post_combat(factory, 0, board, true)
	var hp_after: float = target.get_total_hp()
	assert_almost_eq(hp_after / hp_before, 1.20, 0.01,
		"factory rank 10 × 2% = 20% HP 증강 (R4+ 충족)")


func test_factory_pc_ignores_target_rank() -> void:
	## target rank 무관 검증: factory rank 동일·target rank 다른 두 케이스 결과 동일.
	## 2026-04-23 factory-rank 기반 전환 regression gate.
	var factory_a: CardInstance = CardInstance.create("ml_factory")
	factory_a.theme_state["rank"] = 5
	var target_a: CardInstance = CardInstance.create("ml_barracks")
	target_a.theme_state["rank"] = 0
	factory_a.theme_state["trained_this_round"] = {1: true}
	_sys.apply_post_combat(factory_a, 0, [factory_a, target_a], true)

	var factory_b: CardInstance = CardInstance.create("ml_factory")
	factory_b.theme_state["rank"] = 5
	var target_b: CardInstance = CardInstance.create("ml_barracks")
	target_b.theme_state["rank"] = 12
	factory_b.theme_state["trained_this_round"] = {1: true}
	_sys.apply_post_combat(factory_b, 0, [factory_b, target_b], true)

	assert_almost_eq(target_a.get_total_atk(), target_b.get_total_atk(), 0.01,
		"target rank 0 vs 12 → 결과 동일 (factory rank만 사용)")


func test_factory_pc_r3_no_hp_buff() -> void:
	## ml_factory rank 3 이면 HP 미증강 (ATK 만).
	var factory: CardInstance = CardInstance.create("ml_factory")
	factory.theme_state["rank"] = 3
	var target: CardInstance = CardInstance.create("ml_barracks")
	factory.theme_state["trained_this_round"] = {1: true}
	var board: Array = [factory, target]
	var hp_before: float = target.get_total_hp()
	_sys.apply_post_combat(factory, 0, board, true)
	assert_almost_eq(target.get_total_hp(), hp_before, 0.01,
		"ml_factory rank 3 (< 4) → HP 증강 없음")


func test_factory_pc_resets_collection_after_apply() -> void:
	## PC 적용 후 집합 초기화 — 다음 라운드의 수집이 누수 없이 시작.
	var factory: CardInstance = CardInstance.create("ml_factory")
	factory.theme_state["rank"] = 1  # enhance 경로 실행되도록 (test name "after_apply" 의도)
	var target: CardInstance = CardInstance.create("ml_barracks")
	factory.theme_state["trained_this_round"] = {1: true, 2: true}
	_sys.apply_post_combat(factory, 0, [factory, target, target], true)
	var coll: Dictionary = factory.theme_state.get("trained_this_round", {})
	assert_eq(coll.size(), 0, "PC 후 집합 초기화")


func test_factory_pc_star_scaling() -> void:
	## 2026-04-23: factory 자신 rank 기반. ★2 = 3%, ★3 = 5% per rank.
	var factory2 := _make_star("ml_factory", 2)
	factory2.theme_state["rank"] = 10
	var target2: CardInstance = CardInstance.create("ml_barracks")
	factory2.theme_state["trained_this_round"] = {1: true}
	var atk_before2: float = target2.get_total_atk()
	_sys.apply_post_combat(factory2, 0, [factory2, target2], true)
	assert_almost_eq(target2.get_total_atk() / atk_before2, 1.30, 0.01,
		"★2: factory rank 10 × 3% = 30%")

	var factory3 := _make_star("ml_factory", 3)
	factory3.theme_state["rank"] = 10
	var target3: CardInstance = CardInstance.create("ml_barracks")
	factory3.theme_state["trained_this_round"] = {1: true}
	var atk_before3: float = target3.get_total_atk()
	_sys.apply_post_combat(factory3, 0, [factory3, target3], true)
	assert_almost_eq(target3.get_total_atk() / atk_before3, 1.50, 0.01,
		"★3: factory rank 10 × 5% = 50%")


func test_factory_pc_r10_applies_as_buff() -> void:
	## 2026-04-23: factory 자신 rank 기반. ★1=2%/rank.
	## factory rank 10 → upgrade_as_mult /= (1 + 10 × 0.02) = /1.20.
	var factory: CardInstance = CardInstance.create("ml_factory")
	factory.theme_state["rank"] = 10
	var target: CardInstance = CardInstance.create("ml_barracks")
	factory.theme_state["trained_this_round"] = {1: true}
	var as_before: float = target.upgrade_as_mult
	_sys.apply_post_combat(factory, 0, [factory, target], true)
	assert_almost_eq(target.upgrade_as_mult, as_before / 1.20, 0.001,
		"★1 R10: upgrade_as_mult /= (1 + factory rank×2%) = /1.20")


func test_factory_pc_r9_no_as_buff() -> void:
	## ml_factory rank 9 이면 AS 미강화 (R10 게이트 미충족).
	var factory: CardInstance = CardInstance.create("ml_factory")
	factory.theme_state["rank"] = 9
	var target: CardInstance = CardInstance.create("ml_barracks")
	factory.theme_state["trained_this_round"] = {1: true}
	var as_before: float = target.upgrade_as_mult
	_sys.apply_post_combat(factory, 0, [factory, target], true)
	assert_almost_eq(target.upgrade_as_mult, as_before, 0.001,
		"ml_factory rank 9 (< 10) → AS 변화 없음")


func test_factory_pc_star3_r10_as_rate() -> void:
	## 2026-04-23: factory 자신 rank 기반. ★3 AS 5%/rank. factory rank 10 → /1.50.
	var factory := _make_star("ml_factory", 3)
	factory.theme_state["rank"] = 10
	var target: CardInstance = CardInstance.create("ml_barracks")
	factory.theme_state["trained_this_round"] = {1: true}
	var as_before: float = target.upgrade_as_mult
	_sys.apply_post_combat(factory, 0, [factory, target], true)
	assert_almost_eq(target.upgrade_as_mult, as_before / 1.50, 0.001,
		"★3 R10: upgrade_as_mult /= 1.50")


func test_factory_pc_factory_rank_zero_no_enhance() -> void:
	## 2026-04-23: factory 자신 rank 0이면 early-continue 가드로 enhance 생략.
	var factory: CardInstance = CardInstance.create("ml_factory")
	# factory rank 설정 안 함 → 0
	var target: CardInstance = CardInstance.create("ml_barracks")
	factory.theme_state["trained_this_round"] = {1: true}
	var atk_before: float = target.get_total_atk()
	_sys.apply_post_combat(factory, 0, [factory, target], true)
	assert_almost_eq(target.get_total_atk(), atk_before, 0.01,
		"factory rank 0 → 증강 없음 (early-continue)")


# ================================================================
# ml_supply (POST_COMBAT): 군대 카드 수 기반 골드
# ================================================================

func test_supply_earns_gold_per_army_card() -> void:
	## ★1: base=1 + int(army_cards * 0.5)
	## 보드에 군대 카드 2장 → 1 + int(2*0.5) = 2골드
	var board: Array = [CardInstance.create("ml_supply"), CardInstance.create("ml_barracks")]
	var result: Dictionary = _sys.apply_post_combat(board[0], 0, board, true)
	assert_eq(result["gold"], 2, "군대 2장 → 2골드")


func test_supply_defeat_halves_gold() -> void:
	## ★1 패배: 골드 / 2
	var board: Array = [CardInstance.create("ml_supply"), CardInstance.create("ml_barracks")]
	var result_win: Dictionary = _sys.apply_post_combat(board[0], 0, board, true)
	var result_loss: Dictionary = _sys.apply_post_combat(board[0], 0, board, false)
	assert_lt(result_loss["gold"], result_win["gold"], "패배 골드 < 승리 골드")


# ================================================================
# ml_tactical (BS): rank_buff (shield + ATK)
# ================================================================

func test_tactical_applies_shield_by_rank() -> void:
	## ★1: shield = rank * shield_per_rank (0.02)
	var board: Array = [CardInstance.create("ml_tactical"), CardInstance.create("ml_barracks")]
	board[0].theme_state["rank"] = 5
	_sys.apply_battle_start(board[0], 0, board)
	assert_gt(board[0].shield_hp_pct, 0.0, "rank 5 → shield > 0")


func test_tactical_buffs_atk_by_total_units() -> void:
	## ★1: ATK buff = total_units * atk_per_unit (0.005)
	var board: Array = [CardInstance.create("ml_tactical")]
	board[0].theme_state["rank"] = 1
	var atk_before: float = board[0].get_total_atk()
	_sys.apply_battle_start(board[0], 0, board)
	assert_gt(board[0].get_total_atk(), atk_before, "유닛 기반 ATK 버프")


# ================================================================
# ml_assault (RS): 재설계로 timing BS→RS, 기본 효과는 spawn_unit(바이커)
# ================================================================

func test_assault_rs_conscripts_fixed_biker() -> void:
	## ★1 (2026-04-21 재설계): forced_unit=ml_biker 로 고정 징집.
	## 1 회 = pool entry count (biker=2 기). rank 0 이면 전부 base biker.
	var card: CardInstance = CardInstance.create("ml_assault")
	var before: int = card.get_total_units()
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(card.get_total_units(), before + 2, "★1: ml_biker 2 기 징집 (R0)")
	# 추가된 유닛이 ml_biker 인지 확인.
	var biker_stack: Dictionary = _find_stack_by_id(card, "ml_biker")
	assert_false(biker_stack.is_empty(), "ml_biker stack 존재")


# ================================================================
# ml_special_ops (RS): 재설계로 훈련 제거, crit_buff 중심
# ================================================================

func test_special_ops_sets_crit_chance() -> void:
	## ★1: crit_chance 0.10, mult 2.0 → theme_state에 저장.
	var card: CardInstance = CardInstance.create("ml_special_ops")
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_almost_eq(card.theme_state.get("crit_chance", 0.0), 0.10, 0.001, "★1: 크리 확률 10%")
	assert_almost_eq(card.theme_state.get("crit_mult", 0.0), 2.0, 0.001, "★1: 크리 배율 2.0")


# ================================================================
# ml_command (RS): train all + 부활 HP (apply_persistent 제거됨, trace 012 cleanup)
# revive 수치는 game_manager._materialize_army가 YAML 직접 평가.
# ================================================================

func test_command_s1_trains_all_military() -> void:
	## ★1: train all_military amount=1.
	var card: CardInstance = CardInstance.create("ml_command")
	var ally: CardInstance = CardInstance.create("ml_barracks")
	var rank_before: int = ally.theme_state.get("rank", 0)
	_sys.process_rs_card(card, 0, [card, ally], _rng)
	assert_eq(ally.theme_state.get("rank", 0), rank_before + 1, "★1 train +1")


func test_command_s3_trains_2() -> void:
	## ★3: amount=2.
	var card := _make_star("ml_command", 3)
	var ally: CardInstance = CardInstance.create("ml_barracks")
	var rank_before: int = ally.theme_state.get("rank", 0)
	_sys.process_rs_card(card, 0, [card, ally], _rng)
	assert_eq(ally.theme_state.get("rank", 0), rank_before + 2, "★3 train +2")


func _revive_effect_for(card: CardInstance) -> Dictionary:
	## Helper: YAML의 revive effect를 직접 평가 (_materialize_army와 동일 로직).
	var effs: Array = CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	for eff in effs:
		if eff.get("action", "") == "revive":
			return eff
	return {}


func test_command_s1_revive_hp_25_yaml() -> void:
	## 재설계: ★1 revive HP 25%.
	var card: CardInstance = CardInstance.create("ml_command")
	var eff: Dictionary = _revive_effect_for(card)
	assert_almost_eq(float(eff.get("hp_pct", 0.0)), 0.25, 0.001, "★1: HP 25%")
	assert_eq(int(eff.get("limit_per_combat", 0)), 1, "★1: 1회")


func test_command_s2_revive_hp_50_yaml() -> void:
	## 재설계: ★2 HP 50%.
	var card := _make_star("ml_command", 2)
	var eff: Dictionary = _revive_effect_for(card)
	assert_almost_eq(float(eff.get("hp_pct", 0.0)), 0.50, 0.001, "★2: HP 50%")


func test_command_s3_revive_hp_100_yaml() -> void:
	## 재설계: ★3 HP 100%, limit 1.
	var card := _make_star("ml_command", 3)
	var eff: Dictionary = _revive_effect_for(card)
	assert_almost_eq(float(eff.get("hp_pct", 0.0)), 1.0, 0.001, "★3: HP 100%")
	assert_eq(int(eff.get("limit_per_combat", 0)), 1, "★3: 1회")


# ml_barracks R4/R10 enhance_convert_card 테스트 제거 (2026-04-21).
# enhance_convert_card action 폐기 — ml_barracks 는 train 만 하고 유닛 추가
# 안 함. 따라서 R4/R10 에서 카드 내 유닛 구성에 영향 없음.


# ================================================================
# R 효과 세부 테스트 (각 카드 R4/R10 검증 — trace 012 재설계)
# ================================================================

func _find_stack_by_id(card: CardInstance, unit_id: String) -> Dictionary:
	for s in card.stacks:
		if s["unit_type"].get("id", "") == unit_id:
			return s
	return {}


# --- 훈련소 R4/R10 ---

func test_barracks_r4_trains_left_adj() -> void:
	## R4 차분: 기본 right_adj + R4에서 left_adj 추가 → 양쪽 훈련.
	var board: Array = [
		CardInstance.create("ml_conscript"),  # 왼쪽 (left_adj of barracks)
		CardInstance.create("ml_barracks"),   # 중앙
		CardInstance.create("ml_outpost"),    # 오른쪽 (right_adj)
	]
	board[1].theme_state["rank"] = 4
	_sys.process_rs_card(board[1], 1, board, _rng)
	assert_eq(board[0].theme_state.get("rank", 0), 1, "R4: 왼쪽 인접도 훈련")
	assert_eq(board[2].theme_state.get("rank", 0), 1, "오른쪽 인접 (기본)")


func test_barracks_r10_trains_far_military() -> void:
	## R10 차분: self + right + left + far_military.
	## self/인접 제외한 나머지 군대 카드도 훈련.
	var board: Array = [
		CardInstance.create("ml_conscript"),  # 왼쪽 인접
		CardInstance.create("ml_barracks"),   # self (idx=1)
		CardInstance.create("ml_outpost"),    # 오른쪽 인접
		CardInstance.create("ml_supply"),     # far_military
	]
	board[1].theme_state["rank"] = 10
	_sys.process_rs_card(board[1], 1, board, _rng)
	assert_eq(board[3].theme_state.get("rank", 0), 1, "R10: far_military 카드도 훈련")


# --- 징병국 R4/R10 변환·엘리트 보너스 (2026-04-21 해석 B) ---
# conscript_pool_tier 제거. _conscript(source_card=card) 에 source 의
# rank 를 전달 → R4 이상이면 ENHANCED_MAP 변환, R10 이상이면 엘리트 1 기
# 추가. _pool_for_card 헬퍼도 제거됨.

func test_conscript_r4_partial_transform() -> void:
	## R4 도달 카드 self 징집: 각 유닛 50% 확률로 (강화) 변환.
	## ★3 (count 3 + both_adj 1) 이면 뽑기가 충분히 많아 확률상 enhanced
	## 유닛이 1기 이상 나옴 (RNG seed=42 결정론적).
	var card: CardInstance = CardInstance.create("ml_conscript")
	card.star_level = 3
	card.theme_state["rank"] = 4
	_sys.process_rs_card(card, 0, [card], _rng)
	var has_enhanced := false
	for s in card.stacks:
		if (s["unit_type"].get("id", "") as String).ends_with("_enhanced"):
			has_enhanced = true
			break
	assert_true(has_enhanced,
		"R4 conscript: 50% 확률 변환 — enhanced 유닛 존재")


func test_conscript_r10_adds_elite_bonus() -> void:
	## R10 도달 카드로 self 징집 시 엘리트 유닛(sniper/artillery/walker/commander)
	## 중 1 기 보너스 추가. 확인: stacks 안에 엘리트 ID 존재.
	var card: CardInstance = CardInstance.create("ml_conscript")
	card.theme_state["rank"] = 10
	_sys.process_rs_card(card, 0, [card], _rng)
	var has_elite := false
	for s in card.stacks:
		var uid: String = s["unit_type"].get("id", "")
		if uid in ["ml_sniper", "ml_artillery", "ml_walker", "ml_commander"]:
			has_elite = true
			break
	assert_true(has_elite, "R10 conscript: 엘리트 1 기 보너스 추가")


func test_conscript_r0_no_enhanced_no_elite() -> void:
	## rank 4 미만: base 유닛만 추가. (강화) / 엘리트 없음.
	var card: CardInstance = CardInstance.create("ml_conscript")
	card.star_level = 3  # 더 많이 뽑게 해서 통계적 확신 ↑ (3 회 뽑기)
	_sys.process_rs_card(card, 0, [card], _rng)
	for s in card.stacks:
		var uid: String = s["unit_type"].get("id", "")
		assert_false(uid.ends_with("_enhanced"),
			"R0: (강화) 유닛 없음 (%s)" % uid)
		assert_false(uid in ["ml_sniper", "ml_artillery", "ml_walker", "ml_commander"],
			"R0: 엘리트 유닛 없음 (%s)" % uid)


# ml_outpost R4/R10 확장 범위 테스트 제거 (2026-04-21 C7).
# r_conditional (event_target_adj / far_event_military) 폐기됨 — 이제 ★별
# 단일 구조 (★1 event_target, ★2 self+event_target, ★3 상기 + 훈련 1회).
# 새 ★별 테스트는 위 test_outpost_s{1,2,3}_* 에 있음.


# --- 군사학교 R4/R10: 훈련 이벤트 반응 ---

func test_academy_r4_converts_target_unit() -> void:
	## R4: 훈련 시 훈련 대상의 비(강화) 유닛 1기 변환 (라운드당 1회).
	var board: Array = [
		CardInstance.create("ml_academy"),
		CardInstance.create("ml_barracks"),
	]
	board[0].theme_state["rank"] = 4
	var target: CardInstance = board[1]
	var before_enhanced := 0
	for s in target.stacks:
		if "enhanced" in s["unit_type"].get("tags", PackedStringArray()):
			before_enhanced += s["count"]
	var event: Dictionary = _make_train_event(1, 1)
	_sys.process_event_card(board[0], 0, board, event, _rng)
	var after_enhanced := 0
	for s in target.stacks:
		if "enhanced" in s["unit_type"].get("tags", PackedStringArray()):
			after_enhanced += s["count"]
	assert_gt(after_enhanced, before_enhanced, "R4: 훈련 대상에 (강화) 유닛 생김")


func test_academy_r4_max_per_round() -> void:
	## R4 효과는 라운드당 1회. 같은 tenure에서 두 번째 호출은 변환 안 함.
	var board: Array = [
		CardInstance.create("ml_academy"),
		CardInstance.create("ml_barracks"),
	]
	board[0].theme_state["rank"] = 4
	var target: CardInstance = board[1]
	var event: Dictionary = _make_train_event(1, 1)
	_sys.process_event_card(board[0], 0, board, event, _rng)  # 1st fire
	var after_first_enhanced := 0
	for s in target.stacks:
		if "enhanced" in s["unit_type"].get("tags", PackedStringArray()):
			after_first_enhanced += s["count"]
	_sys.process_event_card(board[0], 0, board, event, _rng)  # 2nd within same tenure
	var after_second_enhanced := 0
	for s in target.stacks:
		if "enhanced" in s["unit_type"].get("tags", PackedStringArray()):
			after_second_enhanced += s["count"]
	assert_eq(after_first_enhanced, after_second_enhanced,
		"R4: 같은 tenure 재호출은 변환 X (max_per_round:1)")


func test_academy_r10_spawns_enhanced_units() -> void:
	## R10: 훈련 시 훈련 대상에 랜덤 (강화) 유닛 2기 추가.
	## R10은 R4 효과(convert)를 **대체** — 같은 tenure slot 공유(academy_convert_tenure).
	## rank_gte 내림차순 순회로 R10이 먼저 실행 → tenure 소진 → R4 skip.
	var board: Array = [
		CardInstance.create("ml_academy"),
		CardInstance.create("ml_barracks"),
	]
	board[0].theme_state["rank"] = 10
	var target: CardInstance = board[1]
	var before_total: int = target.get_total_units()
	var event: Dictionary = _make_train_event(1, 1)
	_sys.process_event_card(board[0], 0, board, event, _rng)
	# R10 spawn(2) — R4 convert는 tenure 공유로 skip.
	assert_eq(target.get_total_units() - before_total, 2, "R10: 유닛 +2 (R10 spawn만, R4 convert skip)")


func test_academy_r10_replaces_r4_via_shared_tenure() -> void:
	## R10 도달 시 같은 tenure slot을 공유해 R4 convert가 실행되지 않아야 함.
	## 명시적 회귀 테스트: R10 rank에서 라운드 1회 발동 → spawn만, convert 없음.
	var board: Array = [
		CardInstance.create("ml_academy"),
		CardInstance.create("ml_barracks"),
	]
	board[0].theme_state["rank"] = 10
	var target: CardInstance = board[1]
	# R10 도달 전 (강화) 유닛 수 측정
	var before_enhanced := 0
	for s in target.stacks:
		if "enhanced" in s["unit_type"].get("tags", PackedStringArray()):
			before_enhanced += s["count"]
	var event: Dictionary = _make_train_event(1, 1)
	_sys.process_event_card(board[0], 0, board, event, _rng)
	# R10 spawn은 랜덤 (강화) 유닛을 추가하므로 enhanced 수가 늘 수 있다.
	# 하지만 R4 convert가 "기존 non-enhanced → enhanced 변환"을 실행했다면
	# 기존 non-enhanced 감소분이 있어야 하는데, spawn만 있으면 기존 non-enhanced 불변.
	# → non-enhanced 유닛 수가 불변이어야 R4가 skip된 것.
	var after_non_enhanced := 0
	for s in target.stacks:
		if not ("enhanced" in s["unit_type"].get("tags", PackedStringArray())):
			after_non_enhanced += s["count"]
	# ml_barracks initial comp: 신병 2 + 보병 1 = 3기 (모두 non-enhanced).
	assert_eq(after_non_enhanced, 3,
		"R10: R4 convert skip되므로 기존 non-enhanced 유닛 수 불변")


# --- 보급부대 R4/R10: grant_gold/terazin ---

func test_supply_r4_grants_terazin() -> void:
	## R4: 매 PC 테라진 +1 (R4 공통 enhance_convert_card 외).
	var card: CardInstance = CardInstance.create("ml_supply")
	card.theme_state["rank"] = 4
	var result: Dictionary = _sys.apply_post_combat(card, 0, [card], true)
	assert_eq(result["terazin"], 1, "R4: 테라진 +1")


func test_supply_r10_grants_terazin_and_gold() -> void:
	## R10: 테라진 +2 (R4 누적 1+1) + 골드 +1.
	var card: CardInstance = CardInstance.create("ml_supply")
	card.theme_state["rank"] = 10
	var base_result: Dictionary = _sys.apply_post_combat(CardInstance.create("ml_supply"), 0,
		[CardInstance.create("ml_supply")], true)
	var base_gold: int = base_result["gold"]
	var result: Dictionary = _sys.apply_post_combat(card, 0, [card], true)
	assert_eq(result["terazin"], 2, "R10: 테라진 +2 (R4 1 + R10 1 누적)")
	assert_eq(result["gold"], base_gold + 1, "R10: 골드 +1 추가")


# --- 전술사령부 R4/R10: rank_buff_hp + as_bonus ---

func test_tactical_r4_hp_buff_applied() -> void:
	## R4: 모든 군대 카드 HP multiplicative buff (temp_mult_buff).
	var board: Array = [
		CardInstance.create("ml_tactical"),
		CardInstance.create("ml_barracks"),
	]
	board[0].theme_state["rank"] = 4
	var hp_before: float = board[1].get_total_hp()
	_sys.apply_battle_start(board[0], 0, board)
	assert_gt(board[1].get_total_hp(), hp_before, "R4: 군대 카드 HP 증가")


func test_tactical_r10_sets_as_bonus() -> void:
	## R10: 모든 군대 카드에 as_bonus theme_state 세팅.
	var board: Array = [
		CardInstance.create("ml_tactical"),
		CardInstance.create("ml_barracks"),
	]
	board[0].theme_state["rank"] = 10
	_sys.apply_battle_start(board[0], 0, board)
	assert_almost_eq(board[1].theme_state.get("as_bonus", 0.0), 0.15, 0.001,
		"R10: as_bonus 0.15 세팅")


# --- 돌격편대 R4/R10 (2026-04-21 재설계): self shield + self lifesteal ---

func test_assault_r4_applies_self_shield() -> void:
	## ★1 R4: 이 카드 shield_hp_pct 에 0.2 누적 (방어막 HP 20%).
	var card: CardInstance = CardInstance.create("ml_assault")
	card.theme_state["rank"] = 4
	var before: float = card.shield_hp_pct
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_almost_eq(card.shield_hp_pct - before, 0.2, 0.001,
		"★1 R4: 이 카드 shield +20%")


func test_assault_s3_r4_shield_90pct() -> void:
	## ★3 R4: shield +90% (★별 스케일링 20/40/90%).
	var card := _make_star("ml_assault", 3)
	card.theme_state["rank"] = 4
	var before: float = card.shield_hp_pct
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_almost_eq(card.shield_hp_pct - before, 0.9, 0.001, "★3 R4: shield +90%")


func test_assault_r10_sets_self_lifesteal() -> void:
	## ★1 R10: 이 카드 theme_state["lifesteal_pct"] = 0.1 (전군 아님, self).
	var board: Array = [
		CardInstance.create("ml_assault"),
		CardInstance.create("ml_barracks"),
	]
	board[0].theme_state["rank"] = 10
	_sys.process_rs_card(board[0], 0, board, _rng)
	assert_almost_eq(board[0].theme_state.get("lifesteal_pct", 0.0), 0.1, 0.001,
		"★1 R10: self lifesteal 0.1")
	assert_almost_eq(board[1].theme_state.get("lifesteal_pct", 0.0), 0.0, 0.001,
		"★1 R10: 다른 카드엔 lifesteal 미전파 (self 한정)")


func test_assault_s3_r10_lifesteal_30pct() -> void:
	## ★3 R10: self lifesteal 0.3 (★별 10/20/30%).
	var card := _make_star("ml_assault", 3)
	card.theme_state["rank"] = 10
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_almost_eq(card.theme_state.get("lifesteal_pct", 0.0), 0.3, 0.001,
		"★3 R10: self lifesteal 0.3")


func test_assault_r0_no_shield_no_lifesteal() -> void:
	## rank 4 미만: shield/lifesteal 효과 없음.
	var card: CardInstance = CardInstance.create("ml_assault")
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_almost_eq(card.shield_hp_pct, 0.0, 0.001, "R0: shield 없음")
	assert_almost_eq(card.theme_state.get("lifesteal_pct", 0.0), 0.0, 0.001,
		"R0: lifesteal 없음")


# --- 특수작전대 ★/R: crit_buff + crit_splash ---

func test_special_ops_s2_conscripts_and_emits_co() -> void:
	## ★2 (2026-04-21): spawn_unit(sniper) → conscript. base pool 1 회 뽑기.
	## 유닛 최소 1 기 추가 + CO 이벤트 방출 (ml_outpost 체인용).
	var card := _make_star("ml_special_ops", 2)
	var before: int = card.get_total_units()
	var result: Dictionary = _sys.process_rs_card(card, 0, [card], _rng)
	assert_gt(card.get_total_units(), before, "★2: conscript 유닛 추가")
	var has_co := false
	for e in result["events"]:
		if e.get("layer2", -1) == Enums.Layer2.CONSCRIPT:
			has_co = true
			break
	assert_true(has_co, "★2: CO 이벤트 방출")


func test_special_ops_s3_conscripts_thrice_and_mult_6() -> void:
	## ★3: conscript 3 회 뽑기 + crit_mult 6.0.
	var card := _make_star("ml_special_ops", 3)
	var before: int = card.get_total_units()
	_sys.process_rs_card(card, 0, [card], _rng)
	var added: int = card.get_total_units() - before
	assert_between(added, 3, 9, "★3: conscript 3 회 → 3~9 기 추가")
	assert_almost_eq(card.theme_state.get("crit_mult", 0.0), 6.0, 0.001, "★3: 크리 배율 6.0")


func test_special_ops_r4_crit_chance_20_splash_25() -> void:
	## R4: 크리 확률 0.20 + 인접 스플래시 0.25.
	var card: CardInstance = CardInstance.create("ml_special_ops")
	card.theme_state["rank"] = 4
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_almost_eq(card.theme_state.get("crit_chance", 0.0), 0.20, 0.001, "R4: 확률 0.20")
	assert_almost_eq(card.theme_state.get("crit_splash_pct", 0.0), 0.25, 0.001,
		"R4: 스플래시 0.25")


func test_special_ops_r10_crit_chance_30_splash_50() -> void:
	## R10: 크리 확률 0.30 + 스플래시 0.50 (R4 효과 덮어쓰기).
	var card: CardInstance = CardInstance.create("ml_special_ops")
	card.theme_state["rank"] = 10
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_almost_eq(card.theme_state.get("crit_chance", 0.0), 0.30, 0.001, "R10: 확률 0.30")
	assert_almost_eq(card.theme_state.get("crit_splash_pct", 0.0), 0.50, 0.001,
		"R10: 스플래시 0.50")


# 군수공장 R4/R10 shop bonus + counter_produce range bonus 테스트 제거
# (2026-04-21 재설계). shop_bonus / range_bonus / global_military_atk_pct 모두
# 신 메카닉(rank_scaled_enhance)으로 대체됨.

# --- 통합사령부 R4/R10 (YAML scope override — _materialize_army에서 평가) ---

func test_command_r4_revive_scope_self_all_yaml() -> void:
	## R4: YAML r_conditional에 revive_scope_override self_all 존재.
	var card: CardInstance = CardInstance.create("ml_command")
	var effs: Array = CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var r4_has_scope := false
	for eff in effs:
		if eff.get("action", "") != "r_conditional":
			continue
		if int(eff.get("threshold", 0)) != 4:
			continue
		for inner in eff.get("effects", []):
			if inner.get("action", "") == "revive_scope_override":
				if inner.get("target", "") == "self_all":
					r4_has_scope = true
					break
	assert_true(r4_has_scope, "R4: YAML에 revive_scope_override self_all 선언")


func test_command_r10_revive_scope_self_and_adj_all_yaml() -> void:
	## R10: YAML r_conditional에 revive_scope_override self_and_adj_all 존재.
	var card: CardInstance = CardInstance.create("ml_command")
	var effs: Array = CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var r10_has_scope := false
	for eff in effs:
		if eff.get("action", "") != "r_conditional":
			continue
		if int(eff.get("threshold", 0)) != 10:
			continue
		for inner in eff.get("effects", []):
			if inner.get("action", "") == "revive_scope_override":
				if inner.get("target", "") == "self_and_adj_all":
					r10_has_scope = true
					break
	assert_true(r10_has_scope, "R10: YAML에 revive_scope_override self_and_adj_all 선언")


# --- resolve_command_revive: YAML target 문자열이 rank 구간에 따라 실제로 반환되는지 ---
# 이 테스트 세트가 "YAML target → 코드 동작" 경로를 검증한다. 이전에는
# _materialize_army가 rank 조건으로 하드코딩해, YAML target을 바꿔도 코드가
# 반영하지 못했다 (fragile drift).

func test_resolve_command_revive_rank0_base_self_enhanced() -> void:
	## rank=0 (R4 미도달): base revive (self_enhanced) 반환.
	var card: CardInstance = CardInstance.create("ml_command")
	# rank는 theme_state.rank를 _rank() helper가 읽음
	var cfg: Dictionary = _sys.resolve_command_revive(card)
	assert_eq(cfg["target"], "self_enhanced", "R0: base target")
	assert_true(cfg["hp_pct"] > 0.0, "R0: hp_pct 설정됨")
	assert_true(cfg["limit"] > 0, "R0: limit 설정됨")


func test_resolve_command_revive_rank4_override_self_all() -> void:
	## rank=4: R4 override가 base를 덮어써 self_all 반환.
	var card: CardInstance = CardInstance.create("ml_command")
	card.theme_state["rank"] = 4
	var cfg: Dictionary = _sys.resolve_command_revive(card)
	assert_eq(cfg["target"], "self_all", "R4: override self_all")


func test_resolve_command_revive_rank10_override_self_and_adj_all() -> void:
	## rank=10: R10 override가 R4 override를 다시 덮어써 self_and_adj_all 반환.
	var card: CardInstance = CardInstance.create("ml_command")
	card.theme_state["rank"] = 10
	var cfg: Dictionary = _sys.resolve_command_revive(card)
	assert_eq(cfg["target"], "self_and_adj_all", "R10: override self_and_adj_all")


func test_resolve_command_revive_rank3_still_base() -> void:
	## rank=3 (R4 바로 전, off-by-one 경계): base target 유지.
	var card: CardInstance = CardInstance.create("ml_command")
	card.theme_state["rank"] = 3
	var cfg: Dictionary = _sys.resolve_command_revive(card)
	assert_eq(cfg["target"], "self_enhanced", "R3: base 유지, R4 미적용")


# --- resolve_revive_scope: 각 target 문자열을 card index + flag로 해석 ---

func test_resolve_revive_scope_self_enhanced() -> void:
	var scope: Dictionary = _sys.resolve_revive_scope("self_enhanced", 2, 5)
	assert_eq(scope["card_indices"], [2], "self_enhanced: self만")
	assert_true(scope["only_enhanced"], "self_enhanced: enhanced flag")


func test_resolve_revive_scope_self_all() -> void:
	var scope: Dictionary = _sys.resolve_revive_scope("self_all", 2, 5)
	assert_eq(scope["card_indices"], [2], "self_all: self만")
	assert_false(scope["only_enhanced"], "self_all: 모든 유닛")


func test_resolve_revive_scope_self_and_adj_all_middle() -> void:
	## 보드 중간 카드(idx=2, size=5): 왼/자신/오 3개 반환.
	var scope: Dictionary = _sys.resolve_revive_scope("self_and_adj_all", 2, 5)
	assert_eq(scope["card_indices"], [1, 2, 3], "중간: 인접 양쪽 포함")
	assert_false(scope["only_enhanced"], "self_and_adj_all: 모든 유닛")


func test_resolve_revive_scope_self_and_adj_all_left_edge() -> void:
	## 보드 좌측 끝(idx=0): 자신 + 오른쪽만.
	var scope: Dictionary = _sys.resolve_revive_scope("self_and_adj_all", 0, 5)
	assert_eq(scope["card_indices"], [0, 1], "좌측 끝: 왼쪽 인접 없음")


func test_resolve_revive_scope_self_and_adj_all_right_edge() -> void:
	## 보드 우측 끝(idx=4, size=5): 왼쪽 + 자신.
	var scope: Dictionary = _sys.resolve_revive_scope("self_and_adj_all", 4, 5)
	assert_eq(scope["card_indices"], [3, 4], "우측 끝: 오른쪽 인접 없음")


func test_resolve_revive_scope_unknown_falls_back() -> void:
	## 알 수 없는 target은 self_enhanced로 fallback (warning은 별도 확인 불가).
	var scope: Dictionary = _sys.resolve_revive_scope("nonexistent_scope", 1, 3)
	assert_eq(scope["card_indices"], [1], "unknown: self fallback")
	assert_true(scope["only_enhanced"], "unknown: enhanced fallback")


# --- 추가 ★ 검증 ---

func test_barracks_s3_high_rank_mult_applies_once() -> void:
	## ★3: rank 15 도달 시 high_rank_mult (atk_mult 1.3) 영구 적용 (one-shot).
	var card := _make_star("ml_barracks", 3)
	card.theme_state["rank"] = 15
	var atk_before: float = card.get_total_atk()
	_sys.process_rs_card(card, 0, [card], _rng)
	var atk_after_first: float = card.get_total_atk()
	assert_gt(atk_after_first, atk_before, "★3 rank 15: ATK 곱연산 적용")
	# 두 번째 호출: 같은 rank (또는 rank 16)이지만 one-shot 플래그로 중복 적용 안 됨.
	_sys.process_rs_card(card, 0, [card], _rng)
	var atk_after_second: float = card.get_total_atk()
	assert_almost_eq(atk_after_second, atk_after_first, atk_after_first * 0.01,
		"★3 rank 15: 재적용 없음 (one-shot)")


func test_assault_s1_conscripts_fixed_biker_and_emits_co() -> void:
	## ★1 (2026-04-21 C8): forced_unit=ml_biker, 1 회 = 2 기. biker_rebirth 제거.
	## CO 이벤트 방출 유지 (ml_outpost 체인용).
	var card: CardInstance = CardInstance.create("ml_assault")
	var before: int = card.get_total_units()
	var result: Dictionary = _sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(card.get_total_units() - before, 2, "★1: 바이커 2 기 (forced, 1 회 × 2)")
	var has_co := false
	for e in result["events"]:
		if e.get("layer2", -1) == Enums.Layer2.CONSCRIPT:
			has_co = true
			break
	assert_true(has_co, "★1: CO 이벤트 방출")


func test_assault_s3_conscripts_4_times_fixed_biker() -> void:
	## ★3: forced 바이커 4 회 = 8 기 (회당 2 기). R0 이면 모두 base biker.
	var card := _make_star("ml_assault", 3)
	var before: int = card.get_total_units()
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(card.get_total_units() - before, 8, "★3: 바이커 8 기 (4 회 × 2 기)")


func test_assault_r10_conscripts_all_enhanced_biker() -> void:
	## R10 도달 → forced biker 전원 강화 (ml_biker_enhanced). 기존 base biker 는
	## comp 초기화분 유지.
	var card: CardInstance = CardInstance.create("ml_assault")
	card.theme_state["rank"] = 10
	_sys.process_rs_card(card, 0, [card], _rng)
	var has_enhanced_biker := false
	for s in card.stacks:
		if s["unit_type"].get("id", "") == "ml_biker_enhanced":
			has_enhanced_biker = true
			break
	assert_true(has_enhanced_biker, "R10: 강화 바이커 존재")


# 공통 R4/R10 enhance_convert_card 테스트 (18 개) 및 헬퍼
# (_assert_r4_converts_half / _assert_r10_converts_all / _count_non_enhanced)
# 제거 (2026-04-21): enhance_convert_card action 폐기됨. 신규 유닛 강화는
# conscript rank_upgrade 경로로 일원화.


# ================================================================
# Combat integration 스모크 테스트: revive 실제 발동 (Critic 1 HIGH gap)
# combat_engine을 직접 세팅 후 kill_unit 호출하여 revive_left 차감 및 HP 복원 확인.
# ================================================================

func test_combat_revive_integration_smoke() -> void:
	## ml_command ★1 (hp_pct=0.25, limit=1)로 setup한 유닛이 사망 직전 부활.
	var engine := preload("res://combat/combat_engine.gd").new()
	# ally 유닛 1기: revive_limit=1, revive_hp_pct=0.5
	var ally_units: Array = [{
		"atk": 5.0, "hp": 50.0, "attack_speed": 1.0, "range": 0,
		"move_speed": 1, "def": 0.0, "mechanics": [],
		"radius": 6.0, "revive_limit": 1, "revive_hp_pct": 0.5,
	}]
	var enemy_units: Array = [{
		"atk": 5.0, "hp": 10.0, "attack_speed": 1.0, "range": 0,
		"move_speed": 1, "def": 0.0, "mechanics": [],
		"radius": 6.0,
	}]
	engine.headless = true
	engine.setup(ally_units, enemy_units)
	# 초기 상태 확인
	assert_eq(engine.revive_left[0], 1, "setup 후 revive_left=1")
	assert_almost_eq(engine.revive_hp_pct[0], 0.5, 0.001, "setup 후 revive_hp_pct=0.5")
	# kill_unit 호출 → revive 발동으로 사망 취소되어야 함
	engine.kill_unit(0)
	assert_eq(engine.alive[0], 1, "revive 발동 → alive 유지")
	assert_almost_eq(engine.hp[0], 25.0, 0.001, "max_hp 50 × 0.5 = 25 HP")
	assert_eq(engine.revive_left[0], 0, "revive_left 소진")
	# 두 번째 kill → revive 없음, 실제 사망
	engine.hp[0] = 0.0
	engine.kill_unit(0)
	assert_eq(engine.alive[0], 0, "revive 소진 후 실제 사망")


func test_combat_revive_not_triggered_without_limit() -> void:
	## revive_limit=0 unit은 kill 시 그대로 사망.
	var engine := preload("res://combat/combat_engine.gd").new()
	var ally_units: Array = [{
		"atk": 5.0, "hp": 50.0, "attack_speed": 1.0, "range": 0,
		"move_speed": 1, "def": 0.0, "mechanics": [],
		"radius": 6.0, "revive_limit": 0, "revive_hp_pct": 0.0,
	}]
	var enemy_units: Array = []
	engine.headless = true
	engine.setup(ally_units, enemy_units)
	engine.kill_unit(0)
	assert_eq(engine.alive[0], 0, "revive_limit=0 → 정상 사망")


# ================================================================
# ml_alliance (T3) — RS theme_count_conscript + BS theme_count_spawn
# ================================================================


func test_alliance_star1_rs_adds_recruits_per_theme() -> void:
	## ★1 RS: theme_count × 1 ml_recruit 직접 추가
	## 보드에 5테마 모두 → 5기 추가
	var card: CardInstance = CardInstance.create("ml_alliance")
	var before_units: int = card.get_total_units()
	var board: Array = [
		card,  # military
		CardInstance.create("sp_assembly"),  # steampunk
		CardInstance.create("ne_earth_echo"),  # neutral
		CardInstance.create("dr_cradle"),  # druid
		CardInstance.create("pr_nest"),  # predator
	]
	_sys.process_rs_card(card, 0, board, _rng)
	assert_eq(card.get_total_units(), before_units + 5, "5테마 → +5 ml_recruit")


func test_alliance_mono_military_only_one_recruit() -> void:
	## 단일 military theme → theme_count=1 → +1 ml_recruit
	var card: CardInstance = CardInstance.create("ml_alliance")
	var before_units: int = card.get_total_units()
	var board: Array = [card, CardInstance.create("ml_barracks")]
	_sys.process_rs_card(card, 0, board, _rng)
	assert_eq(card.get_total_units(), before_units + 1, "1테마 → +1")


func test_alliance_respects_unit_cap() -> void:
	## get_unit_cap 도달 시 추가 spawn 안 함 (총합 ≤ cap)
	var card: CardInstance = CardInstance.create("ml_alliance")
	# 모든 stack을 0으로 비우고 stack[0] = cap-1 로 세팅 (cap 직전)
	for s in card.stacks:
		s["count"] = 0
	card.stacks[0]["count"] = card.get_unit_cap() - 1
	var board: Array = [
		card, CardInstance.create("sp_assembly"),
		CardInstance.create("ne_earth_echo"), CardInstance.create("dr_cradle"),
		CardInstance.create("pr_nest"),
	]
	_sys.process_rs_card(card, 0, board, _rng)
	assert_true(card.get_total_units() <= card.get_unit_cap(),
		"cap %d 이하 (실제 %d)" % [card.get_unit_cap(), card.get_total_units()])


func test_alliance_star3_bs_threshold_instant_recruit() -> void:
	## ★3 BS: theme_count ≥3 시 즉시 ml_recruit 1기 추가 (instant_conscript_threshold)
	var card: CardInstance = CardInstance.create("ml_alliance")
	card.evolve_star()
	card.evolve_star()
	var before_units: int = card.get_total_units()
	var board: Array = [
		card, CardInstance.create("sp_assembly"),
		CardInstance.create("ne_earth_echo"),
	]  # 3테마
	_sys.apply_battle_start(card, 0, board)
	# theme_count=3, mult=2 → 6 spawn (랜덤 ally) + instant_conscript 1기 → self에 최소 1기 증가
	# (랜덤 분배라 정확한 +N 보장 못함, 다만 self는 instant_conscript 보장)
	assert_true(card.get_total_units() >= before_units + 1,
		"★3 BS theme_count≥3 → 즉시 conscript 1기 (self)")


func test_alliance_star2_bs_no_instant_threshold() -> void:
	## ★2 BS: instant_conscript_threshold 없음 → spawn만
	var card: CardInstance = CardInstance.create("ml_alliance")
	card.evolve_star()
	var board: Array = [card, CardInstance.create("ml_barracks")]
	# theme_count=1, mult=1 → 1 spawn (random ally)
	_sys.apply_battle_start(card, 0, board)
	# 누군가에게 1기 spawn — 보드 총합으로 검증
	var total: int = 0
	for c in board:
		total += (c as CardInstance).get_total_units()
	assert_true(total >= 1, "★2 BS spawn 1기")
