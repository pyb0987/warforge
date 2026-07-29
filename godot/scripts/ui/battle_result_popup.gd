extends ColorRect
## Brief battle result popup that auto-fades after 2 seconds.

@onready var result_label: Label = $VBox/ResultLabel
@onready var detail_label: Label = $VBox/DetailLabel

var _last_context: Dictionary = {}
var _last_result_text := ""
var _last_detail_text := ""
var _last_summary_text := ""


func _ready() -> void:
	visible = false


func show_result(won: bool, ally_survived: int, enemy_survived: int,
		gold_change: int, hp_change: int, card_effect_gold: int = 0,
		context: Dictionary = {}) -> void:
	_last_context = context.duplicate(true)
	if won:
		_last_result_text = "VICTORY"
		result_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3))
	else:
		_last_result_text = "DEFEAT"
		result_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
	result_label.text = _last_result_text
	_last_detail_text = _format_detail(
		won, ally_survived, enemy_survived, gold_change, hp_change,
		card_effect_gold, context)
	_last_summary_text = _format_summary(context)
	detail_label.text = _last_detail_text

	visible = true
	modulate.a = 1.0

	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func(): visible = false)


func get_result_text() -> String:
	return _last_result_text


func get_detail_text() -> String:
	return _last_detail_text


func get_summary_text() -> String:
	return _last_summary_text


func get_context() -> Dictionary:
	return _last_context.duplicate(true)


func _format_detail(won: bool, ally_survived: int, enemy_survived: int,
		gold_change: int, hp_change: int, card_effect_gold: int,
		context: Dictionary) -> String:
	if context.is_empty():
		var card_gold_line := "\n+%dg card effects" % card_effect_gold \
			if card_effect_gold > 0 else ""
		if won:
			return "Survived: %d allies\n+%dg bonus%s" % [
				ally_survived, gold_change, card_gold_line]
		return "%d enemies survived\n-%d HP%s" % [
			enemy_survived, absi(hp_change), card_gold_line]

	var round_num: int = int(context.get("round", 0))
	var ally_start: int = int(context.get("ally_start", ally_survived))
	var enemy_start: int = int(context.get("enemy_start", enemy_survived))
	var hp_before: int = int(context.get("hp_before", 0))
	var hp_after: int = int(context.get("hp_after", hp_before + hp_change))
	var gold_before: int = int(context.get("gold_before", 0))
	var gold_after: int = int(context.get(
		"gold_after", gold_before + gold_change + card_effect_gold))
	var damage: int = int(context.get("damage", absi(hp_change)))
	var lines: Array[String] = []
	lines.append("Round %d %s" % [round_num, "cleared" if won else "lost"])
	if won:
		lines.append("Allies: %d/%d survived; enemies cleared" % [
			ally_survived, maxi(ally_start, ally_survived)])
	else:
		lines.append("Enemies: %d/%d survived; damage %d" % [
			enemy_survived, maxi(enemy_start, enemy_survived), damage])
	lines.append("HP: %d -> %d (%s%d)" % [
		hp_before, hp_after, "+" if hp_after >= hp_before else "-", absi(hp_after - hp_before)])
	lines.append("Gold: %d -> %d (+%d win, +%d cards)" % [
		gold_before, gold_after, gold_change, card_effect_gold])
	lines.append(_format_summary(context))
	return "\n".join(lines)


func _format_summary(context: Dictionary) -> String:
	var next_hint := str(context.get("next_hint", "")).strip_edges()
	if next_hint == "":
		next_hint = "Return to BUILD"
	return "Next: %s" % next_hint
