extends Node2D
## Battle phase: manages combat engine + visual rendering at 60fps.

signal battle_finished(result)

const CombatEngineScript = preload("res://combat/combat_engine.gd")

var _engine = null  # CombatEngine instance
var _visuals: Array = []
var _running: bool = false
var _tick_accumulator: float = 0.0
var _speed_mult: float = 1.0
var _battle_context: Dictionary = {}
var _last_status_details: Dictionary = {}

@onready var unit_container: Node2D = $UnitContainer
@onready var status_label: Label = $CanvasLayer/StatusLabel

const TICK_DELTA := 1.0 / 20.0


func start_battle(ally_data: Array, enemy_data: Array,
		context: Dictionary = {}) -> void:
	visible = true
	_dispose_engine()
	_battle_context = context.duplicate(true)
	if not _battle_context.has("round"):
		_battle_context["round"] = 0
	_battle_context["ally_start"] = ally_data.size()
	_battle_context["enemy_start"] = enemy_data.size()
	_engine = CombatEngineScript.new()
	_engine.setup(ally_data, enemy_data)
	_engine.combat_finished.connect(_on_combat_finished)
	_engine.unit_attacked.connect(_on_unit_attacked)

	_setup_visuals()
	_running = true
	_tick_accumulator = 0.0

	if status_label:
		status_label.visible = true
		_refresh_status_label()


func _setup_visuals() -> void:
	for child in unit_container.get_children():
		child.queue_free()
	_visuals.clear()

	for i in _engine.count:
		var vis: Node2D = preload("res://scenes/battle/unit_visual.tscn").instantiate()
		unit_container.add_child(vis)

		var is_ally: bool = _engine.team[i] == 1
		var color := Color(0.2, 0.7, 0.2) if is_ally else Color(0.8, 0.2, 0.2)
		vis.call("setup", i, color, 6.0)
		vis.global_position = _engine.pos[i]
		_visuals.append(vis)


func _process(delta: float) -> void:
	if not _running or _engine == null:
		return

	_tick_accumulator += delta * _speed_mult
	var ticks_to_run := 0
	while _tick_accumulator >= TICK_DELTA:
		_tick_accumulator -= TICK_DELTA
		ticks_to_run += 1

	for _t in ticks_to_run:
		if not _engine.tick():
			_running = false
			break

	# Render with lerp
	var alpha: float = _tick_accumulator / TICK_DELTA
	for i in _visuals.size():
		if i >= _engine.count:
			break
		var vis: Node2D = _visuals[i]
		var lerped: Vector2 = _engine.get_lerp_pos(i, alpha)
		vis.call("update_state", lerped, _engine.get_hp_ratio(i), _engine.is_unit_alive(i))

	if status_label:
		_refresh_status_label()


func _on_combat_finished(result: Dictionary) -> void:
	_running = false
	var outcome := "VICTORY!" if result["player_won"] else "DEFEAT"
	if status_label:
		status_label.text = "%s | R%d start %dA/%dE | Survived: %d ally, %d enemy" % [
			outcome,
			int(_battle_context.get("round", 0)),
			int(_battle_context.get("ally_start", 0)),
			int(_battle_context.get("enemy_start", 0)),
			result["ally_survived"],
			result["enemy_survived"]]
	await get_tree().create_timer(1.5).timeout
	battle_finished.emit(result)
	_dispose_engine()


func _on_unit_attacked(attacker_idx: int, _defender_idx: int) -> void:
	if attacker_idx >= 0 and attacker_idx < _visuals.size():
		_visuals[attacker_idx].call("flash")


func set_speed(mult: float) -> void:
	_speed_mult = mult


func get_engine():
	return _engine


func get_status_details() -> Dictionary:
	if not is_visible_in_tree() or status_label == null or not status_label.is_visible_in_tree():
		return {}
	var details := _last_status_details.duplicate(true)
	details["text"] = status_label.text
	details["visible"] = true
	return details


func stop() -> void:
	_running = false
	visible = false
	_last_status_details = {}
	if status_label:
		status_label.text = ""
		status_label.visible = false
	_dispose_engine()


func _exit_tree() -> void:
	_dispose_engine()


func _dispose_engine() -> void:
	if _engine == null:
		return
	if _engine.has_method("dispose"):
		_engine.dispose()
	_engine = null


func _refresh_status_label() -> void:
	if status_label == null:
		return
	var counts := _count_remaining_units()
	var round_num := int(_battle_context.get("round", 0))
	var ally_start := int(_battle_context.get("ally_start", 0))
	var enemy_start := int(_battle_context.get("enemy_start", 0))
	var ally_remaining := int(counts.get("ally", 0))
	var enemy_remaining := int(counts.get("enemy", 0))
	var tick: int = int(_engine.get_tick()) if _engine != null else 0
	status_label.text = "BATTLE R%d | Start %dA vs %dE | Now %dA vs %dE | Tick %d | %.0fx" % [
		round_num,
		ally_start,
		enemy_start,
		ally_remaining,
		enemy_remaining,
		tick,
		_speed_mult,
	]
	_last_status_details = {
		"round": round_num,
		"ally_start": ally_start,
		"enemy_start": enemy_start,
		"ally_remaining": ally_remaining,
		"enemy_remaining": enemy_remaining,
		"tick": tick,
		"speed": _speed_mult,
		"text": status_label.text,
		"visible": status_label.is_visible_in_tree(),
	}


func _count_remaining_units() -> Dictionary:
	var counts := {"ally": 0, "enemy": 0}
	if _engine == null:
		return counts
	for i in _engine.count:
		if _engine.alive[i] == 0:
			continue
		if _engine.team[i] == 1:
			counts["ally"] += 1
		else:
			counts["enemy"] += 1
	return counts
