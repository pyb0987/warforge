extends ColorRect
## Modal popup: shows 3 conscription unit options, player picks 1.
## Pattern: upgrade_choice_popup.gd와 동일.

signal unit_chosen(unit_id: String)

var _option_ids: Array[String] = []
var _option_panels: Array = []

@onready var title_label: Label = $VBox/TitleLabel
@onready var choice_container: HBoxContainer = $VBox/ChoiceContainer


func show_choices(options: Array[String]) -> void:
	_cleanup()
	_option_ids.assign(options)

	for i in options.size():
		var uid: String = options[i]
		var data: Dictionary = UnitDB.get_data(uid)
		var panel := _create_unit_panel(uid, data)
		choice_container.add_child(panel)
		panel.gui_input.connect(_on_option_input.bind(i))
		_option_panels.append(panel)

	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func _create_unit_panel(uid: String, data: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(160, 180)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var name_label := Label.new()
	name_label.text = data.get("name", uid)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(name_label)

	vbox.add_child(HSeparator.new())

	var stats := [
		["ATK", data.get("atk", 0)],
		["HP", data.get("hp", 0)],
		["AS", data.get("attack_speed", 0)],
		["Range", data.get("attack_range", 0)],
		["MS", data.get("move_speed", 0)],
	]
	for s in stats:
		var line := Label.new()
		line.text = "%s: %s" % [s[0], s[1]]
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.add_theme_font_size_override("font_size", 14)
		vbox.add_child(line)

	return panel


func _on_option_input(event: InputEvent, idx: int) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if idx < 0 or idx >= _option_ids.size():
		return

	var chosen_id: String = _option_ids[idx]
	unit_chosen.emit(chosen_id)
	_cleanup()
	visible = false


func _cleanup() -> void:
	for p in _option_panels:
		p.queue_free()
	_option_panels.clear()
	_option_ids.clear()
