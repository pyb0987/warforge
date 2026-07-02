extends ColorRect
## Run-start modal for choosing a commander.

signal commander_selected(commander_type: int)

@onready var choice_grid: GridContainer = $VBox/ChoiceGrid

var _choice_types: Array[int] = []
var _choice_panels: Array = []


func _ready() -> void:
	visible = false


func get_selectable_types() -> Array[int]:
	return [
		Enums.CommanderType.GAMBLER,
		Enums.CommanderType.BREEDER,
		Enums.CommanderType.SMITH,
		Enums.CommanderType.STRATEGIST,
		Enums.CommanderType.COLLECTOR,
		Enums.CommanderType.RAIDER,
		Enums.CommanderType.ALCHEMIST,
	]


func show_choices(allowed_types: Array = []) -> void:
	_cleanup()
	_choice_types = _to_int_array(allowed_types) if not allowed_types.is_empty() else get_selectable_types()
	for commander_type in _choice_types:
		var data: Dictionary = Commander.get_data(commander_type)
		if data.is_empty():
			continue
		var panel := _create_commander_panel(commander_type, data)
		choice_grid.add_child(panel)
		_choice_panels.append(panel)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func select_commander(commander_type: int) -> void:
	if not _choice_types.has(commander_type):
		return
	commander_selected.emit(commander_type)
	_cleanup()
	visible = false


func _create_commander_panel(commander_type: int, data: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Commander_%d" % commander_type
	panel.custom_minimum_size = Vector2(230, 150)
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var icon_label := Label.new()
	icon_label.text = data.get("icon", "?")
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 34)
	vbox.add_child(icon_label)

	var name_label := Label.new()
	name_label.text = data.get("name", "???")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = data.get("desc", "")
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size.x = 200
	desc_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(desc_label)

	panel.gui_input.connect(_on_panel_input.bind(commander_type))
	return panel


func _on_panel_input(event: InputEvent, commander_type: int) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	select_commander(commander_type)


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
