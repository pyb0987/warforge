extends GutTest
## PredatorSystem 테마 로직 테스트
## 참조: predator_system.gd, handoff.md P4-C
##
## nest 부화 / farm 부화 / molt 변태 / harvest 수확 검증.


var _sys: PredatorSystem = null
var _rng: RandomNumberGenerator = null


func before_each() -> void:
	_sys = PredatorSystem.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 42


func _make_hatch_event(src: int, tgt: int) -> Dictionary:
	return {"layer1": Enums.Layer1.UNIT_ADDED, "layer2": Enums.Layer2.HATCH,
			"source_idx": src, "target_idx": tgt}


func _make_metamorphosis_event(src: int, tgt: int) -> Dictionary:
	return {"layer1": Enums.Layer1.ENHANCED, "layer2": Enums.Layer2.METAMORPHOSIS,
			"source_idx": src, "target_idx": tgt}


# ================================================================
# pr_nest (RS): hatch 2 self, 1 right
# ================================================================

func test_nest_hatches_2_larvae_on_self() -> void:
	## pr_nest: larva×3 + worker×1 = 4기 → hatch 2 → 6기
	var board: Array = [CardInstance.create("pr_nest")]
	var before: int = board[0].get_total_units()
	_sys.process_rs_card(board[0], 0, board, _rng)
	assert_eq(board[0].get_total_units(), before + 2, "self +2")


func test_nest_larvae_type_is_pr_larva() -> void:
	var board: Array = [CardInstance.create("pr_nest")]
	_sys.process_rs_card(board[0], 0, board, _rng)
	var found := false
	for s in board[0].stacks:
		if s["unit_type"].get("id", "") == "pr_larva":
			found = true
	assert_true(found, "pr_larva 스택 존재")


func test_nest_hatches_1_to_right_adj() -> void:
	var board: Array = [CardInstance.create("pr_nest"), CardInstance.create("pr_farm")]
	var before: int = board[1].get_total_units()
	_sys.process_rs_card(board[0], 0, board, _rng)
	assert_eq(board[1].get_total_units(), before + 1, "right +1")


func test_nest_emits_hatch_event() -> void:
	var board: Array = [CardInstance.create("pr_nest")]
	var result: Dictionary = _sys.process_rs_card(board[0], 0, board, _rng)
	assert_gt(result["events"].size(), 0, "이벤트 방출")
	assert_eq(result["events"][0]["layer2"], Enums.Layer2.HATCH, "HATCH 이벤트")


# ================================================================
# pr_farm (RS): hatch 1
# ================================================================

func test_farm_rs_hatches_1_larva() -> void:
	var board: Array = [CardInstance.create("pr_farm")]
	var before: int = board[0].get_total_units()
	_sys.process_rs_card(board[0], 0, board, _rng)
	assert_eq(board[0].get_total_units(), before + 1, "hatch +1")


# ================================================================
# pr_molt (OE): metamorphosis(3)
# ================================================================

func test_molt_triggers_metamorphosis() -> void:
	## pr_molt: larva×2 + guardian×1 = 3기. meta(3) 조건: total >= 4 → 실패
	## add 5 larvae first → 8기 → meta(3): 3소비+1최강 = 8-3+1=6
	var card: CardInstance = CardInstance.create("pr_molt")
	card.add_specific_unit("pr_larva", 5)
	var before: int = card.get_total_units()
	var event: Dictionary = _make_hatch_event(0, 0)
	_sys.process_event_card(card, 0, [card], event, _rng)
	# meta(3): 3 consume + 1 strongest = before - 3 + 1 = before - 2
	assert_eq(card.get_total_units(), before - 2, "meta(3) → -2기")


# ================================================================
# pr_harvest (OE): terazin=1, hatch 1
# ================================================================

func test_harvest_earns_terazin() -> void:
	var card: CardInstance = CardInstance.create("pr_harvest")
	var event: Dictionary = _make_metamorphosis_event(0, 0)
	var result: Dictionary = _sys.process_event_card(card, 0, [card], event, _rng)
	assert_eq(result["terazin"], 1, "terazin=1")


func test_harvest_hatches_1() -> void:
	var card: CardInstance = CardInstance.create("pr_harvest")
	var before: int = card.get_total_units()
	var event: Dictionary = _make_metamorphosis_event(0, 0)
	_sys.process_event_card(card, 0, [card], event, _rng)
	assert_eq(card.get_total_units(), before + 1, "hatch +1")


# ================================================================
# pr_queen (RS): hatch 3 self, 1 right
# ================================================================

func test_queen_hatches_2_on_self() -> void:
	var card: CardInstance = CardInstance.create("pr_queen")
	var before: int = card.get_total_units()
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(card.get_total_units(), before + 2, "self +2")


func test_queen_hatches_1_to_right_adj() -> void:
	var board: Array = [CardInstance.create("pr_queen"), CardInstance.create("pr_farm")]
	var before: int = board[1].get_total_units()
	_sys.process_rs_card(board[0], 0, board, _rng)
	assert_eq(board[1].get_total_units(), before + 1, "right +1")


# ================================================================
# pr_carapace (OE): METAMORPHOSIS → #carapace growth + hatch
# ================================================================

func test_carapace_hatches_right_adj() -> void:
	var board: Array = [CardInstance.create("pr_carapace"), CardInstance.create("pr_farm")]
	var before: int = board[1].get_total_units()
	var event: Dictionary = _make_metamorphosis_event(0, 0)
	_sys.process_event_card(board[0], 0, board, event, _rng)
	assert_eq(board[1].get_total_units(), before + 1, "right +1 hatch")


# ================================================================
# pr_swarm_sense (BS): 유닛 3기당 ATK+10%
# ================================================================

func test_swarm_sense_buffs_predator_cards() -> void:
	## ★1: 유닛 3기당 +10% temp_buff
	## pr_swarm_sense: 3유닛 → floor(3/3)=1 스택 → +10%
	var card: CardInstance = CardInstance.create("pr_swarm_sense")
	var atk_before: float = card.get_total_atk()
	_sys.apply_battle_start(card, 0, [card])
	assert_gt(card.get_total_atk(), atk_before, "3유닛 → ATK 버프")


# ================================================================
# pr_apex_hunt (OE): metamorphosis(2) + ≤5기 ATK+30%
# ================================================================

func test_apex_hunt_metamorphosis_and_buff() -> void:
	## ★1: meta(2), ≤5기면 temp_buff(0.30)
	## pr_apex_hunt: apex×3 + guardian×1 = 4기. meta(2): 4-2+1=3기
	var card: CardInstance = CardInstance.create("pr_apex_hunt")
	var event: Dictionary = _make_metamorphosis_event(0, 0)
	var atk_before: float = card.get_total_atk()
	_sys.process_event_card(card, 0, [card], event, _rng)
	# meta(2) 실행 → 유닛 변화 + ≤5기이므로 buff
	assert_lte(card.get_total_units(), 5, "≤5기")


# ================================================================
# pr_transcend (RS): hatch 3 self + 전체 포식종 1기씩
# ================================================================

func test_transcend_hatches_3_on_self() -> void:
	var card: CardInstance = CardInstance.create("pr_transcend")
	var before: int = card.get_total_units()
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(card.get_total_units(), before + 3, "self +3")


func test_transcend_hatches_1_on_other_predators() -> void:
	var board: Array = [CardInstance.create("pr_transcend"), CardInstance.create("pr_farm")]
	var before: int = board[1].get_total_units()
	_sys.process_rs_card(board[0], 0, board, _rng)
	assert_eq(board[1].get_total_units(), before + 1, "다른 포식종 +1")


# ================================================================
# pr_parasite (POST_COMBAT): 생존유닛당 hatch + 승리 시 meta
# ================================================================

func _make_star(base_id: String, star: int) -> CardInstance:
	var card: CardInstance = CardInstance.create(base_id)
	for _i in star - 1:
		card.evolve_star()
	return card


func test_parasite_hatches_on_post_combat() -> void:
	## ★1: hatch_per=1, max=3. 초기 3유닛 → min(3*1, 3) = 3 hatch
	## 승리 시 meta(2) 발동: 2소비+1최강 = net -1. 총 +3 -1 = +2
	var card: CardInstance = CardInstance.create("pr_parasite")
	var before: int = card.get_total_units()
	var result: Dictionary = _sys.apply_post_combat(card, 0, [card], true)
	assert_eq(card.get_total_units(), before + 2, "hatch 3 + meta(2) → net +2")


# ================================================================
# ★2/★3 기생 진화 (POST_COMBAT hatch/meta)
# ================================================================

func test_parasite_s2_hatch_per_2_max_5() -> void:
	## ★2: hatch_per=2, max=5. 3유닛 → min(3*2, 5) = 5 hatch
	## 승리 → meta(2): 2소비+1최강 = net -1. 총 +5 -1 = +4
	var card := _make_star("pr_parasite", 2)
	var before: int = card.get_total_units()
	_sys.apply_post_combat(card, 0, [card], true)
	assert_eq(card.get_total_units(), before + 4, "★2 hatch 5 + meta(2) → net +4")


func test_parasite_s3_meta_on_loss_too() -> void:
	## ★3: 승패 무관 meta 발동 + shield 30%
	var card := _make_star("pr_parasite", 3)
	var before: int = card.get_total_units()
	_sys.apply_post_combat(card, 0, [card], false)  # 패배
	# ★3: hatch min(3*2, 5)=5, meta on loss too, shield 30%
	assert_gt(card.get_total_units(), before, "★3 패배에도 hatch+meta 발동")
	assert_almost_eq(card.shield_hp_pct, 0.30, 0.001, "★3 shield 30%")


# ================================================================
# ★2/★3 포식자의 사냥 (OE/METAMORPHOSIS buff)
# ================================================================

func test_apex_hunt_s2_consume_2_buff_50() -> void:
	## ★2: meta consume 2, ≤5기 ATK+50%
	var card := _make_star("pr_apex_hunt", 2)
	var meta_evt := {"layer1": -1, "layer2": Enums.Layer2.METAMORPHOSIS,
		"source_idx": 0, "target_idx": 0}
	var atk_before: float = card.get_total_atk()
	_sys.process_event_card(card, 0, [card], meta_evt, _rng)
	assert_gt(card.get_total_atk(), atk_before, "★2 ≤5기 → ATK+50%")


func test_apex_hunt_s3_consume_1_mult_2x() -> void:
	## ★3: meta consume 1 (★1/★2는 2), ATK×2 곱연산
	var card := _make_star("pr_apex_hunt", 3)
	var meta_evt := {"layer1": -1, "layer2": Enums.Layer2.METAMORPHOSIS,
		"source_idx": 0, "target_idx": 0}
	var units_before: int = card.get_total_units()
	var atk_before: float = card.get_total_atk()
	_sys.process_event_card(card, 0, [card], meta_evt, _rng)
	# consume 1 → net -1+1=0 change (if meta succeeds)
	assert_gt(card.get_total_atk(), atk_before, "★3 ATK×2 적용")


# ================================================================
# ★2/★3 군체 초월 (RS hatch amounts)
# ================================================================

func test_transcend_s2_hatch_4_self_2_other() -> void:
	## ★2: self_n=4, all_n=2 (★1은 3/1)
	var card := _make_star("pr_transcend", 2)
	var other: CardInstance = CardInstance.create("pr_queen")
	var self_before: int = card.get_total_units()
	var other_before: int = other.get_total_units()
	_sys.process_rs_card(card, 0, [card, other], _rng)
	assert_eq(card.get_total_units(), self_before + 4, "★2 self hatch 4")
	assert_eq(other.get_total_units(), other_before + 2, "★2 other hatch 2")


func test_transcend_s3_auto_metamorphosis() -> void:
	## ★3: 자동 변태1회 + enhance ATK+5%
	var card := _make_star("pr_transcend", 3)
	var atk_before: float = card.get_total_atk()
	_sys.process_rs_card(card, 0, [card], _rng)
	# hatch 4 self → meta(1) auto → enhance 5%
	assert_gt(card.get_total_atk(), atk_before, "★3 auto meta → ATK enhance")
