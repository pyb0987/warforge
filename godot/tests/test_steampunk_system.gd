extends GutTest
## SteampunkSystem 테마 로직 테스트
## 참조: steampunk_system.gd, handoff.md P4-B
##
## charger 카운터 / warmachine 사거리 / arsenal 흡수 검증.


var _sys: SteampunkSystem = null
var _rng: RandomNumberGenerator = null


func before_each() -> void:
	_sys = SteampunkSystem.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 42


func _make_manufacture_event() -> Dictionary:
	return {"layer1": Enums.Layer1.UNIT_ADDED, "layer2": Enums.Layer2.MANUFACTURE,
			"source_idx": 0, "target_idx": 0}


# ================================================================
# sp_charger: 제조 카운터 10마다 terazin+1 + enhance(0.05)
# ================================================================

func test_charger_counter_increments() -> void:
	var card: CardInstance = CardInstance.create("sp_charger")
	_sys.process_event_card(card, 0, [card], _make_manufacture_event(), _rng)
	assert_eq(card.theme_state.get("manufacture_counter", 0), 1, "counter 0→1")


func test_charger_below_10_no_terazin() -> void:
	var card: CardInstance = CardInstance.create("sp_charger")
	var result: Dictionary = _sys.process_event_card(card, 0, [card], _make_manufacture_event(), _rng)
	assert_eq(result["terazin"], 0, "counter=1 → terazin=0")


func test_charger_at_10_gives_terazin() -> void:
	var card: CardInstance = CardInstance.create("sp_charger")
	card.theme_state["manufacture_counter"] = 9
	var result: Dictionary = _sys.process_event_card(card, 0, [card], _make_manufacture_event(), _rng)
	assert_eq(result["terazin"], 1, "counter 9→10 → terazin=1")
	assert_eq(card.theme_state.get("manufacture_counter", -1), 0, "counter reset to 0")


func test_charger_at_10_also_enhances_atk() -> void:
	var card: CardInstance = CardInstance.create("sp_charger")
	card.theme_state["manufacture_counter"] = 9
	var atk_before: float = card.get_total_atk()
	_sys.process_event_card(card, 0, [card], _make_manufacture_event(), _rng)
	assert_gt(card.get_total_atk(), atk_before, "enhance(0.05) → ATK 증가")


# ================================================================
# sp_warmachine: apply_persistent → #firearm 수 / 8 = range_bonus
# ================================================================

func test_warmachine_low_firearm_count_range_0() -> void:
	## sp_warmachine: turret×1 + cannon×1 + drone×2 = 4유닛, firearm: turret(1)+cannon(1)=2
	var card: CardInstance = CardInstance.create("sp_warmachine")
	_sys.apply_persistent(card)
	assert_eq(card.theme_state.get("range_bonus", -1), 0, "firearm 2 < 8 → range_bonus=0")


func test_warmachine_range_bonus_calculation() -> void:
	var card: CardInstance = CardInstance.create("sp_warmachine")
	# turret은 firearm 태그. 기존 turret 1 + 추가 6 = 7 + cannon 1 = firearm 8
	card.add_specific_unit("sp_turret", 6)
	_sys.apply_persistent(card)
	assert_eq(card.theme_state.get("range_bonus", -1), 1, "firearm 8 → range_bonus=1")


# ================================================================
# sp_arsenal: on_sell_trigger → 최강 유닛 3기 흡수
# ================================================================

func test_arsenal_absorbs_3_strongest_units() -> void:
	var arsenal: CardInstance = CardInstance.create("sp_arsenal")
	var sold: CardInstance = CardInstance.create("sp_assembly")
	sold.attach_upgrade("C1")
	var before: int = arsenal.get_total_units()
	_sys.on_sell_trigger(arsenal, sold)
	assert_eq(arsenal.get_total_units(), before + 3, "3기 흡수")


func test_arsenal_ignores_non_steampunk_sold() -> void:
	var arsenal: CardInstance = CardInstance.create("sp_arsenal")
	var sold: CardInstance = CardInstance.create("dr_cradle")
	var before: int = arsenal.get_total_units()
	_sys.on_sell_trigger(arsenal, sold)
	assert_eq(arsenal.get_total_units(), before, "비스팀펑크 → 무시")


func test_arsenal_absorbed_unit_is_highest_cp() -> void:
	## sp_assembly 최강: sp_sawblade(CP=160) vs sp_spider(80) vs sp_rat(60)
	var arsenal: CardInstance = CardInstance.create("sp_arsenal")
	var sold: CardInstance = CardInstance.create("sp_assembly")
	sold.attach_upgrade("C1")
	_sys.on_sell_trigger(arsenal, sold)
	var found := false
	for s in arsenal.stacks:
		if s["unit_type"].get("id", "") == "sp_sawblade":
			found = true
	assert_true(found, "흡수된 유닛 = sp_sawblade(최강 CP)")


# ================================================================
# process_rs_card → steampunk RS는 generic effects 사용
# ================================================================

func test_process_rs_card_returns_empty() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	var result: Dictionary = _sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(result["events"].size(), 0, "events 없음")
	assert_eq(result["gold"], 0, "gold=0")
	assert_eq(result["terazin"], 0, "terazin=0")


# ================================================================
# sp_furnace: RS generic — spawn self + enhance self 3%
# ================================================================

func test_furnace_spawns_self_via_chain() -> void:
	var engine := ChainEngine.new()
	engine.set_seed(42)
	var board: Array = [CardInstance.create("sp_furnace")]
	var units_before: int = board[0].get_total_units()
	engine.run_growth_chain(board)
	assert_gt(board[0].get_total_units(), units_before, "RS → self spawn")


func test_furnace_enhances_self_via_chain() -> void:
	var engine := ChainEngine.new()
	engine.set_seed(42)
	var board: Array = [CardInstance.create("sp_furnace")]
	var atk_before: float = board[0].get_total_atk()
	engine.run_growth_chain(board)
	assert_gt(board[0].get_total_atk(), atk_before, "RS → self enhance 3%")


func test_furnace_emits_manufacture_event() -> void:
	## sp_furnace spawn → MANUFACTURE 이벤트 → sp_workshop 반응 가능
	var engine := ChainEngine.new()
	engine.set_seed(42)
	var board: Array = [CardInstance.create("sp_furnace"), CardInstance.create("sp_workshop")]
	var result: Dictionary = engine.run_growth_chain(board)
	assert_gte(result["chain_count"], 2, "furnace MF 이벤트 → workshop 반응")


# ================================================================
# sp_circulator: OE(UPGRADE) — spawn event_target
# ================================================================

func test_circulator_reacts_to_upgrade_event() -> void:
	## sp_workshop 이 UPGRADE 이벤트 방출 → sp_circulator 반응
	## 배치: [sp_assembly, sp_workshop, sp_circulator]
	## assembly RS → MF → workshop OE → UPGRADE 이벤트 → circulator 반응
	var engine := ChainEngine.new()
	engine.set_seed(42)
	var board: Array = [
		CardInstance.create("sp_assembly"),
		CardInstance.create("sp_workshop"),
		CardInstance.create("sp_circulator")
	]
	var result: Dictionary = engine.run_growth_chain(board)
	# assembly(RS) → workshop(OE/MF) → circulator(OE/UP) = 최소 3 chain
	assert_gte(result["chain_count"], 3, "assembly→workshop→circulator 3단 체인")


func test_circulator_max_1_activation() -> void:
	## sp_circulator max_act=1
	var engine := ChainEngine.new()
	engine.set_seed(42)
	var board: Array = [
		CardInstance.create("sp_assembly"),
		CardInstance.create("sp_assembly"),
		CardInstance.create("sp_workshop"),
		CardInstance.create("sp_circulator")
	]
	engine.run_growth_chain(board)
	assert_eq(board[3].activations_used, 1, "max_act=1 → 1회만")


# ================================================================
# sp_line: OE(MF, require_other=true) — spawn both_adj
# ================================================================

func test_line_spawns_both_adj_on_other_manufacture() -> void:
	## sp_assembly → MF → sp_line 반응 → both_adj spawn
	var engine := ChainEngine.new()
	engine.set_seed(42)
	var board: Array = [
		CardInstance.create("sp_assembly"),
		CardInstance.create("sp_line"),
		CardInstance.create("sp_assembly")
	]
	var left_before: int = board[0].get_total_units()
	var right_before: int = board[2].get_total_units()
	engine.run_growth_chain(board)
	# sp_line의 both_adj → board[0], board[2]에 spawn
	var total_grew: int = (board[0].get_total_units() - left_before) + (board[2].get_total_units() - right_before)
	assert_gt(total_grew, 0, "both_adj spawn 발동")


func test_line_does_not_react_to_own_events() -> void:
	## require_other=true → 자기 이벤트에 반응 안 함
	var engine := ChainEngine.new()
	engine.set_seed(42)
	var board: Array = [CardInstance.create("sp_line")]
	var result: Dictionary = engine.run_growth_chain(board)
	assert_eq(result["chain_count"], 0, "OE 단독 → chain 0")


# ================================================================
# sp_interest: ON_REROLL — growth chain 밖. 별도 시스템.
# ================================================================

func test_interest_not_in_growth_chain() -> void:
	## ON_REROLL 카드는 run_growth_chain에서 발동 안 함
	var engine := ChainEngine.new()
	engine.set_seed(42)
	var board: Array = [CardInstance.create("sp_interest")]
	var units_before: int = board[0].get_total_units()
	var result: Dictionary = engine.run_growth_chain(board)
	assert_eq(result["chain_count"], 0, "ON_REROLL → chain 0")
	assert_eq(board[0].get_total_units(), units_before, "유닛 불변")


# ================================================================
# sp_barrier: BS — growth chain 밖. game_manager에서 처리.
# ================================================================

func test_barrier_not_in_growth_chain() -> void:
	## BS 카드는 growth chain에서 발동 안 함
	var engine := ChainEngine.new()
	engine.set_seed(42)
	var board: Array = [CardInstance.create("sp_barrier")]
	var result: Dictionary = engine.run_growth_chain(board)
	assert_eq(result["chain_count"], 0, "BS → chain 0")
	assert_eq(board[0].shield_hp_pct, 0.0, "chain에서 shield 미적용")


# ================================================================
# ★2/★3 전쟁 기계 (PERSISTENT range_bonus)
# ================================================================

func _make_star(base_id: String, star: int) -> CardInstance:
	var card: CardInstance = CardInstance.create(base_id)
	for _i in star - 1:
		card.evolve_star()
	return card


func test_warmachine_s2_threshold_6() -> void:
	## ★2: 6기당 range+1 (★1은 8기당)
	var card := _make_star("sp_warmachine", 2)
	card.add_specific_unit("sp_turret", 4)  # turret 1+4=5, firearm total=5+cannon1=6
	_sys.apply_persistent(card)
	assert_eq(card.theme_state.get("range_bonus", -1), 1, "★2 firearm 6 → range+1")


func test_warmachine_s2_firearm_atk_buff() -> void:
	## ★2: #firearm ATK +30% temp_buff
	var card := _make_star("sp_warmachine", 2)
	var atk_before: float = card.get_total_atk()
	_sys.apply_persistent(card)
	assert_gt(card.get_total_atk(), atk_before, "★2 → firearm ATK +30% buff")


func test_warmachine_s1_no_firearm_buff() -> void:
	## ★1: firearm buff 없음
	var card := _make_star("sp_warmachine", 1)
	var atk_before: float = card.get_total_atk()
	_sys.apply_persistent(card)
	assert_eq(card.get_total_atk(), atk_before, "★1 → firearm buff 없음")


func test_warmachine_s3_threshold_4() -> void:
	## ★3: 4기당 range+1
	var card := _make_star("sp_warmachine", 3)
	# firearm: turret 1 + cannon 1 + 2 added = 4
	card.add_specific_unit("sp_turret", 2)
	_sys.apply_persistent(card)
	assert_eq(card.theme_state.get("range_bonus", -1), 1, "★3 firearm 4 → range+1")


# ================================================================
# ★2/★3 태엽 과급기 (OE counter threshold)
# ================================================================

func test_charger_s2_base_fires_at_10() -> void:
	## ★2: 기본 10-threshold 정상 발동 (★1과 동일)
	var card := _make_star("sp_charger", 2)
	card.theme_state["manufacture_counter"] = 9
	var result: Dictionary = _sys.process_event_card(card, 0, [card], _make_manufacture_event(), _rng)
	assert_eq(result["terazin"], 1, "★2 counter 9→10 → terazin=1")
	assert_eq(card.theme_state.get("manufacture_counter", -1), 0, "counter reset")


func test_charger_s2_rare_counter_increments() -> void:
	## ★2: rare_counter 별도 누적
	var card := _make_star("sp_charger", 2)
	_sys.process_event_card(card, 0, [card], _make_manufacture_event(), _rng)
	assert_eq(card.theme_state.get("rare_counter", 0), 1, "rare_counter 0→1")


func test_charger_s2_rare_at_20() -> void:
	## ★2: rare_counter 20 → pending_rare_upgrade
	var card := _make_star("sp_charger", 2)
	card.theme_state["rare_counter"] = 19
	_sys.process_event_card(card, 0, [card], _make_manufacture_event(), _rng)
	assert_true(card.theme_state.get("pending_rare_upgrade", false), "★2 rare 20 → pending")
	assert_eq(card.theme_state.get("rare_counter", -1), 0, "rare_counter reset")


func test_charger_s1_no_rare_counter() -> void:
	## ★1: rare_counter 없음
	var card := _make_star("sp_charger", 1)
	card.theme_state["manufacture_counter"] = 9
	_sys.process_event_card(card, 0, [card], _make_manufacture_event(), _rng)
	assert_false(card.theme_state.has("rare_counter"), "★1 → rare_counter 없음")


func test_charger_s3_base_fires_at_10() -> void:
	## ★3: 기본 10-threshold 정상 발동
	var card := _make_star("sp_charger", 3)
	card.theme_state["manufacture_counter"] = 9
	var result: Dictionary = _sys.process_event_card(card, 0, [card], _make_manufacture_event(), _rng)
	assert_eq(result["terazin"], 1, "★3 counter 9→10 → terazin=1")


func test_charger_s3_has_epic_counter() -> void:
	## ★3: epic_counter 15 → pending_epic_upgrade (rare→epic 승격)
	var card := _make_star("sp_charger", 3)
	card.theme_state["epic_counter"] = 14
	_sys.process_event_card(card, 0, [card], _make_manufacture_event(), _rng)
	assert_true(card.theme_state.get("pending_epic_upgrade", false), "★3 epic 15 → pending")
	assert_eq(card.theme_state.get("epic_counter", -1), 0, "epic_counter reset")


# ================================================================
# ★2/★3 제국 병기창 (ON_SELL absorb)
# ================================================================

func test_arsenal_s2_absorbs_5() -> void:
	## ★2: 5기 흡수 (★1은 3기)
	var arsenal := _make_star("sp_arsenal", 2)
	var sold: CardInstance = CardInstance.create("sp_assembly")
	sold.attach_upgrade("C1")
	var before: int = arsenal.get_total_units()
	_sys.on_sell_trigger(arsenal, sold)
	assert_eq(arsenal.get_total_units(), before + 5, "★2 5기 흡수")


func test_arsenal_s2_transfers_upgrades() -> void:
	## ★2: 판매 카드의 업그레이드를 병기창에 이전
	var arsenal := _make_star("sp_arsenal", 2)
	var sold: CardInstance = CardInstance.create("sp_assembly")
	sold.attach_upgrade("C1")
	sold.attach_upgrade("R1")
	var upg_before: int = arsenal.upgrades.size()
	_sys.on_sell_trigger(arsenal, sold)
	assert_eq(arsenal.upgrades.size(), upg_before + 2, "★2 업그레이드 2개 이전")


func test_arsenal_no_trigger_without_upgrade() -> void:
	## 업그레이드 없는 카드 판매 시 미발동
	var arsenal: CardInstance = CardInstance.create("sp_arsenal")
	var sold: CardInstance = CardInstance.create("sp_assembly")
	var before: int = arsenal.get_total_units()
	_sys.on_sell_trigger(arsenal, sold)
	assert_eq(arsenal.get_total_units(), before, "업그레이드 없으면 미발동")


func test_arsenal_s3_absorbs_7() -> void:
	## ★3: 7기 흡수
	var arsenal := _make_star("sp_arsenal", 3)
	var sold: CardInstance = CardInstance.create("sp_assembly")
	sold.attach_upgrade("C1")
	var before: int = arsenal.get_total_units()
	_sys.on_sell_trigger(arsenal, sold)
	assert_eq(arsenal.get_total_units(), before + 7, "★3 7기 흡수")


func test_arsenal_s3_majority_atk_bonus() -> void:
	## ★3: 최다유닛 타입 ATK +30%
	var arsenal := _make_star("sp_arsenal", 3)
	var sold: CardInstance = CardInstance.create("sp_assembly")
	sold.attach_upgrade("C1")
	var atk_before: float = arsenal.get_total_atk()
	_sys.on_sell_trigger(arsenal, sold)
	assert_gt(arsenal.get_total_atk(), atk_before, "★3 → majority ATK +30%")


# ================================================================
# ON_REROLL: sp_interest (chain_engine.process_reroll_triggers)
# ================================================================

func test_interest_spawns_on_reroll() -> void:
	## sp_interest: 리롤 시 self spawn 1
	var engine := ChainEngine.new()
	engine.set_seed(42)
	var board: Array = [CardInstance.create("sp_interest")]
	var units_before: int = board[0].get_total_units()
	engine.process_reroll_triggers(board)
	assert_eq(board[0].get_total_units(), units_before + 1, "리롤 → self +1 유닛")


func test_interest_enhances_on_reroll() -> void:
	## sp_interest: 리롤 시 self enhance 3%
	var engine := ChainEngine.new()
	engine.set_seed(42)
	var board: Array = [CardInstance.create("sp_interest")]
	var atk_before: float = board[0].get_total_atk()
	engine.process_reroll_triggers(board)
	assert_gt(board[0].get_total_atk(), atk_before, "리롤 → self ATK +3%")


func test_interest_max_3_activations() -> void:
	## max_act=3 → 3회까지만 발동
	var engine := ChainEngine.new()
	engine.set_seed(42)
	var board: Array = [CardInstance.create("sp_interest")]
	for _i in 3:
		engine.process_reroll_triggers(board)
	var units_after_3: int = board[0].get_total_units()
	engine.process_reroll_triggers(board)  # 4회째
	assert_eq(board[0].get_total_units(), units_after_3, "max_act=3 → 4회째 미발동")


func test_interest_no_event_emission() -> void:
	## output_layer=-1 → 이벤트 미방출 (체인 격리)
	var engine := ChainEngine.new()
	engine.set_seed(42)
	var board: Array = [CardInstance.create("sp_interest")]
	var result: Dictionary = engine.process_reroll_triggers(board)
	assert_eq(result["events"].size(), 0, "output_layer=-1 → 이벤트 없음")


func test_interest_ignores_non_reroll_cards() -> void:
	## RS 카드는 process_reroll_triggers에서 무시
	var engine := ChainEngine.new()
	engine.set_seed(42)
	var board: Array = [CardInstance.create("sp_assembly"), CardInstance.create("sp_interest")]
	var assembly_units: int = board[0].get_total_units()
	engine.process_reroll_triggers(board)
	assert_eq(board[0].get_total_units(), assembly_units, "RS 카드 미발동")
