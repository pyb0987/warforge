extends Control
## Visualizes chain events as lines between cards + floating text.

var _field_visuals: Array = []  # references to card_visual panels (all 8 slots)
var _active_board_map: Array = []  # maps active_board index → field_visuals index
var _active_links: Array = []   # currently displayed links
var _chain_counter: int = 0

@onready var counter_label: Label = $CounterLabel

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
	_update_counter()


## Build mapping from active_board indices to field_visual indices.
## Call this before each chain run.
func update_board_map(board: Array) -> void:
	_active_board_map.clear()
	for i in board.size():
		if board[i] != null:
			_active_board_map.append(i)


func connect_engine(engine: ChainEngine) -> void:
	engine.chain_event_fired.connect(_on_chain_event)
	engine.chain_completed.connect(_on_chain_completed)


func clear_links() -> void:
	for link in _active_links:
		if is_instance_valid(link):
			link.queue_free()
	_active_links.clear()
	_chain_counter = 0
	_update_counter()


func _on_chain_event(source_idx, target_idx, _layer1, _layer2, action) -> void:
	_chain_counter += 1
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

	# Line
	var line := Line2D.new()
	var src_center := src_panel.global_position + src_panel.size / 2.0
	var tgt_center := tgt_panel.global_position + tgt_panel.size / 2.0
	line.add_point(src_center)
	line.add_point(tgt_center)
	line.width = 2.0
	line.default_color = _event_colors.get(str(action), Color.WHITE)
	line.z_index = 10
	add_child(line)
	_active_links.append(line)

	# Floating text
	var label := Label.new()
	label.text = _action_text(str(action))
	label.global_position = (src_center + tgt_center) / 2.0 + Vector2(0, -15)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", _event_colors.get(str(action), Color.WHITE))
	label.z_index = 11
	add_child(label)
	_active_links.append(label)

	# Auto-fade after 2 seconds
	var tween := create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 1.5).set_delay(0.5)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.5).set_delay(0.5)
	tween.tween_callback(line.queue_free)
	tween.parallel().tween_callback(label.queue_free)


func _on_chain_completed(chain_count, _gold_earned) -> void:
	_chain_counter = chain_count
	_update_counter()


func _update_counter() -> void:
	if counter_label:
		counter_label.text = "Triggers: %d" % _chain_counter


func _action_text(action: String) -> String:
	match action:
		"spawn": return "+Unit"
		"enhance": return "+ATK%"
		"buff_pct": return "Buff!"
		"shield_pct": return "Shield"
		"grant_gold": return "+Gold"
		_: return action
