class_name EnemyDB
extends RefCounted
## Enemy generation: round-based power scaling with preset variety.
## Ported from sim/data/enemies.py + combat.md design.

## Preset types for variety per round.
enum Preset { SWARM, HEAVY, SNIPER, BALANCED }

## Base stats that scale per round.
const BASE := {
	"swarm_atk": 2.0,   "swarm_hp": 12.0,  "swarm_as": 0.8, "swarm_range": 0, "swarm_ms": 3,
	"melee_atk": 4.0,   "melee_hp": 30.0,  "melee_as": 1.2, "melee_range": 0, "melee_ms": 2,
	"ranged_atk": 3.0,  "ranged_hp": 15.0, "ranged_as": 1.5, "ranged_range": 4, "ranged_ms": 1,
	"heavy_atk": 5.0,   "heavy_hp": 60.0,  "heavy_as": 2.0, "heavy_range": 0, "heavy_ms": 1,
	"sniper_atk": 6.0,  "sniper_hp": 10.0, "sniper_as": 2.0, "sniper_range": 6, "sniper_ms": 1,
}

## Round -> multiplier for enemy stats.
static func _round_mult(r: int) -> float:
	# R1=1.0, R8=2.2, R15=4.0 (quadratic-ish curve)
	return 1.0 + (r - 1) * 0.2 + maxf(0.0, (r - 8)) * 0.1


## Generate enemy army for a given round.
## Returns Array of unit dicts compatible with CombatEngine.setup().
static func generate(round_num: int, rng: RandomNumberGenerator) -> Array:
	var mult := _round_mult(round_num)
	var is_boss := round_num in [4, 8, 12, 15]

	# Pick preset
	var preset: int
	if is_boss:
		preset = _boss_preset(round_num)
	else:
		preset = rng.randi_range(0, 3)

	var units: Array = []

	match preset:
		Preset.SWARM:
			# Many weak melee + few ranged
			var n_swarm := int(8 + round_num * 2.5)
			var n_ranged := int(2 + round_num * 0.5)
			for i in n_swarm:
				units.append(_make("swarm", mult))
			for i in n_ranged:
				units.append(_make("ranged", mult * 0.8))

		Preset.HEAVY:
			# Few tanky + support ranged
			var n_heavy := int(3 + round_num * 0.8)
			var n_melee := int(4 + round_num * 1.0)
			var n_ranged := int(2 + round_num * 0.5)
			for i in n_heavy:
				units.append(_make("heavy", mult))
			for i in n_melee:
				units.append(_make("melee", mult * 0.9))
			for i in n_ranged:
				units.append(_make("ranged", mult * 0.7))

		Preset.SNIPER:
			# Ranged heavy + melee screen
			var n_sniper := int(3 + round_num * 0.6)
			var n_melee := int(5 + round_num * 1.2)
			for i in n_sniper:
				units.append(_make("sniper", mult))
			for i in n_melee:
				units.append(_make("melee", mult * 0.8))

		Preset.BALANCED:
			# Mixed composition
			var n_melee := int(4 + round_num * 1.0)
			var n_ranged := int(3 + round_num * 0.7)
			var n_swarm := int(3 + round_num * 0.5)
			for i in n_melee:
				units.append(_make("melee", mult))
			for i in n_ranged:
				units.append(_make("ranged", mult))
			for i in n_swarm:
				units.append(_make("swarm", mult * 0.9))

	# Boss rounds: +30% stats
	if is_boss:
		for u in units:
			u["atk"] *= 1.3
			u["hp"] *= 1.3

	return units


static func _boss_preset(round_num: int) -> int:
	match round_num:
		4: return Preset.SWARM      # R4: 물량 러시 테스트
		8: return Preset.HEAVY      # R8: 탱크 돌파 테스트
		12: return Preset.SNIPER    # R12: 원거리 대응 테스트
		15: return Preset.BALANCED  # R15: 종합 테스트
		_: return Preset.BALANCED


static func _make(unit_type: String, mult: float) -> Dictionary:
	return {
		"atk": BASE[unit_type + "_atk"] * mult,
		"hp": BASE[unit_type + "_hp"] * mult,
		"attack_speed": BASE[unit_type + "_as"],
		"range": BASE[unit_type + "_range"],
		"move_speed": BASE[unit_type + "_ms"],
		"radius": 6.0,
	}
