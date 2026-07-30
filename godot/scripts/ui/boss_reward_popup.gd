extends ColorRect
## Modal popup: shows N boss reward choices, player picks 1.
## Pattern: upgrade_choice_popup.gd와 동일.

signal reward_selected(reward_id: String)

var _choice_ids: Array[String] = []
var _choice_panels: Array = []

@onready var title_label: Label = $VBox/TitleLabel
@onready var choice_container: HBoxContainer = $VBox/ChoiceContainer


func show_choices(reward_ids: Array[String]) -> void:
	_cleanup()

	title_label.text = "보스 보상 선택 (1개 선택 / %d개 후보)" % reward_ids.size()
	_choice_ids = reward_ids.duplicate()

	for i in reward_ids.size():
		var data: Dictionary = BossRewardDB.get_data(reward_ids[i])
		var panel := _create_reward_panel(data, i)
		choice_container.add_child(panel)
		_choice_panels.append(panel)

	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func get_choice_ids() -> Array[String]:
	return _choice_ids.duplicate()


func get_choice_summaries() -> Array:
	var summaries: Array = []
	for i in _choice_panels.size():
		var panel: PanelContainer = _choice_panels[i] as PanelContainer
		if panel == null:
			continue
		var reward_id := ""
		if i < _choice_ids.size():
			reward_id = _choice_ids[i]
		var data: Dictionary = BossRewardDB.get_data(reward_id)
		var name := _label_text(panel, "VBox/NameLabel")
		var type_text := _label_text(panel, "VBox/TypeLabel")
		var desc := _label_text(panel, "VBox/DescLabel")
		var parts := PackedStringArray()
		for text in [name, type_text, desc]:
			if str(text).strip_edges() != "":
				parts.append(str(text))
		summaries.append({
			"id": reward_id,
			"idx": i,
			"name": name,
			"type": type_text,
			"desc": desc,
			"text": "\n".join(parts),
			"needs_target": int(data.get("needs_target", 0)) != 0,
			"rect": _control_rect(panel),
		})
	return summaries


func select_choice_index(idx: int) -> bool:
	if idx < 0 or idx >= _choice_ids.size():
		return false

	var chosen_id: String = _choice_ids[idx]
	reward_selected.emit(chosen_id)
	_cleanup()
	visible = false
	return true


func _create_reward_panel(data: Dictionary, idx: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "RewardPanel_%d" % idx
	panel.custom_minimum_size = Vector2(180, 200)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var icon_label := Label.new()
	icon_label.name = "IconLabel"
	icon_label.text = data.get("icon", "?")
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 36)
	vbox.add_child(icon_label)

	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = data.get("name", "???")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(name_label)

	var type_label := Label.new()
	type_label.name = "TypeLabel"
	var type_str: String = data.get("type", "")
	var type_display: String = {"instant": "⚡즉시", "permanent": "🔄영구",
		"direct": "💥직접", "structural": "📐구조"}.get(type_str, type_str)
	type_label.text = type_display
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(type_label)

	var desc_label := Label.new()
	desc_label.name = "DescLabel"
	desc_label.text = data.get("desc", "")
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size.x = 160
	desc_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(desc_label)

	panel.gui_input.connect(_on_panel_input.bind(idx))
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return panel


func _on_panel_input(event: InputEvent, idx: int) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	select_choice_index(idx)


func _cleanup() -> void:
	for p in _choice_panels:
		p.queue_free()
	_choice_panels.clear()
	_choice_ids.clear()


func _label_text(root: Node, path: String) -> String:
	var label := root.get_node_or_null(path) as Label
	if label == null:
		return ""
	return label.text


func _control_rect(control: Control) -> Dictionary:
	var rect := control.get_global_rect()
	return {
		"x": rect.position.x,
		"y": rect.position.y,
		"w": rect.size.x,
		"h": rect.size.y,
		"visible": control.is_visible_in_tree(),
	}
