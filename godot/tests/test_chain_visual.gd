extends GutTest
## ChainVisual readability contract for G-9.

const ChainVisualScene = preload("res://scenes/chain/chain_visual.tscn")
const CardVisualScene = preload("res://scenes/build/card_visual.tscn")

var _visual = null
var _field_visuals: Array = []


func before_each() -> void:
	_visual = ChainVisualScene.instantiate()
	add_child_autofree(_visual)
	_field_visuals = [
		_make_field_visual("sp_assembly", 0),
		_make_field_visual("sp_workshop", 1),
	]
	_visual.setup(_field_visuals)
	_visual.update_board_map([
		_field_visuals[0].card_instance,
		_field_visuals[1].card_instance,
	])


func _make_field_visual(card_id: String, slot_idx: int):
	var field_visual = CardVisualScene.instantiate()
	add_child_autofree(field_visual)
	field_visual.position = Vector2(20 + slot_idx * 140, 20)
	field_visual.setup(CardInstance.create(card_id), "board", slot_idx)
	return field_visual


func _counter_label() -> Label:
	return _visual.get_node("EventPanel/VBox/CounterLabel") as Label


func test_event_log_describes_source_target_and_reward() -> void:
	_visual._on_chain_phase_started("ROUND_START")
	_visual._on_chain_event(
		0,
		1,
		Enums.Layer1.UNIT_ADDED,
		Enums.Layer2.MANUFACTURE,
		"spawn"
	)

	var log: String = _visual.get_event_log_text()
	assert_string_contains(log, "#1 Round Start")
	assert_string_contains(log, "L->R")
	assert_string_contains(log, "증기 조립소 -> 태엽 공방")
	assert_string_contains(log, "+Unit")
	assert_string_contains(log, "Unit Added / Manufacture")
	assert_string_contains(_counter_label().text, "Triggers: 1")
	var link_texts: PackedStringArray = _visual.get_active_link_texts()
	assert_eq(link_texts.size(), 1)
	assert_string_contains(link_texts[0], "#1 L->R +Unit")


func test_event_log_tags_right_to_left_chain_events() -> void:
	_visual._on_chain_phase_started("ROUND_START")
	_visual._on_chain_event(
		1,
		0,
		Enums.Layer1.ENHANCED,
		Enums.Layer2.UPGRADE,
		"enhance"
	)

	var log: String = _visual.get_event_log_text()
	assert_string_contains(log, "R->L")
	assert_string_contains(log, "태엽 공방 -> 증기 조립소")
	var link_texts: PackedStringArray = _visual.get_active_link_texts()
	assert_eq(link_texts.size(), 1)
	assert_string_contains(link_texts[0], "#1 R->L +Stats")


func test_event_log_keeps_unmapped_events_readable() -> void:
	_visual._on_chain_phase_started("BFS_CASCADE")
	_visual._on_chain_event(
		3,
		4,
		Enums.Layer1.ENHANCED,
		Enums.Layer2.UPGRADE,
		"enhance"
	)

	var log: String = _visual.get_event_log_text()
	assert_string_contains(log, "#1 Cascade")
	assert_string_contains(log, "slot 4 -> slot 5")
	assert_string_contains(log, "+Stats")
	assert_string_contains(log, "Enhanced / Upgrade")


func test_completion_summarizes_trigger_count_and_gold() -> void:
	_visual._on_chain_phase_started("ROUND_START")
	_visual._on_chain_event(
		0,
		1,
		Enums.Layer1.UNIT_ADDED,
		Enums.Layer2.MANUFACTURE,
		"spawn"
	)
	_visual._on_chain_completed(3, 2)

	var log: String = _visual.get_event_log_text()
	assert_string_contains(log, "Complete: 3 triggers, +2g")
	assert_string_contains(_visual.get_chain_history_text(), "Complete: 3 triggers, +2g")
	assert_string_contains(_counter_label().text, "Triggers: 3")
	assert_string_contains(_counter_label().text, "+2g")


func test_connected_engine_populates_readability_panel() -> void:
	var engine := ChainEngine.new()
	engine.set_seed(42)
	_visual.connect_engine(engine)

	var board: Array = [
		_field_visuals[0].card_instance,
		_field_visuals[1].card_instance,
	]
	var result: Dictionary = engine.run_growth_chain(board)

	assert_gt(result["chain_count"], 0)
	var log: String = _visual.get_event_log_text()
	assert_string_contains(log, "증기 조립소 -> 태엽 공방")
	assert_string_contains(log, "Complete:")
	assert_true(_visual.get_node("EventPanel").visible)


func test_clear_links_resets_readability_panel() -> void:
	_visual._on_chain_phase_started("ROUND_START")
	_visual._on_chain_event(
		0,
		1,
		Enums.Layer1.UNIT_ADDED,
		Enums.Layer2.MANUFACTURE,
		"spawn"
	)
	_visual._on_chain_completed(1, 1)

	_visual.clear_links()

	assert_eq(_visual.get_event_log_text(), "No chain events yet")
	assert_string_contains(_visual.get_chain_history_text(), "Complete: 1 triggers, +1g")
	assert_eq(_counter_label().text, "Triggers: 0")
	assert_eq(_visual.get_node("EventPanel/VBox/PhaseLabel").text, "Phase: Idle")
	assert_false(_visual.get_node("EventPanel").visible)


func test_clear_links_can_explicitly_clear_history() -> void:
	_visual._on_chain_phase_started("ROUND_START")
	_visual._on_chain_event(
		0,
		1,
		Enums.Layer1.UNIT_ADDED,
		Enums.Layer2.MANUFACTURE,
		"spawn"
	)
	_visual._on_chain_completed(1, 1)

	_visual.clear_links(true)

	assert_eq(_visual.get_chain_history_text(), "")


func test_chain_history_keeps_more_than_visible_log_lines() -> void:
	_visual._on_chain_phase_started("ROUND_START")
	for _i in 8:
		_visual._on_chain_event(
			0,
			1,
			Enums.Layer1.UNIT_ADDED,
			Enums.Layer2.MANUFACTURE,
			"spawn"
		)
	_visual._on_chain_completed(8, 0)

	var visible_log: String = _visual.get_event_log_text()
	var history: String = _visual.get_chain_history_text()
	assert_false(visible_log.contains("#1 Round Start"),
		"compact live log keeps only the most recent entries")
	assert_string_contains(history, "#1 Round Start")
	assert_string_contains(history, "#8 Round Start")
	assert_string_contains(history, "Complete: 8 triggers")
