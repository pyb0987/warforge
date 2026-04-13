extends GutTest
## 중립 카드 14장 개별 효과 테스트 (chain_engine 통합)
## 참조: card_db.gd _register_neutral, chain_engine.gd _execute_effects
##
## RS / OE / 인내(tenure) / 경제(gold/terazin) / diversity_gold 검증.


var _engine: ChainEngine = null


func before_each() -> void:
	_engine = ChainEngine.new()
	_engine.set_seed(42)


func _make_board(ids: Array) -> Array:
	var board: Array = []
	for id in ids:
		board.append(CardInstance.create(id))
	return board


# ================================================================
# ① RS 제조기 3장
# ================================================================

func test_earth_echo_spawns_right_adj() -> void:
	## ne_earth_echo(RS): spawn right_adj 1
	var board := _make_board(["ne_earth_echo", "sp_assembly"])
	var right_before: int = board[1].get_total_units()
	_engine.run_growth_chain(board)
	assert_gt(board[1].get_total_units(), right_before, "right adj +1 유닛")


func test_earth_echo_solo_no_spawn() -> void:
	## 단독 → right_adj 없음
	var board := _make_board(["ne_earth_echo"])
	var before: int = board[0].get_total_units()
	_engine.run_growth_chain(board)
	assert_eq(board[0].get_total_units(), before, "단독 → right 없어 유닛 불변")


func test_wild_pulse_enhances_self() -> void:
	## ne_wild_pulse(RS): enhance self 3%
	var board := _make_board(["ne_wild_pulse"])
	var atk_before: float = board[0].get_total_atk()
	_engine.run_growth_chain(board)
	assert_gt(board[0].get_total_atk(), atk_before, "self enhance → ATK 증가")


func test_ruin_resonance_spawn_and_enhance_self() -> void:
	## ne_ruin_resonance(RS): spawn self + enhance self 2%
	var board := _make_board(["ne_ruin_resonance"])
	var units_before: int = board[0].get_total_units()
	var atk_before: float = board[0].get_total_atk()
	_engine.run_growth_chain(board)
	assert_gt(board[0].get_total_units(), units_before, "self spawn → 유닛 증가")
	assert_gt(board[0].get_total_atk(), atk_before, "self enhance → ATK 증가")


# ================================================================
# ② 브릿지 2장 (OE)
# ================================================================

func test_wanderers_enhances_event_target_on_unit_added() -> void:
	## ne_wanderers(OE/UNIT_ADDED): enhance event_target 3%
	## sp_assembly(RS) spawn right_adj → wanderers에 UNIT_ADDED → wanderers가 event_target(assembly) enhance
	var board := _make_board(["sp_assembly", "ne_wanderers"])
	var wanderers_atk_before: float = board[1].get_total_atk()
	var result: Dictionary = _engine.run_growth_chain(board)
	assert_gte(result["chain_count"], 2, "RS + OE = 최소 2 chain")
	# wanderers가 event_target(=assembly spawn의 target=wanderers 자신)을 enhance
	# target_idx는 spawn의 대상(board[1])이므로 wanderers 자신이 enhance됨
	assert_gt(board[1].get_total_atk(), wanderers_atk_before, "wanderers event_target enhance → ATK 증가")


func test_wanderers_max_2_activations() -> void:
	## ne_wanderers max_act=2, RS카드 3장 → 2회만 반응
	var board := _make_board(["sp_assembly", "sp_assembly", "sp_assembly", "ne_wanderers"])
	_engine.run_growth_chain(board)
	assert_eq(board[3].activations_used, 2, "max_act=2 → 2회만")


func test_mutant_adapt_spawns_self_on_enhanced() -> void:
	## ne_mutant_adapt(OE/ENHANCED): spawn self
	## ne_wild_pulse(RS) → ENHANCED 이벤트 → mutant_adapt 반응
	var board := _make_board(["ne_wild_pulse", "ne_mutant_adapt"])
	var units_before: int = board[1].get_total_units()
	_engine.run_growth_chain(board)
	assert_gt(board[1].get_total_units(), units_before, "ENHANCED 이벤트 → self spawn")


# ================================================================
# ③ 증폭기 2장 (OE)
# ================================================================

func test_mana_crystal_spawns_both_adj_on_unit_added() -> void:
	## ne_mana_crystal(OE/UNIT_ADDED): spawn both_adj
	## 배치: [sp_assembly, ne_mana_crystal, sp_assembly]
	## assembly[0] RS → UNIT_ADDED → mana_crystal 반응 → both_adj spawn
	var board := _make_board(["sp_assembly", "ne_mana_crystal", "sp_assembly"])
	var left_before: int = board[0].get_total_units()
	var right_before: int = board[2].get_total_units()
	_engine.run_growth_chain(board)
	# mana_crystal의 both_adj → board[0]과 board[2]에 spawn
	var left_grew: bool = board[0].get_total_units() > left_before
	var right_grew: bool = board[2].get_total_units() > right_before
	assert_true(left_grew or right_grew, "both_adj 중 최소 한쪽에 spawn")


func test_ancient_catalyst_enhances_both_adj_on_enhanced() -> void:
	## ne_ancient_catalyst(OE/ENHANCED): enhance both_adj 2%
	## 배치: [ne_wild_pulse, ne_ancient_catalyst, sp_assembly]
	## wild_pulse RS → ENHANCED → catalyst 반응 → both_adj enhance
	var board := _make_board(["ne_wild_pulse", "ne_ancient_catalyst", "sp_assembly"])
	var pulse_atk_before: float = board[0].get_total_atk()
	var assembly_atk_before: float = board[2].get_total_atk()
	var result: Dictionary = _engine.run_growth_chain(board)
	assert_gte(result["chain_count"], 2, "RS + OE 반응")
	# catalyst의 both_adj = board[0], board[2] enhance
	var pulse_grew: bool = board[0].get_total_atk() > pulse_atk_before
	var assembly_grew: bool = board[2].get_total_atk() > assembly_atk_before
	assert_true(pulse_grew or assembly_grew, "both_adj 중 최소 한쪽 ATK 증가")


# ================================================================
# ⑤ 경제 3장
# ================================================================

func test_dim_merchant_diversity_gold_1_theme() -> void:
	## ne_dim_merchant(RS): diversity_gold, 보드에 1테마 → 1g
	var board := _make_board(["ne_dim_merchant"])
	var result: Dictionary = _engine.run_growth_chain(board)
	assert_eq(result["gold_earned"], 1, "1테마 → 1g")


func test_dim_merchant_diversity_gold_3_themes() -> void:
	## 보드에 3테마(neutral, steampunk, druid) → 3g
	var board := _make_board(["ne_dim_merchant", "sp_assembly", "dr_cradle"])
	var result: Dictionary = _engine.run_growth_chain(board)
	assert_gte(result["gold_earned"], 3, "3테마 → 최소 3g")


# ================================================================
# ⑦ 인내 2장 (tenure)
# ================================================================

func test_ruins_no_fire_before_tenure_2() -> void:
	## ne_ruins(RS, tenure=2): tenure < 2 → 미발동
	var board := _make_board(["ne_ruins", "sp_assembly"])
	var result: Dictionary = _engine.run_growth_chain(board)
	# 첫 라운드: tenure=0 → 미발동 (run_growth_chain이 tenure를 0→1로 증가시킴)
	# tenure 검사는 증가 전에 수행 → 첫 라운드 tenure=0 < 2 → 미발동
	assert_eq(result["gold_earned"], 0, "tenure 0 → 미발동 → gold 0")


func test_ruins_fires_at_tenure_2() -> void:
	## ne_ruins: tenure=2일 때 발동 → gold 2 + spawn right_adj
	var board := _make_board(["ne_ruins", "sp_assembly"])
	# 2라운드 시뮬
	_engine.run_growth_chain(board)  # R1: tenure 0→1, 미발동
	_engine.run_growth_chain(board)  # R2: tenure 1→2, >=2 발동
	var right_units: int = board[1].get_total_units()
	assert_gt(right_units, 2, "tenure 2 → right_adj spawn")


func test_ruins_fires_every_round_after_tenure() -> void:
	## tenure 달성 후 매 라운드 발동
	var board := _make_board(["ne_ruins", "sp_assembly"])
	_engine.run_growth_chain(board)  # R1
	_engine.run_growth_chain(board)  # R2: 발동
	var units_after_r2: int = board[1].get_total_units()
	_engine.run_growth_chain(board)  # R3: 다시 발동
	assert_gt(board[1].get_total_units(), units_after_r2, "tenure 후 매 라운드 발동")


func test_awakening_no_fire_before_tenure_4() -> void:
	## ne_awakening(RS, tenure=4, threshold=true): 4R 전 미발동
	var board := _make_board(["ne_awakening"])
	var units_before: int = board[0].get_total_units()
	for _i in 3:
		_engine.run_growth_chain(board)  # R1~R3
	# tenure=3 < 4 → 미발동 → 유닛 수 불변
	assert_eq(board[0].get_total_units(), units_before, "tenure 3 → 미발동 유닛 불변")
	assert_eq(board[0].shield_hp_pct, 0.0, "tenure 3 → shield 미적용")


func test_awakening_fires_at_tenure_4() -> void:
	## ne_awakening: tenure=4에서 발동 (threshold → 1회만)
	## spawn all_allies 2 + enhance all_allies 10% + shield 20%
	var board := _make_board(["ne_awakening", "sp_assembly"])
	for _i in 4:
		_engine.run_growth_chain(board)  # R1~R4
	# R4 (tenure 3→4): threshold 발동 → all_allies에 spawn 2 + enhance 10%
	assert_gt(board[0].shield_hp_pct, 0.0, "shield 적용")


func test_awakening_threshold_fires_once() -> void:
	## is_threshold=true → 1회 발동 후 threshold_fired=true
	var board := _make_board(["ne_awakening"])
	for _i in 4:
		_engine.run_growth_chain(board)
	assert_true(board[0].threshold_fired, "threshold 발동 완료")
	var units_after: int = board[0].get_total_units()
	_engine.run_growth_chain(board)  # R5: threshold_fired → 재발동 안 함
	assert_eq(board[0].get_total_units(), units_after, "threshold → 재발동 안 함")


# ================================================================
# ON_EVENT chain cascade 검증
# ================================================================

func test_earth_echo_triggers_wanderers_chain() -> void:
	## earth_echo(RS) → UNIT_ADDED → wanderers(OE/UA) 반응
	var board := _make_board(["ne_earth_echo", "ne_wanderers"])
	var result: Dictionary = _engine.run_growth_chain(board)
	assert_gte(result["chain_count"], 2, "RS → OE 연쇄")


func test_ruin_resonance_triggers_mutant_chain() -> void:
	## ruin_resonance(RS) → ENHANCED → mutant_adapt(OE/EN) 반응
	var board := _make_board(["ne_ruin_resonance", "ne_mutant_adapt"])
	var result: Dictionary = _engine.run_growth_chain(board)
	assert_gte(result["chain_count"], 2, "ENHANCED → mutant adapt 반응")


# ================================================================
# ★2/★3 고대의 각성 (tenure threshold, stronger effects)
# ================================================================

func _make_star(base_id: String, star: int) -> CardInstance:
	var card: CardInstance = CardInstance.create(base_id)
	for _i in star - 1:
		card.evolve_star()
	return card


func _make_star_board(base_id: String, star: int, extras: Array = []) -> Array:
	var board: Array = [_make_star(base_id, star)]
	for id in extras:
		board.append(CardInstance.create(id))
	return board


func test_awakening_s2_stronger_effects() -> void:
	## ★2: spawn 3 + enhance 15% + shield 30% (★1은 2/10%/20%)
	var board := _make_star_board("ne_awakening", 2, ["sp_assembly"])
	var units_before: int = board[0].get_total_units()
	var atk_before: float = board[0].get_total_atk()
	for _i in 4:
		_engine.run_growth_chain(board)  # R4: threshold 발동
	# ★2: all_allies spawn 3 → 유닛 증가
	assert_gt(board[0].get_total_units(), units_before, "★2 spawn 3 → 유닛 증가")
	# ★2: all_allies enhance 15% → ATK 증가
	assert_gt(board[0].get_total_atk(), atk_before, "★2 enhance 15% → ATK 증가")
	# ★2 shield 30% > ★1 shield 20%
	assert_almost_eq(board[0].shield_hp_pct, 0.30, 0.01, "★2 shield 30%")


func test_awakening_s2_resets_threshold_on_evolve() -> void:
	## evolve_star()가 threshold_fired를 리셋 → ★2 재발동 가능
	var card: CardInstance = CardInstance.create("ne_awakening")
	card.threshold_fired = true  # ★1에서 이미 발동됨
	card.evolve_star()  # ★2로 진화
	assert_false(card.threshold_fired, "evolve → threshold 리셋")


func test_dim_merchant_s2_gold_per_theme_2() -> void:
	## ★2: 2테마 × 2g = 4g
	var board := _make_star_board("ne_dim_merchant", 2, ["sp_assembly"])
	var result: Dictionary = _engine.run_growth_chain(board)
	# 2테마(neutral + steampunk) × gold_per_theme=2 = 4g
	assert_eq(result["gold_earned"], 4, "★2 2테마×2g = 4g")


func test_dim_merchant_s2_3_themes() -> void:
	## ★2: 3테마 × 2g = 6g
	var board := _make_star_board("ne_dim_merchant", 2, ["sp_assembly", "dr_cradle"])
	var result: Dictionary = _engine.run_growth_chain(board)
	assert_eq(result["gold_earned"], 6, "★2 3테마×2g = 6g")


func test_dim_merchant_s3_gold_per_theme_3() -> void:
	## ★3: 3테마 × 3g = 9g
	var board := _make_star_board("ne_dim_merchant", 3, ["sp_assembly", "dr_cradle"])
	var result: Dictionary = _engine.run_growth_chain(board)
	assert_eq(result["gold_earned"], 9, "★3 3테마×3g = 9g")


func test_dim_merchant_s3_terazin_at_3_themes() -> void:
	## ★3: 3종 이상 → 테마수 × 1 테라진
	var board := _make_star_board("ne_dim_merchant", 3, ["sp_assembly", "dr_cradle"])
	var result: Dictionary = _engine.run_growth_chain(board)
	# 3테마 >= terazin_threshold(3) → 3 × 1 = 3 테라진
	assert_eq(result["terazin_earned"], 3, "★3 3테마 → 3 테라진")


func test_dim_merchant_s3_no_terazin_below_threshold() -> void:
	## ★3: 2종 < threshold(3) → 테라진 없음
	var board := _make_star_board("ne_dim_merchant", 3, ["sp_assembly"])
	var result: Dictionary = _engine.run_growth_chain(board)
	assert_eq(result.get("terazin_earned", 0), 0, "★3 2테마 < 3 → 테라진 0")


func test_dim_merchant_s3_mercenary_spawn() -> void:
	## ★3: 비중립 카드마다 해당 카드에 유닛 1기 추가
	## OE 카드(sp_workshop) 사용 — RS 자체 spawn 없어 mercenary_spawn만 격리 검증
	var board := _make_star_board("ne_dim_merchant", 3, ["sp_workshop", "sp_workshop"])
	var ws1_before: int = board[1].get_total_units()
	var ws2_before: int = board[2].get_total_units()
	_engine.run_growth_chain(board)
	# 비중립 2장(sp_workshop ×2) → 각각 유닛 +1
	assert_eq(board[1].get_total_units(), ws1_before + 1, "workshop1 +1 용병 유닛")
	assert_eq(board[2].get_total_units(), ws2_before + 1, "workshop2 +1 용병 유닛")


# ================================================================
# ON_MERGE: ne_spirit_blessing (chain_engine.process_merge_triggers)
# ================================================================

func test_spirit_blessing_grants_terazin_on_merge() -> void:
	## ★1: 합성 시 1 테라진 획득
	var board := _make_board(["ne_spirit_blessing", "sp_assembly"])
	var merged_card: CardInstance = board[1]
	var result: Dictionary = _engine.process_merge_triggers(board, merged_card)
	assert_eq(result["terazin"], 1, "ON_MERGE → +1 terazin")


func test_spirit_blessing_spawns_on_merged_card() -> void:
	## ★1: 합성된 카드(event_target)에 유닛 2기 추가
	var board := _make_board(["ne_spirit_blessing", "sp_assembly"])
	var merged_card: CardInstance = board[1]
	var units_before: int = merged_card.get_total_units()
	_engine.process_merge_triggers(board, merged_card)
	assert_eq(merged_card.get_total_units(), units_before + 2, "합성 카드에 +2 유닛")


func test_spirit_blessing_respects_max_activations() -> void:
	## max_act=1 → 라운드당 1회만 발동
	var board := _make_board(["ne_spirit_blessing", "sp_assembly"])
	var merged_card: CardInstance = board[1]
	_engine.process_merge_triggers(board, merged_card)  # 1회
	var units_after_1: int = merged_card.get_total_units()
	_engine.process_merge_triggers(board, merged_card)  # 2회 시도
	assert_eq(merged_card.get_total_units(), units_after_1, "max_act=1 → 2회째 미발동")


func test_spirit_blessing_not_in_growth_chain() -> void:
	## ON_MERGE 카드는 run_growth_chain에서 발동 안 함
	var board := _make_board(["ne_spirit_blessing"])
	var result: Dictionary = _engine.run_growth_chain(board)
	assert_eq(result["chain_count"], 0, "ON_MERGE → growth chain 0")


func test_spirit_blessing_ignores_non_merge_cards() -> void:
	## ON_MERGE가 아닌 카드는 process_merge_triggers에서 무시
	var board := _make_board(["sp_assembly", "ne_spirit_blessing"])
	var merged_card: CardInstance = board[0]
	var sp_units_before: int = board[0].get_total_units()
	var result: Dictionary = _engine.process_merge_triggers(board, merged_card)
	# spirit_blessing만 발동, sp_assembly(RS)는 무시
	assert_eq(result["terazin"], 1, "spirit_blessing만 발동")


func test_spirit_blessing_s2_grants_gold_and_more_units() -> void:
	## ★2: 1 테라진 + 2 골드, 합성 카드에 유닛 3기
	var board: Array = [_make_star("ne_spirit_blessing", 2), CardInstance.create("sp_assembly")]
	var merged_card: CardInstance = board[1]
	var units_before: int = merged_card.get_total_units()
	var result: Dictionary = _engine.process_merge_triggers(board, merged_card)
	assert_eq(result["terazin"], 1, "★2 → +1 terazin")
	assert_eq(result["gold"], 2, "★2 → +2 gold")
	assert_eq(merged_card.get_total_units(), units_before + 3, "★2 → 합성 카드 +3 유닛")


func test_spirit_blessing_s3_all_allies_spawn() -> void:
	## ★3: 1 테라진 + 2 골드, 합성 카드 +3, 전체 아군 +1씩
	var board: Array = [_make_star("ne_spirit_blessing", 3),
		CardInstance.create("sp_assembly"), CardInstance.create("dr_cradle")]
	var merged_card: CardInstance = board[1]
	var spirit_before: int = board[0].get_total_units()
	var dr_before: int = board[2].get_total_units()
	var result: Dictionary = _engine.process_merge_triggers(board, merged_card)
	assert_eq(result["terazin"], 1, "★3 → +1 terazin")
	assert_eq(result["gold"], 2, "★3 → +2 gold")
	# 전체 아군: spirit +1, dr_cradle +1
	assert_eq(board[0].get_total_units(), spirit_before + 1, "★3 → spirit +1 유닛")
	assert_eq(board[2].get_total_units(), dr_before + 1, "★3 → dr_cradle +1 유닛")
