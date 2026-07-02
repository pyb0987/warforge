extends Control
## Overlay for selecting a field card to attach an upgrade to.
## Highlights eligible cards, handles click and ESC cancel.

signal target_selected(field_idx: int)
signal target_cancelled

var _active: bool = false
var _field_visuals: Array = []
var _click_connections: Array[Dictionary] = []  # [{visual, callable}]
var _preview_labels: Array[Label] = []

@onready var instruction_label: Label = $InstructionLabel
@onready var detail_label: Label = get_node_or_null("DetailLabel") as Label


## eligible_predicate: Callable(card: CardInstance) -> bool. null = 모든 비-null 카드 선택 가능.
## upgrade 부착용은 can_attach_upgrade 필터, theme transform / unit transfer 등은 null.
func start_selection(field_visuals: Array, board: Array,
		eligible_predicate: Callable = Callable(),
		context: Dictionary = {}) -> void:
	if _active:
		end_selection()
	_field_visuals = field_visuals
	_active = true
	visible = true
	instruction_label.text = context.get("instruction",
		"Click a field card (ESC to cancel)")
	if detail_label:
		detail_label.text = context.get("detail", "")
		detail_label.visible = detail_label.text != ""
	var note_formatter: Callable = context.get("note_formatter", Callable())

	# Highlight eligible cards and connect click handlers
	for i in field_visuals.size():
		var vis: Panel = field_visuals[i]
		if i >= board.size():
			continue
		var card = board[i]
		if card == null:
			continue
		var eligible := true
		# 핸들러별 predicate 적용 (default: 모든 비-null 카드 가능)
		if eligible_predicate.is_valid():
			eligible = bool(eligible_predicate.call(card))
		if note_formatter.is_valid():
			var note := str(note_formatter.call(card, eligible, i))
			if note != "":
				_create_preview_label(vis, note, eligible)
		if eligible:
			# Add highlight border
			_set_highlight(vis, true)
			var callable := _on_field_clicked.bind(i)
			vis.gui_input.connect(callable)
			_click_connections.append({"visual": vis, "callable": callable})


func end_selection() -> void:
	_active = false
	visible = false
	# Remove highlights and disconnect handlers
	for conn in _click_connections:
		var vis: Panel = conn["visual"]
		_set_highlight(vis, false)
		if vis.gui_input.is_connected(conn["callable"]):
			vis.gui_input.disconnect(conn["callable"])
	_click_connections.clear()
	for label in _preview_labels:
		if is_instance_valid(label):
			label.queue_free()
	_preview_labels.clear()
	if detail_label:
		detail_label.visible = false


func get_preview_texts() -> Array[String]:
	var result: Array[String] = []
	for label in _preview_labels:
		if is_instance_valid(label):
			result.append(label.text)
	return result


func _on_field_clicked(event: InputEvent, field_idx: int) -> void:
	if not _active:
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	target_selected.emit(field_idx)
	end_selection()


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		target_cancelled.emit()
		end_selection()
		get_viewport().set_input_as_handled()


func _set_highlight(vis: Panel, on: bool) -> void:
	if on:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.8, 0.2, 0.3)
		style.border_width_left = 3
		style.border_width_right = 3
		style.border_width_top = 3
		style.border_width_bottom = 3
		style.border_color = Color(0.2, 1.0, 0.2)
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		vis.add_theme_stylebox_override("panel", style)
	else:
		# Refresh the card visual to restore its original style
		if vis.has_method("refresh"):
			vis.call("refresh")


func _create_preview_label(vis: Panel, text: String, eligible: bool) -> void:
	var label := Label.new()
	label.name = "TargetNote_%d" % _preview_labels.size()
	label.text = text
	label.custom_minimum_size = Vector2(maxf(vis.size.x, 120.0), 42.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color",
		Color(0.88, 1.0, 0.86) if eligible else Color(1.0, 0.55, 0.48))
	label.z_index = 50
	add_child(label)
	label.global_position = vis.global_position + Vector2(0, -50)
	_preview_labels.append(label)
