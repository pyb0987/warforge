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
# pr_apex_hunt 2026-04-21 재설계:
#   RS (non-primary timing): 자체 meta_consume(1, net 0) → MT 이벤트 방출.
#     이 MT 는 다른 카드의 OE 는 트리거하지만, 자기 OE 는 require_other 로 차단.
#   OE (primary, listen MT, require_other: true): 다른 카드의 MT 에만 반응.
#     조건 없이 buff + meta_consume(★별). 자기 MT 체인으로 max_act 자동 소진
#     되는 기존 문제 해결.
# ================================================================

func test_apex_hunt_oe_unconditional_buff_from_other_card() -> void:
	## ★1 OE: 다른 카드의 MT 이벤트 (source_idx != self) 시 무조건 buff + meta(2).
	var card: CardInstance = CardInstance.create("pr_apex_hunt")
	# source_idx=1 → 다른 카드가 방출한 MT
	var event: Dictionary = _make_metamorphosis_event(1, 0)
	var atk_before: float = card.get_total_atk()
	_sys.process_event_card(card, 0, [card], event, _rng)
	assert_gt(card.get_total_atk(), atk_before, "OE 반응 시 buff 적용 (조건 없음)")
	assert_eq(card.get_total_units(), 3, "meta(2) 성공: 4-2+1=3기")


func test_apex_hunt_oe_has_require_other_flag() -> void:
	## OE 블록의 require_other_card flag 가 true 여야 chain_engine 에서
	## 자기 MT 이벤트를 스킵함. YAML → 템플릿 흐름 검증.
	var card: CardInstance = CardInstance.create("pr_apex_hunt")
	var oe_block: Dictionary = {}
	for block in card.template.get("effects", []):
		if block.get("trigger_timing", -1) == Enums.TriggerTiming.ON_EVENT:
			oe_block = block
			break
	assert_false(oe_block.is_empty(), "OE 블록 존재")
	assert_true(oe_block.get("require_other_card", false),
		"OE require_other_card=true (자기 MT 스킵용)")


func test_apex_hunt_rs_self_fires_meta() -> void:
	## RS: consume=1 자체 meta → MT 이벤트 방출. 유닛 net 0 (1-1+1=4).
	var card: CardInstance = CardInstance.create("pr_apex_hunt")
	var units_before: int = card.get_total_units()
	var result: Dictionary = _sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(card.get_total_units(), units_before,
		"RS consume=1: 1기 소모 + 1기 추가 → net 0 (4기 유지)")
	assert_eq(result["events"].size(), 1, "MT 이벤트 1건 방출")
	assert_eq(result["events"][0]["layer2"], Enums.Layer2.METAMORPHOSIS,
		"이벤트 layer2 = MT")


func test_apex_hunt_rs_unit_shortage_no_op() -> void:
	## 유닛 1기뿐이면 metamorphosis 실패 (need consume+1=2). 이벤트 미방출.
	var card: CardInstance = CardInstance.create("pr_apex_hunt")
	# comp 초기화 후 유닛 대부분 제거 — stacks 직접 조작.
	while card.get_total_units() > 1:
		card.remove_weakest(1)
	var result: Dictionary = _sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(result["events"].size(), 0, "유닛 부족 시 MT 이벤트 방출 안됨")


# ================================================================
# pr_transcend (2026-04-21 개편): RS 부화 완전 제거, PERSISTENT 제거.
# 다른 카드의 HA/MT 이벤트 OE 반응 + 반응 시 본카드 ATK +3% 영구 성장.
# ================================================================

func test_transcend_no_rs_effect() -> void:
	## RS 핸들러 제거. process_rs_card 호출해도 아무 변화 없어야.
	var card: CardInstance = CardInstance.create("pr_transcend")
	var board: Array = [card, CardInstance.create("pr_farm")]
	var self_before: int = card.get_total_units()
	var other_before: int = board[1].get_total_units()
	_sys.process_rs_card(card, 0, board, _rng)
	assert_eq(card.get_total_units(), self_before, "RS → self 변화 없음")
	assert_eq(board[1].get_total_units(), other_before, "RS → 다른 카드 변화 없음")


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
	## 승리 → meta(2) × 2회: (2소비+1최강) × 2 = net -2. 총 +5 -2 = +3
	## 변태 성공 시 HP +15% 성장
	var card := _make_star("pr_parasite", 2)
	var before: int = card.get_total_units()
	_sys.apply_post_combat(card, 0, [card], true)
	assert_eq(card.get_total_units(), before + 3, "★2 hatch 5 + meta(2)×2 → net +3")
	assert_almost_eq(card.growth_hp_pct, 0.15, 0.001, "★2 승리 시 HP +15% 성장")


func test_parasite_s3_meta_on_loss_too() -> void:
	## ★3: 승패 무관 meta 1기 소모 × 2회 + HP +20% 성장 + shield 30%
	var card := _make_star("pr_parasite", 3)
	var before: int = card.get_total_units()
	_sys.apply_post_combat(card, 0, [card], false)  # 패배
	# ★3: hatch min(3*2, 5)=5, meta(1)×2 = net 0, 총 +5. HP +20%. shield 30%
	assert_eq(card.get_total_units(), before + 5, "★3 hatch 5 + meta(1)×2 → net +5")
	assert_almost_eq(card.growth_hp_pct, 0.20, 0.001, "★3 패배에도 HP +20% 성장")
	assert_almost_eq(card.shield_hp_pct, 0.30, 0.001, "★3 shield 30%")


# ================================================================
# ★2/★3 포식자의 사냥 (OE/METAMORPHOSIS buff)
# ================================================================

func test_apex_hunt_s2_consume_2_buff_50() -> void:
	## ★2 OE: 다른 카드 MT 시 meta consume 2, ATK+50% 무조건.
	var card := _make_star("pr_apex_hunt", 2)
	var meta_evt := {"layer1": -1, "layer2": Enums.Layer2.METAMORPHOSIS,
		"source_idx": 1, "target_idx": 0}
	var atk_before: float = card.get_total_atk()
	_sys.process_event_card(card, 0, [card], meta_evt, _rng)
	assert_gt(card.get_total_atk(), atk_before, "★2 ATK+50% (조건 없음)")


func test_apex_hunt_s3_consume_1_mult_2x() -> void:
	## ★3 OE: 다른 카드 MT 시 meta consume 1 (★1/★2는 2), ATK×2 곱연산 무조건.
	var card := _make_star("pr_apex_hunt", 3)
	var meta_evt := {"layer1": -1, "layer2": Enums.Layer2.METAMORPHOSIS,
		"source_idx": 1, "target_idx": 0}
	var units_before: int = card.get_total_units()
	var atk_before: float = card.get_total_atk()
	_sys.process_event_card(card, 0, [card], meta_evt, _rng)
	# consume 1 → net -1+1=0 유지
	assert_eq(card.get_total_units(), units_before,
		"★3 OE consume=1: net 0 유지")
	assert_gt(card.get_total_atk(), atk_before, "★3 ATK×2 적용")


func test_apex_hunt_s3_rs_still_consume_1() -> void:
	## ★3 RS: 모든 ★에서 RS consume=1 통일 (★별 변화 없음).
	var card := _make_star("pr_apex_hunt", 3)
	var units_before: int = card.get_total_units()
	var result: Dictionary = _sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(card.get_total_units(), units_before, "★3 RS consume=1: net 0")
	assert_eq(result["events"].size(), 1, "★3 RS MT 이벤트 방출")


# ================================================================
# ★2/★3 군체 초월 (RS hatch amounts)
# ================================================================

## (구 ★2/★3 RS 테스트 제거 — RS 효과 자체가 사라짐)


# ================================================================
# pr_transcend OE 반응 (2026-04-21 신규):
# 다른 포식종의 HA / MT 이벤트 시 본카드에 부화 / 변태 반영
# ================================================================

func test_transcend_s1_oe_hatch_reaction() -> void:
	## ★1: 다른 포식종의 HATCH 이벤트 → 본카드 self +1기.
	var card: CardInstance = CardInstance.create("pr_transcend")
	var before: int = card.get_total_units()
	var event := {"layer1": Enums.Layer1.UNIT_ADDED,
		"layer2": Enums.Layer2.HATCH,
		"source_idx": 1, "target_idx": 0}
	_sys.process_event_card(card, 0, [card], event, _rng)
	assert_eq(card.get_total_units(), before + 1,
		"★1 HA 이벤트 → self hatch 1기")


func test_transcend_s1_oe_meta_reaction() -> void:
	## ★1: 다른 포식종의 METAMORPHOSIS 이벤트 → 본카드 변태 1회.
	## metamorphosis(consume:1) = 약자 1 제거 + 강자 1 추가 = net 0.
	var card: CardInstance = CardInstance.create("pr_transcend")
	var before: int = card.get_total_units()
	var event := {"layer1": Enums.Layer1.ENHANCED,
		"layer2": Enums.Layer2.METAMORPHOSIS,
		"source_idx": 1, "target_idx": 0}
	_sys.process_event_card(card, 0, [card], event, _rng)
	assert_eq(card.get_total_units(), before,
		"★1 MT 이벤트 → 변태 1회 (net 0)")


func test_transcend_s3_oe_hatch_count_2() -> void:
	## ★3: HA 반응으로 self +2기.
	var card := _make_star("pr_transcend", 3)
	var before: int = card.get_total_units()
	var event := {"layer1": Enums.Layer1.UNIT_ADDED,
		"layer2": Enums.Layer2.HATCH,
		"source_idx": 1, "target_idx": 0}
	_sys.process_event_card(card, 0, [card], event, _rng)
	assert_eq(card.get_total_units(), before + 2,
		"★3 HA 이벤트 → self hatch 2기")


func test_transcend_s3_oe_meta_count_2() -> void:
	## ★3: MT 반응으로 변태 2회 (consume:1 × count:2). net 0.
	var card := _make_star("pr_transcend", 3)
	var before: int = card.get_total_units()
	var event := {"layer1": Enums.Layer1.ENHANCED,
		"layer2": Enums.Layer2.METAMORPHOSIS,
		"source_idx": 1, "target_idx": 0}
	_sys.process_event_card(card, 0, [card], event, _rng)
	assert_eq(card.get_total_units(), before,
		"★3 MT 이벤트 → 변태 2회 (net 0)")


func test_transcend_oe_ha_grows_atk_3pct() -> void:
	## HA 반응 → 본카드 ATK +3% 영구 성장.
	var card: CardInstance = CardInstance.create("pr_transcend")
	var event := {"layer1": Enums.Layer1.UNIT_ADDED,
		"layer2": Enums.Layer2.HATCH,
		"source_idx": 1, "target_idx": 0}
	_sys.process_event_card(card, 0, [card], event, _rng)
	assert_almost_eq(card.growth_atk_pct, 0.03, 0.001,
		"HA 반응 1회 → growth_atk_pct = 0.03")


func test_transcend_oe_mt_grows_atk_3pct() -> void:
	## MT 반응 → 본카드 ATK +3% 영구 성장 (블록 1회 발동당 +3%,
	## 변태 횟수와 무관).
	var card: CardInstance = CardInstance.create("pr_transcend")
	var event := {"layer1": Enums.Layer1.ENHANCED,
		"layer2": Enums.Layer2.METAMORPHOSIS,
		"source_idx": 1, "target_idx": 0}
	_sys.process_event_card(card, 0, [card], event, _rng)
	assert_almost_eq(card.growth_atk_pct, 0.03, 0.001,
		"MT 반응 1회 → growth_atk_pct = 0.03")


func test_transcend_oe_stacks_growth_across_events() -> void:
	## HA + HA + MT = 총 3회 발동 → +9% 누적 (0.03 × 3).
	var card: CardInstance = CardInstance.create("pr_transcend")
	var ha_event := {"layer1": Enums.Layer1.UNIT_ADDED,
		"layer2": Enums.Layer2.HATCH,
		"source_idx": 1, "target_idx": 0}
	var mt_event := {"layer1": Enums.Layer1.ENHANCED,
		"layer2": Enums.Layer2.METAMORPHOSIS,
		"source_idx": 1, "target_idx": 0}
	_sys.process_event_card(card, 0, [card], ha_event, _rng)
	_sys.process_event_card(card, 0, [card], ha_event, _rng)
	_sys.process_event_card(card, 0, [card], mt_event, _rng)
	assert_almost_eq(card.growth_atk_pct, 0.09, 0.001,
		"HA+HA+MT → 누적 0.09")
