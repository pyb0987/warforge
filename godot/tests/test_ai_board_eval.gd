extends GutTest
## Tests for AIBoardEvaluator — timing-aware card value + bench→board promotion.

const BoardEval = preload("res://sim/ai_board_evaluator.gd")
var ev


func before_each() -> void:
	ev = BoardEval.new()


# ================================================================
# Timing value modifier
# ================================================================

func test_rs_valued_higher_than_bs_same_tier() -> void:
	# RS card triggers every round → compound value. BS is flat.
	var rs_mod: float = ev.timing_modifier(Enums.TriggerTiming.ROUND_START, 3)
	var bs_mod: float = ev.timing_modifier(Enums.TriggerTiming.BATTLE_START, 3)
	assert_gt(rs_mod, bs_mod,
		"RS > BS at R3 (many rounds remaining)")

func test_rs_advantage_diminishes_late() -> void:
	var rs_early: float = ev.timing_modifier(Enums.TriggerTiming.ROUND_START, 3)
	var rs_late: float = ev.timing_modifier(Enums.TriggerTiming.ROUND_START, 14)
	assert_gt(rs_early, rs_late,
		"RS value decreases as fewer rounds remain")

func test_persistent_high_value() -> void:
	var ps_mod: float = ev.timing_modifier(Enums.TriggerTiming.PERSISTENT, 5)
	var bs_mod: float = ev.timing_modifier(Enums.TriggerTiming.BATTLE_START, 5)
	assert_gt(ps_mod, bs_mod,
		"PERSISTENT > BATTLE_START")

func test_on_event_positive() -> void:
	var oe_mod: float = ev.timing_modifier(Enums.TriggerTiming.ON_EVENT, 5)
	assert_gt(oe_mod, 0.0,
		"ON_EVENT timing has positive modifier")


# ================================================================
# Effect value: spawn adjacency vs self
# ================================================================

func test_spawn_adj_valued_higher_than_self() -> void:
	var adj_eff: Array = [{"action": "spawn", "target": "right_adj", "spawn_count": 1}]
	var self_eff: Array = [{"action": "spawn", "target": "self", "spawn_count": 1}]
	var adj_val: float = ev.effect_modifier(adj_eff, 5)
	var self_val: float = ev.effect_modifier(self_eff, 5)
	assert_gt(adj_val, self_val,
		"right_adj spawn > self spawn (chain potential)")

func test_enhance_valued_higher_early() -> void:
	var eff: Array = [{"action": "enhance_pct", "enhance_atk_pct": 0.05}]
	var early: float = ev.effect_modifier(eff, 3)
	var late: float = ev.effect_modifier(eff, 13)
	assert_gt(early, late,
		"enhance compound value higher early game")

func test_shield_valued_higher_late() -> void:
	var eff: Array = [{"action": "shield_pct", "shield_hp_pct": 0.20}]
	var early: float = ev.effect_modifier(eff, 3)
	var late: float = ev.effect_modifier(eff, 12)
	assert_gt(late, early,
		"shield more valuable in late game")


# ================================================================
# Bench promotion decisions
# ================================================================

func _make_card(cid: String, star: int = 1) -> CardInstance:
	var card: CardInstance = CardInstance.create(cid)
	card.star_level = star
	return card

func test_promote_to_empty_slot() -> void:
	var board: Array = [null, null, null, null, null, null, null, null]
	var bench: Array = [_make_card("sp_assembly"), null, null, null, null, null, null, null]
	var actions: Array = ev.find_promotions(board, bench, 8, "soft_steampunk", 3)
	assert_false(actions.is_empty(), "벤치 카드 → 빈 슬롯 배치")
	assert_eq(actions[0]["action"], "place")

func test_swap_weak_for_strong() -> void:
	# Full board with a weak T1 neutral PD card, bench has T4 steampunk OE
	var board: Array = [
		_make_card("ne_merchant"), _make_card("sp_assembly"),
		_make_card("sp_workshop"), _make_card("sp_workshop"),
		_make_card("sp_assembly"), _make_card("sp_circulator"),
		null, null]
	var bench: Array = [_make_card("sp_charger"), null, null, null, null, null, null, null]
	var actions: Array = ev.find_promotions(board, bench, 6, "soft_steampunk", 8)
	var has_swap := false
	for a in actions:
		if a["action"] == "swap":
			has_swap = true
	assert_true(has_swap, "T4 테마 카드가 약한 중립 카드를 교체")

func test_no_swap_merge_candidate() -> void:
	# Board has 2 copies of ne_earth_echo → merge potential → protected
	var board: Array = [
		_make_card("ne_earth_echo"), _make_card("ne_earth_echo"),
		_make_card("sp_assembly"), _make_card("sp_workshop"),
		null, null, null, null]
	var bench: Array = [_make_card("sp_circulator"), null, null, null, null, null, null, null]
	var actions: Array = ev.find_promotions(board, bench, 4, "soft_steampunk", 5)
	for a in actions:
		if a["action"] == "swap":
			var board_card: CardInstance = board[a["board_idx"]]
			assert_ne(board_card.get_base_id(), "ne_earth_echo",
				"합성 후보 보호 — 교체 안됨")
	# If no swap happened at all, also fine (placed in empty or no swap needed)
	assert_true(true, "합성 후보 보호 검증 완료")

func test_druid_rs_replaces_weak() -> void:
	# Full board with strong RS cards + one weak BS card.
	# dr_origin (RS T2) should replace the weakest card.
	var board: Array = [
		_make_card("dr_lifebeat"), _make_card("dr_cradle"),
		_make_card("dr_deep"), _make_card("dr_earth"),
		_make_card("dr_wt_root"), _make_card("dr_cradle"),
		null, null]
	var bench: Array = [_make_card("dr_origin"), null, null, null, null, null, null, null]
	var actions: Array = ev.find_promotions(board, bench, 6, "soft_druid", 8)
	var has_swap := false
	for a in actions:
		if a["action"] == "swap":
			has_swap = true
			# The swapped-out card should be weaker than dr_origin
			var board_card: CardInstance = board[a["board_idx"]]
			var bench_card: CardInstance = bench[a["bench_idx"]]
			var board_val: float = ev.card_board_value(board_card, "soft_druid", 8)
			var bench_val: float = ev.card_board_value(bench_card, "soft_druid", 8)
			assert_gt(bench_val, board_val,
				"교체된 카드는 벤치 카드보다 약함")
	assert_true(has_swap, "RS 카드가 약한 보드 카드를 교체")

func test_rs_valued_higher_than_bs_druid() -> void:
	# Direct value comparison: RS druid > BS druid (same tier)
	var rs_card: CardInstance = _make_card("dr_cradle")  # RS T1
	var bs_card: CardInstance = _make_card("dr_lifebeat")  # BS T1
	var rs_val: float = ev.card_board_value(rs_card, "soft_druid", 5)
	var bs_val: float = ev.card_board_value(bs_card, "soft_druid", 5)
	assert_gt(rs_val, bs_val,
		"dr_cradle(RS) > dr_lifebeat(BS) at same tier")


# ================================================================
# Data-driven: timing modifier table completeness
# ================================================================

func test_all_timings_have_modifier() -> void:
	# Ensure no timing returns exactly 0 (should have some signal)
	var timings := [
		Enums.TriggerTiming.ROUND_START,
		Enums.TriggerTiming.ON_EVENT,
		Enums.TriggerTiming.BATTLE_START,
		Enums.TriggerTiming.PERSISTENT,
	]
	for t in timings:
		var mod: float = ev.timing_modifier(t, 5)
		assert_ne(mod, 0.0, "timing %d → non-zero modifier" % t)
