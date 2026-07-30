extends ColorRect
## Game Over / Victory overlay with result summary and restart button.

@onready var title_label: Label = $VBox/TitleLabel
@onready var summary_label: Label = $VBox/SummaryLabel
@onready var restart_button: Button = $VBox/RestartButton

signal restart_requested


func _ready() -> void:
	visible = false
	restart_button.pressed.connect(func(): restart_requested.emit())


func show_result(won: bool, round_num: int, hp: int,
		unlocks: Array = [], context: Dictionary = {}) -> void:
	var lines: PackedStringArray = []
	if won:
		title_label.text = "VICTORY!"
		title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		lines.append("All 15 rounds cleared!")
		lines.append("HP remaining: %d" % hp)
	else:
		title_label.text = "GAME OVER"
		title_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
		lines.append("Defeated at round %d" % round_num)
		lines.append("Final HP: %d" % hp)
		for line in _format_final_battle_lines(
				context.get("final_battle", {})):
			lines.append(line)
	var progress_line := _format_run_progress_line(context)
	if progress_line != "":
		lines.append("")
		lines.append(progress_line)
	var next_run_hint := _format_next_run_hint(won, round_num, context)
	if next_run_hint != "":
		lines.append(next_run_hint)
	var unlock_text := MetaProgress.format_unlock_recap_text(
		"New unlocks available", unlocks)
	if unlock_text != "":
		lines.append("")
		lines.append(unlock_text)
	summary_label.text = "\n".join(lines)
	visible = true


func _format_final_battle_lines(final_battle_value) -> PackedStringArray:
	var lines := PackedStringArray()
	var final_battle: Dictionary = \
		final_battle_value if final_battle_value is Dictionary else {}
	if final_battle.is_empty():
		return lines
	if final_battle.has("ally_survived") and final_battle.has("enemy_survived"):
		lines.append("Last fight: %d allies / %d enemies survived" % [
			int(final_battle.get("ally_survived", 0)),
			int(final_battle.get("enemy_survived", 0)),
		])
	if final_battle.has("damage") \
			and final_battle.has("hp_before") \
			and final_battle.has("hp_after"):
		lines.append("Damage: %d HP (%d -> %d)" % [
			int(final_battle.get("damage", 0)),
			int(final_battle.get("hp_before", 0)),
			int(final_battle.get("hp_after", 0)),
		])
	return lines


func _format_run_progress_line(context: Dictionary) -> String:
	var stats_value = context.get("run_stats", {})
	var stats: Dictionary = stats_value if stats_value is Dictionary else {}
	var parts := PackedStringArray()
	var max_units := int(stats.get("max_field_units", 0))
	if max_units > 0:
		parts.append("%d field units" % max_units)
	var upgrades := int(stats.get("max_attached_upgrades", 0))
	if upgrades > 0:
		parts.append("%d upgrades" % upgrades)
	var streak := int(stats.get("best_win_streak", 0))
	if streak > 0:
		parts.append("%d-win streak" % streak)
	var boss_rewards := int(context.get("boss_rewards", 0))
	if boss_rewards > 0:
		parts.append("%d boss %s" % [
			boss_rewards,
			"reward" if boss_rewards == 1 else "rewards",
		])
	if parts.is_empty():
		return ""
	return "Run bests: %s" % ", ".join(parts)


func _format_next_run_hint(won: bool, round_num: int,
		context: Dictionary) -> String:
	if won:
		return ""
	var final_battle_value = context.get("final_battle", {})
	var final_battle: Dictionary = \
		final_battle_value if final_battle_value is Dictionary else {}
	var milestone := _format_pressure_milestone(round_num)
	var enemy_survived := int(final_battle.get("enemy_survived", -1))
	if enemy_survived > 0:
		return "Next run: last fight left %d enemies; add damage or growth before %s." % [
			enemy_survived,
			milestone,
		]
	var stats_value = context.get("run_stats", {})
	var stats: Dictionary = stats_value if stats_value is Dictionary else {}
	var upgrades := int(stats.get("max_attached_upgrades", 0))
	if upgrades <= 0:
		return "Next run: attach upgrades before %s." % milestone
	return "Next run: reach %s with stronger upgraded units." % milestone


func _format_pressure_milestone(round_num: int) -> String:
	if round_num <= 4:
		return "the R4 boss"
	if round_num <= 8:
		return "the R8 boss"
	if round_num <= 12:
		return "the R12 boss"
	return "the final boss"
