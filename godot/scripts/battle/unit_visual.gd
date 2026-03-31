extends Node2D
## Renders a combat unit as a colored circle + HP bar.

var unit_idx: int = -1
var team_color: Color = Color.GREEN
var unit_radius: float = 6.0
var hp_ratio: float = 1.0
var is_alive: bool = true


func setup(idx: int, color: Color, radius: float) -> void:
	unit_idx = idx
	team_color = color
	unit_radius = radius
	hp_ratio = 1.0
	is_alive = true
	queue_redraw()


func update_state(pos: Vector2, hp_pct: float, alive: bool) -> void:
	global_position = pos
	hp_ratio = hp_pct
	is_alive = alive
	visible = alive
	if alive:
		queue_redraw()


func _draw() -> void:
	if not is_alive:
		return
	# Body circle
	draw_circle(Vector2.ZERO, unit_radius, team_color)
	# HP bar background
	var bar_w := unit_radius * 2.5
	var bar_h := 2.0
	var bar_y := -unit_radius - 4.0
	draw_rect(Rect2(-bar_w / 2.0, bar_y, bar_w, bar_h), Color(0.2, 0.2, 0.2))
	# HP bar foreground
	var hp_color := Color.GREEN if hp_ratio > 0.5 else (Color.YELLOW if hp_ratio > 0.25 else Color.RED)
	draw_rect(Rect2(-bar_w / 2.0, bar_y, bar_w * hp_ratio, bar_h), hp_color)
