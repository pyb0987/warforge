class_name SpatialGrid
extends RefCounted
## 2D flat-array spatial grid for O(N) nearest-enemy queries.
## Battlefield 1000×500, cell_size 64 → 16×8 = 128 cells max.
## Uses flat Array instead of Dictionary for zero-hash lookups.
## Cell contents are Array (reference type) — avoids PackedInt32Array copy-on-write issue.

var _cell_size: float
var _cols: int
var _rows: int
var _cells: Array = []  # flat array of Array[int], indexed by row * _cols + col


func _init(cell_size: float = 64.0) -> void:
	_cell_size = cell_size
	# Sized for battlefield 1000×500 with margin
	_cols = ceili(1100.0 / cell_size)  # 18 cols
	_rows = ceili(600.0 / cell_size)   # 10 rows
	_cells.resize(_cols * _rows)
	for i in _cells.size():
		_cells[i] = []


func rebuild(positions: PackedVector2Array, alive_flags: PackedByteArray) -> void:
	# Clear all cells (Array.clear() on reference type — no reallocation)
	for i in _cells.size():
		_cells[i].clear()
	# Insert alive units
	for i in positions.size():
		if alive_flags[i] == 1:
			var ci: int = _cell_index(positions[i])
			if ci >= 0:
				_cells[ci].append(i)


## Find nearest unit in opposing team within max_range.
## Returns index or -1 if none found.
func find_nearest(pos: Vector2, is_ally: bool, team_flags: PackedByteArray,
		alive_flags: PackedByteArray, positions: PackedVector2Array,
		max_range: float) -> int:
	var search_radius := ceili(max_range / _cell_size)
	var cx := floori(pos.x / _cell_size)
	var cy := floori(pos.y / _cell_size)
	var best_idx := -1
	var best_dist_sq := max_range * max_range

	var dx_min := maxi(cx - search_radius, 0)
	var dx_max := mini(cx + search_radius, _cols - 1)
	var dy_min := maxi(cy - search_radius, 0)
	var dy_max := mini(cy + search_radius, _rows - 1)

	for gx in range(dx_min, dx_max + 1):
		for gy in range(dy_min, dy_max + 1):
			var cell: Array = _cells[gy * _cols + gx]
			for idx in cell:
				if alive_flags[idx] == 0:
					continue
				var is_same_team := (team_flags[idx] == 1) == is_ally
				if is_same_team:
					continue
				var dist_sq := pos.distance_squared_to(positions[idx])
				if dist_sq < best_dist_sq:
					best_dist_sq = dist_sq
					best_idx = idx

	return best_idx


## Find all units of opposing team within radius of a center point.
## Used for splash/AOE damage — replaces O(N) full scan with grid-local query.
func find_in_radius(center: Vector2, radius: float, attacker_team: int,
		team_flags: PackedByteArray, alive_flags: PackedByteArray,
		positions: PackedVector2Array, exclude_idx: int = -1) -> PackedInt32Array:
	var result: PackedInt32Array = []
	var search_cells := ceili(radius / _cell_size)
	var cx := floori(center.x / _cell_size)
	var cy := floori(center.y / _cell_size)
	var radius_sq := radius * radius

	var dx_min := maxi(cx - search_cells, 0)
	var dx_max := mini(cx + search_cells, _cols - 1)
	var dy_min := maxi(cy - search_cells, 0)
	var dy_max := mini(cy + search_cells, _rows - 1)

	for gx in range(dx_min, dx_max + 1):
		for gy in range(dy_min, dy_max + 1):
			var cell: Array = _cells[gy * _cols + gx]
			for idx in cell:
				if idx == exclude_idx or alive_flags[idx] == 0:
					continue
				if team_flags[idx] == attacker_team:
					continue
				if center.distance_squared_to(positions[idx]) <= radius_sq:
					result.append(idx)
	return result


## Convert position to flat cell index. Returns -1 if out of bounds.
func _cell_index(pos: Vector2) -> int:
	var cx := floori(pos.x / _cell_size)
	var cy := floori(pos.y / _cell_size)
	if cx < 0 or cx >= _cols or cy < 0 or cy >= _rows:
		return -1
	return cy * _cols + cx
