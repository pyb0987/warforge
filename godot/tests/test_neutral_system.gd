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
	var board: Array = []
	for i in Enums.MAX_FIELD_SLOTS:
		if i == 0:
			board.append(card)
		else:
			board.append(CardInstance.create("ne_scrap" if false else "sp_assembly"))
	# stack temp_atk_mult 변화 없음
	_sys.apply_battle_start(card, 0, board)
	assert_almost_eq(card.stacks[0]["temp_atk_mult"], 1.0, 0.001, "E=0 → buff 0")


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
	# allies ATK +M×7% = +21% (자기 제외)
	assert_almost_eq(ally1.stacks[0]["temp_atk_mult"], 1.0 + 0.07 * 3, 0.001, "ally ATK ×1.21")


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
