extends GutTest
## Tests for AIPositionSolver — adjacency-aware board positioning.

const PosSolver = preload("res://sim/ai_position_solver.gd")
var solver


func before_each() -> void:
	solver = PosSolver.new()


func _make_card(cid: String) -> CardInstance:
	return CardInstance.create(cid)


func _get_ids(arr: Array) -> Array[String]:
	var ids: Array[String] = []
	for item in arr:
		if item != null:
			ids.append((item as CardInstance).get_base_id())
	return ids


# ================================================================
# Steampunk adjacency
# ================================================================

func test_assembly_before_workshop() -> void:
	# sp_assembly spawns right_adj → should be LEFT of sp_workshop
	var cards: Array = [_make_card("sp_workshop"), _make_card("sp_assembly")]
	var result: Array = solver.solve_positions(cards)
	var ids: Array[String] = _get_ids(result)
	var a_idx: int = ids.find("sp_assembly")
	var w_idx: int = ids.find("sp_workshop")
	assert_lt(a_idx, w_idx,
		"sp_assembly(right_adj spawn) 왼쪽에 배치")

func test_assembly_workshop_circulator_chain() -> void:
	# Chain: assembly(RS,MF) → workshop(OE,MF→UP) → circulator(OE,UP→MF)
	var cards: Array = [
		_make_card("sp_circulator"),
		_make_card("sp_workshop"),
		_make_card("sp_assembly"),
	]
	var result: Array = solver.solve_positions(cards)
	var ids: Array[String] = _get_ids(result)
	var a_idx: int = ids.find("sp_assembly")
	var w_idx: int = ids.find("sp_workshop")
	var c_idx: int = ids.find("sp_circulator")
	assert_lt(a_idx, w_idx, "assembly before workshop")
	assert_lt(a_idx, c_idx, "assembly before circulator")

func test_line_between_reactors() -> void:
	# sp_line targets both_adj → should have cards on both sides
	var cards: Array = [
		_make_card("sp_assembly"),
		_make_card("sp_line"),
		_make_card("sp_workshop"),
		_make_card("sp_workshop"),
	]
	var result: Array = solver.solve_positions(cards)
	var ids: Array[String] = _get_ids(result)
	var line_idx: int = ids.find("sp_line")
	# line should not be at position 0 or last (needs neighbors)
	if ids.size() > 2:
		assert_gt(line_idx, 0, "sp_line not at leftmost (needs left neighbor)")
		assert_lt(line_idx, ids.size() - 1, "sp_line not at rightmost (needs right neighbor)")


# ================================================================
# Druid positioning
# ================================================================

func test_druid_cradle_before_deep() -> void:
	# dr_cradle generates 🌳 for adjacent druids → should be near dr_deep
	var cards: Array = [_make_card("dr_deep"), _make_card("dr_cradle")]
	var result: Array = solver.solve_positions(cards)
	var ids: Array[String] = _get_ids(result)
	var cradle_idx: int = ids.find("dr_cradle")
	var deep_idx: int = ids.find("dr_deep")
	# Cradle is RS with adjacency benefit → should be near deep
	assert_lte(absi(cradle_idx - deep_idx), 1,
		"dr_cradle 인접 dr_deep (🌳 전달)")


# ================================================================
# Edge cases
# ================================================================

func test_single_card_trivial() -> void:
	var cards: Array = [_make_card("sp_assembly")]
	var result: Array = solver.solve_positions(cards)
	assert_eq(result.size(), 1)
	assert_eq((result[0] as CardInstance).get_base_id(), "sp_assembly")

func test_empty_board() -> void:
	var cards: Array = []
	var result: Array = solver.solve_positions(cards)
	assert_eq(result.size(), 0)

func test_no_adj_cards_stable_order() -> void:
	# Cards with no adjacency needs → should not crash, return some order
	var cards: Array = [_make_card("sp_interest"), _make_card("sp_barrier")]
	var result: Array = solver.solve_positions(cards)
	assert_eq(result.size(), 2, "두 카드 모두 유지")


# ================================================================
# Cross-theme
# ================================================================

func test_neutral_earth_echo_before_wanderers() -> void:
	# ne_earth_echo spawns right_adj → ne_wanderers listens
	var cards: Array = [_make_card("ne_wanderers"), _make_card("ne_earth_echo")]
	var result: Array = solver.solve_positions(cards)
	var ids: Array[String] = _get_ids(result)
	var echo_idx: int = ids.find("ne_earth_echo")
	var wand_idx: int = ids.find("ne_wanderers")
	assert_lt(echo_idx, wand_idx,
		"ne_earth_echo(right_adj) → ne_wanderers(OE listener)")
