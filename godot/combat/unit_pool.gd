class_name UnitPool
extends Node
## Object pool for combat unit visuals. Pre-allocates Node2D instances.

var _pool: Array[Node2D] = []
var _active_count: int = 0
var _visual_scene: PackedScene


func setup(max_units: int, parent: Node) -> void:
	_visual_scene = preload("res://scenes/battle/unit_visual.tscn")
	for i in max_units:
		var vis: Node2D = _visual_scene.instantiate()
		vis.visible = false
		parent.add_child(vis)
		_pool.append(vis)
	_active_count = 0


func acquire() -> Node2D:
	if _active_count >= _pool.size():
		push_warning("UnitPool exhausted (%d)" % _pool.size())
		return null
	var vis := _pool[_active_count]
	vis.visible = true
	_active_count += 1
	return vis


func release_all() -> void:
	for i in _active_count:
		_pool[i].visible = false
	_active_count = 0


func get_active_count() -> int:
	return _active_count
