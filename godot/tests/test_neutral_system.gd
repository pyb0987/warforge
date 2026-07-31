extends GutTest
## NeutralSystem 테마 로직 테스트.
## 참조: neutral_system.gd, Phase 3b/3b-2a/3b-2b 구현.
##
## Phase 5b 커버리지 (단순 4카드):
##   - ne_envoy (T2): RS +Ng + ★3 BS +1g
##   - ne_hoarder (T3): SELL tenure × Ng
##   - ne_void_force (T4): BS empty_slot_scaling (temp_mult_buff)
##   - ne_fusion_end (T4): PERSISTENT star_aura — 각 ★≥2 아군 buff (이번 전투)


var _sys: NeutralSystem = null
var _rng: RandomNumberGenerator = null


func before_each() -> void:
	_sys = NeutralSystem.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 42


# ================================================================
# ne_envoy (T2) — RS grant_gold + ★3 BS grant_gold
# ================================================================


func test_envoy_star1_rs_grants_1g() -> void:
	var card: CardInstance = CardInstance.create("ne_envoy")
	var result: Dictionary = _sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(result.get("gold", 0), 1, "★1 RS → +1g")


func test_envoy_star2_rs_grants_2g() -> void:
	var card: CardInstance = CardInstance.create("ne_envoy")
	card.evolve_star()
	var result: Dictionary = _sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(result.get("gold", 0), 2, "★2 RS → +2g")


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
# ne_hoarder (T3, 2026-04-29 재설계) — SELL transfer stacks + tenure-based enhance
# ================================================================


func test_hoarder_returns_transfer_dict() -> void:
	## SELL → hoarder_transfer dict + needs_target_select 반환.
	var card: CardInstance = CardInstance.create("ne_hoarder")
	var other: CardInstance = CardInstance.create("ne_envoy")
	card.tenure = 3
	var result: Dictionary = _sys.process_self_sell(card, [card, other])
	assert_eq(result.get("needs_target_select", ""), "ne_hoarder",
		"target select UI flag")
	var transfer: Dictionary = result.get("hoarder_transfer", {})
	assert_false(transfer.is_empty(), "transfer dict non-empty")
	assert_almost_eq(float(transfer.get("atk_per_tenure", 0.0)), 0.02, 0.0001,
		"★1 atk_per_tenure=0.02")
	assert_eq(transfer.get("source_card"), card, "source = self")
	assert_eq(transfer.get("target_card"), other, "auto-target = first non-self")


func test_hoarder_no_other_card_returns_empty() -> void:
	## 보드에 다른 카드가 없으면 SELL 효과 무발동 (empty_result).
	var card: CardInstance = CardInstance.create("ne_hoarder")
	var result: Dictionary = _sys.process_self_sell(card, [card])
	assert_eq(result.get("needs_target_select", ""), "",
		"보드 비-self 카드 0 → no target select")


func test_hoarder_star3_includes_bonus_unit_cap() -> void:
	## ★3: bonus_unit_cap=1 — UI 적용 단계 (game_manager) 에서 사용될 정보 보존.
	var card: CardInstance = CardInstance.create("ne_hoarder")
	card.evolve_star()
	card.evolve_star()
	var other: CardInstance = CardInstance.create("ne_envoy")
	var result: Dictionary = _sys.process_self_sell(card, [card, other])
	var transfer: Dictionary = result.get("hoarder_transfer", {})
	assert_eq(transfer.get("bonus_unit_cap", 0), 1, "★3 unit_cap +1")
	assert_almost_eq(float(transfer.get("atk_per_tenure", 0.0)), 0.04, 0.0001,
		"★3 atk_per_tenure=0.04")
	assert_almost_eq(float(transfer.get("hp_per_tenure", 0.0)), 0.02, 0.0001,
		"★3 hp_per_tenure=0.02")


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
# ne_fusion_end (T4 PERSISTENT) — star_aura
# 2026-04-27 재설계 (사용자 피드백):
#   각 ★≥2 아군 카드 (자기 포함) 에게 ATK/HP 배율 buff. flat per-card,
#   M scaling 없음. ★1: 30/15  ★2: 40/20  ★3: 50/30 (이번 전투 한정).
# ================================================================


func test_fusion_end_star1_no_star2_or_higher_no_buff() -> void:
	## 보드에 ★≥2 카드 0장 (self ★1 + ally ★1) → 누구도 buff 안 받음.
	var card: CardInstance = CardInstance.create("ne_fusion_end")
	var sp_card: CardInstance = CardInstance.create("sp_assembly")  # ★1
	_sys.apply_persistent(card, [card, sp_card])
	assert_almost_eq(card.stacks[0]["temp_atk_mult"], 1.0, 0.001,
		"self ★1 < min_star → no buff")
	assert_almost_eq(sp_card.stacks[0]["temp_atk_mult"], 1.0, 0.001,
		"ally ★1 < min_star → no buff")


func test_fusion_end_star1_buffs_each_star2_ally() -> void:
	## ★1 fusion_end + ★2 ally → ally 만 +30%/+15% (★1 self 는 < min_star).
	var card: CardInstance = CardInstance.create("ne_fusion_end")
	var ally: CardInstance = CardInstance.create("sp_assembly")
	ally.evolve_star()  # ★2
	_sys.apply_persistent(card, [card, ally])
	assert_almost_eq(ally.stacks[0]["temp_atk_mult"], 1.30, 0.001,
		"★2 ally → ATK +30%")
	assert_almost_eq(ally.stacks[0]["temp_hp_mult"], 1.15, 0.001,
		"★2 ally → HP +15%")
	# self ★1 < min_star=2 → 무영향
	assert_almost_eq(card.stacks[0]["temp_atk_mult"], 1.0, 0.001,
		"★1 self < min_star → no buff")


func test_fusion_end_star3_self_buffs_self_too() -> void:
	## ★3 fusion_end + ★3 ally → 둘 다 +50%/+30% (include_self: true).
	var card: CardInstance = CardInstance.create("ne_fusion_end")
	card.evolve_star()
	card.evolve_star()  # ★3
	var ally: CardInstance = CardInstance.create("sp_assembly")
	ally.evolve_star()
	ally.evolve_star()  # ★3
	_sys.apply_persistent(card, [card, ally])
	assert_almost_eq(card.stacks[0]["temp_atk_mult"], 1.50, 0.001,
		"★3 self → ATK +50% (include_self)")
	assert_almost_eq(card.stacks[0]["temp_hp_mult"], 1.30, 0.001,
		"★3 self → HP +30%")
	assert_almost_eq(ally.stacks[0]["temp_atk_mult"], 1.50, 0.001,
		"★3 ally → ATK +50%")


func test_fusion_end_star2_buff_each_qualifying() -> void:
	## ★2 fusion_end + ★2 ally + ★1 ally → ★2 둘에만 +40%/+20%.
	var card: CardInstance = CardInstance.create("ne_fusion_end")
	card.evolve_star()  # ★2
	var ally2: CardInstance = CardInstance.create("sp_assembly")
	ally2.evolve_star()  # ★2
	var ally1: CardInstance = CardInstance.create("ne_earth_echo")  # ★1
	_sys.apply_persistent(card, [card, ally2, ally1])
	# self ★2 ≥ min_star → buff 받음
	assert_almost_eq(card.stacks[0]["temp_atk_mult"], 1.40, 0.001,
		"★2 self → ATK +40%")
	assert_almost_eq(ally2.stacks[0]["temp_atk_mult"], 1.40, 0.001,
		"★2 ally → ATK +40%")
	# ★1 ally → 미적용
	assert_almost_eq(ally1.stacks[0]["temp_atk_mult"], 1.0, 0.001,
		"★1 ally → no buff")


func test_fusion_end_includes_self_when_qualifying() -> void:
	## ★2 fusion_end 자기 자신 ★≥2 만족 → 자기 포함 buff.
	## (사용자 명시 확인: include_self true 의도된 동작)
	var card: CardInstance = CardInstance.create("ne_fusion_end")
	card.evolve_star()  # ★2
	_sys.apply_persistent(card, [card])
	assert_almost_eq(card.stacks[0]["temp_atk_mult"], 1.40, 0.001,
		"★2 self solo → ATK +40% (include_self)")


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
# ne_nexus (T5 OE) — mirror_l1, cross_theme filter, multi-block
# 2026-04-27: filter non_neutral_target → cross_theme.
# 발동 카드(source) 와 이벤트 대상(target) 의 테마가 서로 다를 때만 fire.
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


func test_nexus_same_theme_filtered() -> void:
	## source/target 같은 테마 (steampunk → steampunk) → cross_theme false → 무시.
	var card: CardInstance = CardInstance.create("ne_nexus")
	var sp1: CardInstance = CardInstance.create("sp_assembly")
	var sp2: CardInstance = CardInstance.create("sp_furnace")
	var board: Array = [card, sp1, sp2]
	var event := _make_event(Enums.Layer1.UNIT_ADDED, 1, 2)
	_sys.process_event_card(card, 0, board, event, _rng)
	assert_almost_eq(card.growth_atk_pct, 0.0, 0.001, "같은 테마 → 무시")


func test_nexus_star1_cross_theme_enhances() -> void:
	## 다른 테마 (sp → ne_target) UA → self ATK +2%.
	var card: CardInstance = CardInstance.create("ne_nexus")
	var sp: CardInstance = CardInstance.create("sp_assembly")  # source
	var ne_t: CardInstance = CardInstance.create("ne_earth_echo")  # target (neutral)
	var board: Array = [card, sp, ne_t]
	var event := _make_event(Enums.Layer1.UNIT_ADDED, 1, 2)
	_sys.process_event_card(card, 0, board, event, _rng)
	assert_almost_eq(card.growth_atk_pct, 0.02, 0.001, "★1 cross-theme UA → +2% ATK")


func test_nexus_star1_en_event_also_fires() -> void:
	## EN 이벤트도 별도 OE block 으로 listen → cross-theme 시 ATK +2%.
	var card: CardInstance = CardInstance.create("ne_nexus")
	var sp: CardInstance = CardInstance.create("sp_assembly")
	var ml_t: CardInstance = CardInstance.create("ml_barracks")
	var board: Array = [card, sp, ml_t]
	var event := _make_event(Enums.Layer1.ENHANCED, 1, 2)
	_sys.process_event_card(card, 0, board, event, _rng)
	assert_almost_eq(card.growth_atk_pct, 0.02, 0.001, "★1 cross-theme EN → +2% ATK")


func test_nexus_star3_spawns_unit() -> void:
	## ★3: spawn_unit=1 → cross-theme 시 첫 stack unit 1기 추가.
	var card: CardInstance = CardInstance.create("ne_nexus")
	card.evolve_star()
	card.evolve_star()
	var sp: CardInstance = CardInstance.create("sp_assembly")
	var ml_t: CardInstance = CardInstance.create("ml_barracks")
	var board: Array = [card, sp, ml_t]
	var before_units: int = card.get_total_units()
	var event := _make_event(Enums.Layer1.UNIT_ADDED, 1, 2)
	_sys.process_event_card(card, 0, board, event, _rng)
	assert_eq(card.get_total_units(), before_units + 1, "★3 cross-theme → 유닛 1기 spawn")


func test_nexus_star2_atk_and_hp() -> void:
	## ★2: cross-theme ATK +3%, HP +1%.
	var card: CardInstance = CardInstance.create("ne_nexus")
	card.evolve_star()
	var sp: CardInstance = CardInstance.create("sp_assembly")
	var ml_t: CardInstance = CardInstance.create("ml_barracks")
	var board: Array = [card, sp, ml_t]
	var event := _make_event(Enums.Layer1.UNIT_ADDED, 1, 2)
	_sys.process_event_card(card, 0, board, event, _rng)
	assert_almost_eq(card.growth_atk_pct, 0.03, 0.001, "★2 cross-theme UA → ATK +3%")
	assert_almost_eq(card.growth_hp_pct, 0.01, 0.001, "★2 cross-theme UA → HP +1%")


func test_nexus_omni_target_filtered() -> void:
	## omni-theme target 은 모든 테마 매치 → cross_theme false → 무시.
	var card: CardInstance = CardInstance.create("ne_nexus")
	var sp: CardInstance = CardInstance.create("sp_assembly")
	var omni: CardInstance = CardInstance.create("ml_barracks")
	omni.is_omni_theme = true
	var board: Array = [card, sp, omni]
	var event := _make_event(Enums.Layer1.UNIT_ADDED, 1, 2)
	_sys.process_event_card(card, 0, board, event, _rng)
	assert_almost_eq(card.growth_atk_pct, 0.0, 0.001, "omni target → 무시 (모든 테마 매치)")


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
# ne_council ★2/★3 council_epic_grant — 카운터 시스템
# ================================================================


func test_council_star2_yaml_has_council_epic_grant() -> void:
	## ★2 effects의 RS block에 council_epic_grant action threshold=5
	var blocks := CardDB.get_effect_blocks("ne_council", 2)
	var found := false
	for block in blocks:
		if block.get("trigger_timing") != Enums.TriggerTiming.ROUND_START:
			continue
		for a in block.get("actions", []):
			if a.get("action") == "council_epic_grant":
				assert_eq(a.get("threshold", 0), 5, "★2 threshold = 5")
				found = true
	assert_true(found, "★2에 council_epic_grant 존재")


func test_council_star3_yaml_has_council_epic_grant() -> void:
	## ★3 effects의 RS block에 council_epic_grant action threshold=3
	var blocks := CardDB.get_effect_blocks("ne_council", 3)
	var found := false
	for block in blocks:
		if block.get("trigger_timing") != Enums.TriggerTiming.ROUND_START:
			continue
		for a in block.get("actions", []):
			if a.get("action") == "council_epic_grant":
				assert_eq(a.get("threshold", 0), 3, "★3 threshold = 3")
				found = true
	assert_true(found, "★3에 council_epic_grant 존재")


func test_game_state_council_counter_initial_zero() -> void:
	## council_counter 초기값 검증 (사용자 결정 후 council_bonus_used 폐기)
	var state := GameState.new()
	assert_eq(state.council_counter, 0, "초기 counter = 0")


# ================================================================
# ne_awakening SELL — transfer_units_and_upgrade
# ================================================================


func test_awakening_sell_returns_awakening_transfer() -> void:
	## ne_awakening ★1 SELL → awakening_transfer dict 반환 (rarity=common, transfer_units=false)
	var card: CardInstance = CardInstance.create("ne_awakening")
	card.attach_upgrade("C1")
	var other: CardInstance = CardInstance.create("sp_assembly")
	var board: Array = [card, other]
	var result := _sys.process_self_sell(card, board)
	var awakening: Dictionary = result.get("awakening_transfer", {})
	assert_false(awakening.is_empty(), "★1 awakening_transfer 존재")
	assert_eq(awakening.get("rarity", ""), "common", "★1 = common rarity")
	assert_false(awakening.get("transfer_units", true), "★1 = transfer_units=false")
	assert_eq(result.get("needs_target_select", ""), "ne_awakening",
		"needs_target_select=ne_awakening")


func test_awakening_star2_transfer_rare_with_units() -> void:
	## ★2: rarity=rare, transfer_units=true
	var card: CardInstance = CardInstance.create("ne_awakening")
	card.evolve_star()  # ★2
	var other: CardInstance = CardInstance.create("sp_assembly")
	var board: Array = [card, other]
	var result := _sys.process_self_sell(card, board)
	var awakening: Dictionary = result.get("awakening_transfer", {})
	assert_eq(awakening.get("rarity", ""), "rare", "★2 = rare")
	assert_true(awakening.get("transfer_units", false), "★2 = transfer_units=true")


func test_awakening_star3_transfer_epic_with_units() -> void:
	## ★3: rarity=epic, transfer_units=true
	var card: CardInstance = CardInstance.create("ne_awakening")
	card.evolve_star()
	card.evolve_star()  # ★3
	var other: CardInstance = CardInstance.create("sp_assembly")
	var board: Array = [card, other]
	var result := _sys.process_self_sell(card, board)
	var awakening: Dictionary = result.get("awakening_transfer", {})
	assert_eq(awakening.get("rarity", ""), "epic", "★3 = epic")
	assert_true(awakening.get("transfer_units", false), "★3 = transfer_units=true")


func test_awakening_sell_no_target_returns_empty() -> void:
	## ne_awakening 단독 보드 (다른 카드 없음) → target 없음 → 빈 결과
	var card: CardInstance = CardInstance.create("ne_awakening")
	var board: Array = [card]
	var result := _sys.process_self_sell(card, board)
	assert_true(result.get("awakening_transfer", {}).is_empty(),
		"target 없으면 awakening_transfer 미발동")


# ================================================================
# 통합 검증 — _sim_apply_awakening_transfer (sim 경로) edge cases
# ================================================================


func _attach_upgrade_helper(card: CardInstance, upgrade_id: String) -> void:
	var u := UpgradeDB.get_upgrade(upgrade_id)
	if not u.is_empty():
		card.upgrades.append(u)


func test_apply_awakening_transfer_no_matching_rarity_no_op() -> void:
	## ne_awakening ★1 (rarity=common)인데 부착 업글이 모두 레어 → 매치 0개 → 업글 이전 X
	var source: CardInstance = CardInstance.create("ne_awakening")
	var target: CardInstance = CardInstance.create("sp_assembly")
	# 레어 업글 부착 (R2 산탄개조 등 — common이 아닌 것)
	_attach_upgrade_helper(source, "R2")
	var target_upg_before: int = target.upgrades.size()
	# sim 경로 직접 시뮬: rarity_int = COMMON, matching = []
	var awakening: Dictionary = {
		"source_card": source,
		"target_card": target,
		"rarity": "common",
		"transfer_units": false,
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var runner_script = load("res://sim/headless_runner.gd")
	var runner = runner_script.new(Genome.create_default(), "auto", 42)
	runner._sim_apply_awakening_transfer(awakening, rng)
	assert_eq(target.upgrades.size(), target_upg_before,
		"매치 등급 없으면 target 업글 변화 없음")


func test_apply_awakening_transfer_target_slot_full_silent_fail() -> void:
	## target 업글 슬롯 5개 만석 → 업글 이전 silent fail (단순화: 업글만 검증)
	var source: CardInstance = CardInstance.create("ne_awakening")
	var target: CardInstance = CardInstance.create("sp_assembly")
	# source에 common 업글
	_attach_upgrade_helper(source, "C1")
	# target 슬롯 5개 만석 (C1~C5 또는 더미)
	for upg_id in ["C1", "C2", "C3", "C4", "C5"]:
		_attach_upgrade_helper(target, upg_id)
	assert_eq(target.upgrades.size(), 5, "target 슬롯 만석")
	var awakening: Dictionary = {
		"source_card": source,
		"target_card": target,
		"rarity": "common",
		"transfer_units": false,
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var runner_script = load("res://sim/headless_runner.gd")
	var runner = runner_script.new(Genome.create_default(), "auto", 42)
	runner._sim_apply_awakening_transfer(awakening, rng)
	# 업글 슬롯 만석이라 추가 안 됨 (silent fail)
	assert_eq(target.upgrades.size(), 5, "만석 silent fail — 업글 5개 유지")


func test_apply_awakening_transfer_applies_upgrade_stat_mods() -> void:
	var source: CardInstance = CardInstance.create("ne_awakening")
	var target: CardInstance = CardInstance.create("sp_assembly")
	_attach_upgrade_helper(source, "C1")
	var target_atk_before: float = target.get_total_atk()
	var awakening: Dictionary = {
		"source_card": source,
		"target_card": target,
		"rarity": "common",
		"transfer_units": false,
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var runner_script = load("res://sim/headless_runner.gd")
	var runner = runner_script.new(Genome.create_default(), "auto", 42)
	runner._sim_apply_awakening_transfer(awakening, rng)

	assert_eq(target.upgrades.size(), 1,
		"Awakening attaches one matching upgrade to the target")
	assert_almost_eq(target.get_total_atk(), target_atk_before * 1.15,
		target_atk_before * 0.01,
		"transferred common upgrade applies its ATK stat modifier")


func test_apply_awakening_transfer_units_cap_60() -> void:
	## ★2 transfer_units=true, target 50기 + ne_awakening 30기 → cap 60 적용 → 10기만 이전
	var source: CardInstance = CardInstance.create("ne_awakening")
	source.evolve_star()  # ★2
	# source의 stack을 30기로 설정 (기본 6기 → 30기 강제)
	source.stacks[0]["count"] = 30
	# target sp_assembly에 50기 부여
	var target: CardInstance = CardInstance.create("sp_assembly")
	target.stacks = [target.stacks[0]]
	target.stacks[0]["count"] = 50
	assert_eq(target.get_total_units(), 50, "target 50기")
	var awakening: Dictionary = {
		"source_card": source,
		"target_card": target,
		"rarity": "rare",
		"transfer_units": true,
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var runner_script = load("res://sim/headless_runner.gd")
	var runner = runner_script.new(Genome.create_default(), "auto", 42)
	runner._sim_apply_awakening_transfer(awakening, rng)
	# cap 60 적용 — target은 60기 도달 (room 10만 추가)
	assert_eq(target.get_total_units(), 60, "cap 60 적용")


func test_apply_awakening_transfer_units_full_cap_no_transfer() -> void:
	## target이 이미 cap 도달 → 유닛 0기 추가
	var source: CardInstance = CardInstance.create("ne_awakening")
	source.evolve_star()
	source.stacks[0]["count"] = 30
	var target: CardInstance = CardInstance.create("sp_assembly")
	target.stacks[0]["count"] = target.get_unit_cap()  # cap 도달
	var units_before: int = target.get_total_units()
	var awakening: Dictionary = {
		"source_card": source,
		"target_card": target,
		"rarity": "rare",
		"transfer_units": true,
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var runner_script = load("res://sim/headless_runner.gd")
	var runner = runner_script.new(Genome.create_default(), "auto", 42)
	runner._sim_apply_awakening_transfer(awakening, rng)
	assert_eq(target.get_total_units(), units_before, "cap 도달 → 추가 없음")


# ================================================================
# ne_masquerade UI flow 메타 검증
# ================================================================


func test_masquerade_sell_returns_needs_target_select() -> void:
	## ne_masquerade SELL → needs_target_select="ne_masquerade" 메타 포함 (UI 분기용)
	var card: CardInstance = CardInstance.create("ne_masquerade")
	var other: CardInstance = CardInstance.create("sp_assembly")
	var board: Array = [card, other]
	var result := _sys.process_self_sell(card, board)
	assert_eq(result.get("needs_target_select", ""), "ne_masquerade",
		"needs_target_select=ne_masquerade")
	assert_false(result.get("transform_theme", {}).is_empty(),
		"transform_theme dict 존재")


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


func test_fusion_end_star1_aura_buffs_star3_allies_only() -> void:
	## ★1 fusion_end: 각 ★≥2 아군 +30%/+15% buff. self ★1 < min_star → 자기 미적용.
	var card: CardInstance = CardInstance.create("ne_fusion_end")
	var ally1: CardInstance = CardInstance.create("sp_assembly")
	ally1.evolve_star()
	ally1.evolve_star()  # ★3
	var ally2: CardInstance = CardInstance.create("ne_earth_echo")
	ally2.evolve_star()
	ally2.evolve_star()  # ★3
	_sys.apply_persistent(card, [card, ally1, ally2])
	# self ★1 < min_star=2 → no buff
	assert_almost_eq(card.stacks[0]["temp_atk_mult"], 1.0, 0.001,
		"★1 self < min_star → no buff")
	# 두 ★3 ally 각자 +30%/+15%
	assert_almost_eq(ally1.stacks[0]["temp_atk_mult"], 1.30, 0.001,
		"★3 ally1 → ATK +30%")
	assert_almost_eq(ally1.stacks[0]["temp_hp_mult"], 1.15, 0.001,
		"★3 ally1 → HP +15%")
	assert_almost_eq(ally2.stacks[0]["temp_atk_mult"], 1.30, 0.001,
		"★3 ally2 → ATK +30%")
