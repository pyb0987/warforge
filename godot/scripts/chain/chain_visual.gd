extends Control
## Visualizes chain events as lines between cards + floating text.

const MAX_EVENT_LOG_LINES := 6
const MAX_CHAIN_HISTORY_LINES := 30
const LINK_PULSE_SCALE := Vector2(1.08, 1.08)
const LINK_FLOAT_RISE := Vector2(0, -8)

var _field_visuals: Array = []  # references to card_visual panels (all 8 slots)
var _active_board_map: Array = []  # maps active_board index → field_visuals index
var _active_links: Array = []   # currently displayed links
var _event_log: Array[String] = []
var _current_chain_history: Array[String] = []
var _last_chain_history: Array[String] = []
var _chain_counter: int = 0
var _last_phase: String = ""
var _last_gold_earned: int = 0

@onready var event_panel: PanelContainer = $EventPanel
@onready var phase_label: Label = $EventPanel/VBox/PhaseLabel
@onready var counter_label: Label = $EventPanel/VBox/CounterLabel
@onready var event_log_label: Label = $EventPanel/VBox/EventLogLabel

var _event_colors := {
	"spawn": Color(0.2, 0.8, 0.2),      # green
	"enhance": Color(1.0, 0.8, 0.2),     # yellow
	"buff_pct": Color(0.8, 0.2, 0.2),    # red
	"shield_pct": Color(0.2, 0.5, 1.0),  # blue
	"grant_gold": Color(1.0, 0.9, 0.3),  # gold
}


func setup(field_visuals: Array) -> void:
	_field_visuals = field_visuals
	_chain_counter = 0
	_last_gold_earned = 0
	_last_phase = ""
	_event_log.clear()
	_current_chain_history.clear()
	_last_chain_history.clear()
	_update_counter()
	_update_event_log()


## Build mapping from active_board indices to field_visual indices.
## Call this before each chain run.
func update_board_map(board: Array) -> void:
	_active_board_map.clear()
	for i in board.size():
		if board[i] != null:
			_active_board_map.append(i)


func connect_engine(engine: ChainEngine) -> void:
	var event_callable := Callable(self, "_on_chain_event")
	if not engine.chain_event_fired.is_connected(event_callable):
		engine.chain_event_fired.connect(event_callable)
	var phase_callable := Callable(self, "_on_chain_phase_started")
	if not engine.chain_phase_started.is_connected(phase_callable):
		engine.chain_phase_started.connect(phase_callable)
	var completed_callable := Callable(self, "_on_chain_completed")
	if not engine.chain_completed.is_connected(completed_callable):
		engine.chain_completed.connect(completed_callable)


func clear_links(clear_history: bool = false) -> void:
	for link in _active_links:
		if is_instance_valid(link):
			link.queue_free()
	_active_links.clear()
	_chain_counter = 0
	_last_gold_earned = 0
	_last_phase = ""
	_event_log.clear()
	_current_chain_history.clear()
	if clear_history:
		_last_chain_history.clear()
	_update_counter()
	_update_event_log()


func get_event_log_text() -> String:
	if event_log_label:
		return event_log_label.text
	return _join_event_log()


func get_chain_history_text() -> String:
	return _join_lines(_last_chain_history)


func get_active_link_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	for link in _active_links:
		if is_instance_valid(link) and link is Label:
			texts.append((link as Label).text)
	return texts


func _on_chain_phase_started(phase_name) -> void:
	_last_phase = str(phase_name)
	_update_counter()
	_update_event_log()


func _on_chain_event(source_idx, target_idx, layer1, layer2, action) -> void:
	_chain_counter += 1
	_add_event_log(_format_event_line(
		_chain_counter,
		int(source_idx),
		int(target_idx),
		int(layer1),
		int(layer2),
		str(action)
	))
	_update_counter()

	# Map active_board indices to field_visual indices
	if source_idx < 0 or target_idx < 0:
		return
	var src_visual_idx: int = _active_board_map[source_idx] if source_idx < _active_board_map.size() else -1
	var tgt_visual_idx: int = _active_board_map[target_idx] if target_idx < _active_board_map.size() else -1
	if src_visual_idx < 0 or tgt_visual_idx < 0:
		return
	if src_visual_idx >= _field_visuals.size() or tgt_visual_idx >= _field_visuals.size():
		return

	var src_panel: Panel = _field_visuals[src_visual_idx]
	var tgt_panel: Panel = _field_visuals[tgt_visual_idx]
	if not is_instance_valid(src_panel) or not is_instance_valid(tgt_panel):
		return
	var flow_hint := _direction_hint(src_visual_idx, tgt_visual_idx)

	# Line
	var line := Line2D.new()
	var src_center := src_panel.global_position + src_panel.size / 2.0
	var tgt_center := tgt_panel.global_position + tgt_panel.size / 2.0
	line.add_point(src_center)
	line.add_point(tgt_center)
	line.width = 3.2
	line.default_color = _event_colors.get(str(action), Color.WHITE)
	line.z_index = 10
	add_child(line)
	_active_links.append(line)

	# Floating text
	var label := Label.new()
	var floating_text := _action_text(str(action))
	if flow_hint != "":
		floating_text = "%s %s" % [flow_hint, floating_text]
	label.text = "#%d %s" % [_chain_counter, floating_text]
	label.global_position = (src_center + tgt_center) / 2.0 + Vector2(0, -15)
	label.scale = LINK_PULSE_SCALE
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", _event_colors.get(str(action), Color.WHITE))
	label.z_index = 11
	add_child(label)
	_active_links.append(label)

	# Pulse, drift, then auto-fade after roughly 2 seconds.
	var tween := create_tween()
	tween.tween_property(line, "width", 2.0, 0.16)
	tween.parallel().tween_property(label, "scale", Vector2.ONE, 0.16)
	tween.parallel().tween_property(label, "position", label.position + LINK_FLOAT_RISE, 0.32)
	tween.tween_property(line, "modulate:a", 0.0, 1.25).set_delay(0.43)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.25).set_delay(0.43)
	tween.tween_callback(line.queue_free)
	tween.parallel().tween_callback(label.queue_free)


func _on_chain_completed(chain_count, gold_earned) -> void:
	_chain_counter = chain_count
	_last_gold_earned = gold_earned
	_add_event_log(_format_completed_line(chain_count, gold_earned))
	_last_chain_history = _current_chain_history.duplicate()
	_update_counter()


func _update_counter() -> void:
	if counter_label:
		var reward_suffix := ""
		if _last_gold_earned > 0:
			reward_suffix = " · +%dg" % _last_gold_earned
		counter_label.text = "Triggers: %d%s" % [_chain_counter, reward_suffix]
	if phase_label:
		phase_label.text = "Phase: %s" % _phase_text()


func _update_event_log() -> void:
	if event_log_label == null:
		return
	if event_panel:
		event_panel.visible = not _event_log.is_empty() or _last_phase != ""
	if _event_log.is_empty():
		event_log_label.text = "No chain events yet"
	else:
		event_log_label.text = _join_event_log()


func _add_event_log(line: String) -> void:
	_current_chain_history.append(line)
	while _current_chain_history.size() > MAX_CHAIN_HISTORY_LINES:
		_current_chain_history.remove_at(0)
	_event_log.append(line)
	while _event_log.size() > MAX_EVENT_LOG_LINES:
		_event_log.remove_at(0)
	_update_event_log()


func _join_event_log() -> String:
	return _join_lines(_event_log)


func _join_lines(lines: Array[String]) -> String:
	var text := ""
	for i in lines.size():
		if i > 0:
			text += "\n"
		text += lines[i]
	return text


func _format_event_line(event_no: int, source_idx: int, target_idx: int,
		layer1: int, layer2: int, action: String) -> String:
	var layer_hint := _layer_text(layer1, layer2)
	if layer_hint != "":
		layer_hint = " " + layer_hint
	var flow_prefix := ""
	var flow_hint := _flow_hint_for_active_indices(source_idx, target_idx)
	if flow_hint != "":
		flow_prefix = "[%s] " % flow_hint
	return "#%d %s: %s%s -> %s %s%s" % [
		event_no,
		_phase_text(),
		flow_prefix,
		_active_label(source_idx),
		_active_label(target_idx),
		_action_text(action),
		layer_hint,
	]


func _format_completed_line(chain_count: int, gold_earned: int) -> String:
	var reward_text := "no gold"
	if gold_earned > 0:
		reward_text = "+%dg" % gold_earned
	return "Complete: %d triggers, %s" % [chain_count, reward_text]


func _active_label(active_idx: int) -> String:
	if active_idx < 0:
		return "none"
	var field_idx := _field_index_for_active(active_idx)
	if field_idx >= 0 and field_idx < _field_visuals.size():
		var visual = _field_visuals[field_idx]
		if is_instance_valid(visual):
			var card: CardInstance = visual.get("card_instance")
			if card != null:
				return card.get_name()
	return "slot %d" % (active_idx + 1)


func _field_index_for_active(active_idx: int) -> int:
	if active_idx < 0 or active_idx >= _active_board_map.size():
		return -1
	return int(_active_board_map[active_idx])


func _flow_hint_for_active_indices(source_idx: int, target_idx: int) -> String:
	return _direction_hint(
		_field_index_for_active(source_idx),
		_field_index_for_active(target_idx)
	)


func _direction_hint(source_field_idx: int, target_field_idx: int) -> String:
	if source_field_idx < 0 or target_field_idx < 0:
		return ""
	if target_field_idx > source_field_idx:
		return "L->R"
	if target_field_idx < source_field_idx:
		return "R->L"
	return "SELF"


func _phase_text() -> String:
	match _last_phase:
		"ROUND_START":
			return "Round Start"
		"BFS_CASCADE":
			return "Cascade"
		"":
			return "Idle"
		_:
			return _last_phase.replace("_", " ")


func _layer_text(layer1: int, layer2: int) -> String:
	var parts: Array[String] = []
	if layer1 >= 0:
		parts.append(_layer1_text(layer1))
	if layer2 >= 0 and layer2 != Enums.Layer2.NONE:
		parts.append(_layer2_text(layer2))
	if parts.is_empty():
		return ""
	return "(%s)" % " / ".join(PackedStringArray(parts))


func _layer1_text(layer1: int) -> String:
	match layer1:
		Enums.Layer1.UNIT_ADDED:
			return "Unit Added"
		Enums.Layer1.UNIT_REMOVED:
			return "Unit Removed"
		Enums.Layer1.ENHANCED:
			return "Enhanced"
		_:
			return "L1:%d" % layer1


func _layer2_text(layer2: int) -> String:
	match layer2:
		Enums.Layer2.MANUFACTURE:
			return "Manufacture"
		Enums.Layer2.UPGRADE:
			return "Upgrade"
		Enums.Layer2.TREE_GROW:
			return "Tree"
		Enums.Layer2.BREED:
			return "Breed"
		Enums.Layer2.HATCH:
			return "Hatch"
		Enums.Layer2.METAMORPHOSIS:
			return "Metamorphosis"
		Enums.Layer2.TRAIN:
			return "Train"
		Enums.Layer2.CONSCRIPT:
			return "Conscript"
		Enums.Layer2.ANY:
			return "Any"
		_:
			return "L2:%d" % layer2


func _action_text(action: String) -> String:
	match action:
		"spawn": return "+Unit"
		"enhance": return "+Stats"
		"buff_pct": return "Buff!"
		"shield_pct": return "Shield"
		"grant_gold": return "+Gold"
		_: return action
