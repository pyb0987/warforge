class_name MechanicsHandler
extends RefCounted
## Handles all 19 upgrade mechanic types during combat.
## Called by CombatEngine at specific hook points.

var _e  # CombatEngine reference (untyped to avoid circular ref)


func _init(engine) -> void:
	_e = engine


# =============================================================
# Hook: Combat Start (called once after setup)
# =============================================================

func apply_combat_start() -> void:
	for i in _e._base_count:
		if _e.alive[i] == 0:
			continue
		# battle_start_heal: HP +X% at combat start
		var bsh: Dictionary = _e._get_mechanic(i, "battle_start_heal")
		if not bsh.is_empty():
			var heal: float = _e.max_hp[i] * bsh.get("heal_hp_pct", 0.0)
			_e.hp[i] = minf(_e.hp[i] + heal, _e.max_hp[i])
		# battle_start_shield: overHP shield
		var bss: Dictionary = _e._get_mechanic(i, "battle_start_shield")
		if not bss.is_empty():
			var shield: float = _e.max_hp[i] * bss.get("shield_hp_pct", 0.0)
			_e.hp[i] += shield
			_e.max_hp[i] += shield


# =============================================================
# Hook: Per-tick (called every tick before _update_unit loop)
# =============================================================

func apply_per_tick() -> void:
	_apply_slow_auras()
	_apply_regen()
	_update_retreat_timers()


func _apply_slow_auras() -> void:
	## Reset slow factors, then apply auras.
	## Early exit: skip entirely if no alive unit has slow_aura.
	if not _e._has_any_slow_aura:
		return

	for i in _e._alive_list:
		_e.slow_factor[i] = 1.0

	for i in _e._alive_list:
		var m: Dictionary = _e._get_mechanic(i, "slow_aura")
		if m.is_empty():
			continue
		var slow_pct: float = m.get("slow_pct", 0.0)
		var aura_range: float = _e.attack_range[i]
		# Grid-based query instead of O(N) full scan
		var targets: PackedInt32Array = _e.find_enemies_in_radius(_e.pos[i], aura_range, _e.team[i])
		for j in targets:
			_e.slow_factor[j] = maxf(_e.slow_factor[j] - slow_pct, 0.4)  # min 40% speed


func _apply_regen() -> void:
	if not _e._has_any_regen:
		return
	for i in _e._alive_list:
		var m: Dictionary = _e._get_mechanic(i, "regen")
		if m.is_empty():
			continue
		if _e.berserk_active[i] == 1:
			continue  # berserk blocks healing
		_e.regen_timer[i] += _e.TICK_DELTA
		var interval: float = m.get("interval_sec", 3.0)
		if _e.regen_timer[i] >= interval:
			_e.regen_timer[i] -= interval
			var heal: float = _e.max_hp[i] * m.get("heal_hp_pct", 0.0)
			_e.hp[i] = minf(_e.hp[i] + heal, _e.max_hp[i])


func _update_retreat_timers() -> void:
	for i in _e._alive_list:
		# Tactical retreat timer
		if _e.retreat_active[i] == 1:
			_e.retreat_timer[i] -= 1.0
			if _e.retreat_timer[i] <= 0.0:
				_e.retreat_active[i] = 0
				_e.invuln[i] = 0
		# Immortal core invuln timer (shares retreat_timer when retreat_active==0)
		elif _e.invuln[i] == 1 and _e.retreat_timer[i] > 0.0:
			_e.retreat_timer[i] -= 1.0
			if _e.retreat_timer[i] <= 0.0:
				_e.invuln[i] = 0
				# Heal 50% HP on immortal recovery
				_e.hp[i] = _e.max_hp[i] * 0.5


# =============================================================
# Hook: Attack resolution (replaces simple hp -= atk)
# =============================================================

func resolve_attack(attacker: int, defender: int) -> void:
	var dmg: float = _calc_damage(attacker, defender)

	# --- Defender damage intake ---
	dmg = _apply_defender_mechanics(defender, attacker, dmg)
	if dmg <= 0.0:
		return  # fully negated (phase_shift, invuln)

	_e.hp[defender] -= dmg
	_check_defender_thresholds(defender)

	# --- Attacker on-hit effects ---
	_apply_attacker_on_hit(attacker, defender, dmg)

	# --- Emit attack event for combat chain ---
	_e.unit_attacked.emit(attacker, defender)

	# --- Death check ---
	if _e.hp[defender] <= 0.0:
		_on_kill(attacker, defender)


func _calc_damage(attacker: int, defender: int) -> float:
	var base_atk: float = _e.atk[attacker]

	# Focus fire: stacking ATK on same target
	var focus: Dictionary = _e._get_mechanic(attacker, "focus_fire")
	if not focus.is_empty():
		if _e.focus_target[attacker] == defender:
			_e.focus_stacks[attacker] += 1
		else:
			_e.focus_target[attacker] = defender
			_e.focus_stacks[attacker] = 0
		base_atk *= 1.0 + focus.get("stack_atk_pct", 0.0) * _e.focus_stacks[attacker]

	# Berserk: ATK multiplier when active
	var berserk: Dictionary = _e._get_mechanic(attacker, "berserk")
	if not berserk.is_empty() and _e.berserk_active[attacker] == 1:
		base_atk *= berserk.get("atk_mult", 2.0)

	# Soul harvest: accumulated ATK bonus
	base_atk *= 1.0 + _e.soul_atk_bonus[attacker]

	# Critical hit
	var crit: Dictionary = _e._get_mechanic(attacker, "critical")
	if not crit.is_empty():
		var chance: float = crit.get("crit_chance", 0.0)
		if randf() < chance:
			base_atk *= crit.get("crit_mult", 2.5)
			# 특수작전대 R4/R10: 치명타 발동 시 인접 적 스플래시 추가 피해
			var crit_splash_pct: float = crit.get("splash_pct", 0.0)
			if crit_splash_pct > 0.0:
				_apply_splash(attacker, defender, crit_splash_pct, _e.RANGE_SCALE)

	# DEF reduction with armor pierce
	var def_val: float = _e.defense[defender]
	if def_val > 0.0:
		var pierce: Dictionary = _e._get_mechanic(attacker, "armor_pierce")
		if not pierce.is_empty():
			def_val *= 1.0 - pierce.get("ignore_def_pct", 0.0)
		base_atk = maxf(1.0, base_atk - def_val)

	# hp_percent_dmg: % of current HP (ignores DEF)
	var hp_pct: Dictionary = _e._get_mechanic(attacker, "hp_percent_dmg")
	if not hp_pct.is_empty():
		base_atk += _e.hp[defender] * hp_pct.get("dmg_pct", 0.0)

	return base_atk


func _apply_defender_mechanics(defender: int, _attacker: int, dmg: float) -> float:
	# Invulnerable (retreat or immortal)
	if _e.invuln[defender] == 1:
		return 0.0

	# Phase shift: first hit immunity
	if _e.phase_shift_left[defender] > 0:
		_e.phase_shift_left[defender] -= 1
		return 0.0

	# Immortal core: survive lethal hit
	if dmg >= _e.hp[defender] and _e.immortal_left[defender] > 0:
		_e.immortal_left[defender] -= 1
		_e.hp[defender] = 1.0
		_e.invuln[defender] = 1
		# 3 sec invuln = 60 ticks at 20fps
		_e.retreat_timer[defender] = 60.0  # reusing retreat_timer for invuln duration
		return 0.0

	# 💀 금간 해골: 첫 치사 HP1 생존 (유닛당 1회)
	if dmg >= _e.hp[defender] and _e.undying[defender] == 1:
		_e.undying[defender] = 0
		_e.hp[defender] = 1.0
		return 0.0

	return dmg


func _check_defender_thresholds(defender: int) -> void:
	if _e.alive[defender] == 0:
		return
	var hp_ratio: float = _e.hp[defender] / _e.max_hp[defender] if _e.max_hp[defender] > 0.0 else 0.0

	# Tactical retreat: HP <= 25%
	if _e.retreat_active[defender] == 0:
		var retreat: Dictionary = _e._get_mechanic(defender, "tactical_retreat")
		if not retreat.is_empty():
			var threshold: float = retreat.get("hp_threshold", 0.25)
			if hp_ratio <= threshold:
				_e.retreat_active[defender] = 1
				_e.invuln[defender] = 1
				_e.retreat_timer[defender] = 5.0 * _e.TICK_RATE  # 5 sec

	# Berserk: HP <= 30%
	if _e.berserk_active[defender] == 0:
		var berserk: Dictionary = _e._get_mechanic(defender, "berserk")
		if not berserk.is_empty():
			var threshold: float = berserk.get("hp_threshold", 0.30)
			if hp_ratio <= threshold:
				_e.berserk_active[defender] = 1
				# AS multiplier applied: halve cooldown interval
				var as_mult: float = berserk.get("as_mult", 2.0)
				_e.attack_speed[defender] /= as_mult


func _apply_attacker_on_hit(attacker: int, defender: int, dmg: float) -> void:
	# Thorns: reflect damage back to attacker
	var thorns: Dictionary = _e._get_mechanic(defender, "thorns")
	if not thorns.is_empty():
		var reflect: float = _e.atk[defender] * thorns.get("reflect_pct", 0.0)
		if reflect > 0.0 and _e.invuln[attacker] == 0:
			_e.hp[attacker] -= reflect
			if _e.hp[attacker] <= 0.0:
				_e.kill_unit(attacker)

	# Lifesteal: heal attacker
	var lifesteal: Dictionary = _e._get_mechanic(attacker, "lifesteal")
	if not lifesteal.is_empty():
		if _e.berserk_active[attacker] == 0:  # berserk blocks healing
			var heal: float = dmg * lifesteal.get("steal_pct", 0.0)
			_e.hp[attacker] = minf(_e.hp[attacker] + heal, _e.max_hp[attacker])

	# Splash: AOE damage to nearby enemies
	var splash: Dictionary = _e._get_mechanic(attacker, "splash")
	if not splash.is_empty():
		_apply_splash(attacker, defender, splash.get("splash_pct", 0.0), _e.RANGE_SCALE)

	# Chain explosion: splash part (on-hit, not on-kill)
	var chain_exp: Dictionary = _e._get_mechanic(attacker, "chain_explosion")
	if not chain_exp.is_empty():
		_apply_splash(attacker, defender, chain_exp.get("splash_pct", 0.0), _e.RANGE_SCALE)

	# Attack stack: ATK +X% per attack (warmachine ★3)
	var atk_stack: Dictionary = _e._get_mechanic(attacker, "attack_stack")
	if not atk_stack.is_empty():
		_e.soul_atk_bonus[attacker] += atk_stack.get("atk_pct", 0.0)


func _apply_splash(attacker: int, center_unit: int, splash_pct: float, aoe_range: float) -> void:
	if splash_pct <= 0.0:
		return
	var splash_dmg: float = _e.atk[attacker] * splash_pct
	var center: Vector2 = _e.pos[center_unit]
	# Grid-based AOE query instead of O(N) full scan
	var targets: PackedInt32Array = _e.find_enemies_in_radius(center, aoe_range, _e.team[attacker], center_unit)
	for j in targets:
		_e.hp[j] -= splash_dmg
		if _e.hp[j] <= 0.0:
			_e.kill_unit(j)


# =============================================================
# Hook: On-kill effects
# =============================================================

func _on_kill(attacker: int, defender: int) -> void:
	_e.kill_unit(defender)

	# Chain discharge: AOE on kill — grid-based query
	var cd: Dictionary = _e._get_mechanic(attacker, "chain_discharge")
	if not cd.is_empty():
		var chain_dmg: float = _e.atk[attacker] * cd.get("chain_dmg_pct", 0.0)
		var center: Vector2 = _e.pos[defender]
		var targets: PackedInt32Array = _e.find_enemies_in_radius(center, _e.RANGE_SCALE, _e.team[attacker], defender)
		for j in targets:
			_e.hp[j] -= chain_dmg
			if _e.hp[j] <= 0.0:
				_e.kill_unit(j)

	# Chain explosion: kill AOE (separate from splash) — grid-based query
	var ce: Dictionary = _e._get_mechanic(attacker, "chain_explosion")
	if not ce.is_empty():
		var exp_dmg: float = _e.atk[attacker] * ce.get("splash_pct", 0.5)
		var exp_range: float = _e.RANGE_SCALE * 2.0  # 2칸 반경
		var center: Vector2 = _e.pos[defender]
		var targets: PackedInt32Array = _e.find_enemies_in_radius(center, exp_range, _e.team[attacker], defender)
		for j in targets:
			_e.hp[j] -= exp_dmg
			if _e.hp[j] <= 0.0:
				_e.kill_unit(j)

	# Soul harvest: kill → ATK% stack
	var sh: Dictionary = _e._get_mechanic(attacker, "soul_harvest")
	if not sh.is_empty():
		_e.soul_kills[attacker] += 1
		_e.soul_atk_bonus[attacker] += sh.get("kill_atk_pct", 0.05)
		# 10 kills → AS ×1.5 (one-time)
		if _e.soul_kills[attacker] == 10:
			_e.attack_speed[attacker] /= 1.5


# =============================================================
# Hook: Fission (triggered from kill_unit)
# =============================================================

func trigger_fission(original_idx: int) -> void:
	var m: Dictionary = _e._get_mechanic(original_idx, "fission")
	if m.is_empty():
		return
	var slots: Array = _e._fission_slots.get(original_idx, [])
	for slot_idx in slots:
		if slot_idx >= _e.count:
			continue
		# Spawn clone with 50% stats
		_e.alive[slot_idx] = 1
		_e.hp[slot_idx] = _e.max_hp[original_idx] * 0.5
		_e.max_hp[slot_idx] = _e.hp[slot_idx]
		_e.atk[slot_idx] = _e.atk[original_idx] * 0.5
		_e.attack_speed[slot_idx] = _e.attack_speed[original_idx]
		_e.attack_range[slot_idx] = _e.attack_range[original_idx]
		_e.move_speed[slot_idx] = _e.move_speed[original_idx]
		_e.defense[slot_idx] = _e.defense[original_idx]
		_e.radius[slot_idx] = _e.radius[original_idx]
		_e.pos[slot_idx] = _e.pos[original_idx]
		_e.prev_pos[slot_idx] = _e.pos[original_idx]
		_e.cooldown[slot_idx] = 0.0
		_e.target_idx[slot_idx] = -1
		_e.is_clone[slot_idx] = 1
		_e.mechanics[slot_idx] = []  # clones cannot re-fission
		_e._rebuild_mech_cache_single(slot_idx)  # sync cache for clone
		_e.invuln[slot_idx] = 0
		_e.berserk_active[slot_idx] = 0
		_e.retreat_active[slot_idx] = 0
		# Track alive count for clone spawn
		if _e.team[slot_idx] == 1:
			_e._ally_alive += 1
		else:
			_e._enemy_alive += 1
