class_name CombatEngine
extends RefCounted
## Tick-based 2D combat engine. 20fps logic, data-oriented.
## Units: arrays of structs (SoA pattern for cache efficiency).

signal combat_finished(result: Dictionary)
signal unit_died(idx: int)

const TICK_RATE := 20.0
const TICK_DELTA := 1.0 / TICK_RATE
const MAX_TICKS := 1200  # 60 seconds max
const BATTLEFIELD_W := 1000.0
const BATTLEFIELD_H := 500.0
const SEPARATION_DIST := 14.0

# --- Unit data arrays (SoA) ---
var count: int = 0
var pos: PackedVector2Array
var prev_pos: PackedVector2Array  # for lerp rendering
var hp: PackedFloat32Array
var max_hp: PackedFloat32Array
var atk: PackedFloat32Array
var attack_speed: PackedFloat32Array  # seconds between attacks
var attack_range: PackedFloat32Array  # pixels
var move_speed: PackedFloat32Array    # pixels per tick
var cooldown: PackedFloat32Array      # ticks until next attack
var radius: PackedFloat32Array        # collision radius (pixels)
var defense: PackedFloat32Array        # DEF stat (damage reduction)
var team: PackedByteArray             # 1=ally, 0=enemy
var alive: PackedByteArray            # 1=alive, 0=dead
var target_idx: PackedInt32Array      # current target (-1=none)
var mechanics: Array = []             # Array of Array[Dictionary] per unit

# --- Per-unit mechanic state ---
var focus_target: PackedInt32Array      # last attack target for focus_fire
var focus_stacks: PackedInt32Array      # focus_fire stack count
var phase_shift_left: PackedByteArray   # remaining phase_shift uses
var immortal_left: PackedByteArray      # remaining immortal_core uses
var soul_kills: PackedInt32Array        # soul_harvest kill count
var soul_atk_bonus: PackedFloat32Array  # soul_harvest accumulated ATK%
var berserk_active: PackedByteArray     # berserk triggered
var retreat_active: PackedByteArray     # tactical_retreat in progress
var retreat_timer: PackedFloat32Array   # retreat invuln ticks remaining
var invuln: PackedByteArray             # currently invulnerable
var regen_timer: PackedFloat32Array     # ticks until next regen
var is_clone: PackedByteArray           # fission clones cannot re-fission
var slow_factor: PackedFloat32Array     # slow_aura applied MS multiplier

# --- Fission pre-allocation ---
var _fission_slots: Dictionary = {}     # original_idx → [clone_idx1, clone_idx2]
var _base_count: int = 0               # units before fission slots

# --- Systems ---
const _SpatialGridScript = preload("res://combat/spatial_grid.gd")
const _FlowFieldScript = preload("res://combat/flow_field.gd")
const _MechanicsScript = preload("res://combat/mechanics_handler.gd")
var _grid = null
var _flow_ally = null
var _flow_enemy = null
var _mech = null  # MechanicsHandler
var _tick: int = 0
var _running: bool = false

# --- Pixel scale ---
const RANGE_SCALE := 32.0   # 1 range unit = 32px
const SPEED_SCALE := 16.0   # 1 move_speed = 16px/tick (at 20fps = 320px/sec)


func setup(ally_units: Array, enemy_units: Array) -> void:
	## ally_units/enemy_units: Array of {atk, hp, attack_speed, range, move_speed, def, mechanics}
	_base_count = ally_units.size() + enemy_units.size()

	# Count fission-capable units for pre-allocation
	var fission_extra := 0
	for u in ally_units:
		for m in u.get("mechanics", []):
			if m.get("type", "") == "fission":
				fission_extra += m.get("clone_count", 2)
				break
	for u in enemy_units:
		for m in u.get("mechanics", []):
			if m.get("type", "") == "fission":
				fission_extra += m.get("clone_count", 2)
				break

	count = _base_count + fission_extra
	_init_arrays(count)
	_fission_slots.clear()
	_grid = _SpatialGridScript.new(64.0)
	_flow_ally = _FlowFieldScript.new()
	_flow_enemy = _FlowFieldScript.new()
	_mech = _MechanicsScript.new(self)
	_tick = 0
	_running = false

	# Place real units
	var idx := 0
	for u in ally_units:
		_set_unit(idx, u, true)
		idx += 1
	for u in enemy_units:
		_set_unit(idx, u, false)
		idx += 1

	# Pre-allocate fission clone slots (start dead)
	var clone_idx := _base_count
	for i in _base_count:
		if _has_mechanic(i, "fission") and is_clone[i] == 0:
			var m := _get_mechanic(i, "fission")
			var cc: int = m.get("clone_count", 2)
			var slots: Array[int] = []
			for _n in cc:
				alive[clone_idx] = 0
				is_clone[clone_idx] = 1
				team[clone_idx] = team[i]
				mechanics[clone_idx] = []
				slots.append(clone_idx)
				clone_idx += 1
			_fission_slots[i] = slots

	_place_units()
	_mech.apply_combat_start()


func _init_arrays(n: int) -> void:
	pos = PackedVector2Array()
	pos.resize(n)
	prev_pos = PackedVector2Array()
	prev_pos.resize(n)
	hp = PackedFloat32Array()
	hp.resize(n)
	max_hp = PackedFloat32Array()
	max_hp.resize(n)
	atk = PackedFloat32Array()
	atk.resize(n)
	attack_speed = PackedFloat32Array()
	attack_speed.resize(n)
	attack_range = PackedFloat32Array()
	attack_range.resize(n)
	move_speed = PackedFloat32Array()
	move_speed.resize(n)
	cooldown = PackedFloat32Array()
	cooldown.resize(n)
	radius = PackedFloat32Array()
	radius.resize(n)
	defense = PackedFloat32Array()
	defense.resize(n)
	team = PackedByteArray()
	team.resize(n)
	alive = PackedByteArray()
	alive.resize(n)
	target_idx = PackedInt32Array()
	target_idx.resize(n)
	mechanics = []
	mechanics.resize(n)
	focus_target = PackedInt32Array()
	focus_target.resize(n)
	focus_stacks = PackedInt32Array()
	focus_stacks.resize(n)
	phase_shift_left = PackedByteArray()
	phase_shift_left.resize(n)
	immortal_left = PackedByteArray()
	immortal_left.resize(n)
	soul_kills = PackedInt32Array()
	soul_kills.resize(n)
	soul_atk_bonus = PackedFloat32Array()
	soul_atk_bonus.resize(n)
	berserk_active = PackedByteArray()
	berserk_active.resize(n)
	retreat_active = PackedByteArray()
	retreat_active.resize(n)
	retreat_timer = PackedFloat32Array()
	retreat_timer.resize(n)
	invuln = PackedByteArray()
	invuln.resize(n)
	regen_timer = PackedFloat32Array()
	regen_timer.resize(n)
	is_clone = PackedByteArray()
	is_clone.resize(n)
	slow_factor = PackedFloat32Array()
	slow_factor.resize(n)


func _set_unit(idx: int, data: Dictionary, is_ally: bool) -> void:
	hp[idx] = data["hp"]
	max_hp[idx] = data["hp"]
	atk[idx] = data["atk"]
	attack_speed[idx] = data["attack_speed"] * TICK_RATE  # convert seconds to ticks
	attack_range[idx] = data["range"] * RANGE_SCALE
	if attack_range[idx] < SEPARATION_DIST:
		attack_range[idx] = SEPARATION_DIST  # melee minimum
	move_speed[idx] = data["move_speed"] * SPEED_SCALE
	radius[idx] = data.get("radius", 6.0)  # collision radius in pixels
	defense[idx] = float(data.get("def", 0))
	cooldown[idx] = 0.0
	team[idx] = 1 if is_ally else 0
	alive[idx] = 1
	target_idx[idx] = -1
	mechanics[idx] = data.get("mechanics", [])
	focus_target[idx] = -1
	focus_stacks[idx] = 0
	phase_shift_left[idx] = 1 if _has_mechanic_in(data.get("mechanics", []), "phase_shift") else 0
	immortal_left[idx] = 1 if _has_mechanic_in(data.get("mechanics", []), "immortal_core") else 0
	soul_kills[idx] = 0
	soul_atk_bonus[idx] = 0.0
	berserk_active[idx] = 0
	retreat_active[idx] = 0
	retreat_timer[idx] = 0.0
	invuln[idx] = 0
	regen_timer[idx] = 0.0
	is_clone[idx] = 0
	slow_factor[idx] = 1.0


func _place_units() -> void:
	var ally_count := 0
	var enemy_count := 0
	for i in count:
		if team[i] == 1:
			ally_count += 1
		else:
			enemy_count += 1

	# Place allies on left third, enemies on right third
	var ai := 0
	var ei := 0
	for i in count:
		if team[i] == 1:
			var row := ai / 10
			var col := ai % 10
			pos[i] = Vector2(80.0 + col * 20.0, 80.0 + row * 20.0)
			ai += 1
		else:
			var row := ei / 10
			var col := ei % 10
			pos[i] = Vector2(BATTLEFIELD_W - 80.0 - col * 20.0, 80.0 + row * 20.0)
			ei += 1
		prev_pos[i] = pos[i]


## Run one combat tick. Returns true if combat is still ongoing.
func tick() -> bool:
	if _tick >= MAX_TICKS:
		_finish(false)  # timeout = player loss
		return false

	_tick += 1

	# Save positions for lerp
	for i in count:
		prev_pos[i] = pos[i]

	# Rebuild spatial grid
	_grid.rebuild(pos, alive)

	# Update flow fields
	_flow_ally.compute(_get_centroid(false))   # allies move toward enemy centroid
	_flow_enemy.compute(_get_centroid(true))   # enemies move toward ally centroid

	# Apply slow auras and per-tick mechanics
	_mech.apply_per_tick()

	# Per-unit update
	for i in count:
		if alive[i] == 0:
			continue
		_update_unit(i)

	# Collision separation (push overlapping units apart)
	_resolve_collisions()

	# Check win condition
	var allies_alive := false
	var enemies_alive := false
	for i in count:
		if alive[i] == 0:
			continue
		if team[i] == 1:
			allies_alive = true
		else:
			enemies_alive = true
		if allies_alive and enemies_alive:
			break

	if not enemies_alive:
		_finish(true)
		return false
	if not allies_alive:
		_finish(false)
		return false

	return true


func _update_unit(i: int) -> void:
	var is_ally := team[i] == 1
	var eff_ms: float = move_speed[i] * slow_factor[i]

	# Tactical retreat: move away from enemies, skip attacking
	if retreat_active[i] == 1:
		var flow = _flow_enemy if is_ally else _flow_ally  # retreat = away from enemies
		var dir: Vector2 = -flow.get_direction(pos[i])  # reverse direction
		pos[i] += dir * eff_ms * 2.0  # double speed
		pos[i] = pos[i].clamp(Vector2.ZERO, Vector2(BATTLEFIELD_W, BATTLEFIELD_H))
		return

	# Find target
	var max_search := maxf(attack_range[i], RANGE_SCALE * 4.0)
	target_idx[i] = _grid.find_nearest(pos[i], is_ally, team, alive, pos, max_search)

	if target_idx[i] < 0:
		var flow = _flow_ally if is_ally else _flow_enemy
		var dir: Vector2 = flow.get_direction(pos[i])
		pos[i] += dir * eff_ms
		pos[i] = pos[i].clamp(Vector2.ZERO, Vector2(BATTLEFIELD_W, BATTLEFIELD_H))
		return

	var t := target_idx[i]
	var dist := pos[i].distance_to(pos[t])

	if dist <= attack_range[i]:
		cooldown[i] -= 1.0
		if cooldown[i] <= 0.0:
			_do_attack(i, t)
			cooldown[i] = attack_speed[i]
	else:
		var dir := (pos[t] - pos[i]).normalized()
		var step := minf(eff_ms, dist - attack_range[i] + 2.0)
		pos[i] += dir * step
		pos[i] = pos[i].clamp(Vector2.ZERO, Vector2(BATTLEFIELD_W, BATTLEFIELD_H))


func _resolve_collisions() -> void:
	## Push overlapping units apart using spatial grid neighbors.
	## Only checks same-cell and adjacent-cell pairs. O(N) average.
	var checked := {}  # avoid duplicate pair checks
	for i in count:
		if alive[i] == 0:
			continue
		var cell := Vector2i(floori(pos[i].x / 64.0), floori(pos[i].y / 64.0))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var key := Vector2i(cell.x + dx, cell.y + dy)
				if not _grid._cells.has(key):
					continue
				for j in _grid._cells[key]:
					if j <= i or alive[j] == 0:
						continue
					var min_dist := radius[i] + radius[j]
					var diff := pos[i] - pos[j]
					var dist_sq := diff.length_squared()
					if dist_sq < min_dist * min_dist and dist_sq > 0.01:
						var dist := sqrt(dist_sq)
						var overlap := min_dist - dist
						var push := diff / dist * (overlap * 0.5)
						pos[i] += push
						pos[j] -= push
					elif dist_sq <= 0.01:
						# Exactly overlapping: push in random direction
						var nudge := Vector2(0.5 - randf(), 0.5 - randf()).normalized()
						pos[i] += nudge * min_dist * 0.5
						pos[j] -= nudge * min_dist * 0.5
	# Clamp all to battlefield
	for i in count:
		if alive[i] == 1:
			pos[i] = pos[i].clamp(Vector2.ZERO, Vector2(BATTLEFIELD_W, BATTLEFIELD_H))


func _do_attack(attacker: int, defender: int) -> void:
	_mech.resolve_attack(attacker, defender)


func _get_centroid(ally_side: bool) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for i in count:
		if alive[i] == 0:
			continue
		if (team[i] == 1) == ally_side:
			sum += pos[i]
			n += 1
	return sum / maxf(n, 1.0)


func _finish(player_won: bool) -> void:
	_running = false
	var ally_survived := 0
	var enemy_survived := 0
	for i in count:
		if alive[i] == 0:
			continue
		if team[i] == 1:
			ally_survived += 1
		else:
			enemy_survived += 1
	combat_finished.emit({
		"player_won": player_won,
		"ally_survived": ally_survived,
		"enemy_survived": enemy_survived,
		"ticks": _tick,
	})


## Get lerp alpha for rendering between ticks.
func get_lerp_pos(i: int, alpha: float) -> Vector2:
	return prev_pos[i].lerp(pos[i], alpha)


func get_tick() -> int:
	return _tick


func is_unit_alive(i: int) -> bool:
	return alive[i] == 1


func is_ally(i: int) -> bool:
	return team[i] == 1


func get_hp_ratio(i: int) -> float:
	return hp[i] / max_hp[i] if max_hp[i] > 0 else 0.0


## Kill a unit (shared logic for attacks, AOE, fission source).
func kill_unit(i: int) -> void:
	if alive[i] == 0:
		return
	alive[i] = 0
	unit_died.emit(i)
	# Fission: spawn clones on death
	if is_clone[i] == 0 and _fission_slots.has(i):
		_mech.trigger_fission(i)


## Check if unit has a specific mechanic type.
func _has_mechanic(i: int, mtype: String) -> bool:
	for m in mechanics[i]:
		if m.get("type", "") == mtype:
			return true
	return false


## Get mechanic dict for a unit, or {} if not found.
func _get_mechanic(i: int, mtype: String) -> Dictionary:
	for m in mechanics[i]:
		if m.get("type", "") == mtype:
			return m
	return {}


## Static helper: check mechanic in a raw array (used during _set_unit).
static func _has_mechanic_in(mechs: Array, mtype: String) -> bool:
	for m in mechs:
		if m.get("type", "") == mtype:
			return true
	return false
