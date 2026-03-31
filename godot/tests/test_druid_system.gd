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
# dr_origin (RS): 🌳+1, 인접 드루이드에서 🌳 흡수, breed
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
# dr_earth (RS): 🌳+1, 전체 드루이드 유닛수 기반 enhance
# ================================================================

func test_earth_adds_1_tree() -> void:
	var card: CardInstance = CardInstance.create("dr_earth")
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_eq(card.theme_state.get("trees", 0), 1, "🌳+1")


func test_earth_enhances_by_unit_ratio() -> void:
	## ★1: floor(units/5)% enhance. dr_earth 2유닛 → floor(2/5)=0% → ATK 불변
	## 10유닛이면 floor(10/5)=2%
	var card: CardInstance = CardInstance.create("dr_earth")
	card.add_specific_unit("dr_wolf", 8)  # 2+8=10유닛
	var atk_before: float = card.get_total_atk()
	_sys.process_rs_card(card, 0, [card], _rng)
	# floor(10/5) = 2% → enhance(null, 0.02, 0.02)
	assert_gt(card.get_total_atk(), atk_before, "10유닛 → 2% 성장")


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
# dr_wrath (PERSISTENT): ≤5기 ATK 버프
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


func test_wrath_s3_skips_if_over_5_units() -> void:
	## ★3도 >5기이면 미적용
	var card := _make_star("dr_wrath", 3)
	card.add_specific_unit("dr_boar", 5)  # 기존 2 + 5 = 7 > 5
	var atk_before: float = card.get_total_atk()
	_sys.apply_persistent(card)
	assert_eq(card.get_total_atk(), atk_before, "7기 → 미적용")


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


func test_world_s3_unit_cap_30() -> void:
	## ★3: unit_cap=30 (★1/★2는 20)
	var card := _make_star("dr_world", 3)
	# 유닛 21기 추가 → ★2는 20상한 초과로 skip, ★3은 30이하로 실행
	for _i in 18:
		card.spawn_random(_rng)
	# total 3(base) + 18 = 21
	var atk_before: float = card.get_total_atk()
	_sys.process_rs_card(card, 0, [card], _rng)
	assert_gt(card.get_total_atk(), atk_before, "★3 21기 < 30 → 성장 실행")


func test_world_s1_over_20_stops_growth() -> void:
	## ★1: 20기 초과 시 성장 중단
	var card: CardInstance = CardInstance.create("dr_world")
	for _i in 20:
		card.spawn_random(_rng)
	# total 3(base) + 20 = 23 > 20
	var atk_before: float = card.get_total_atk()
	_sys.process_rs_card(card, 0, [card], _rng)
	# trees는 증가하지만 multiply_stats는 미적용 (unit_cap 초과)
	assert_eq(card.get_total_atk(), atk_before, "★1 23기 > 20 → 성장 중단")
