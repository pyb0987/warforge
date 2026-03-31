extends Control
## Overlay for selecting a field card to attach an upgrade to.
## Highlights eligible cards, handles click and ESC cancel.

signal target_selected(field_idx: int)
signal target_cancelled

var _active: bool = false
var _field_visuals: Array = []
var _click_connections: Array[Dictionary] = []  # [{visual, callable}]

@onready var instruction_label: Label = $InstructionLabel


func start_selection(field_visuals: Array, board: Array) -> void:
	_field_visuals = field_visuals
	_active = true
	visible = true
	instruction_label.text = "Click a field card to attach upgrade (ESC to cancel)"

	# Highlight eligible cards and connect click handlers
	for i in field_visuals.size():
		var vis: Panel = field_visuals[i]
		if i >= board.size():
			continue
		var card = board[i]
		if card == null or not (card as CardInstance).can_attach_upgrade():
			continue
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
