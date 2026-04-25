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
# dr_world (RS): 🌳+2, multiply_stats ×1.10
# ================================================================

func test_world_applies_multiply_stats_atk_110() -> void:
	var card: CardInstance = CardInstance.create("dr_world")
	var atk_before: float = card.get_total_atk()
	_sys.process_rs_card(card, 0, [card], _rng)
	# ★1: multiply_stats(base_atk=1.10, base_hp=1.05) → ATK ×1.10
	assert_almost_eq(card.get_total_atk(), atk_before * 1.10, 0.1, "ATK ×1.10")


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
	# units=2(<=3) → ×1.5 = 0.12
	assert_almost_eq(card.shield_hp_pct, 0.12, 0.001, "trees=1, ≤3units → shield=0.12")


func test_lifebeat_shield_increases_with_trees() -> void:
	var card: CardInstance = CardInstance.create("dr_lifebeat")
	card.theme_state["trees"] = 3
	_sys.apply_battle_start(card, 0, [card])
	# _add_trees → trees=4, shield = 0.05 + 4*0.03 = 0.17
	# units=2(<=3) → ×1.5 = 0.255
	assert_almost_eq(card.shield_hp_pct, 0.255, 0.001, "trees=4 → shield=0.255")


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


# ================================================================
# dr_wrath (PERSISTENT): 유닛 상한 ★1=5, ★2=6, ★3=7. 상한 이내일 때 ATK 버프.
# ================================================================

func test_wrath_persistent_buffs_when_few_units() -> void:
	## ★1: ≤5기일 때 temp_buff(null, 0.80 + trees*0.05)
	var card: CardInstance = CardInstance.create("dr_wrath")
	card.theme_state["trees"] = 4
	var atk_before: float = card.get_total_atk()
	_sys.apply_persistent(card)
	# 0.80 + 4*0.05 = 1.00 → temp_buff 100%
	assert_gt(card.get_total_atk(), atk_before, "≤5기 → ATK 버프")


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
	_sys.apply_persistent(card)
	# 1.20 + 5*0.08 = 1.60 → temp_buff 160%
	assert_gt(card.get_total_atk(), atk_before, "★2 → 더 높은 ATK 버프")


func test_wrath_s3_uses_mult_buff() -> void:
	## ★3: temp_mult_buff(1.5) — 곱연산
	var card := _make_star("dr_wrath", 3)
	card.theme_state["trees"] = 0
	var atk_before: float = card.get_total_atk()
	_sys.apply_persistent(card)
	# ★3 ATK ×1.5
	assert_gt(card.get_total_atk(), atk_before, "★3 → ATK ×1.5")


func test_wrath_s3_skips_if_over_unit_cap() -> void:
	## ★3 유닛 상한은 7기(★1=5, ★2=6, ★3=7). >7기이면 미적용.
	## 기존 2기 + 6기 = 8기 > 7 → 버프 비적용.
	var card := _make_star("dr_wrath", 3)
	card.add_specific_unit("dr_boar", 6)
	var atk_before: float = card.get_total_atk()
	_sys.apply_persistent(card)
	assert_eq(card.get_total_atk(), atk_before, "8기 → 미적용")


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


func test_world_s2_higher_atk_mult() -> void:
	## ★2: ATK×1.15 (★1은 ×1.10)
	var card := _make_star("dr_world", 2)
	var atk_before: float = card.get_total_atk()
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_gt(card.get_total_atk(), atk_before, "★2 ATK×1.15 적용")


func test_world_s3_unit_cap_200() -> void:
	## ★3: unit_cap=200 (OBS-048). 33기(S5-R14 재현)에서도 성장 실행
	var card := _make_star("dr_world", 3)
	for _i in 30:
		card.spawn_random(_rng)
	var atk_before: float = card.get_total_atk()
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_gt(card.get_total_atk(), atk_before, "★3 33기 < 200 → 성장 실행")


func test_world_s2_unit_cap_40() -> void:
	## ★2: unit_cap=40 (OBS-048). 21기에서 성장 실행
	var card := _make_star("dr_world", 2)
	for _i in 18:
		card.spawn_random(_rng)
	# total ~21
	var atk_before: float = card.get_total_atk()
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_gt(card.get_total_atk(), atk_before, "★2 21기 < 40 → 성장 실행")


func test_world_no_unit_cap_always_grows() -> void:
	## 2026-04-21: unit_cap 제거 — 유닛 수 무관 항상 성장.
	var card: CardInstance = CardInstance.create("dr_world")
	for _i in 20:
		card.spawn_random(_rng)
	var atk_before: float = card.get_total_atk()
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_almost_eq(card.get_total_atk(), atk_before * 1.10, 0.1,
		"★1: 23기여도 ATK ×1.10 성장 (cap 없음)")


func test_world_applies_to_all_board_cards() -> void:
	## 2026-04-21: target: all_allies — dr_world 외 카드 (드루이드 아닌 포함) 도 배수 적용.
	var world: CardInstance = CardInstance.create("dr_world")
	var non_druid: CardInstance = CardInstance.create("sp_assembly")  # 스팀펑크
	var non_druid_atk_before: float = non_druid.get_total_atk()
	_sys.process_rs_card(world, 0, [world, non_druid], _rng)
	# ★1 base_atk 1.10, 0 나무 → ×1.10 배수 적용 예상.
	assert_almost_eq(non_druid.get_total_atk(), non_druid_atk_before * 1.10, 0.1,
		"비-드루이드 카드도 ATK ×1.10 성장")


func test_world_as_multiplier_applies_to_upgrade_as() -> void:
	## 2026-04-21 bugfix: AS 배수가 실제 전투에 반영되도록 upgrade_as_mult 누적.
	## ★1 as_base 1.05 → RS 1회 후 upgrade_as_mult ×1.05.
	var card: CardInstance = CardInstance.create("dr_world")
	var as_before: float = card.upgrade_as_mult
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_almost_eq(card.upgrade_as_mult, as_before * 1.05, 0.001,
		"★1 AS ×1.05 누적 (upgrade_as_mult)")


func test_world_uses_forest_depth_all_druid_trees() -> void:
	## 2026-04-21 bugfix: tree_source: forest_depth — 모든 드루이드 카드 🌳 합.
	## dr_world ★1 RS 1회: self +2, cradle +1 → forest 3. atk_tree_step 30 이므로
	## floor(3/30)=0 → atk_mult 그대로 1.10. 30 단위를 넘기려면 다수 라운드.
	## 여기선 cradle 에 🌳 28 미리 설정 → RS 후 forest = (2+28) + (1) = 31 이면 30/30=1.
	var world: CardInstance = CardInstance.create("dr_world")
	var cradle: CardInstance = CardInstance.create("dr_cradle")
	cradle.theme_state["trees"] = 28  # cradle 에 나무 28 프리-설정
	# RS 1회 후: world.trees = 0+2=2, cradle.trees = 28+1=29 → forest = 31
	# ★1 atk_tree_step 30 → floor(31/30) = 1 → +0.1 → atk_mult 1.20
	var atk_before: float = world.get_total_atk()
	_sys.process_rs_card(world, 0, [world, cradle], _rng)
	assert_almost_eq(world.get_total_atk(), atk_before * 1.20, 0.1,
		"forest_depth 31 → ★1 ATK ×1.20")


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
