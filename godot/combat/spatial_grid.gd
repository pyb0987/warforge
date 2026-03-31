class_name SpatialGrid
extends RefCounted
## 2D spatial hash grid for O(N) nearest-enemy queries.
## Cell size should be >= max attack range to guarantee correctness.

var _cell_size: float
var _cells: Dictionary = {}  # Vector2i -> Array[int] (unit indices)


func _init(cell_size: float = 128.0) -> void:
	_cell_size = cell_size


func clear() -> void:
	_cells.clear()


func insert(idx: int, pos: Vector2) -> void:
	var key := _to_cell(pos)
	if not _cells.has(key):
		_cells[key] = []
	_cells[key].append(idx)


func rebuild(positions: PackedVector2Array, alive_flags: PackedByteArray) -> void:
	_cells.clear()
	for i in positions.size():
		if alive_flags[i] == 1:
			insert(i, positions[i])


## Find nearest unit in opposing team within max_range.
## Returns index or -1 if none found.
func find_nearest(pos: Vector2, is_ally: bool, team_flags: PackedByteArray,
		alive_flags: PackedByteArray, positions: PackedVector2Array,
		max_range: float) -> int:
	var search_radius := ceili(max_range / _cell_size)
	var center_cell := _to_cell(pos)
	var best_idx := -1
	var best_dist_sq := max_range * max_range

	for dx in range(-search_radius, search_radius + 1):
		for dy in range(-search_radius, search_radius + 1):
			var key := Vector2i(center_cell.x + dx, center_cell.y + dy)
			if not _cells.has(key):
				continue
			for idx in _cells[key]:
				if alive_flags[idx] == 0:
					continue
				# team_flags: 1=ally, 0=enemy
				var is_same_team := (team_flags[idx] == 1) == is_ally
				if is_same_team:
					continue
				var dist_sq := pos.distance_squared_to(positions[idx])
				if dist_sq < best_dist_sq:
					best_dist_sq = dist_sq
					best_idx = idx

	return best_idx


func _to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / _cell_size), floori(pos.y / _cell_size))
