extends Node2D
## Battle phase: manages combat engine + visual rendering at 60fps.

signal battle_finished(result)

const CombatEngineScript = preload("res://combat/combat_engine.gd")

var _engine = null  # CombatEngine instance
var _visuals: Array = []
var _running: bool = false
var _tick_accumulator: float = 0.0
var _speed_mult: float = 1.0

@onready var unit_container: Node2D = $UnitContainer
@onready var status_label: Label = $CanvasLayer/StatusLabel

const TICK_DELTA := 1.0 / 20.0


func start_battle(ally_data: Array, enemy_data: Array) -> void:
	visible = true
	_engine = CombatEngineScript.new()
	_engine.setup(ally_data, enemy_data)
	_engine.combat_finished.connect(_on_combat_finished)
	_engine.unit_attacked.connect(_on_unit_attacked)

	_setup_visuals()
	_running = true
	_tick_accumulator = 0.0

	if status_label:
		status_label.text = "BATTLE!"


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
		var ally_n := 0
		var enemy_n := 0
		for i in _engine.count:
			if _engine.alive[i] == 0:
				continue
			if _engine.team[i] == 1:
				ally_n += 1
			else:
				enemy_n += 1
		status_label.text = "Tick %d | Ally: %d vs Enemy: %d | Speed: %.0fx" % [
			_engine.get_tick(), ally_n, enemy_n, _speed_mult]


func _on_combat_finished(result: Dictionary) -> void:
	_running = false
	var outcome := "VICTORY!" if result["player_won"] else "DEFEAT"
	if status_label:
		status_label.text = "%s | Survived: %d ally, %d enemy" % [
			outcome, result["ally_survived"], result["enemy_survived"]]
	await get_tree().create_timer(1.5).timeout
	battle_finished.emit(result)


func _on_unit_attacked(attacker_idx: int, _defender_idx: int) -> void:
	if attacker_idx >= 0 and attacker_idx < _visuals.size():
		_visuals[attacker_idx].call("flash")


func set_speed(mult: float) -> void:
	_speed_mult = mult


func get_engine():
	return _engine


func stop() -> void:
	_running = false
	visible = false
