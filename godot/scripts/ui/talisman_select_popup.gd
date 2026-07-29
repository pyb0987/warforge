extends ColorRect
## Run-start modal for choosing a talisman.

signal talisman_selected(talisman_type: int)

@onready var choice_grid: GridContainer = $VBox/ChoiceGrid
@onready var context_label: Label = $VBox/ContextLabel

var _choice_types: Array[int] = []
var _choice_panels: Array = []


func _ready() -> void:
	visible = false


func get_selectable_types() -> Array[int]:
	return [
		Enums.TalismanType.BURST_SACK,
		Enums.TalismanType.WAR_DRUM,
		Enums.TalismanType.MERCURY_DROP,
		Enums.TalismanType.GLASS_EYE,
		Enums.TalismanType.TWO_FACED_COIN,
		Enums.TalismanType.GOLDEN_DIE,
		Enums.TalismanType.CRACKED_EGG,
		Enums.TalismanType.FLINT,
		Enums.TalismanType.CRACKED_SKULL,
		Enums.TalismanType.RUSTY_WRENCH,
		Enums.TalismanType.SOUL_JAR,
		Enums.TalismanType.COPPER_WIRE,
	]


func show_choices(allowed_types: Array = [],
		selected_commander_type: int = Enums.CommanderType.NONE) -> void:
	_cleanup()
	context_label.text = _format_context_text(selected_commander_type)
	_choice_types = _to_int_array(allowed_types) if not allowed_types.is_empty() else get_selectable_types()
	for talisman_type in _choice_types:
		var data: Dictionary = Talisman.get_data(talisman_type)
		if data.is_empty():
			continue
		var panel := _create_talisman_panel(talisman_type, data)
		choice_grid.add_child(panel)
		_choice_panels.append(panel)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func select_talisman(talisman_type: int) -> void:
	if not _choice_types.has(talisman_type):
		return
	talisman_selected.emit(talisman_type)
	_cleanup()
	visible = false


func get_context_text() -> String:
	if context_label == null:
		return ""
	return context_label.text


func get_context_rect() -> Dictionary:
	return _control_rect(context_label)


func get_choice_summaries() -> Array:
	var summaries: Array = []
	for i in _choice_panels.size():
		var panel := _choice_panels[i] as PanelContainer
		if panel == null:
			continue
		var id := str(_choice_types[i]) if i < _choice_types.size() else ""
		var name_text := _label_text(panel, "VBox/NameLabel")
		var desc_text := _label_text(panel, "VBox/DescLabel")
		var text_parts := PackedStringArray()
		for path in ["VBox/IconLabel", "VBox/NameLabel", "VBox/DescLabel"]:
			var part := _label_text(panel, path).strip_edges()
			if part != "":
				text_parts.append(part)
		summaries.append({
			"id": id,
			"idx": i,
			"name": name_text,
			"desc": desc_text,
			"text": "\n".join(text_parts),
			"rect": _control_rect(panel),
		})
	return summaries


func _create_talisman_panel(talisman_type: int, data: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Talisman_%d" % talisman_type
	panel.custom_minimum_size = Vector2(230, 135)
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var icon_label := Label.new()
	icon_label.name = "IconLabel"
	icon_label.text = data.get("icon", "?")
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 32)
	vbox.add_child(icon_label)

	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = data.get("name", "???")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 17)
	vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.name = "DescLabel"
	desc_label.text = data.get("desc", "")
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size.x = 200
	desc_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(desc_label)

	panel.gui_input.connect(_on_panel_input.bind(talisman_type))
	return panel


func _format_context_text(selected_commander_type: int) -> String:
	var base := "부적 = 커맨더를 보조하는 작은 규칙 1개"
	if selected_commander_type == Enums.CommanderType.NONE:
		return base
	var data: Dictionary = Commander.get_data(selected_commander_type)
	if data.is_empty():
		return base
	return "선택한 커맨더: %s %s - %s\n%s" % [
		data.get("icon", "?"),
		data.get("name", str(selected_commander_type)),
		data.get("desc", ""),
		base,
	]


func _on_panel_input(event: InputEvent, talisman_type: int) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	select_talisman(talisman_type)


func _cleanup() -> void:
	for panel in _choice_panels:
		panel.queue_free()
	_choice_panels.clear()
	_choice_types.clear()


func _to_int_array(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value in values:
		result.append(int(value))
	return result


func _label_text(root: Node, path: String) -> String:
	var label := root.get_node_or_null(path) as Label
	if label == null:
		return ""
	return label.text


func _control_rect(control: Control) -> Dictionary:
	if control == null:
		return {}
	var rect := control.get_global_rect()
	return {
		"x": rect.position.x,
		"y": rect.position.y,
		"w": rect.size.x,
		"h": rect.size.y,
		"visible": control.is_visible_in_tree(),
	}
