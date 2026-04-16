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
# ml_conscript (T1 RS self 징집, 스왑 후 이전 _outpost 역할)
# ================================================================

func test_conscript_defers_self_conscription() -> void:
	var card: CardInstance = CardInstance.create("ml_conscript")
	var before: int = card.get_total_units()
	_sys.process_rs_card(card, 0, [card], _rng)
	# Self-conscription is deferred — units NOT added yet
	assert_eq(card.get_total_units(), before, "deferred: 유닛 미추가")
	assert_eq(_sys.pending_conscriptions.size(), 1, "pending 1건")
	assert_eq(_sys.pending_conscriptions[0]["count"], 2, "count=2")


func test_conscript_pending_has_card_ref() -> void:
	var card: CardInstance = CardInstance.create("ml_conscript")
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(_sys.pending_conscriptions[0]["card_ref"], card, "card_ref 일치")
	assert_eq(_sys.pending_conscriptions[0]["card_idx"], 0, "card_idx=0")


func test_conscript_star3_defers_3() -> void:
	var card: CardInstance = CardInstance.create("ml_conscript")
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
	var card: CardInstance = CardInstance.create("ml_conscript")
	var before: int = card.get_total_units()
	var added: int = _sys.apply_conscript(card, "ml_recruit")
	assert_eq(added, 1, "1기 추가")
	assert_eq(card.get_total_units(), before + 1, "총 유닛 +1")


func test_clear_pending() -> void:
	var card: CardInstance = CardInstance.create("ml_conscript")
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_gt(_sys.pending_conscriptions.size(), 0, "pending 있음")
	_sys.clear_pending()
	assert_eq(_sys.pending_conscriptions.size(), 0, "clear 후 비어있음")


# ================================================================
# ml_outpost (T2 OE 반응 증폭, 스왑 후 이전 _conscript_react 역할)
# ================================================================

func test_outpost_react_adds_unit_to_target() -> void:
	## ★1: CONSCRIPT 이벤트 감지 → event_target에 1기 징집 추가.
	var board: Array = [CardInstance.create("ml_outpost"), CardInstance.create("ml_conscript")]
	var before: int = board[1].get_total_units()
	var event: Dictionary = _make_conscript_event(0, 1)
	_sys.process_event_card(board[0], 0, board, event, _rng)
	assert_eq(board[1].get_total_units(), before + 1, "target +1 징집")


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
# ml_factory (OE): CONSCRIPT 카운터 누적, rewards 구조 변경 (terazin 제거)
# ================================================================

func test_factory_counter_increments() -> void:
	var card: CardInstance = CardInstance.create("ml_factory")
	var event: Dictionary = _make_conscript_event(0, 0)
	_sys.process_event_card(card, 0, [card], event, _rng)
	assert_eq(card.theme_state.get("conscript_counter", 0), 1, "counter=1")


func test_factory_at_10_resets_counter() -> void:
	## 재설계: terazin 제거, global_military_atk_pct 적용. counter는 리셋만 확인.
	var card: CardInstance = CardInstance.create("ml_factory")
	card.theme_state["conscript_counter"] = 9
	var event: Dictionary = _make_conscript_event(0, 0)
	var result: Dictionary = _sys.process_event_card(card, 0, [card], event, _rng)
	assert_eq(result["terazin"], 0, "재설계: terazin 지급 없음")
	assert_eq(card.theme_state.get("conscript_counter", 0), 0, "counter 리셋 (10→0)")


func test_factory_at_10_buffs_all_military_atk() -> void:
	## ★1: counter 10 → global_military_atk_pct 0.05 → 모든 군대 카드 ATK +5% 영구.
	var board: Array = [CardInstance.create("ml_factory"), CardInstance.create("ml_barracks")]
	board[0].theme_state["conscript_counter"] = 9
	var atk_before_board1: float = board[1].get_total_atk()
	var event: Dictionary = _make_conscript_event(0, 0)
	_sys.process_event_card(board[0], 0, board, event, _rng)
	assert_gt(board[1].get_total_atk(), atk_before_board1, "군대 카드 ATK 증가")


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

func test_assault_rs_spawns_biker() -> void:
	## ★1: 매 RS 바이커 1기 추가.
	var card: CardInstance = CardInstance.create("ml_assault")
	var before: int = card.get_total_units()
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(card.get_total_units(), before + 1, "★1: 바이커 +1")


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
# ml_command (RS + apply_persistent): train all + 부활 HP
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


func test_command_s1_revive_hp_25() -> void:
	## 재설계: ★1 revive HP 25% (기존 50% → 25%).
	var card: CardInstance = CardInstance.create("ml_command")
	_sys.apply_persistent(card)
	assert_almost_eq(card.theme_state.get("revive_hp_pct", 0.0), 0.25, 0.001, "★1: HP 25%")
	assert_eq(card.theme_state.get("revive_limit", 0), 1, "★1: 1회")


func test_command_s2_revive_hp_50() -> void:
	## 재설계: ★2 HP 50%.
	var card := _make_star("ml_command", 2)
	_sys.apply_persistent(card)
	assert_almost_eq(card.theme_state.get("revive_hp_pct", 0.0), 0.50, 0.001, "★2: HP 50%")
	assert_eq(card.theme_state.get("revive_limit", 0), 1, "★2: 1회")


func test_command_s3_revive_hp_100() -> void:
	## 재설계: ★3 HP 100%, limit 1 (기존 3회 → 1회).
	var card := _make_star("ml_command", 3)
	_sys.apply_persistent(card)
	assert_almost_eq(card.theme_state.get("revive_hp_pct", 0.0), 1.0, 0.001, "★3: HP 100%")
	assert_eq(card.theme_state.get("revive_limit", 0), 1, "★3: 1회 (on_revive 버프 제거)")


# ================================================================
# 공통 R4/R10: enhance_convert_card (모든 카드)
# ================================================================

func test_barracks_r4_converts_half_to_enhanced() -> void:
	## rank 4 도달 시 비(강화) 유닛 절반이 (강화)로 변환.
	## ml_barracks comp: 신병×2 보병×1 (총 3 비강화).
	var card: CardInstance = CardInstance.create("ml_barracks")
	card.theme_state["rank"] = 4
	# R4 효과는 r_conditional에서 매 실행 시 발동.
	_sys.process_rs_card(card, 0, [card], _rng)
	# 비(강화) 절반(floor 3*0.5=1) 변환. (강화) 유닛 1기 이상 존재해야 함.
	var has_enhanced := false
	for s in card.stacks:
		var ut_tags: PackedStringArray = s["unit_type"].get("tags", PackedStringArray())
		if "enhanced" in ut_tags:
			has_enhanced = true
			break
	assert_true(has_enhanced, "R4: (강화) 유닛 존재")


func test_barracks_r10_converts_all_to_enhanced() -> void:
	## rank 10 도달 시 모든 비(강화) 유닛이 (강화)로 변환.
	var card: CardInstance = CardInstance.create("ml_barracks")
	card.theme_state["rank"] = 10
	_sys.process_rs_card(card, 0, [card], _rng)
	# 전원 (강화) 또는 엘리트(변환 불가 유닛).
	for s in card.stacks:
		var ut_tags: PackedStringArray = s["unit_type"].get("tags", PackedStringArray())
		var uid: String = s["unit_type"].get("id", "")
		# ENHANCED_MAP에 있는 유닛만 변환 대상. 이 카드는 recruit/infantry로 모두 변환 가능.
		if MilitarySystem.ENHANCED_MAP.has(uid):
			assert_true(false, "R10: 변환 가능한 비(강화) 유닛이 남아있으면 안 됨 (%s)" % uid)
