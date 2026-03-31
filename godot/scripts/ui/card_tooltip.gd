extends PanelContainer
## Card detail tooltip shown on hover.

@onready var name_label: Label = $VBox/NameLabel
@onready var info_label: Label = $VBox/InfoLabel
@onready var effect_label: Label = $VBox/EffectLabel
@onready var units_label: Label = $VBox/UnitsLabel

var _timing_names := {
	Enums.TriggerTiming.ROUND_START: "Round Start",
	Enums.TriggerTiming.ON_EVENT: "On Event",
	Enums.TriggerTiming.BATTLE_START: "Battle Start",
	Enums.TriggerTiming.POST_COMBAT: "Post Combat",
	Enums.TriggerTiming.POST_COMBAT_DEFEAT: "On Defeat",
	Enums.TriggerTiming.POST_COMBAT_VICTORY: "On Victory",
	Enums.TriggerTiming.ON_REROLL: "On Reroll",
	Enums.TriggerTiming.ON_MERGE: "On Merge",
	Enums.TriggerTiming.ON_SELL: "On Sell",
	Enums.TriggerTiming.PERSISTENT: "Passive",
}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_card(card: CardInstance, at_pos: Vector2) -> void:
	if card == null:
		visible = false
		return

	var tmpl := card.template
	name_label.text = "%s  T%d ★%d" % [tmpl.get("name", "???"), tmpl.get("tier", 0), card.star_level]

	# Trigger info
	var timing: int = tmpl.get("trigger_timing", -1)
	var timing_text: String = _timing_names.get(timing, "???")
	var max_act: int = tmpl.get("max_activations", -1)
	var act_text := " (max %d/R)" % max_act if max_act > 0 else ""
	info_label.text = "Trigger: %s%s" % [timing_text, act_text]

	# Effect summary
	var effects: Array = tmpl.get("effects", [])
	if effects.is_empty():
		effect_label.text = "(Theme system effect)"
	else:
		var lines: PackedStringArray = []
		for eff in effects:
			lines.append(_describe_effect(eff))
		effect_label.text = "\n".join(lines)

	# Unit composition
	var unit_lines: PackedStringArray = []
	for s in card.stacks:
		var ut: Dictionary = s["unit_type"]
		unit_lines.append("%s ×%d (A%.0f H%.0f)" % [
			ut.get("name", "?"), s["count"],
			card.eff_atk_for(s), card.eff_hp_for(s)])
	units_label.text = "\n".join(unit_lines)

	# Position
	global_position = at_pos + Vector2(10, 10)
	# Keep on screen
	var vp_size := get_viewport_rect().size
	if global_position.x + size.x > vp_size.x:
		global_position.x = at_pos.x - size.x - 10
	if global_position.y + size.y > vp_size.y:
		global_position.y = vp_size.y - size.y - 10

	visible = true


func hide_tooltip() -> void:
	visible = false


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
