class_name EnemyDB
extends RefCounted
## Enemy generation: round-based power scaling with preset variety.
## Single source of truth for both play (game_manager) and sim (headless_runner).
##
## All scaling parameters (cp curve, composition, base stats, boss mult) live in
## Genome. If no genome is provided, falls back to Genome.create_default()
## which mirrors the original hardcoded values.

## Preset types for variety per round.
enum Preset { SWARM, HEAVY, SNIPER, BALANCED }

const PRESET_NAMES := ["swarm", "heavy", "sniper", "balanced"]

## Range/MoveSpeed/Radius are not genome-controlled (geometry constants).
const BASE := {
	"swarm_atk": 2.0,   "swarm_hp": 12.0,  "swarm_as": 0.8, "swarm_range": 0, "swarm_ms": 3,
	"melee_atk": 4.0,   "melee_hp": 30.0,  "melee_as": 1.2, "melee_range": 0, "melee_ms": 2,
	"ranged_atk": 3.0,  "ranged_hp": 15.0, "ranged_as": 1.5, "ranged_range": 4, "ranged_ms": 1,
	"heavy_atk": 5.0,   "heavy_hp": 60.0,  "heavy_as": 2.0, "heavy_range": 0, "heavy_ms": 1,
	"sniper_atk": 6.0,  "sniper_hp": 10.0, "sniper_as": 2.0, "sniper_range": 6, "sniper_ms": 1,
}


## Mirror of default cp curve formula. Kept for tests and as a sanity reference.
## When genome is provided, genome.enemy_cp_curve[r-1] is used instead.
static func _round_mult(r: int) -> float:
	return 1.0 + (r - 1) * 0.2 + maxf(0.0, (r - 8)) * 0.1


## Generate enemy army for a given round.
## genome=null falls back to Genome.create_default() (matches original constants).
static func generate(round_num: int, rng: RandomNumberGenerator, genome: Genome = null) -> Array:
	var g: Genome = genome if genome != null else Genome.create_default()

	var is_boss := round_num in [4, 8, 12, 15]
	var preset: int = rng.randi_range(0, 3)

	var preset_name: String = PRESET_NAMES[preset]
	var comp: Dictionary = g.get_enemy_comp(preset_name)
	var cp_mult: float = g.enemy_cp_curve[round_num - 1] if round_num >= 1 and round_num <= 15 else 1.0

	var units: Array = []
	for key in comp:
		if not key.ends_with("_base"):
			continue
		var type_name: String = key.replace("_base", "")
		var base_count: int = int(comp[key])
		var per_r: float = comp.get(type_name + "_per_r", 0.0)
		var count: int = maxi(int(base_count + round_num * per_r), 1)

		var stat: Dictionary = g.get_enemy_stat(type_name)
		var base_atk: float = stat.get("atk", 3.0)
		var base_hp: float = stat.get("hp", 20.0)
		var base_as: float = stat.get("as", 1.0)

		var scaled_atk: float = base_atk * cp_mult
		var scaled_hp: float = base_hp * cp_mult

		# Preset sub-multipliers (preserve original variety in role-stat balance)
		var sub_mult: float = _sub_mult(preset_name, type_name)
		scaled_atk *= sub_mult
		scaled_hp *= sub_mult

		var range_val: int = BASE.get(type_name + "_range", 0)
		var ms_val: int = BASE.get(type_name + "_ms", 2)

		for _i in count:
			units.append({
				"atk": scaled_atk,
				"hp": scaled_hp,
				"attack_speed": base_as,
				"range": range_val,
				"move_speed": ms_val,
				"radius": 6.0,
			})

	# Boss scaling
	if is_boss:
		var bm: Dictionary = g.get_boss_mult()
		var batk: float = bm.get("atk_mult", 1.3)
		var bhp: float = bm.get("hp_mult", 1.3)
		for u in units:
			u["atk"] *= batk
			u["hp"] *= bhp

	return units


static func _sub_mult(preset_name: String, type_name: String) -> float:
	if preset_name == "swarm" and type_name == "ranged":
		return 0.8
	if preset_name == "heavy":
		if type_name == "melee":
			return 0.9
		if type_name == "ranged":
			return 0.7
	if preset_name == "sniper" and type_name == "melee":
		return 0.8
	if preset_name == "balanced" and type_name == "swarm":
		return 0.9
	return 1.0


static func _boss_preset(round_num: int) -> int:
	match round_num:
		4: return Preset.SWARM      # R4: 물량 러시 테스트
		8: return Preset.HEAVY      # R8: 탱크 돌파 테스트
		12: return Preset.SNIPER    # R12: 원거리 대응 테스트
		15: return Preset.BALANCED  # R15: 종합 테스트
		_: return Preset.BALANCED
