extends Panel
## Visual representation of a card (Phase 1: colored rectangle + text).

signal card_clicked(card_visual)
signal card_drag_started(card_visual)

var card_instance: CardInstance = null
var zone: String = ""  # "board" or "bench"
var slot_idx: int = -1

@onready var name_label: Label = $NameLabel
@onready var stats_label: Label = $StatsLabel
@onready var tier_label: Label = $TierLabel


func _ready() -> void:
	# Ensure Labels don't intercept mouse — Panel must receive hover events.
	mouse_filter = Control.MOUSE_FILTER_STOP
	for child in [name_label, stats_label, tier_label]:
		if child:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Use high-level signals (more reliable than NOTIFICATION_MOUSE_ENTER).
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _star_glyph(star: int) -> String:
	return "★%d" % star


func _on_mouse_entered() -> void:
	if card_instance == null:
		return
	var tooltip_node = get_tree().get_first_node_in_group("card_tooltip")
	if tooltip_node and tooltip_node.has_method("show_card"):
		tooltip_node.show_card(card_instance, global_position + Vector2(size.x, 0))


func _on_mouse_exited() -> void:
	var tooltip_node = get_tree().get_first_node_in_group("card_tooltip")
	if tooltip_node and tooltip_node.has_method("hide_tooltip"):
		tooltip_node.hide_tooltip()

var _theme_colors := {
	Enums.CardTheme.NEUTRAL: Color(0.5, 0.5, 0.5),
	Enums.CardTheme.STEAMPUNK: Color(0.9, 0.6, 0.2),
	Enums.CardTheme.DRUID: Color(0.3, 0.7, 0.3),
	Enums.CardTheme.PREDATOR: Color(0.6, 0.2, 0.7),
	Enums.CardTheme.MILITARY: Color(0.2, 0.4, 0.8),
}

var _is_dragging := false
var _drag_offset := Vector2.ZERO


func setup(card: CardInstance, z: String, idx: int) -> void:
	card_instance = card
	zone = z
	slot_idx = idx
	if card != null:
		card.stats_changed.connect(_on_stats_changed)
	refresh()


func refresh() -> void:
	visible = true
	if card_instance == null:
		name_label.text = ""
		tier_label.text = ""
		stats_label.text = ""
		var empty_style := StyleBoxFlat.new()
		empty_style.bg_color = Color(0.15, 0.15, 0.15, 0.5)
		empty_style.corner_radius_top_left = 4
		empty_style.corner_radius_top_right = 4
		empty_style.corner_radius_bottom_left = 4
		empty_style.corner_radius_bottom_right = 4
		empty_style.border_width_left = 1
		empty_style.border_width_right = 1
		empty_style.border_width_top = 1
		empty_style.border_width_bottom = 1
		empty_style.border_color = Color(0.3, 0.3, 0.3, 0.5)
		add_theme_stylebox_override("panel", empty_style)
		return

	var tmpl := card_instance.template
	name_label.text = tmpl.get("name", "???")
	# Format: "T2 ★1"  (shop adds cost: "T2 ★1 · 3g")
	var tier_text := "T%d %s" % [tmpl.get("tier", 0), _star_glyph(card_instance.star_level)]
	if zone == "shop":
		var cost: int = tmpl.get("cost", 0)
		tier_text += " · %dg" % cost

	# Theme color
	var theme: int = tmpl.get("theme", Enums.CardTheme.NEUTRAL)

	# Theme state display on card face
	if theme == Enums.CardTheme.MILITARY and card_instance.theme_state.has("rank"):
		tier_text += " R%d" % card_instance.theme_state["rank"]
	elif theme == Enums.CardTheme.DRUID and card_instance.theme_state.has("trees"):
		tier_text += " 🌳%d" % card_instance.theme_state["trees"]

	tier_label.text = tier_text

	var units := card_instance.get_total_units()
	var atk := card_instance.get_total_atk()
	var hp := card_instance.get_total_hp()
	stats_label.text = "%du A%.0f H%.0f" % [units, atk, hp]
	var base_color: Color = _theme_colors.get(theme, Color.GRAY)

	var style := StyleBoxFlat.new()
	style.bg_color = base_color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = base_color.lightened(0.3)
	add_theme_stylebox_override("panel", style)


func clear() -> void:
	if card_instance != null and card_instance.stats_changed.is_connected(_on_stats_changed):
		card_instance.stats_changed.disconnect(_on_stats_changed)
	card_instance = null
	visible = false


func _on_stats_changed() -> void:
	refresh()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if card_instance == null:
		return null
	# Create drag preview
	var preview := Label.new()
	preview.text = card_instance.get_name()
	preview.add_theme_color_override("font_color", Color.WHITE)
	set_drag_preview(preview)

	return {"source_zone": zone, "source_idx": slot_idx, "card_visual": self}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("source_zone")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	# Delegate to parent (build_phase.gd)
	var parent := get_parent()
	while parent != null:
		if parent.has_method("_on_card_dropped"):
			parent._on_card_dropped(data, zone, slot_idx)
			return
		parent = parent.get_parent()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT and card_instance != null:
			# Right-click = sell card
			var parent := get_parent()
			while parent != null:
				if parent.has_method("_on_card_sell"):
					parent._on_card_sell(zone, slot_idx)
					return
				parent = parent.get_parent()


