extends GutTest
## MilitarySystem 테마 로직 테스트
## 참조: military_system.gd, handoff.md P4-D
##
## barracks 훈련/임계값 / outpost 징집 / academy 추가 훈련 / factory 카운터 / command 부활 검증.


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


# ================================================================
# ml_barracks (RS): train +1 self, +1 adj military
# ================================================================

func test_barracks_trains_self_plus1() -> void:
	var card: CardInstance = CardInstance.create("ml_barracks")
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(card.theme_state.get("rank", 0), 1, "rank=1")


func test_barracks_trains_adjacent_military() -> void:
	var board: Array = [CardInstance.create("ml_barracks"), CardInstance.create("ml_outpost")]
	_sys.process_rs_card(board[0], 0, board, _rng)
	assert_eq(board[1].theme_state.get("rank", 0), 1, "adj military rank=1")


func test_barracks_no_train_to_non_military_adj() -> void:
	var board: Array = [CardInstance.create("ml_barracks"), CardInstance.create("sp_assembly")]
	_sys.process_rs_card(board[0], 0, board, _rng)
	assert_eq(board[1].theme_state.get("rank", 0), 0, "비군대 → rank 불변")


# ================================================================
# ml_barracks threshold: rank3→infantry
# ================================================================

func test_barracks_rank3_adds_infantry() -> void:
	var card: CardInstance = CardInstance.create("ml_barracks")
	card.theme_state["rank"] = 2
	var units_before: int = card.get_total_units()
	_sys.process_rs_card(card, 0, [card], _rng)
	# rank 2→3, threshold 3 → ml_infantry 1기 추가
	assert_eq(card.theme_state.get("rank", 0), 3, "rank=3")
	assert_eq(card.get_total_units(), units_before + 1, "infantry +1")


func test_barracks_rank_threshold_fires_once_only() -> void:
	var card: CardInstance = CardInstance.create("ml_barracks")
	card.theme_state["rank"] = 2
	_sys.process_rs_card(card, 0, [card], _rng)  # rank=3 → infantry 추가
	var units_after_first: int = card.get_total_units()
	_sys.process_rs_card(card, 0, [card], _rng)  # rank=4 → threshold 이미 발동
	assert_eq(card.get_total_units(), units_after_first, "재발동 없음")


# ================================================================
# ml_outpost (RS): conscript 2
# ================================================================

func test_outpost_defers_self_conscription() -> void:
	var card: CardInstance = CardInstance.create("ml_outpost")
	var before: int = card.get_total_units()
	_sys.process_rs_card(card, 0, [card], _rng)
	# Self-conscription is deferred — units NOT added yet
	assert_eq(card.get_total_units(), before, "deferred: 유닛 미추가")
	assert_eq(_sys.pending_conscriptions.size(), 1, "pending 1건")
	assert_eq(_sys.pending_conscriptions[0]["count"], 2, "count=2")


func test_outpost_pending_has_card_ref() -> void:
	var card: CardInstance = CardInstance.create("ml_outpost")
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(_sys.pending_conscriptions[0]["card_ref"], card, "card_ref 일치")
	assert_eq(_sys.pending_conscriptions[0]["card_idx"], 0, "card_idx=0")


func test_outpost_star3_defers_3() -> void:
	var card: CardInstance = CardInstance.create("ml_outpost")
	card.star_level = 3
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(_sys.pending_conscriptions[0]["count"], 3, "★3: count=3")


func test_pick_conscript_options_returns_3() -> void:
	var options: Array[String] = _sys.pick_conscript_options(_rng, 3)
	assert_eq(options.size(), 3, "3개 옵션")
	var pool_ids: Array = []
	for entry in MilitarySystem.CONSCRIPT_POOL:
		pool_ids.append(entry["id"])
	for uid in options:
		assert_true(uid in pool_ids, "옵션 '%s'이 CONSCRIPT_POOL에 있어야 함" % uid)


func test_apply_conscript_adds_unit() -> void:
	var card: CardInstance = CardInstance.create("ml_outpost")
	var before: int = card.get_total_units()
	var added: int = _sys.apply_conscript(card, "ml_recruit")
	assert_eq(added, 1, "1기 추가")
	assert_eq(card.get_total_units(), before + 1, "총 유닛 +1")


func test_clear_pending() -> void:
	var card: CardInstance = CardInstance.create("ml_outpost")
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_gt(_sys.pending_conscriptions.size(), 0, "pending 있음")
	_sys.clear_pending()
	assert_eq(_sys.pending_conscriptions.size(), 0, "clear 후 비어있음")


# ================================================================
# ml_academy (OE): TRAIN 이벤트 → target 추가 훈련
# ================================================================

func test_academy_adds_rank_to_train_target() -> void:
	var board: Array = [CardInstance.create("ml_academy"), CardInstance.create("ml_barracks")]
	var event: Dictionary = _make_train_event(1, 1)
	_sys.process_event_card(board[0], 0, board, event, _rng)
	assert_eq(board[1].theme_state.get("rank", 0), 1, "target rank +1")


func test_academy_star1_bonus_train_1() -> void:
	## ★1: bonus_train=1, growth=0
	var board: Array = [CardInstance.create("ml_academy"), CardInstance.create("ml_barracks")]
	var atk_before: float = board[1].get_total_atk()
	var event: Dictionary = _make_train_event(1, 1)
	_sys.process_event_card(board[0], 0, board, event, _rng)
	# ★1: growth=0 → ATK 불변, rank만 +1
	assert_almost_eq(board[1].get_total_atk(), atk_before, 0.01, "★1: ATK 불변")


# ================================================================
# ml_factory (OE): 징집 카운터 10마다 terazin
# ================================================================

func test_factory_counter_increments() -> void:
	var card: CardInstance = CardInstance.create("ml_factory")
	var event: Dictionary = _make_conscript_event(0, 0)
	_sys.process_event_card(card, 0, [card], event, _rng)
	assert_eq(card.theme_state.get("conscript_counter", 0), 1, "counter=1")


func test_factory_at_10_gives_terazin() -> void:
	var card: CardInstance = CardInstance.create("ml_factory")
	card.theme_state["conscript_counter"] = 9
	var event: Dictionary = _make_conscript_event(0, 0)
	var result: Dictionary = _sys.process_event_card(card, 0, [card], event, _rng)
	assert_eq(result["terazin"], 1, "counter 9→10 → terazin=1")
	assert_eq(card.theme_state.get("conscript_counter", 0), 0, "counter reset")


# ================================================================
# ml_command: apply_persistent → revive 설정
# ================================================================

func test_command_sets_revive_hp_50pct() -> void:
	var card: CardInstance = CardInstance.create("ml_command")
	_sys.apply_persistent(card)
	assert_almost_eq(card.theme_state.get("revive_hp_pct", 0.0), 0.50, 0.001, "revive_hp=0.50")


# ================================================================
# ml_barracks threshold: rank5→plasma, rank8→walker
# ================================================================

func test_barracks_rank5_adds_plasma() -> void:
	var card: CardInstance = CardInstance.create("ml_barracks")
	card.theme_state["rank"] = 4
	card.theme_state["rank_triggers"] = {3: true}
	var units_before: int = card.get_total_units()
	_sys.process_rs_card(card, 0, [card], _rng)
	# rank 4→5, threshold 5 → ml_plasma 1기 추가
	assert_eq(card.theme_state.get("rank", 0), 5, "rank=5")
	assert_eq(card.get_total_units(), units_before + 1, "plasma +1")


func test_barracks_rank8_adds_walker() -> void:
	var card: CardInstance = CardInstance.create("ml_barracks")
	card.theme_state["rank"] = 7
	card.theme_state["rank_triggers"] = {3: true, 5: true}
	var units_before: int = card.get_total_units()
	_sys.process_rs_card(card, 0, [card], _rng)
	# rank 7→8, threshold 8 → ml_walker 1기 추가
	assert_eq(card.theme_state.get("rank", 0), 8, "rank=8")
	assert_eq(card.get_total_units(), units_before + 1, "walker +1")


# ================================================================
# ml_conscript (OE): CONSCRIPT 이벤트 → target에 징집 추가
# ================================================================

func test_conscript_react_adds_unit_to_target() -> void:
	## ★1: event target에 1기 징집
	var board: Array = [CardInstance.create("ml_conscript"), CardInstance.create("ml_outpost")]
	var before: int = board[1].get_total_units()
	var event: Dictionary = _make_conscript_event(0, 1)
	_sys.process_event_card(board[0], 0, board, event, _rng)
	assert_eq(board[1].get_total_units(), before + 1, "target +1 징집")


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
# ml_tactical (BS): rank×2% shield + 총유닛×0.5% ATK
# ================================================================

func test_tactical_applies_shield_by_rank() -> void:
	## ★1: shield = rank * 2%
	var board: Array = [CardInstance.create("ml_tactical"), CardInstance.create("ml_barracks")]
	board[0].theme_state["rank"] = 5
	_sys.apply_battle_start(board[0], 0, board)
	assert_gt(board[0].shield_hp_pct, 0.0, "rank 5 → shield > 0")


func test_tactical_buffs_atk_by_total_units() -> void:
	## ★1: ATK buff = total_units * 0.5%
	var board: Array = [CardInstance.create("ml_tactical")]
	board[0].theme_state["rank"] = 1
	var atk_before: float = board[0].get_total_atk()
	_sys.apply_battle_start(board[0], 0, board)
	assert_gt(board[0].get_total_atk(), atk_before, "유닛 기반 ATK 버프")


# ================================================================
# ml_assault (BS): 총유닛×1% ATK + MS 보너스
# ================================================================

func test_assault_buffs_atk() -> void:
	## ★1: total_units * 1% ATK buff
	var card: CardInstance = CardInstance.create("ml_assault")
	var atk_before: float = card.get_total_atk()
	_sys.apply_battle_start(card, 0, [card])
	assert_gt(card.get_total_atk(), atk_before, "ATK 버프")


func test_assault_ms_bonus_below_threshold() -> void:
	## ★1: total_units >= 15 → ms_bonus=1. 초기 3유닛 → 미달
	var card: CardInstance = CardInstance.create("ml_assault")
	_sys.apply_battle_start(card, 0, [card])
	assert_eq(card.theme_state.get("ms_bonus", 0), 0, "3유닛 < 15 → ms 없음")


# ================================================================
# ml_special_ops (RS): train +1 self/adj + rank threshold → commander
# ================================================================

func test_special_ops_trains_self() -> void:
	var card: CardInstance = CardInstance.create("ml_special_ops")
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(card.theme_state.get("rank", 0), 1, "rank=1")


func test_special_ops_rank8_adds_commander() -> void:
	## ★1: rank≥8 → ml_commander 1기 추가
	var card: CardInstance = CardInstance.create("ml_special_ops")
	card.theme_state["rank"] = 7
	var units_before: int = card.get_total_units()
	_sys.process_rs_card(card, 0, [card], _rng)
	# rank 7→8, threshold 8 → ml_commander ×1
	assert_eq(card.theme_state.get("rank", 0), 8, "rank=8")
	assert_eq(card.get_total_units(), units_before + 1, "commander +1")


func _make_star(base_id: String, star: int) -> CardInstance:
	var card: CardInstance = CardInstance.create(base_id)
	for _i in star - 1:
		card.evolve_star()
	return card


# ================================================================
# ★2/★3 특수 작전대 (RS leader threshold)
# ================================================================

func test_special_ops_s2_leader_at_rank6() -> void:
	## ★2: rank≥6에서 leader (★1은 8)
	var card := _make_star("ml_special_ops", 2)
	card.theme_state["rank"] = 5
	card.theme_state["rank_triggers"] = {3: true}
	var units_before: int = card.get_total_units()
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(card.theme_state.get("rank", 0), 6, "rank=6")
	assert_eq(card.get_total_units(), units_before + 1, "★2 rank6 → commander +1")


func test_special_ops_s3_leader_at_rank5_x2() -> void:
	## ★3: rank≥5에서 leader 2기
	var card := _make_star("ml_special_ops", 3)
	card.theme_state["rank"] = 4
	card.theme_state["rank_triggers"] = {3: true}
	var units_before: int = card.get_total_units()
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(card.theme_state.get("rank", 0), 5, "rank=5")
	assert_eq(card.get_total_units(), units_before + 2, "★3 rank5 → commander ×2")


# ================================================================
# ★2/★3 군수 공장 (OE conscript counter)
# ================================================================

func test_factory_s2_threshold_8() -> void:
	## ★2: counter 8에서 발동 (★1은 10) + terazin 1 + ATK 3%
	var card := _make_star("ml_factory", 2)
	card.theme_state["conscript_counter"] = 7
	var atk_before: float = card.get_total_atk()
	var conscript_evt := {"layer1": -1, "layer2": Enums.Layer2.CONSCRIPT,
		"source_idx": 0, "target_idx": 0}
	var result: Dictionary = _sys.process_event_card(card, 0, [card], conscript_evt, _rng)
	assert_eq(result["terazin"], 1, "★2 counter 8 → terazin 1")
	assert_gt(card.get_total_atk(), atk_before, "★2 → ATK 3% enhance")


func test_factory_s3_threshold_6_terazin_2() -> void:
	## ★3: counter 6 + terazin 2 + ATK 5%
	var card := _make_star("ml_factory", 3)
	card.theme_state["conscript_counter"] = 5
	var atk_before: float = card.get_total_atk()
	var conscript_evt := {"layer1": -1, "layer2": Enums.Layer2.CONSCRIPT,
		"source_idx": 0, "target_idx": 0}
	var result: Dictionary = _sys.process_event_card(card, 0, [card], conscript_evt, _rng)
	assert_eq(result["terazin"], 2, "★3 counter 6 → terazin 2")
	assert_gt(card.get_total_atk(), atk_before, "★3 → ATK +5% enhance")


func test_factory_s1_no_enhance_at_10() -> void:
	## ★1: terazin만, enhance 없음
	var card: CardInstance = CardInstance.create("ml_factory")
	card.theme_state["conscript_counter"] = 9
	var atk_before: float = card.get_total_atk()
	var conscript_evt := {"layer1": -1, "layer2": Enums.Layer2.CONSCRIPT,
		"source_idx": 0, "target_idx": 0}
	var result: Dictionary = _sys.process_event_card(card, 0, [card], conscript_evt, _rng)
	assert_eq(result["terazin"], 1, "★1 counter 10 → terazin 1")
	assert_eq(card.get_total_atk(), atk_before, "★1 → enhance 없음")


# ================================================================
# ★2/★3 통합 사령부 (RS train + PERSISTENT revive)
# ================================================================

func test_command_s3_trains_2_per_ally() -> void:
	## ★3: amount=2 (★1/★2는 1)
	var card := _make_star("ml_command", 3)
	var ally: CardInstance = CardInstance.create("ml_barracks")
	var rank_before: int = ally.theme_state.get("rank", 0)
	_sys.process_rs_card(card, 0, [card, ally], _rng)
	assert_eq(ally.theme_state.get("rank", 0), rank_before + 2, "★3 train +2")


func test_command_s2_revive_hp_75() -> void:
	## ★2: revive HP 75% (★1은 50%)
	var card := _make_star("ml_command", 2)
	_sys.apply_persistent(card)
	assert_almost_eq(card.theme_state.get("revive_hp_pct", 0.0), 0.75, 0.001, "★2 revive HP 75%")


func test_command_s3_revive_limit_3_hp_100() -> void:
	## ★3: revive 3회, HP 100%
	var card := _make_star("ml_command", 3)
	_sys.apply_persistent(card)
	assert_almost_eq(card.theme_state.get("revive_hp_pct", 0.0), 1.0, 0.001, "★3 revive HP 100%")
	assert_eq(card.theme_state.get("revive_limit", 0), 3, "★3 revive 3회")


func test_command_s1_revive_limit_1_hp_50() -> void:
	## ★1: revive 1회, HP 50%
	var card: CardInstance = CardInstance.create("ml_command")
	_sys.apply_persistent(card)
	assert_almost_eq(card.theme_state.get("revive_hp_pct", 0.0), 0.50, 0.001, "★1 revive HP 50%")
	assert_eq(card.theme_state.get("revive_limit", 0), 1, "★1 revive 1회")
