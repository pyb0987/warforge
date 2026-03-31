class_name FlowField
extends RefCounted
## Simple flow field for melee unit movement.
## Computes direction toward enemy centroid per cell.

var _cell_size: float
var _field: Dictionary = {}  # Vector2i -> Vector2 (direction)
var _target: Vector2 = Vector2.ZERO


func _init(cell_size: float = 64.0) -> void:
	_cell_size = cell_size


## Recompute flow toward target position (enemy centroid).
func compute(target_pos: Vector2) -> void:
	_target = target_pos
	_field.clear()
	# Simple: direction = normalize(target - cell_center)
	# No obstacles in Phase 1, so just direct paths.


## Get movement direction for a position.
func get_direction(pos: Vector2) -> Vector2:
	var key := Vector2i(floori(pos.x / _cell_size), floori(pos.y / _cell_size))
	if _field.has(key):
		return _field[key]
	# Fallback: direct to target
	var diff := _target - pos
	return diff.normalized() if diff.length_squared() > 1.0 else Vector2.ZERO
