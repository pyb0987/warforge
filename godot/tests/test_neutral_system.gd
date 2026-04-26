extends GutTest
## NeutralSystem 테마 로직 테스트.
## 참조: neutral_system.gd, Phase 3b/3b-2a/3b-2b 구현.
##
## Phase 5b 커버리지 (단순 4카드):
##   - ne_envoy (T2): RS +Ng + ★3 BS +1g
##   - ne_hoarder (T3): SELL tenure × Ng
##   - ne_void_force (T4): BS empty_slot_scaling (temp_mult_buff)
##   - ne_fusion_end (T4): BS star3_count_scaling


var _sys: NeutralSystem = null
var _rng: RandomNumberGenerator = null


func before_each() -> void:
	_sys = NeutralSystem.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 42


# ================================================================
# ne_envoy (T2) — RS grant_gold + ★3 BS grant_gold
# ================================================================


func test_envoy_star1_rs_grants_2g() -> void:
	var card: CardInstance = CardInstance.create("ne_envoy")
	var result: Dictionary = _sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(result.get("gold", 0), 2, "★1 RS → +2g")


func test_envoy_star2_rs_grants_3g() -> void:
	var card: CardInstance = CardInstance.create("ne_envoy")
	card.evolve_star()
	var result: Dictionary = _sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(result.get("gold", 0), 3, "★2 RS → +3g")


func test_envoy_star3_rs_grants_4g() -> void:
	var card: CardInstance = CardInstance.create("ne_envoy")
	card.evolve_star()
	card.evolve_star()
	var result: Dictionary = _sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(result.get("gold", 0), 4, "★3 RS → +4g")


func test_envoy_star1_no_bs_gold() -> void:
	## ★1 BS handler returns empty (early return on star_level < 3)
	var card: CardInstance = CardInstance.create("ne_envoy")
	var result: Dictionary = _sys.apply_battle_start(card, 0, [card])
	assert_eq(result.get("gold", 0), 0, "★1 BS → 0g")


func test_envoy_star3_bs_grants_1g() -> void:
	## ★3 has BS block with grant_gold:1
	var card: CardInstance = CardInstance.create("ne_envoy")
	card.evolve_star()
	card.evolve_star()
	var result: Dictionary = _sys.apply_battle_start(card, 0, [card])
	assert_eq(result.get("gold", 0), 1, "★3 BS → +1g")


# ================================================================
# ne_hoarder (T3) — SELL tenure × N gold
# ================================================================


func test_hoarder_star1_tenure3_sells_3g() -> void:
	## ★1: tenure × 1g
	var card: CardInstance = CardInstance.create("ne_hoarder")
	card.tenure = 3
	var result: Dictionary = _sys.process_self_sell(card, [])
	assert_eq(result.get("gold", 0), 3, "★1 tenure 3 → +3g")


func test_hoarder_star2_tenure5_sells_10g() -> void:
	## ★2: tenure × 2g
	var card: CardInstance = CardInstance.create("ne_hoarder")
	card.evolve_star()
	card.tenure = 5
	var result: Dictionary = _sys.process_self_sell(card, [])
	assert_eq(result.get("gold", 0), 10, "★2 tenure 5 → +10g")


func test_hoarder_star3_tenure10_sells_40g() -> void:
	## ★3: tenure × 4g
	var card: CardInstance = CardInstance.create("ne_hoarder")
	card.evolve_star()
	card.evolve_star()
	card.tenure = 10
	var result: Dictionary = _sys.process_self_sell(card, [])
	assert_eq(result.get("gold", 0), 40, "★3 tenure 10 → +40g")


func test_hoarder_tenure0_no_gold() -> void:
	## tenure=0 (즉시 판매) → 0g (의도된 design — 최소 1R 보유)
	var card: CardInstance = CardInstance.create("ne_hoarder")
	card.tenure = 0
	var result: Dictionary = _sys.process_self_sell(card, [])
	assert_eq(result.get("gold", 0), 0, "tenure 0 → 0g")


# ================================================================
# ne_void_force (T4 BS) — empty_slot_scaling (temp_mult_buff)
# ================================================================


func test_void_force_no_empty_slots_no_buff() -> void:
	## board.size() == MAX_FIELD_SLOTS → empty=0 → no fire
	var card: CardInstance = CardInstance.create("ne_void_force")
	# 8 카드로 보드 가득
	var board: Array = [card]
	for i in range(1, Enums.MAX_FIELD_SLOTS):
		board.append(CardInstance.create("sp_assembly"))
	_sys.apply_battle_start(card, 0, board)
	assert_almost_eq(card.stacks[0]["temp_atk_mult"], 1.0, 0.001, "E=0 → buff 0")


func test_void_force_star2_solo_buff() -> void:
	## ★2 E=7 → ATK ×(1+0.40×7)=3.8, HP ×(1+0.20×7)=2.4 — multi-review missing ★ branch
	var card: CardInstance = CardInstance.create("ne_void_force")
	card.evolve_star()
	_sys.apply_battle_start(card, 0, [card])
	assert_almost_eq(card.stacks[0]["temp_atk_mult"], 1.0 + 0.40 * 7, 0.001,
		"★2 E=7 → ATK ×3.8")
	assert_almost_eq(card.stacks[0]["temp_hp_mult"], 1.0 + 0.20 * 7, 0.001,
		"★2 E=7 → HP ×2.4")
	# ★2 는 AS scaling 없음 (★3 only)
	assert_almost_eq(card.temp_as_mult, 1.0, 0.001, "★2 → temp_as_mult 변화 없음")


func test_void_force_star1_solo_max_buff() -> void:
	## board.size()=1 (self only) → empty=7 → ATK ×(1+0.30×7)=3.1, HP ×(1+0.15×7)=2.05
	var card: CardInstance = CardInstance.create("ne_void_force")
	_sys.apply_battle_start(card, 0, [card])
	assert_almost_eq(card.stacks[0]["temp_atk_mult"], 1.0 + 0.30 * 7, 0.001,
		"★1 E=7 → temp_atk_mult ×3.1")
	assert_almost_eq(card.stacks[0]["temp_hp_mult"], 1.0 + 0.15 * 7, 0.001,
		"★1 E=7 → temp_hp_mult ×2.05")


func test_void_force_star3_includes_as_scaling() -> void:
	## ★3: ATK ×3.5, HP ×2.1, AS / (1 + 0.05×7) = / 1.35
	var card: CardInstance = CardInstance.create("ne_void_force")
	card.evolve_star()
	card.evolve_star()
	_sys.apply_battle_start(card, 0, [card])
	assert_almost_eq(card.stacks[0]["temp_atk_mult"], 1.0 + 0.50 * 7, 0.001, "★3 ATK ×4.5")
	assert_almost_eq(card.stacks[0]["temp_hp_mult"], 1.0 + 0.30 * 7, 0.001, "★3 HP ×3.1")
	assert_almost_eq(card.temp_as_mult, 1.0 / (1.0 + 0.05 * 7), 0.001, "★3 AS /1.35")


func test_void_force_clear_temp_buffs_resets_as() -> void:
	## clear_temp_buffs 호출 시 temp_as_mult 도 1.0 으로 리셋
	var card: CardInstance = CardInstance.create("ne_void_force")
	card.evolve_star()
	card.evolve_star()
	_sys.apply_battle_start(card, 0, [card])
	assert_true(card.temp_as_mult < 1.0, "BS 후 temp_as_mult < 1.0")
	card.clear_temp_buffs()
	assert_almost_eq(card.temp_as_mult, 1.0, 0.001, "clear_temp_buffs → temp_as_mult = 1.0")


# ================================================================
# ne_fusion_end (T4 BS) — star3_count_scaling
# ================================================================


func test_fusion_end_no_star3_no_buff() -> void:
	## 보드에 ★3 카드 0장 → M=0 → no fire
	var card: CardInstance = CardInstance.create("ne_fusion_end")
	var sp_card: CardInstance = CardInstance.create("sp_assembly")
	_sys.apply_battle_start(card, 0, [card, sp_card])
	assert_almost_eq(card.stacks[0]["temp_atk_mult"], 1.0, 0.001, "M=0 → no buff")


func test_fusion_end_star3_self_only_m1() -> void:
	## self ★3 + 다른 카드 ★1 → M=1 (self) → ATK ×1.65, HP ×1.35
	var card: CardInstance = CardInstance.create("ne_fusion_end")
	card.evolve_star()
	card.evolve_star()
	var sp_card: CardInstance = CardInstance.create("sp_assembly")
	_sys.apply_battle_start(card, 0, [card, sp_card])
	assert_almost_eq(card.stacks[0]["temp_atk_mult"], 1.0 + 0.65, 0.001,
		"★3 self M=1 → ATK ×1.65")
	assert_almost_eq(card.stacks[0]["temp_hp_mult"], 1.0 + 0.35, 0.001,
		"★3 self M=1 → HP ×1.35")


func test_fusion_end_m3_triggers_allies_aura() -> void:
	## M=3 (self ★3 + 2 ★3) → self 강화 + 모든 아군 ATK +M×7%
	var card: CardInstance = CardInstance.create("ne_fusion_end")
	card.evolve_star()
	card.evolve_star()
	var ally1: CardInstance = CardInstance.create("sp_assembly")
	ally1.evolve_star()
	ally1.evolve_star()
	var ally2: CardInstance = CardInstance.create("ne_earth_echo")
	ally2.evolve_star()
	ally2.evolve_star()
	_sys.apply_battle_start(card, 0, [card, ally1, ally2])
	# M=3, self ATK +0.65×3=+195%, HP +0.35×3=+105%
	assert_almost_eq(card.stacks[0]["temp_atk_mult"], 1.0 + 0.65 * 3, 0.001, "self ATK ×2.95")
	# allies ATK +M×7% = +21% (자기 제외) — ally1 + ally2 모두 검증
	assert_almost_eq(ally1.stacks[0]["temp_atk_mult"], 1.0 + 0.07 * 3, 0.001, "ally1 ATK ×1.21")
	assert_almost_eq(ally2.stacks[0]["temp_atk_mult"], 1.0 + 0.07 * 3, 0.001, "ally2 ATK ×1.21")


func test_fusion_end_star2_no_allies_aura() -> void:
	## ★2: allies_atk_pct_per_m 없음 → ★3 N≥3 라도 아군 buff 안 함 (multi-review 누락 ★)
	## A안: ★2 self 는 weight 0.5 로 M 에 포함 → M = 2 (★3) + 0.5 (★2 self) = 2.5
	var card: CardInstance = CardInstance.create("ne_fusion_end")
	card.evolve_star()  # ★2
	var ally1: CardInstance = CardInstance.create("sp_assembly")
	ally1.evolve_star()
	ally1.evolve_star()
	var ally2: CardInstance = CardInstance.create("ne_earth_echo")
	ally2.evolve_star()
	ally2.evolve_star()
	_sys.apply_battle_start(card, 0, [card, ally1, ally2])
	# ★2 self M=2.5 → ATK ×(1+0.55×2.5)=2.375, HP ×(1+0.20×2.5)=1.5
	assert_almost_eq(card.stacks[0]["temp_atk_mult"], 1.0 + 0.55 * 2.5, 0.001,
		"★2 self M=2.5 → ATK ×2.375")
	assert_almost_eq(card.stacks[0]["temp_hp_mult"], 1.0 + 0.20 * 2.5, 0.001,
		"★2 self M=2.5 → HP ×1.50")
	assert_almost_eq(ally1.stacks[0]["temp_atk_mult"], 1.0, 0.001, "★2 → 아군 aura 없음")


func test_fusion_end_star2_weight_self_only() -> void:
	## A안: ★2 self 단독, ★3 0장 → M = 0.5 (★2 self × 0.5).
	## 0 < M 이므로 self buff 발동.
	var card: CardInstance = CardInstance.create("ne_fusion_end")
	card.evolve_star()  # ★2
	var sp_card: CardInstance = CardInstance.create("sp_assembly")  # ★1
	_sys.apply_battle_start(card, 0, [card, sp_card])
	# ★2 self M=0.5 → ATK ×(1+0.55×0.5)=1.275, HP ×(1+0.20×0.5)=1.10
	assert_almost_eq(card.stacks[0]["temp_atk_mult"], 1.0 + 0.55 * 0.5, 0.001,
		"★2 self only M=0.5 → ATK ×1.275")
	assert_almost_eq(card.stacks[0]["temp_hp_mult"], 1.0 + 0.20 * 0.5, 0.001,
		"★2 self only M=0.5 → HP ×1.10")


func test_fusion_end_star3_with_star2_ally() -> void:
	## A안: self ★3 + ally ★2 → star3=1, M = 1 + 0.5 = 1.5.
	## ★3 self 스케일에 ★2 가중치 합산.
	var card: CardInstance = CardInstance.create("ne_fusion_end")
	card.evolve_star()
	card.evolve_star()  # ★3
	var ally2: CardInstance = CardInstance.create("sp_assembly")
	ally2.evolve_star()  # ★2
	_sys.apply_battle_start(card, 0, [card, ally2])
	# ★3 self M=1.5 → ATK ×(1+0.65×1.5)=1.975, HP ×(1+0.35×1.5)=1.525
	assert_almost_eq(card.stacks[0]["temp_atk_mult"], 1.0 + 0.65 * 1.5, 0.001,
		"★3 self + ★2 ally M=1.5 → ATK ×1.975")
	assert_almost_eq(card.stacks[0]["temp_hp_mult"], 1.0 + 0.35 * 1.5, 0.001,
		"★3 self + ★2 ally M=1.5 → HP ×1.525")
	# aura: star3_count=1 < threshold=3 → 아군 buff 없음
	assert_almost_eq(ally2.stacks[0]["temp_atk_mult"], 1.0, 0.001,
		"★3 1장만 → 아군 aura 미발동")


func test_fusion_end_aura_threshold_strict_star3_count() -> void:
	## ★3 self + ★2 ally 4장 → M = 1 + 4×0.5 = 3.0 (≥ threshold=3) 이지만
	## aura threshold 는 정수 ★3 카운트 기준 (=1) → aura 미발동.
	## (★2 가중 합산이 aura threshold 를 넘기지 못함을 검증)
	var card: CardInstance = CardInstance.create("ne_fusion_end")
	card.evolve_star()
	card.evolve_star()  # ★3
	var allies: Array = []
	for i in range(4):
		var a: CardInstance = CardInstance.create("sp_assembly")
		a.evolve_star()  # ★2
		allies.append(a)
	var board: Array = [card]
	board.append_array(allies)
	_sys.apply_battle_start(card, 0, board)
	# self M=3.0 → ATK ×(1+0.65×3)=2.95
	assert_almost_eq(card.stacks[0]["temp_atk_mult"], 1.0 + 0.65 * 3.0, 0.001,
		"M=3.0 self ATK ×2.95")
	# aura 미발동: star3_count=1 < 3
	for a in allies:
		assert_almost_eq((a as CardInstance).stacks[0]["temp_atk_mult"], 1.0, 0.001,
			"★3 카운트<3 → aura 미발동")


func test_fusion_end_m2_below_threshold_no_aura() -> void:
	## ★3 self M=2 (★3 ally 1장만) → allies_threshold(3) 미달 → 아군 aura 없음
	## (boundary 검증 — multi-review 누락)
	var card: CardInstance = CardInstance.create("ne_fusion_end")
	card.evolve_star()
	card.evolve_star()
	var ally1: CardInstance = CardInstance.create("sp_assembly")
	ally1.evolve_star()
	ally1.evolve_star()
	_sys.apply_battle_start(card, 0, [card, ally1])
	# self ATK ×(1+0.65×2)=2.30
	assert_almost_eq(card.stacks[0]["temp_atk_mult"], 1.0 + 0.65 * 2, 0.001,
		"M=2 self ATK ×2.30")
	# 아군 aura 없음 (M=2 < threshold 3)
	assert_almost_eq(ally1.stacks[0]["temp_atk_mult"], 1.0, 0.001,
		"M<3 → aura 미발동")


# ================================================================
# ne_legion (T3 PERSISTENT) — duplicate_buff_aura
# ================================================================


func test_legion_no_duplicates_no_buff() -> void:
	## 중복 카드 없음 (각 template_id 1장) → buff 없음
	var card: CardInstance = CardInstance.create("ne_legion")
	var sp: CardInstance = CardInstance.create("sp_assembly")
	var board: Array = [card, sp]
	_sys.apply_persistent(card, board)
	assert_almost_eq(sp.stacks[0]["temp_atk_mult"], 1.0, 0.001, "중복 없음 → no buff")
	assert_almost_eq(card.stacks[0]["temp_atk_mult"], 1.0, 0.001, "self도 변화 없음")


func test_legion_star1_buffs_duplicates() -> void:
	## 같은 sp_assembly 2장 → N_excl=1, ATK +20%, HP +10% 각각 적용
	var card: CardInstance = CardInstance.create("ne_legion")
	var sp1: CardInstance = CardInstance.create("sp_assembly")
	var sp2: CardInstance = CardInstance.create("sp_assembly")
	var board: Array = [card, sp1, sp2]
	_sys.apply_persistent(card, board)
	assert_almost_eq(sp1.stacks[0]["temp_atk_mult"], 1.0 + 0.20, 0.001, "sp1 ATK ×1.20")
	assert_almost_eq(sp2.stacks[0]["temp_atk_mult"], 1.0 + 0.20, 0.001, "sp2 ATK ×1.20")
	assert_almost_eq(sp1.stacks[0]["temp_hp_mult"], 1.0 + 0.10, 0.001, "sp1 HP ×1.10")


func test_legion_star2_3_duplicates_n_excl_2() -> void:
	## 같은 sp_assembly 3장 → N_excl=2 → 각각 ATK +60%, HP +30%
	var card: CardInstance = CardInstance.create("ne_legion")
	card.evolve_star()  # ★2: atk_per_n=0.30, hp_per_n=0.15
	var sp1: CardInstance = CardInstance.create("sp_assembly")
	var sp2: CardInstance = CardInstance.create("sp_assembly")
	var sp3: CardInstance = CardInstance.create("sp_assembly")
	var board: Array = [card, sp1, sp2, sp3]
	_sys.apply_persistent(card, board)
	assert_almost_eq(sp1.stacks[0]["temp_atk_mult"], 1.0 + 0.30 * 2, 0.001,
		"★2 N_excl=2 → ATK ×1.60")
	assert_almost_eq(sp1.stacks[0]["temp_hp_mult"], 1.0 + 0.15 * 2, 0.001,
		"★2 N_excl=2 → HP ×1.30")


func test_legion_star3_spawns_per_card() -> void:
	## ★3: spawn_per_card=1 → 각 중복 카드에 첫 stack 유닛 1기 추가
	var card: CardInstance = CardInstance.create("ne_legion")
	card.evolve_star()
	card.evolve_star()
	var sp1: CardInstance = CardInstance.create("sp_assembly")
	var sp2: CardInstance = CardInstance.create("sp_assembly")
	var sp1_units: int = sp1.get_total_units()
	var sp2_units: int = sp2.get_total_units()
	_sys.apply_persistent(card, [card, sp1, sp2])
	assert_eq(sp1.get_total_units(), sp1_units + 1, "★3 sp1 +1기")
	assert_eq(sp2.get_total_units(), sp2_units + 1, "★3 sp2 +1기")


# ================================================================
# ne_nexus (T5 OE) — mirror_l1, non_neutral_target filter, multi-block
# ================================================================


func _make_event(l1_type: int, src: int, tgt: int) -> Dictionary:
	return {"layer1": l1_type, "layer2": -1,
			"source_idx": src, "target_idx": tgt}


func test_nexus_self_source_ignored() -> void:
	## source_idx == self idx → 무한 루프 방지
	var card: CardInstance = CardInstance.create("ne_nexus")
	var event := _make_event(Enums.Layer1.UNIT_ADDED, 0, 1)
	_sys.process_event_card(card, 0, [card], event, _rng)
	assert_almost_eq(card.growth_atk_pct, 0.0, 0.001, "self-source → no fire")


func test_nexus_neutral_target_filtered() -> void:
	## target이 NEUTRAL → 무시 (filter: non_neutral_target)
	var card: CardInstance = CardInstance.create("ne_nexus")
	var ne_target: CardInstance = CardInstance.create("ne_earth_echo")
	var board: Array = [card, ne_target]
	var event := _make_event(Enums.Layer1.UNIT_ADDED, 1, 1)
	_sys.process_event_card(card, 0, board, event, _rng)
	assert_almost_eq(card.growth_atk_pct, 0.0, 0.001, "NEUTRAL target → 무시")


func test_nexus_star1_non_neutral_target_enhances() -> void:
	## 비-NEUTRAL target (sp_assembly) UA → self ATK +2%
	var card: CardInstance = CardInstance.create("ne_nexus")
	var sp: CardInstance = CardInstance.create("sp_assembly")
	var board: Array = [card, sp]
	var event := _make_event(Enums.Layer1.UNIT_ADDED, 1, 1)
	_sys.process_event_card(card, 0, board, event, _rng)
	assert_almost_eq(card.growth_atk_pct, 0.02, 0.001, "★1 UA → +2% ATK")


func test_nexus_star1_en_event_also_fires() -> void:
	## EN 이벤트도 별도 OE block으로 listen → ATK +2%
	var card: CardInstance = CardInstance.create("ne_nexus")
	var sp: CardInstance = CardInstance.create("sp_assembly")
	var board: Array = [card, sp]
	var event := _make_event(Enums.Layer1.ENHANCED, 1, 1)
	_sys.process_event_card(card, 0, board, event, _rng)
	assert_almost_eq(card.growth_atk_pct, 0.02, 0.001, "★1 EN → +2% ATK")


func test_nexus_star3_spawns_unit() -> void:
	## ★3: spawn_unit=1 → 첫 stack unit 1기 추가
	var card: CardInstance = CardInstance.create("ne_nexus")
	card.evolve_star()
	card.evolve_star()
	var sp: CardInstance = CardInstance.create("sp_assembly")
	var board: Array = [card, sp]
	var before_units: int = card.get_total_units()
	var event := _make_event(Enums.Layer1.UNIT_ADDED, 1, 1)
	_sys.process_event_card(card, 0, board, event, _rng)
	assert_eq(card.get_total_units(), before_units + 1, "★3 → 유닛 1기 spawn")


func test_nexus_star2_atk_and_hp() -> void:
	## ★2: ATK +3%, HP +1% (multi-review missing ★ branch)
	var card: CardInstance = CardInstance.create("ne_nexus")
	card.evolve_star()
	var sp: CardInstance = CardInstance.create("sp_assembly")
	var board: Array = [card, sp]
	var event := _make_event(Enums.Layer1.UNIT_ADDED, 1, 1)
	_sys.process_event_card(card, 0, board, event, _rng)
	assert_almost_eq(card.growth_atk_pct, 0.03, 0.001, "★2 UA → ATK +3%")
	assert_almost_eq(card.growth_hp_pct, 0.01, 0.001, "★2 UA → HP +1%")


func test_nexus_omni_target_filtered_as_neutral() -> void:
	## omni-theme target 은 NEUTRAL 매치 → 무시
	var card: CardInstance = CardInstance.create("ne_nexus")
	var omni: CardInstance = CardInstance.create("sp_assembly")
	omni.is_omni_theme = true
	var board: Array = [card, omni]
	var event := _make_event(Enums.Layer1.UNIT_ADDED, 1, 1)
	_sys.process_event_card(card, 0, board, event, _rng)
	assert_almost_eq(card.growth_atk_pct, 0.0, 0.001, "omni target → 무시 (NEUTRAL 매치)")


# ================================================================
# ne_council (T5 PERSISTENT) — all_themes_field_bonus
# ================================================================


func _make_5_theme_board(council: CardInstance) -> Array:
	## council + sp + ml + dr + pr 5장 → 5테마 보드
	return [
		council,  # neutral (council 자체)
		CardInstance.create("sp_assembly"),
		CardInstance.create("ml_barracks"),
		CardInstance.create("dr_cradle"),
		CardInstance.create("pr_nest"),
	]


func test_council_star1_no_aura() -> void:
	## ★1: field_slots는 game_manager 처리. PERSISTENT handler는 aura만 (★1=0).
	var card: CardInstance = CardInstance.create("ne_council")
	var board := _make_5_theme_board(card)
	_sys.apply_persistent(card, board)
	# ★1 aura 0% — sp_assembly 변화 없음
	assert_almost_eq(board[1].stacks[0]["temp_atk_mult"], 1.0, 0.001, "★1 → 아군 aura 없음")


func test_council_star2_5theme_allies_atk_bonus() -> void:
	## ★2: 5테마 충족 시 모든 아군 ATK +5%
	var card: CardInstance = CardInstance.create("ne_council")
	card.evolve_star()
	var board := _make_5_theme_board(card)
	_sys.apply_persistent(card, board)
	for c in board:
		assert_almost_eq((c as CardInstance).stacks[0]["temp_atk_mult"], 1.0 + 0.05, 0.001,
			"★2 5테마 → ATK ×1.05")


func test_council_star3_atk_hp_bonus() -> void:
	## ★3: 5테마 충족 시 ATK +7%, HP +5%
	var card: CardInstance = CardInstance.create("ne_council")
	card.evolve_star()
	card.evolve_star()
	var board := _make_5_theme_board(card)
	_sys.apply_persistent(card, board)
	assert_almost_eq(board[1].stacks[0]["temp_atk_mult"], 1.0 + 0.07, 0.001, "★3 ATK ×1.07")
	assert_almost_eq(board[1].stacks[0]["temp_hp_mult"], 1.0 + 0.05, 0.001, "★3 HP ×1.05")


func test_council_below_5_themes_no_aura() -> void:
	## 4테마만 → 조건 미달 → ★3라도 aura 없음
	var card: CardInstance = CardInstance.create("ne_council")
	card.evolve_star()
	card.evolve_star()
	var board: Array = [
		card, CardInstance.create("sp_assembly"),
		CardInstance.create("ml_barracks"),
		CardInstance.create("dr_cradle"),  # 4 테마 (no predator)
	]
	_sys.apply_persistent(card, board)
	assert_almost_eq(board[1].stacks[0]["temp_atk_mult"], 1.0, 0.001, "4테마 → aura 없음")


func test_council_omni_card_satisfies_all_themes() -> void:
	## omni-theme 카드 1장이 모든 5테마 매치 → council 단독 + omni 1장으로 발동
	var card: CardInstance = CardInstance.create("ne_council")
	card.evolve_star()
	var omni: CardInstance = CardInstance.create("sp_assembly")
	omni.is_omni_theme = true
	var board: Array = [card, omni]
	_sys.apply_persistent(card, board)
	assert_almost_eq(omni.stacks[0]["temp_atk_mult"], 1.0 + 0.05, 0.001,
		"★2 + omni(5테마) → 아군 aura 발동")


# ================================================================
# ne_pawnbroker (T1 REROLL levelup_discount + ★3 RS free_reroll)
# ================================================================


func test_pawnbroker_star1_rs_no_signal() -> void:
	## ★1 은 RS block 자체가 없음 — process_rs_card 가 free_rerolls 신호 없는
	## empty_result 반환 (★1/★2 카드는 dispatch 미진입).
	var card: CardInstance = CardInstance.create("ne_pawnbroker")
	var result: Dictionary = _sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(result.get("free_rerolls", 0), 0, "★1 RS → free_rerolls 신호 없음")


func test_pawnbroker_star3_rs_emits_one_free_reroll() -> void:
	## ★3 RS: YAML 의 free_reroll: {value: 1} 을 result.free_rerolls 로 신호.
	## ChainEngine 가 누적해 game_state.pending_free_rerolls 로 전달.
	var card: CardInstance = CardInstance.create("ne_pawnbroker")
	card.evolve_star()
	card.evolve_star()
	var result: Dictionary = _sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(result.get("free_rerolls", 0), 1, "★3 RS → free_rerolls 1")


func test_pawnbroker_self_sell_empty() -> void:
	## ne_pawnbroker 는 SELL block 정의가 없음 — self_sell 핸들러 미진입.
	## 분열체와 달리 판매 페널티 없음 (T1 일반 카드 가격 환급).
	var card: CardInstance = CardInstance.create("ne_pawnbroker")
	var result: Dictionary = _sys.process_self_sell(card, [])
	assert_eq(result.get("gold", 0), 0, "전당포 SELL → 골드 효과 없음")
	assert_false(result.has("transfer_upgrade"), "transfer signal 없음")


# ================================================================
# ne_masquerade (T4 SELL transform_theme + ★3 omni)
# ================================================================


func test_masquerade_no_target_no_transform() -> void:
	## 보드에 다른 카드 없음 (self 만) → transform 없음
	var card: CardInstance = CardInstance.create("ne_masquerade")
	var result: Dictionary = _sys.process_self_sell(card, [card])
	assert_false(result.has("transform_theme"), "타겟 없음 → transform 없음")


func test_masquerade_star1_returns_target_and_theme() -> void:
	## ★1 SELL: 첫 비-self 카드 + 비-NEUTRAL theme (sim 결정성)
	## sp target → PREDATOR 변환 (sim 결정성: STEAMPUNK 면 PREDATOR, 아니면 STEAMPUNK)
	var card: CardInstance = CardInstance.create("ne_masquerade")
	var sp: CardInstance = CardInstance.create("sp_assembly")
	var result: Dictionary = _sys.process_self_sell(card, [card, sp])
	var transform: Dictionary = result.get("transform_theme", {})
	assert_eq(transform.get("target_card"), sp, "target_card = sp")
	assert_false(transform.get("omni", true), "★1 omni=false")
	assert_eq(transform.get("new_theme"), Enums.CardTheme.PREDATOR,
		"sp target → PREDATOR (sim 결정성)")


func test_masquerade_default_theme_for_non_steampunk() -> void:
	## target이 비-STEAMPUNK (예: dr_cradle) → default STEAMPUNK 변환
	var card: CardInstance = CardInstance.create("ne_masquerade")
	var dr: CardInstance = CardInstance.create("dr_cradle")
	var result: Dictionary = _sys.process_self_sell(card, [card, dr])
	var t: Dictionary = result.get("transform_theme", {})
	assert_eq(t.get("new_theme"), Enums.CardTheme.STEAMPUNK,
		"dr target → default STEAMPUNK")


func test_masquerade_sparse_board_skips_nulls() -> void:
	## sparse board (null 중간) → null skip + 첫 비-self 카드 선택
	var card: CardInstance = CardInstance.create("ne_masquerade")
	var sp: CardInstance = CardInstance.create("sp_assembly")
	var sparse_board: Array = [card, null, sp, null]
	var result: Dictionary = _sys.process_self_sell(card, sparse_board)
	var t: Dictionary = result.get("transform_theme", {})
	assert_eq(t.get("target_card"), sp, "null skip + sp 선택")


func test_masquerade_target_skips_self() -> void:
	## 보드에 self + sp + dr → target=첫 비-self = sp (self 건너뜀)
	var card: CardInstance = CardInstance.create("ne_masquerade")
	var sp: CardInstance = CardInstance.create("sp_assembly")
	var dr: CardInstance = CardInstance.create("dr_cradle")
	var result: Dictionary = _sys.process_self_sell(card, [card, sp, dr])
	assert_eq(result.get("transform_theme", {}).get("target_card"), sp,
		"sp 첫 비-self target")


func test_masquerade_star3_omni_flag() -> void:
	## ★3: omni=true 반환 → game_manager 가 target.is_omni_theme 설정
	var card: CardInstance = CardInstance.create("ne_masquerade")
	card.evolve_star()
	card.evolve_star()
	var sp: CardInstance = CardInstance.create("sp_assembly")
	var result: Dictionary = _sys.process_self_sell(card, [card, sp])
	assert_true(result.get("transform_theme", {}).get("omni", false),
		"★3 omni=true")


func test_masquerade_target_is_steampunk_picks_predator() -> void:
	## sim 결정성: target이 STEAMPUNK 면 PREDATOR로 변환 (default 회피)
	var card: CardInstance = CardInstance.create("ne_masquerade")
	var sp: CardInstance = CardInstance.create("sp_assembly")
	var result: Dictionary = _sys.process_self_sell(card, [card, sp])
	var t: Dictionary = result.get("transform_theme", {})
	assert_eq(t.get("new_theme"), Enums.CardTheme.PREDATOR,
		"sp target → predator로 변환")


func test_fusion_end_star1_no_allies_aura() -> void:
	## ★1: allies_atk_pct_per_m 0 → 아군 buff 안 함 (M ≥ 3 라도)
	var card: CardInstance = CardInstance.create("ne_fusion_end")
	# self ★1 + 2 다른 ★3 → M=2 (self ★1, 자기는 not ★3)
	var ally1: CardInstance = CardInstance.create("sp_assembly")
	ally1.evolve_star()
	ally1.evolve_star()
	var ally2: CardInstance = CardInstance.create("ne_earth_echo")
	ally2.evolve_star()
	ally2.evolve_star()
	_sys.apply_battle_start(card, 0, [card, ally1, ally2])
	# self ★1 ATK ×(1+0.40×2)=1.8 (M=2)
	assert_almost_eq(card.stacks[0]["temp_atk_mult"], 1.0 + 0.40 * 2, 0.001,
		"★1 self M=2 → ATK ×1.8")
	# allies 변화 없음
	assert_almost_eq(ally1.stacks[0]["temp_atk_mult"], 1.0, 0.001, "★1 → 아군 aura 없음")
