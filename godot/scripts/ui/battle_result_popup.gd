extends ColorRect
## Brief battle result popup that auto-fades after 2 seconds.

@onready var result_label: Label = $VBox/ResultLabel
@onready var detail_label: Label = $VBox/DetailLabel


func _ready() -> void:
	visible = false


func show_result(won: bool, ally_survived: int, enemy_survived: int,
		gold_change: int, hp_change: int, card_effect_gold: int = 0) -> void:
	var card_gold_line := "\n+%dg card effects" % card_effect_gold if card_effect_gold > 0 else ""
	if won:
		result_label.text = "VICTORY"
		result_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3))
		detail_label.text = "Survived: %d allies\n+%dg bonus%s" % [ally_survived, gold_change, card_gold_line]
	else:
		result_label.text = "DEFEAT"
		result_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
		detail_label.text = "%d enemies survived\n-%d HP%s" % [enemy_survived, absi(hp_change), card_gold_line]

	visible = true
	modulate.a = 1.0

	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func(): visible = false)
