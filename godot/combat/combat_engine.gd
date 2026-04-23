class_name CombatEngine
extends RefCounted
## Tick-based 2D combat engine. 20fps logic, data-oriented.
## Units: arrays of structs (SoA pattern for cache efficiency).

signal combat_finished(result: Dictionary)
signal unit_died(idx: int)
signal unit_attacked(attacker_idx: int, defender_idx: int)

const TICK_RATE := 20.0
const TICK_DELTA := 1.0 / TICK_RATE
const MAX_TICKS := 1200  # 60 seconds max
## Spatial grid cell size. 2026-04-19: 실험 결과 32는 target 탐색 cell 수 ×3 → 역효과. 64 유지.
const CELL_SIZE := 64.0
## Collision 빈도 (tick interval). 2026-04-19: 3 → 5 (headless에서 속도 우선, 1.67배 절감).
const COLLISION_INTERVAL := 5
const BATTLEFIELD_W := 1000.0
const BATTLEFIELD_H := 500.0
const SEPARATION_DIST := 14.0
const NEAR_SEARCH_RANGE := 320.0  # 5-cell radius first pass for find_nearest

# --- Performance flags ---
var headless: bool = false  # skip rendering-only work (prev_pos, etc.)

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
var revive_left: PackedByteArray        # 군대 통합사령부 revive 잔여 횟수 (유닛 단위)
var revive_hp_pct: PackedFloat32Array   # 부활 시 HP 복원 비율 (max_hp × pct)
var soul_kills: PackedInt32Array        # soul_harvest kill count
var soul_atk_bonus: PackedFloat32Array  # soul_harvest accumulated ATK%
var berserk_active: PackedByteArray     # berserk triggered
var retreat_active: PackedByteArray     # tactical_retreat in progress
var retreat_timer: PackedFloat32Array   # retreat invuln ticks remaining
var invuln: PackedByteArray             # currently invulnerable
var regen_timer: PackedFloat32Array     # ticks until next regen
var is_clone: PackedByteArray           # fission clones cannot re-fission
var slow_factor: PackedFloat32Array     # slow_aura applied MS multiplier
var undying: PackedByteArray            # 💀 금간 해골: 1=첫 치사 HP1 생존 가능

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

# --- Mechanic pre-computed cache ---
var _mech_cache: Array = []  # Array of Dictionary per unit: {type_str: mechanic_dict}
var _has_any_slow_aura: bool = false
var _has_any_regen: bool = false

# --- Alive tracking (avoid full-scan win condition check) ---
var _ally_alive: int = 0
var _enemy_alive: int = 0

# --- Cached flow fields ---
var _cached_flow_ally_dir: Vector2 = Vector2.ZERO
var _cached_flow_enemy_dir: Vector2 = Vector2.ZERO

# --- Alive index list (rebuilt once per tick for efficient iteration) ---
var _alive_list: PackedInt32Array = []
var _interleaved_order: PackedInt32Array = []  # team-interleaved iteration order (fair first-strike)
var _pos_snapshot: PackedVector2Array  # pre-phase-1 pos cache for symmetric movement

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
	_grid = _SpatialGridScript.new(CELL_SIZE)
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
	_build_mech_cache()
	_count_alive()
	_rebuild_alive_list()
	_grid.rebuild(pos, alive)  # initial grid for direct resolve_attack calls (tests)
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
	revive_left = PackedByteArray()
	revive_left.resize(n)
	revive_hp_pct = PackedFloat32Array()
	revive_hp_pct.resize(n)
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
	undying = PackedByteArray()
	undying.resize(n)


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
	# 군대 통합사령부 revive — data에 revive_limit, revive_hp_pct가 있으면 주입.
	revive_left[idx] = data.get("revive_limit", 0)
	revive_hp_pct[idx] = data.get("revive_hp_pct", 0.0)
	soul_kills[idx] = 0
	soul_atk_bonus[idx] = 0.0
	berserk_active[idx] = 0
	retreat_active[idx] = 0
	retreat_timer[idx] = 0.0
	invuln[idx] = 0
	regen_timer[idx] = 0.0
	is_clone[idx] = 0
	slow_factor[idx] = 1.0
	undying[idx] = 0  # 💀 금간 해골: setup() 후 외부에서 설정


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
	# 방어적 클램프: 유닛 수가 극단적으로 많을 때 y > BATTLEFIELD_H 방지
	for i in count:
		pos[i] = pos[i].clamp(Vector2.ZERO, Vector2(BATTLEFIELD_W, BATTLEFIELD_H))


## Run one combat tick. Returns true if combat is still ongoing.
func tick() -> bool:
	if _tick >= MAX_TICKS:
		_finish(false)  # timeout = player loss
		return false

	_tick += 1

	# Save positions for lerp (rendering only — skip in headless)
	if not headless:
		for i in count:
			prev_pos[i] = pos[i]

	# Rebuild alive list once per tick (used by all subsequent loops)
	_rebuild_alive_list()

	# Rebuild spatial grid
	_grid.rebuild(pos, alive)

	# Update flow fields (every 5 ticks in headless — centroids shift slowly)
	if not headless or _tick % 5 == 1:
		_cached_flow_ally_dir = _get_centroid_fast(false)
		_cached_flow_enemy_dir = _get_centroid_fast(true)
		_flow_ally.compute(_cached_flow_ally_dir)
		_flow_enemy.compute(_cached_flow_enemy_dir)

	# Apply slow auras and per-tick mechanics
	_mech.apply_per_tick()

	# Two-phase update to eliminate iteration-order bias (2026-04-23).
	# Previously single-phase: team 1 units moved+attacked first, then team 0.
	# This let team 0 see team 1's post-movement position and get first-strike
	# when engagement range was crossed within a tick.
	# Fix 1 (phase split): Phase 1 moves all, Phase 2 attacks from post-move
	#   positions — both teams see each other's final state symmetrically.
	# Fix 2 (team-interleaved order): within each phase, residual bias came
	#   from lower-index units attacking first (team 1 spawns at lower idx).
	#   Build interleaved order (t1[0], t0[0], t1[1], t0[1], ...) so the
	#   kill-before-counter advantage alternates per unit within one tick —
	#   symmetric first-strike distribution.
	_rebuild_interleaved_order()
	# Snapshot pos so phase 1 movements are computed from pre-tick state
	# (prevents earlier-iterating units' new position leaking into later units'
	# target-distance reads).
	if _pos_snapshot.size() != count:
		_pos_snapshot.resize(count)
	for i in _alive_list:
		_pos_snapshot[i] = pos[i]
	for idx in _interleaved_order:
		_move_unit(idx)
	for idx in _interleaved_order:
		_attack_unit(idx)

	# Collision separation (every COLLISION_INTERVAL ticks in headless — visual smoothness not needed)
	if not headless or _tick % COLLISION_INTERVAL == 0:
		_resolve_collisions()

	# Win condition (tracked incrementally via _ally_alive/_enemy_alive)
	if _enemy_alive <= 0:
		_finish(true)
		return false
	if _ally_alive <= 0:
		_finish(false)
		return false

	return true


## Phase 1: movement only. Updates target and pos based on PRE-attack-phase state.
## Phase 2 (_attack_unit) will see post-movement positions for all units symmetrically.
func _move_unit(i: int) -> void:
	var is_ally := team[i] == 1
	var eff_ms: float = move_speed[i] * slow_factor[i]

	# Tactical retreat: move away from enemies, skip attacking
	if retreat_active[i] == 1:
		var flow = _flow_enemy if is_ally else _flow_ally  # retreat = away from enemies
		var dir: Vector2 = -flow.get_direction(pos[i])  # reverse direction
		pos[i] += dir * eff_ms * 2.0  # double speed
		pos[i] = pos[i].clamp(Vector2.ZERO, Vector2(BATTLEFIELD_W, BATTLEFIELD_H))
		return

	# Target caching: skip find_nearest if current target is alive and in attack range.
	# Only re-search when target dies or moves out of range.
	var t_cached := target_idx[i]
	var need_search := true
	if t_cached >= 0 and alive[t_cached] == 1:
		var cached_dist_sq := pos[i].distance_squared_to(pos[t_cached])
		if cached_dist_sq <= attack_range[i] * attack_range[i]:
			need_search = false  # attacking current target, no need to re-search

	if need_search:
		# Two-pass search to avoid 2401-cell grid scan.
		# Pass 1: moderate radius (NEAR_SEARCH_RANGE = 320px = 5 cells).
		# Pass 2: full battlefield only if pass 1 misses (rare during active combat).
		# Full search guarantees no unit-escape-bug (traces/failures/unit-escape-bug).
		var near_range := maxf(attack_range[i], NEAR_SEARCH_RANGE)
		target_idx[i] = _grid.find_nearest(pos[i], is_ally, team, alive, pos, near_range)
		if target_idx[i] < 0:
			const FULL_BATTLEFIELD_SEARCH := BATTLEFIELD_W + BATTLEFIELD_H
			target_idx[i] = _grid.find_nearest(pos[i], is_ally, team, alive, pos, FULL_BATTLEFIELD_SEARCH)

	if target_idx[i] < 0:
		# 여기 도달 = 반대편 팀이 0명 → 다음 tick 말에 _finish 호출됨.
		# 이동시키지 않고 제자리에 두어 이탈 방지.
		return

	# 2026-04-23: Read target pos from snapshot (pre-tick state) so earlier
	# iterations' pos writes don't leak into later units' movement decisions.
	# Self pos uses current (possibly already-updated in same tick? No —
	# each unit writes its own pos only once per tick, so pos[i] == snapshot here).
	var t := target_idx[i]
	var target_pos: Vector2 = _pos_snapshot[t]
	var dist_sq := pos[i].distance_squared_to(target_pos)
	var range_sq := attack_range[i] * attack_range[i]

	if dist_sq > range_sq:
		var dist := sqrt(dist_sq)
		var dir := (target_pos - pos[i]) / dist
		var step := minf(eff_ms, dist - attack_range[i] + 2.0)
		pos[i] += dir * step
		pos[i] = pos[i].clamp(Vector2.ZERO, Vector2(BATTLEFIELD_W, BATTLEFIELD_H))


## Phase 2: attack resolution from post-movement positions. All units see the
## same snapshot of final positions (symmetric across teams).
func _attack_unit(i: int) -> void:
	# Skip retreating or dead units (phase 1 may have invalidated state).
	if alive[i] == 0 or retreat_active[i] == 1:
		return
	var t := target_idx[i]
	if t < 0 or alive[t] == 0:
		return
	var dist_sq := pos[i].distance_squared_to(pos[t])
	var range_sq := attack_range[i] * attack_range[i]
	if dist_sq > range_sq:
		return
	cooldown[i] -= 1.0
	if cooldown[i] <= 0.0:
		_do_attack(i, t)
		cooldown[i] = attack_speed[i]


func _resolve_collisions() -> void:
	## Push overlapping units apart using spatial grid neighbors.
	## Only checks same-cell and adjacent-cell pairs. O(N) average.
	## OBS-054: push를 버퍼에 누적 후 MAX_PUSH로 cap하여 적용.
	## 적-아군 push 유지(OBS-027 겹침 방지) + 누적 관통 차단.
	var push_accum: PackedVector2Array
	push_accum.resize(count)
	push_accum.fill(Vector2.ZERO)
	for i in _alive_list:
		var cx := floori(pos[i].x / CELL_SIZE)
		var cy := floori(pos[i].y / CELL_SIZE)
		for dx in range(maxi(cx - 1, 0), mini(cx + 2, _grid._cols)):
			for dy in range(maxi(cy - 1, 0), mini(cy + 2, _grid._rows)):
				var cell: Array = _grid._cells[dy * _grid._cols + dx]
				for j in cell:
					if j <= i or alive[j] == 0:
						continue
					var min_dist := radius[i] + radius[j]
					var diff := pos[i] - pos[j]
					var dist_sq := diff.length_squared()
					if dist_sq < min_dist * min_dist and dist_sq > 0.01:
						var dist := sqrt(dist_sq)
						var overlap := min_dist - dist
						var push := diff / dist * (overlap * 0.5)
						push_accum[i] += push
						push_accum[j] -= push
					elif dist_sq <= 0.01:
						var nudge := Vector2(0.5 - randf(), 0.5 - randf()).normalized()
						push_accum[i] += nudge * min_dist * 0.5
						push_accum[j] -= nudge * min_dist * 0.5
	# Apply capped push + clamp to battlefield
	const MAX_PUSH := SEPARATION_DIST  # 14.0px — 1쌍 분리에 충분, 다중 누적 관통 차단
	for i in _alive_list:
		var p := push_accum[i]
		if p.length_squared() > MAX_PUSH * MAX_PUSH:
			p = p.normalized() * MAX_PUSH
		pos[i] += p
		pos[i] = pos[i].clamp(Vector2.ZERO, Vector2(BATTLEFIELD_W, BATTLEFIELD_H))


func _do_attack(attacker: int, defender: int) -> void:
	_mech.resolve_attack(attacker, defender)


## Fast centroid using alive_list (avoids dead-unit iteration).
func _get_centroid_fast(ally_side: bool) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for i in _alive_list:
		if (team[i] == 1) == ally_side:
			sum += pos[i]
			n += 1
	return sum / maxf(n, 1.0)


func _finish(player_won: bool) -> void:
	_running = false
	combat_finished.emit({
		"player_won": player_won,
		"ally_survived": _ally_alive,
		"enemy_survived": _enemy_alive,
		"ticks": _tick,
	})


## Rebuild alive index list. Called once per tick.
func _rebuild_alive_list() -> void:
	_alive_list.resize(0)
	for i in count:
		if alive[i] == 1:
			_alive_list.append(i)


## Build a team-interleaved version of _alive_list for fair iteration.
## Pattern: team1[0], team0[0], team1[1], team0[1], ... (remaining after shorter
## team exhausted appended at tail). Ensures no team has a block-wise first-mover
## advantage within a single tick.
func _rebuild_interleaved_order() -> void:
	_interleaved_order.resize(0)
	# Partition alive_list by team (stable by index within each team).
	var t1: PackedInt32Array = []
	var t0: PackedInt32Array = []
	for idx in _alive_list:
		if team[idx] == 1:
			t1.append(idx)
		else:
			t0.append(idx)
	var n := maxi(t1.size(), t0.size())
	for i in n:
		if i < t1.size():
			_interleaved_order.append(t1[i])
		if i < t0.size():
			_interleaved_order.append(t0[i])


## Grid-based AOE query: find enemy units within radius of center.
## Returns PackedInt32Array of unit indices. Used by splash/chain_discharge.
func find_enemies_in_radius(center: Vector2, aoe_range: float, attacker_team: int,
		exclude_idx: int = -1) -> PackedInt32Array:
	return _grid.find_in_radius(center, aoe_range, attacker_team, team, alive, pos, exclude_idx)


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
	# 군대 통합사령부 revive: 사망 직전 체크. revive_left > 0이면 HP 복원하고 살림.
	# 패턴은 immortal_core와 유사하지만 부활은 이미 사망 판정 시점이라 alive는 유지.
	if revive_left[i] > 0 and revive_hp_pct[i] > 0.0:
		revive_left[i] -= 1
		hp[i] = max_hp[i] * revive_hp_pct[i]
		target_idx[i] = -1
		cooldown[i] = 0.0
		return  # 부활 성공 — 사망 처리 취소
	alive[i] = 0
	if team[i] == 1:
		_ally_alive -= 1
	else:
		_enemy_alive -= 1
	if not headless:
		unit_died.emit(i)
	# Fission: spawn clones on death
	if is_clone[i] == 0 and _fission_slots.has(i):
		_mech.trigger_fission(i)


## Check if unit has a specific mechanic type (cached O(1) lookup).
func _has_mechanic(i: int, mtype: String) -> bool:
	if i >= _mech_cache.size():
		# Fallback: cache not built yet (e.g. called during setup before _build_mech_cache)
		for m in mechanics[i]:
			if m.get("type", "") == mtype:
				return true
		return false
	return _mech_cache[i].has(mtype)


## Get mechanic dict for a unit, or {} if not found (cached O(1) lookup).
func _get_mechanic(i: int, mtype: String) -> Dictionary:
	if i >= _mech_cache.size():
		# Fallback: cache not built yet
		for m in mechanics[i]:
			if m.get("type", "") == mtype:
				return m
		return {}
	return _mech_cache[i].get(mtype, {})


## Build mechanic cache from mechanics arrays. Call after all units are set up.
func _build_mech_cache() -> void:
	_mech_cache.resize(count)
	_has_any_slow_aura = false
	_has_any_regen = false
	for i in count:
		var cache := {}
		for m in mechanics[i]:
			var t: String = m.get("type", "")
			if t != "":
				cache[t] = m
		_mech_cache[i] = cache
		if cache.has("slow_aura"):
			_has_any_slow_aura = true
		if cache.has("regen"):
			_has_any_regen = true


## Rebuild mechanic cache for a single unit (after fission clone spawn).
func _rebuild_mech_cache_single(i: int) -> void:
	var cache := {}
	for m in mechanics[i]:
		var t: String = m.get("type", "")
		if t != "":
			cache[t] = m
	_mech_cache[i] = cache


## Count alive units per team. Call after setup.
func _count_alive() -> void:
	_ally_alive = 0
	_enemy_alive = 0
	for i in count:
		if alive[i] == 0:
			continue
		if team[i] == 1:
			_ally_alive += 1
		else:
			_enemy_alive += 1


## Static helper: check mechanic in a raw array (used during _set_unit).
static func _has_mechanic_in(mechs: Array, mtype: String) -> bool:
	for m in mechs:
		if m.get("type", "") == mtype:
			return true
	return false
