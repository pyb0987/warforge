extends ColorRect
## Game Over / Victory overlay with result summary and restart button.

@onready var title_label: Label = $VBox/TitleLabel
@onready var summary_label: Label = $VBox/SummaryLabel
@onready var restart_button: Button = $VBox/RestartButton

signal restart_requested


func _ready() -> void:
	visible = false
	restart_button.pressed.connect(func(): restart_requested.emit())


func show_result(won: bool, round_num: int, hp: int) -> void:
	if won:
		title_label.text = "VICTORY!"
		title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		summary_label.text = "All 15 rounds cleared!\nHP remaining: %d" % hp
	else:
		title_label.text = "GAME OVER"
		title_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
		summary_label.text = "Defeated at round %d" % round_num
	visible = true
