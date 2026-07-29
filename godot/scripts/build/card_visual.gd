extends Panel
## Visual representation of a card (Phase 1: colored rectangle + text).

signal card_clicked(card_visual)
signal card_drag_started(card_visual)

var card_instance: CardInstance = null
var zone: String = ""  # "board" or "bench"
var slot_idx: int = -1
var _shop_cost_override: int = -1
var _shop_price_note: String = ""

@onready var name_label: Label = $NameLabel
@onready var stats_label: Label = $StatsLabel
@onready var tier_label: Label = $TierLabel
@onready var role_label: Label = $RoleLabel


func _ready() -> void:
	# Ensure Labels don't intercept mouse — Panel must receive hover events.
	mouse_filter = Control.MOUSE_FILTER_STOP
	for child in [name_label, stats_label, tier_label, role_label]:
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


func setup(card: CardInstance, z: String, idx: int,
		shop_cost_override: int = -1, shop_price_note: String = "") -> void:
	if card_instance != null and card_instance != card \
			and card_instance.stats_changed.is_connected(_on_stats_changed):
		card_instance.stats_changed.disconnect(_on_stats_changed)
	card_instance = card
	zone = z
	slot_idx = idx
	_shop_cost_override = shop_cost_override
	_shop_price_note = shop_price_note
	if card != null and not card.stats_changed.is_connected(_on_stats_changed):
		card.stats_changed.connect(_on_stats_changed)
	refresh()


func get_shop_price_note() -> String:
	return _shop_price_note


func get_face_tier_text() -> String:
	if tier_label == null:
		return ""
	return tier_label.text


func get_face_role_text() -> String:
	if role_label == null:
		return ""
	return role_label.text


func refresh() -> void:
	visible = true
	if tier_label:
		tier_label.remove_theme_color_override("font_color")
	if card_instance == null:
		name_label.text = ""
		tier_label.text = ""
		if role_label != null:
			role_label.text = ""
			role_label.visible = false
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
		var cost: int = _shop_cost_override if _shop_cost_override >= 0 else tmpl.get("cost", 0)
		tier_text += " · %dg" % cost
		if _shop_price_note != "":
			tier_text += " COIN %s" % _shop_price_note
			if _shop_price_note.begins_with("-"):
				tier_label.add_theme_color_override("font_color", Color(0.78, 1.0, 0.62))
			elif _shop_price_note.begins_with("+"):
				tier_label.add_theme_color_override("font_color", Color(1.0, 0.64, 0.52))

	# Theme color
	var theme: int = tmpl.get("theme", Enums.CardTheme.NEUTRAL)

	# Theme state display on card face
	if theme == Enums.CardTheme.MILITARY and card_instance.theme_state.has("rank"):
		tier_text += " R%d" % card_instance.theme_state["rank"]
	elif theme == Enums.CardTheme.DRUID and card_instance.theme_state.has("trees"):
		tier_text += " 🌳%d" % card_instance.theme_state["trees"]

	tier_label.text = tier_text
	var role_text := _format_role_text(tmpl)
	if role_label != null:
		role_label.text = role_text
		role_label.visible = zone == "shop" and role_text != ""

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
	if zone == "shop" and _shop_price_note != "":
		style.border_width_left = 4
		style.border_width_right = 4
		style.border_width_top = 4
		style.border_width_bottom = 4
		if _shop_price_note.begins_with("-"):
			style.border_color = Color(0.56, 1.0, 0.32)
		elif _shop_price_note.begins_with("+"):
			style.border_color = Color(1.0, 0.42, 0.32)
	add_theme_stylebox_override("panel", style)


func _format_role_text(tmpl: Dictionary) -> String:
	var block := _representative_block(tmpl)
	var timing := _format_role_timing(int(block.get(
		"trigger_timing", tmpl.get("trigger_timing", -1))))
	var role := _format_role_mechanic(_collect_role_actions(block))
	if timing == "":
		return role
	if role == "":
		return timing
	return "%s · %s" % [timing, role]


func _representative_block(tmpl: Dictionary) -> Dictionary:
	var blocks: Array = tmpl.get("effects", [])
	if blocks.size() > 0 and blocks[0] is Dictionary:
		return blocks[0]
	return {
		"trigger_timing": tmpl.get("trigger_timing", -1),
		"actions": tmpl.get("actions", []),
	}


func _format_role_timing(timing: int) -> String:
	match timing:
		Enums.TriggerTiming.ROUND_START:
			return "시작"
		Enums.TriggerTiming.ON_EVENT:
			return "반응"
		Enums.TriggerTiming.BATTLE_START:
			return "전투"
		Enums.TriggerTiming.ON_COMBAT_ATTACK:
			return "공격"
		Enums.TriggerTiming.ON_COMBAT_DEATH:
			return "사망"
		Enums.TriggerTiming.POST_COMBAT:
			return "전후"
		Enums.TriggerTiming.POST_COMBAT_DEFEAT:
			return "패배"
		Enums.TriggerTiming.POST_COMBAT_VICTORY:
			return "승리"
		Enums.TriggerTiming.ON_REROLL:
			return "리롤"
		Enums.TriggerTiming.ON_MERGE:
			return "합성"
		Enums.TriggerTiming.ON_SELL:
			return "판매"
		Enums.TriggerTiming.PERSISTENT:
			return "지속"
	return ""


func _collect_role_actions(block: Dictionary) -> Array[String]:
	var actions: Array[String] = []
	_append_role_actions(actions, block.get("actions", []))
	for key in ["conditional_effects", "r_conditional_effects",
			"post_threshold_effects"]:
		for conditional in block.get(key, []):
			if conditional is Dictionary:
				_append_role_actions(actions, conditional.get("effects", []))
	return actions


func _append_role_actions(result: Array[String], actions: Array) -> void:
	for action_data in actions:
		if not (action_data is Dictionary):
			continue
		var action_name := str(action_data.get("action", ""))
		if action_name != "":
			result.append(action_name)
		if action_data.has("effects"):
			_append_role_actions(result, action_data.get("effects", []))


func _format_role_mechanic(actions: Array[String]) -> String:
	if _has_any_action(actions, [
			"grant_gold", "grant_terazin", "diversity_gold", "economy",
			"terazin", "tree_gold", "free_reroll", "levelup_discount",
			"epic_shop_unlock", "council_epic_grant"]):
		return "경제"
	if _has_any_action(actions, [
			"shield", "shield_pct", "tree_shield"]):
		return "보호"
	if _has_any_action(actions, [
			"tree_combat_bonus", "tree_temp_buff", "range_bonus", "lifesteal",
			"crit_splash", "debuff_store", "swarm_buff", "on_combat_result"]):
		return "화력"
	if _has_any_action(actions, [
			"enhance", "enhance_pct", "tree_enhance",
			"gear_diversity_enhance", "hatch_enhance", "rank_scaled_enhance",
			"rank_buff", "rank_buff_hp", "train", "multiply_stats",
			"growth_multiply", "duplicate_buff_aura", "star_aura", "buff",
			"buff_pct", "crit_buff", "high_rank_mult", "transform_theme",
			"meta_consume", "tree_absorb", "tree_distribute",
			"absorb_steampunk"]):
		return "강화"
	if _has_any_action(actions, [
			"spawn", "manufacture", "counter_produce", "conscript",
			"theme_count_conscript", "theme_count_spawn", "hatch",
			"hatch_scaled", "spawn_enhanced_random", "tree_add",
			"mirror_spawn_to_tree", "revive"]):
		return "유닛+"
	if _has_any_action(actions, [
			"awakening_sell", "hoarder_transfer", "prune", "scrap_adjacent",
			"empty_slot_scaling"]):
		return "전환"
	if _has_any_action(actions, ["mirror_l1", "mirror_l2"]):
		return "연결"
	return "효과"


func _has_any_action(actions: Array[String], wanted: Array) -> bool:
	for action in actions:
		if action in wanted:
			return true
	return false


func clear() -> void:
	if card_instance != null and card_instance.stats_changed.is_connected(_on_stats_changed):
		card_instance.stats_changed.disconnect(_on_stats_changed)
	card_instance = null
	_shop_cost_override = -1
	_shop_price_note = ""
	if role_label != null:
		role_label.text = ""
		role_label.visible = false
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
		if event.button_index == MOUSE_BUTTON_LEFT and card_instance != null:
			card_clicked.emit(self)
		elif event.button_index == MOUSE_BUTTON_RIGHT and card_instance != null:
			# Right-click = sell card
			var parent := get_parent()
			while parent != null:
				if parent.has_method("_on_card_sell"):
					parent._on_card_sell(zone, slot_idx)
					return
				parent = parent.get_parent()
