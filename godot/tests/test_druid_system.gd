extends GutTest
## DruidSystem 테마 로직 테스트
## 참조: druid_system.gd, handoff.md P4-A
##
## 🌳 트리 관리 / RS 카드 / on_sell / BS shield / PC gold 검증.


var _sys: DruidSystem = null
var _rng: RandomNumberGenerator = null


func before_each() -> void:
	_sys = DruidSystem.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 42


func test_druid_theme_system_handles_all_current_yaml_actions() -> void:
	var handled := {
		Enums.TriggerTiming.ROUND_START: [
			"tree_add", "tree_absorb", "tree_enhance", "prune",
			"tree_distribute", "multiply_stats", "epic_shop_unlock",
		],
		Enums.TriggerTiming.BATTLE_START: [
			"tree_add", "tree_shield", "tree_combat_bonus", "debuff_store",
		],
		Enums.TriggerTiming.PERSISTENT: ["tree_temp_buff"],
		Enums.TriggerTiming.POST_COMBAT: ["tree_gold", "free_reroll"],
		Enums.TriggerTiming.ON_EVENT: ["listen", "mirror_spawn_to_tree"],
	}

	for card_id in CardDB.get_ids_by_theme(Enums.CardTheme.DRUID):
		for star in [1, 2, 3]:
			for block in CardDB.get_effect_blocks(card_id, star):
				var timing: int = block.get("trigger_timing", -1)
				var timing_actions: Array = handled.get(timing, [])
				for eff in block.get("actions", []):
					var action: String = eff.get("action", "")
					assert_true(timing_actions.has(action),
						"%s★%d timing %d action %s has Druid runtime coverage"
							% [card_id, star, timing, action])


# ================================================================
# dr_cradle (RS): 🌳+1 self, +1 right druid
# ================================================================

func test_cradle_adds_1_tree_to_self() -> void:
	var board: Array = [CardInstance.create("dr_cradle")]
	_sys.process_rs_card(board[0], 0, board, _rng)
	assert_eq(board[0].theme_state.get("trees", 0), 1, "🌳+1 self")


func test_cradle_adds_1_tree_to_right_druid_adj() -> void:
	var board: Array = [CardInstance.create("dr_cradle"), CardInstance.create("dr_origin")]
	_sys.process_rs_card(board[0], 0, board, _rng)
	assert_eq(board[0].theme_state.get("trees", 0), 1, "cradle 🌳=1")
	assert_eq(board[1].theme_state.get("trees", 0), 1, "right druid 🌳=1")


func test_cradle_no_tree_to_non_druid_right() -> void:
	var board: Array = [CardInstance.create("dr_cradle"), CardInstance.create("sp_assembly")]
	_sys.process_rs_card(board[0], 0, board, _rng)
	assert_eq(board[1].theme_state.get("trees", 0), 0, "비드루이드 → 🌳 없음")


# ================================================================
# dr_deep (RS): 🌳+1, growth = trees × 0.008
# ================================================================

func test_deep_adds_1_tree_per_round() -> void:
	var card: CardInstance = CardInstance.create("dr_deep")
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(card.theme_state.get("trees", 0), 1, "🌳+1")


func test_deep_star1_growth_rate_0012() -> void:
	var card: CardInstance = CardInstance.create("dr_deep")
	var atk_before: float = card.get_total_atk()
	_sys.process_rs_card(card, 0, [card], _rng)
	# trees=1, units=2(<=3) → low_rate=0.012, growth=1×0.012=0.012
	var expected: float = atk_before * (1.0 + 0.012)
	assert_almost_eq(card.get_total_atk(), expected, 0.01, "growth=1×0.012")


func test_deep_mult_threshold_10_applies_130() -> void:
	var card: CardInstance = CardInstance.create("dr_deep")
	card.theme_state["trees"] = 9
	var atk_before: float = card.get_total_atk()
	_sys.process_rs_card(card, 0, [card], _rng)
	# trees=10, units=2(<=3) → low_rate=0.012, growth=10×0.012=0.12, ×1.3=0.156
	var expected: float = atk_before * (1.0 + 0.156)
	assert_almost_eq(card.get_total_atk(), expected, 0.01, "🌳10+ → ×1.3 배율")


# ================================================================
# dr_world (RS): 🌳+2, 누적 가산 ATK/HP/AS 동시 +per_step (2026-04-28 재설계)
# ================================================================

func test_world_no_buff_below_tree_step() -> void:
	## ★1 tree_step=30 — trees<30 이면 increment=0, buff_pct 변화 없음.
	var card: CardInstance = CardInstance.create("dr_world")
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_almost_eq(card.unique_buff_pct, 0.0, 0.0001, "trees=2 < 30 → 누적 0")


func test_world_buff_accumulates_at_threshold() -> void:
	## trees ≥ tree_step (30) 이면 1 step 기여 (per_step=0.05).
	var card: CardInstance = CardInstance.create("dr_world")
	card.theme_state["trees"] = 28  # +2 self → 30
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_almost_eq(card.unique_buff_pct, 0.05, 0.0001, "trees=30 → +0.05")


func test_world_buff_cumulative_across_rounds() -> void:
	## 매 라운드 누적 (replace 가 아님). 동일 trees 로 2 회 RS → +0.10.
	var card: CardInstance = CardInstance.create("dr_world")
	card.theme_state["trees"] = 28  # +2 = 30
	_sys.process_rs_card(card, 0, [card], _rng)
	# 두 번째 RS: trees 는 30 → 32 → forest_depth=32, increment = floor(32/30)*0.05 = 0.05
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_almost_eq(card.unique_buff_pct, 0.10, 0.0001, "2회 누적 +0.10")


func test_world_atk_hp_move_together() -> void:
	## atk/hp 가 같은 buff 로 derive. 매 RS 마다 일관.
	var card: CardInstance = CardInstance.create("dr_world")
	card.theme_state["trees"] = 28
	_sys.process_rs_card(card, 0, [card], _rng)
	for s in card.stacks:
		assert_almost_eq(float(s["unique_atk_mult"]), float(s["unique_hp_mult"]),
			0.0001, "ATK/HP unique mult 동일")


func test_world_as_inverted_for_faster_attacks() -> void:
	## unique_as_mult = 1/(1 + buff_pct) — buff 가 커질수록 attack_speed 감소(=빨라짐).
	var card: CardInstance = CardInstance.create("dr_world")
	card.theme_state["trees"] = 28
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_almost_eq(card.unique_as_mult, 1.0 / 1.05, 0.0001,
		"unique_as_mult = 1/(1+0.05)")


func test_world_adds_2_trees_to_self() -> void:
	var card: CardInstance = CardInstance.create("dr_world")
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(card.theme_state.get("trees", 0), 2, "🌳+2 self")


# ================================================================
# on_sell: 판매 시 다른 드루이드에게 🌳 분배
# ================================================================

func test_on_sell_distributes_all_trees_to_others() -> void:
	var sold: CardInstance = CardInstance.create("dr_cradle")
	sold.theme_state["trees"] = 6
	var other: CardInstance = CardInstance.create("dr_origin")
	_sys.on_sell(sold, [other])
	assert_eq(other.theme_state.get("trees", 0), 6, "6🌳 전부 전달")


func test_on_sell_divides_evenly_multiple_druids() -> void:
	var sold: CardInstance = CardInstance.create("dr_cradle")
	sold.theme_state["trees"] = 6
	var dr1: CardInstance = CardInstance.create("dr_origin")
	var dr2: CardInstance = CardInstance.create("dr_deep")
	_sys.on_sell(sold, [dr1, dr2])
	assert_eq(dr1.theme_state.get("trees", 0), 3, "dr1 🌳=3")
	assert_eq(dr2.theme_state.get("trees", 0), 3, "dr2 🌳=3")


func test_on_sell_ignores_non_druid_sold() -> void:
	var sold: CardInstance = CardInstance.create("sp_assembly")
	sold.theme_state["trees"] = 5
	var dr: CardInstance = CardInstance.create("dr_origin")
	_sys.on_sell(sold, [dr])
	assert_eq(dr.theme_state.get("trees", 0), 0, "비드루이드 판매 → 무시")


# ================================================================
# apply_battle_start: dr_lifebeat → shield
# ================================================================

func test_lifebeat_battle_adds_base_shield_005() -> void:
	## trees=0, ★1: shield = 0.05 + 0×0.03 = 0.05
	## lifebeat BS에서 🌳+1 먼저 추가됨 → trees=1 → shield = 0.05 + 1×0.03 = 0.08
	var card: CardInstance = CardInstance.create("dr_lifebeat")
	_sys.apply_battle_start(card, 0, [card])
	# lifebeat._lifebeat_battle: _add_trees(card, 1) → trees=1, shield = 0.05 + 1*0.03 = 0.08
	# units=2(<=2) → ×1.5 = 0.12
	assert_almost_eq(card.shield_hp_pct, 0.12, 0.001, "trees=1, ≤2units → shield=0.12")


func test_lifebeat_shield_increases_with_trees() -> void:
	var card: CardInstance = CardInstance.create("dr_lifebeat")
	card.theme_state["trees"] = 3
	_sys.apply_battle_start(card, 0, [card])
	# _add_trees → trees=4, shield = 0.05 + 4*0.03 = 0.17
	# units=2(<=2) → ×1.5 = 0.255
	assert_almost_eq(card.shield_hp_pct, 0.255, 0.001, "trees=4 → shield=0.255")


func test_common_tree_combat_bonus_scales_with_own_trees() -> void:
	var card: CardInstance = CardInstance.create("dr_cradle")
	card.theme_state["trees"] = 5
	var atk_before: float = card.get_total_atk()
	var hp_before: float = card.get_total_hp()
	_sys.apply_battle_start(card, 0, [card])
	assert_almost_eq(card.get_total_atk(), atk_before * 1.25, 0.01,
		"5🌳 → ATK +25% 이번 전투")
	assert_almost_eq(card.get_total_hp(), hp_before * 1.25, 0.01,
		"5🌳 → HP +25% 이번 전투")


func test_common_tree_combat_bonus_caps_at_60_percent() -> void:
	var card: CardInstance = CardInstance.create("dr_cradle")
	card.theme_state["trees"] = 15
	var atk_before: float = card.get_total_atk()
	var hp_before: float = card.get_total_hp()
	_sys.apply_battle_start(card, 0, [card])
	assert_almost_eq(card.get_total_atk(), atk_before * 1.60, 0.01,
		"15🌳 → ATK cap +60%")
	assert_almost_eq(card.get_total_hp(), hp_before * 1.60, 0.01,
		"15🌳 → HP cap +60%")


func test_common_tree_combat_bonus_clears_after_combat() -> void:
	var card: CardInstance = CardInstance.create("dr_cradle")
	card.theme_state["trees"] = 10
	var atk_before: float = card.get_total_atk()
	_sys.apply_battle_start(card, 0, [card])
	assert_gt(card.get_total_atk(), atk_before, "전투 중 임시 보너스 적용")
	card.clear_temp_buffs()
	assert_almost_eq(card.get_total_atk(), atk_before, 0.01,
		"clear_temp_buffs 후 영구 성장으로 남지 않음")


func test_lifebeat_common_bonus_counts_battle_tree() -> void:
	var card: CardInstance = CardInstance.create("dr_lifebeat")
	var atk_before: float = card.get_total_atk()
	_sys.apply_battle_start(card, 0, [card])
	assert_almost_eq(card.get_total_atk(), atk_before * 1.05, 0.01,
		"lifebeat BS 🌳+1 이후 공통 보너스 +5%")


# ================================================================
# apply_post_combat: dr_grace
# ================================================================

func test_grace_victory_earns_gold() -> void:
	var card: CardInstance = CardInstance.create("dr_grace")
	var result: Dictionary = _sys.apply_post_combat(card, 0, [card], true)
	# trees=0, ★1: gold = 1 + 0/3 = 1
	assert_eq(result["gold"], 1, "승리 골드=1")


func test_grace_trees_bonus_gold() -> void:
	var card: CardInstance = CardInstance.create("dr_grace")
	card.theme_state["trees"] = 6
	var result: Dictionary = _sys.apply_post_combat(card, 0, [card], true)
	# trees=6, ★1: gold = 1 + 6/3 = 3
	assert_eq(result["gold"], 3, "trees=6 → 골드=3")


func test_grace_s3_returns_free_reroll_signal() -> void:
	var card := _make_star("dr_grace", 3)
	var result: Dictionary = _sys.apply_post_combat(card, 0, [card], true)
	assert_eq(result.get("free_rerolls", 0), 1, "★3 → free reroll signal")


# ================================================================
# dr_origin (RS): 🌳+1, 인접 드루이드에서 🌳 흡수, all_druid tree_enhance
# ================================================================

func test_origin_adds_1_tree() -> void:
	var card: CardInstance = CardInstance.create("dr_origin")
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(card.theme_state.get("trees", 0), 1, "🌳+1")


func test_origin_absorbs_tree_from_adj_druid() -> void:
	var board: Array = [CardInstance.create("dr_cradle"), CardInstance.create("dr_origin")]
	board[0].theme_state["trees"] = 3
	_sys.process_rs_card(board[1], 1, board, _rng)
	# dr_origin ★1: 인접 드루이드에서 1 🌳 흡수
	assert_eq(board[1].theme_state.get("trees", 0), 2, "origin 🌳=1+1흡수=2")
	assert_eq(board[0].theme_state.get("trees", 0), 2, "cradle 🌳=3-1=2")


# ================================================================
# dr_prune (RS): 🌳+1, 유닛 최다 카드의 최약 유닛 → 🌳 변환
# ================================================================

func test_prune_adds_1_tree_to_self() -> void:
	var card: CardInstance = CardInstance.create("dr_prune")
	var target: CardInstance = CardInstance.create("dr_cradle")
	target.add_specific_unit("dr_wolf", 5)  # enough units to prune
	_sys.process_rs_card(card, 0, [card, target], _rng)
	assert_eq(card.theme_state.get("trees", 0), 1, "self 🌳+1")


func test_prune_removes_weakest_and_adds_trees() -> void:
	## ★1: count=2, min_units=3. Target needs ≥3 units.
	var prune: CardInstance = CardInstance.create("dr_prune")
	var target: CardInstance = CardInstance.create("dr_cradle")
	target.add_specific_unit("dr_wolf", 3)  # 2 base + 3 = 5 units
	var units_before: int = target.get_total_units()
	_sys.process_rs_card(prune, 0, [prune, target], _rng)
	assert_eq(target.get_total_units(), units_before - 2, "2기 가지치기")
	assert_gte(target.theme_state.get("trees", 0), 2, "가지치기한 카드에 🌳+2")


func test_prune_skips_when_too_few_units() -> void:
	## min_units=3 → skip if target has < 3 units
	var prune: CardInstance = CardInstance.create("dr_prune")
	var target: CardInstance = CardInstance.create("dr_cradle")  # 2 base units
	var units_before: int = target.get_total_units()
	_sys.process_rs_card(prune, 0, [prune, target], _rng)
	assert_eq(target.get_total_units(), units_before, "2기 → 스킵")


# ================================================================
# dr_wt_root (RS): 🌳+1, 임계값에 따라 다른 드루이드에 🌳 분배
# ================================================================

func test_wt_root_adds_1_tree() -> void:
	var card: CardInstance = CardInstance.create("dr_wt_root")
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(card.theme_state.get("trees", 0), 1, "🌳+1")


func test_wt_root_distributes_trees_at_threshold() -> void:
	## ★1: 🌳≥4 → 다른 드루이드에 +1, 🌳≥8 → +2
	var board: Array = [CardInstance.create("dr_wt_root"), CardInstance.create("dr_cradle")]
	board[0].theme_state["trees"] = 3  # +1 → 4 → 임계값 도달
	_sys.process_rs_card(board[0], 0, board, _rng)
	assert_eq(board[0].theme_state.get("trees", 0), 4, "wt_root 🌳=4")
	assert_gte(board[1].theme_state.get("trees", 0), 1, "cradle 🌳≥1 (분배)")


# ================================================================
# dr_spore_cloud (BS): 적 AS/ATK 디버프
# ================================================================

func test_spore_cloud_sets_enemy_as_debuff() -> void:
	## ★1: enemy_as_debuff = min(0.15 + trees*0.015, 0.50)
	var card: CardInstance = CardInstance.create("dr_spore_cloud")
	card.theme_state["trees"] = 5
	_sys.apply_battle_start(card, 0, [card])
	# 0.15 + 5*0.015 = 0.225
	assert_almost_eq(card.theme_state.get("enemy_as_debuff", 0.0), 0.225, 0.001, "AS 디버프=0.225")


func test_spore_cloud_s2_sets_enemy_as_and_atk_debuff() -> void:
	## ★2: enemy debuff = min(0.20 + trees*0.02, 0.50)
	var card := _make_star("dr_spore_cloud", 2)
	card.theme_state["trees"] = 5
	_sys.apply_battle_start(card, 0, [card])
	assert_almost_eq(card.theme_state.get("enemy_as_debuff", 0.0), 0.3, 0.001,
		"★2 AS 디버프=0.30")
	assert_almost_eq(card.theme_state.get("enemy_atk_debuff", 0.0), 0.3, 0.001,
		"★2 ATK 디버프=0.30")


func test_spore_cloud_s3_applies_debuffs_and_self_shield() -> void:
	var card := _make_star("dr_spore_cloud", 3)
	card.theme_state["trees"] = 5
	_sys.apply_battle_start(card, 0, [card])
	assert_almost_eq(card.theme_state.get("enemy_as_debuff", 0.0), 0.425, 0.001,
		"★3 AS 디버프=0.425")
	assert_almost_eq(card.theme_state.get("enemy_atk_debuff", 0.0), 0.4, 0.001,
		"★3 ATK 디버프=0.4")
	assert_almost_eq(card.shield_hp_pct, 0.2, 0.001,
		"★3 shield=0.10+🌳5×0.02")


# ================================================================
# dr_wrath (PERSISTENT): 유닛 상한 ★1=3, ★2=8, ★3=16. 상한 이내일 때 전투 버프.
# ================================================================

func test_wrath_persistent_buffs_when_few_units() -> void:
	## ★1: ≤3기일 때 temp_buff(null, 0.80 + trees*0.05)
	var card: CardInstance = CardInstance.create("dr_wrath")
	card.theme_state["trees"] = 4
	var atk_before: float = card.get_total_atk()
	_sys.apply_persistent(card)
	# 0.80 + 4*0.05 = 1.00 → base ATK +100%
	assert_almost_eq(card.get_total_atk(), atk_before * 2.0, 0.01,
		"≤3기 → ATK +100%")


func _make_star(base_id: String, star: int) -> CardInstance:
	var card: CardInstance = CardInstance.create(base_id)
	for _i in star - 1:
		card.evolve_star()
	return card


# ================================================================
# ★2/★3 태고의 분노 (PERSISTENT buff)
# ================================================================

func test_wrath_s2_higher_buff() -> void:
	## ★2: 1.20 + trees*0.08 (★1은 0.80 + trees*0.05)
	var card := _make_star("dr_wrath", 2)
	card.theme_state["trees"] = 5
	var atk_before: float = card.get_total_atk()
	var hp_before: float = card.get_total_hp()
	_sys.apply_persistent(card)
	# 1.20 + 5*0.08 = 1.60 → base ATK +160%
	assert_almost_eq(card.get_total_atk(), atk_before * 2.6, 0.01,
		"★2 → ATK +160%")
	assert_almost_eq(card.get_total_hp(), hp_before * 1.6, 0.01,
		"★2 → HP +60%")


func test_wrath_s3_uses_mult_buff() -> void:
	## ★3: temp_mult_buff(1.5, 1.3) + kill HP recovery — 곱연산
	var card := _make_star("dr_wrath", 3)
	card.theme_state["trees"] = 0
	var atk_before: float = card.get_total_atk()
	var hp_before: float = card.get_total_hp()
	_sys.apply_persistent(card)
	assert_gt(card.get_total_atk(), atk_before, "★3 → ATK ×1.5")
	assert_gt(card.get_total_hp(), hp_before, "★3 → HP ×1.3")
	assert_almost_eq(card.theme_state.get("kill_hp_recover_pct", 0.0), 0.15, 0.001,
		"★3 → kill HP recovery 15%")


func test_wrath_s3_skips_if_over_unit_cap() -> void:
	## 2026-04-26 cap 재조정 (3/8/16): 2장분량 흡수 정책 정합 (★1×3 fresh skip → ★2 4u, ★2×3 fresh skip → ★3 8u 기준 + 50% 버퍼).
	## ★3 cap=16 → 17기이면 미적용. 기존 3기 + 14기 = 17기.
	var card := _make_star("dr_wrath", 3)
	card.add_specific_unit("dr_boar", 14)
	card.theme_state["kill_hp_recover_pct"] = 0.15
	var atk_before: float = card.get_total_atk()
	var hp_before: float = card.get_total_hp()
	_sys.apply_persistent(card)
	assert_eq(card.get_total_atk(), atk_before, "17기 → 미적용 (cap 16)")
	assert_eq(card.get_total_hp(), hp_before, "17기 → HP도 미적용 (cap 16)")
	assert_almost_eq(card.theme_state.get("kill_hp_recover_pct", 0.0), 0.0, 0.001,
		"17기 → kill HP recovery도 미적용")


# ================================================================
# ★2/★3 세계수의 뿌리 (RS tree distribution thresholds)
# ================================================================

func test_wt_root_s2_lower_threshold() -> void:
	## ★2: thresh_low=3 (★1은 4). 🌳3에서 전체 +1 분배
	var card := _make_star("dr_wt_root", 2)
	card.theme_state["trees"] = 2  # +1 → 3 → thresh_low=3 도달
	var other: CardInstance = CardInstance.create("dr_cradle")
	var other_trees_before: int = other.theme_state.get("trees", 0)
	_sys.process_rs_card(card, 0, [card, other], _rng)
	assert_gt(other.theme_state.get("trees", 0), other_trees_before, "★2 🌳3 → 분배")


func test_wt_root_s1_no_dist_at_3() -> void:
	## ★1: thresh_low=4. 🌳3에서는 미분배
	var card: CardInstance = CardInstance.create("dr_wt_root")
	card.theme_state["trees"] = 2  # +1 → 3 < 4
	var other: CardInstance = CardInstance.create("dr_cradle")
	_sys.process_rs_card(card, 0, [card, other], _rng)
	assert_eq(other.theme_state.get("trees", 0), 0, "★1 🌳3 < 4 → 미분배")


func test_wt_root_s3_adds_2_trees() -> void:
	## ★3: 🌳+2 (★1/★2는 +1)
	var card := _make_star("dr_wt_root", 3)
	var trees_before: int = card.theme_state.get("trees", 0)
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(card.theme_state.get("trees", 0), trees_before + 2, "★3 🌳+2")


# ================================================================
# ★2/★3 세계수 (RS growth multipliers)
# ================================================================

func test_world_s2_self_trees_3() -> void:
	## ★2: self_trees=3 (★1은 2)
	var card := _make_star("dr_world", 2)
	var trees_before: int = card.theme_state.get("trees", 0)
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(card.theme_state.get("trees", 0), trees_before + 3, "★2 self 🌳+3")


func test_world_s2_smaller_tree_step_easier_to_trigger() -> void:
	## ★2: tree_step=20 (★1은 30). trees=20 에서 이미 +0.05 누적.
	var card := _make_star("dr_world", 2)
	card.theme_state["trees"] = 17  # +3 self → 20
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_almost_eq(card.unique_buff_pct, 0.05, 0.0001, "★2 trees=20 → +0.05")


func test_world_s3_smallest_tree_step() -> void:
	## ★3: tree_step=5 — 가장 빠르게 누적. trees=5 에서 +0.05.
	var card := _make_star("dr_world", 3)
	card.theme_state["trees"] = 2  # +3 self → 5
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_almost_eq(card.unique_buff_pct, 0.05, 0.0001, "★3 trees=5 → +0.05")


func test_world_unit_count_irrelevant_to_growth() -> void:
	## 유닛 수 무관 — 30 trees 도달 시 buff 누적 (★1).
	var card: CardInstance = CardInstance.create("dr_world")
	for _i in 20:
		card.spawn_random(_rng)
	card.theme_state["trees"] = 28
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_almost_eq(card.unique_buff_pct, 0.05, 0.0001,
		"23기여도 trees=30 도달 시 누적 적용")


func test_world_applies_to_all_board_cards() -> void:
	## target: all_allies — dr_world 외 카드(비드루이드 포함) 도 buff_pct 누적.
	var world: CardInstance = CardInstance.create("dr_world")
	world.theme_state["trees"] = 28
	var non_druid: CardInstance = CardInstance.create("sp_assembly")
	_sys.process_rs_card(world, 0, [world, non_druid], _rng)
	# trees(self+) = 30, increment = floor(30/30)*0.05 = 0.05
	assert_almost_eq(non_druid.unique_buff_pct, 0.05, 0.0001,
		"비드루이드도 buff_pct +0.05")


func test_world_uses_forest_depth_all_druid_trees() -> void:
	## tree_source: forest_depth — 모든 드루이드 카드 🌳 합.
	## ★1 (tree_step=30): cradle 에 28 프리-설정 → RS 후 forest=31 이면 increment=0.05.
	var world: CardInstance = CardInstance.create("dr_world")
	var cradle: CardInstance = CardInstance.create("dr_cradle")
	cradle.theme_state["trees"] = 28
	_sys.process_rs_card(world, 0, [world, cradle], _rng)
	# RS 후: world.trees = 0+2=2, cradle.trees = 28+1=29 → forest = 31
	assert_almost_eq(world.unique_buff_pct, 0.05, 0.0001,
		"forest_depth 31 → +0.05 누적")


# ================================================================
# dr_resonance (T4 OE l1:UA, filter non_druid_target) — mirror spawn → tree+enhance
# ================================================================


func _make_ua_event(src: int, tgt: int) -> Dictionary:
	return {"layer1": Enums.Layer1.UNIT_ADDED, "layer2": -1,
			"source_idx": src, "target_idx": tgt}


func test_resonance_self_source_ignored() -> void:
	## source_idx == self idx → 무한 루프 방지
	var card: CardInstance = CardInstance.create("dr_resonance")
	var event := _make_ua_event(0, 1)  # source=self
	_sys.process_event_card(card, 0, [card], event, _rng)
	assert_eq(card.theme_state.get("trees", 0), 0, "self-source → no fire")


func test_resonance_druid_target_filtered_out() -> void:
	## target이 druid이면 무시 (filter: non_druid_target)
	var card: CardInstance = CardInstance.create("dr_resonance")
	var druid_target: CardInstance = CardInstance.create("dr_cradle")
	var board: Array = [card, druid_target]
	var event := _make_ua_event(1, 1)  # source=1 (druid_target), target=1 (druid)
	_sys.process_event_card(card, 0, board, event, _rng)
	assert_eq(card.theme_state.get("trees", 0), 0, "druid target → 무시")


func test_resonance_star1_non_druid_target_tree_and_enhance() -> void:
	## 비-druid target → tree_add +1, self ATK +2%
	var card: CardInstance = CardInstance.create("dr_resonance")
	var sp_target: CardInstance = CardInstance.create("sp_assembly")
	var board: Array = [card, sp_target]
	var event := _make_ua_event(1, 1)
	_sys.process_event_card(card, 0, board, event, _rng)
	assert_eq(card.theme_state.get("trees", 0), 1, "★1 tree_add +1")
	assert_almost_eq(card.growth_atk_pct, 0.02, 0.001, "★1 ATK +2%")


func test_resonance_star2_tree_atk_hp() -> void:
	## ★2: tree +1, ATK +3%, HP +2% (multi-review missing coverage)
	var card: CardInstance = CardInstance.create("dr_resonance")
	card.evolve_star()
	var sp_target: CardInstance = CardInstance.create("sp_assembly")
	var board: Array = [card, sp_target]
	var event := _make_ua_event(1, 1)
	_sys.process_event_card(card, 0, board, event, _rng)
	assert_eq(card.theme_state.get("trees", 0), 1, "★2 tree +1")
	assert_almost_eq(card.growth_atk_pct, 0.03, 0.001, "★2 ATK +3%")
	assert_almost_eq(card.growth_hp_pct, 0.02, 0.001, "★2 HP +2%")


func test_resonance_star3_double_tree_and_hp() -> void:
	## ★3: tree +2, ATK +4%, HP +3%
	var card: CardInstance = CardInstance.create("dr_resonance")
	card.evolve_star()
	card.evolve_star()
	var sp_target: CardInstance = CardInstance.create("sp_assembly")
	var board: Array = [card, sp_target]
	var event := _make_ua_event(1, 1)
	_sys.process_event_card(card, 0, board, event, _rng)
	assert_eq(card.theme_state.get("trees", 0), 2, "★3 tree +2")
	assert_almost_eq(card.growth_atk_pct, 0.04, 0.001, "★3 ATK +4%")
	assert_almost_eq(card.growth_hp_pct, 0.03, 0.001, "★3 HP +3%")


func test_resonance_omni_target_treated_as_druid() -> void:
	## omni-theme 카드는 druid에도 매치 → resonance 발동 안 함
	var card: CardInstance = CardInstance.create("dr_resonance")
	var omni_target: CardInstance = CardInstance.create("ne_earth_echo")
	omni_target.is_omni_theme = true
	var board: Array = [card, omni_target]
	var event := _make_ua_event(1, 1)
	_sys.process_event_card(card, 0, board, event, _rng)
	assert_eq(card.theme_state.get("trees", 0), 0, "omni target → 무시 (druid 매치)")
