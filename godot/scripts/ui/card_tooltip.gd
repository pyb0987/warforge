extends PanelContainer
## Card detail tooltip shown on hover.

@onready var name_label: Label = $VBox/NameLabel
@onready var cost_label: Label = $VBox/CostLabel
@onready var info_label: Label = $VBox/InfoLabel
@onready var effect_label: RichTextLabel = $VBox/EffectLabel
@onready var units_label: Label = $VBox/UnitsLabel

var _keyword_popup: PanelContainer
var _keyword_label: Label

var _timing_names := {
	Enums.TriggerTiming.ROUND_START: "라운드 시작",
	Enums.TriggerTiming.ON_EVENT: "반응",
	Enums.TriggerTiming.BATTLE_START: "전투 시작",
	Enums.TriggerTiming.POST_COMBAT: "전투 종료",
	Enums.TriggerTiming.POST_COMBAT_DEFEAT: "전투 패배",
	Enums.TriggerTiming.POST_COMBAT_VICTORY: "전투 승리",
	Enums.TriggerTiming.ON_REROLL: "리롤",
	Enums.TriggerTiming.ON_MERGE: "★합성",
	Enums.TriggerTiming.ON_SELL: "판매",
	Enums.TriggerTiming.PERSISTENT: "지속",
}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("card_tooltip")
	_setup_keyword_popup()


func _setup_keyword_popup() -> void:
	_keyword_popup = PanelContainer.new()
	_keyword_popup.z_index = 200
	_keyword_popup.visible = false
	_keyword_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keyword_popup.top_level = true  # Independent of parent layout
	_keyword_label = Label.new()
	_keyword_label.name = "DefLabel"
	_keyword_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_keyword_label.custom_minimum_size = Vector2(200, 0)
	_keyword_popup.add_child(_keyword_label)
	add_child(_keyword_popup)


func show_card(card: CardInstance, at_pos: Vector2) -> void:
	if card == null:
		visible = false
		return

	var base_tmpl := card.template
	var tmpl := CardDB.get_star_template(base_tmpl.get("id", ""), card.star_level)
	if tmpl.is_empty():
		tmpl = base_tmpl
	name_label.text = "%s  T%d ★%d" % [tmpl.get("name", "???"), tmpl.get("tier", base_tmpl.get("tier", 0)), card.star_level]

	# Cost
	var cost: int = tmpl.get("cost", base_tmpl.get("cost", 0))
	cost_label.text = "비용: %d골드" % cost

	# Trigger info
	var timing: int = tmpl.get("trigger_timing", -1)
	var timing_text: String = _timing_names.get(timing, "???")
	var max_act: int = tmpl.get("max_activations", -1)
	var act_text := " (최대 %d/R)" % max_act if max_act > 0 else ""
	info_label.text = "발동: %s%s" % [timing_text, act_text]

	# Effect summary — card_descs 우선, 없으면 effects[] fallback
	var card_id: String = base_tmpl.get("id", "")
	var desc: String = CardDescs.get_desc(card_id, card.star_level)
	var raw_text: String
	if desc != "":
		raw_text = desc
	else:
		var effects: Array = tmpl.get("effects", [])
		if effects.is_empty():
			raw_text = "(Theme system effect)"
		else:
			var lines: PackedStringArray = []
			for eff in effects:
				lines.append(_describe_effect(eff))
			raw_text = "\n".join(lines)
	_set_effect_text(raw_text)

	# Keyword glossary — auto-show definitions for keywords found in text
	_update_keyword_panel(raw_text)

	# Theme-specific state display
	var tmpl_theme: int = tmpl.get("theme", Enums.CardTheme.NEUTRAL)
	match tmpl_theme:
		Enums.CardTheme.MILITARY:
			if card.theme_state.has("rank"):
				var rank: int = card.theme_state["rank"]
				# R4/R10 milestone 재설계 (trace 012): 고정 milestone 두 단계.
				var next_milestone: int = -1
				if rank < 4:
					next_milestone = 4
				elif rank < 10:
					next_milestone = 10
				if next_milestone > 0:
					info_label.text += "\n계급 %d (다음 R%d)" % [rank, next_milestone]
				else:
					info_label.text += "\n계급 %d (R10 도달)" % rank
			if card.theme_state.has("conscript_counter"):
				var cc: int = card.theme_state["conscript_counter"]
				var ct := 10
				match card.star_level:
					2: ct = 8
					3: ct = 6
				info_label.text += "\n징집 %d/%d" % [cc, ct]
		Enums.CardTheme.DRUID:
			if card.theme_state.has("trees"):
				info_label.text += "\n🌳 %d" % card.theme_state["trees"]
		Enums.CardTheme.STEAMPUNK:
			if card.theme_state.has("manufacture_counter"):
				var mc: int = card.theme_state["manufacture_counter"]
				var mt := 10
				if card.star_level == 2:
					mt = 20
				info_label.text += "\n⚙ %d/%d" % [mc, mt]

	# Unit composition + total CP
	var unit_lines: PackedStringArray = []
	for s in card.stacks:
		var ut: Dictionary = s["unit_type"]
		unit_lines.append("%s ×%d (A%.0f H%.0f)" % [
			ut.get("name", "?"), s["count"],
			card.eff_atk_for(s), card.eff_hp_for(s)])
	unit_lines.append("CP: %.0f" % card.get_total_cp())
	units_label.text = "\n".join(unit_lines)

	# Force layout recalculation so size reflects updated content
	reset_size()

	# Position
	global_position = at_pos + Vector2(10, 10)
	# Keep on screen (all edges)
	var vp_size := get_viewport_rect().size
	if global_position.x + size.x > vp_size.x:
		global_position.x = at_pos.x - size.x - 10
	if global_position.y + size.y > vp_size.y:
		global_position.y = vp_size.y - size.y - 10
	if global_position.x < 0:
		global_position.x = 0
	if global_position.y < 0:
		global_position.y = 0

	# Place keyword popup to the right of tooltip (global coords since top_level=true)
	_keyword_popup.global_position = global_position + Vector2(size.x + 5, 0)

	visible = true


func hide_tooltip() -> void:
	visible = false


func _set_effect_text(raw_text: String) -> void:
	# Escape square brackets so they aren't parsed as BBCode tags (e.g. [반응])
	# Must use placeholder to avoid chained-replace corruption
	var escaped := raw_text.replace("[", "\x01").replace("]", "[rb]").replace("\x01", "[lb]")
	var bbcode := escaped
	for kw in KeywordGlossary.get_all_keywords():
		bbcode = bbcode.replace(kw, "[url=%s][color=#aaccff]%s[/color][/url]" % [kw, kw])
	effect_label.clear()
	effect_label.append_text(bbcode)


func _update_keyword_panel(raw_text: String) -> void:
	var found: PackedStringArray = []
	for kw in KeywordGlossary.get_all_keywords():
		if raw_text.contains(kw):
			var theme_name: String = KeywordGlossary.get_theme(kw)
			var definition: String = KeywordGlossary.get_definition(kw)
			found.append("[%s] %s: %s" % [theme_name, kw, definition])
	if found.is_empty():
		_keyword_popup.visible = false
	else:
		_keyword_label.text = "\n".join(found)
		_keyword_popup.visible = true


func _describe_effect(eff: Dictionary) -> String:
	var action: String = eff.get("action", "")
	match action:
		"spawn":
			var count: int = eff.get("spawn_count", 1)
			var target: String = eff.get("target", "self")
			return "+%d unit → %s" % [count, target]
		"enhance_pct":
			var atk: float = eff.get("enhance_atk_pct", 0.0) * 100
			var hp: float = eff.get("enhance_hp_pct", 0.0) * 100
			var target: String = eff.get("target", "self")
			if hp > 0:
				return "ATK +%.0f%% HP +%.0f%% → %s" % [atk, hp, target]
			return "ATK +%.0f%% → %s" % [atk, target]
		"buff_pct":
			var atk: float = eff.get("buff_atk_pct", 0.0) * 100
			return "Combat ATK +%.0f%%" % atk
		"shield_pct":
			var hp: float = eff.get("shield_hp_pct", 0.0) * 100
			return "Shield %.0f%% HP" % hp
		"grant_gold":
			return "+%dg" % eff.get("gold_amount", 0)
		"grant_terazin":
			return "+%d terazin" % eff.get("terazin_amount", 0)
		"diversity_gold":
			return "Theme count × gold"
		"absorb_units":
			return "Absorb %d strongest units" % eff.get("absorb_count", 0)
		_:
			return action
