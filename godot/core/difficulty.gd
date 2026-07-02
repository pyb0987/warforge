extends Node
## Cumulative run difficulty rules.
## Keep this as a thin modifier layer so base curves, cards, and genome values stay stable.

const MIN_DIFFICULTY := 1
const MAX_DIFFICULTY := 8
const BASE_SHOP_SIZE := 6

const D2_ENEMY_HP_MULT := 1.2
const D3_STARTING_GOLD_LEGACY_PENALTY := 3
const D3_STARTING_GOLD_LEGACY_BASE := 13.0
const D4_ENEMY_COUNT_MULT := 1.10
const D6_SHOP_SIZE := 4
const D6_REROLL_COST := 2
const D7_ENEMY_ATK_MULT := 1.10
const D8_PLAYER_HP := 20


func clamp_difficulty(value: int) -> int:
	return clampi(value, MIN_DIFFICULTY, MAX_DIFFICULTY)


func get_enemy_hp_mult(difficulty: int) -> float:
	return D2_ENEMY_HP_MULT if clamp_difficulty(difficulty) >= 2 else 1.0


func get_starting_gold(base_gold: int, difficulty: int) -> int:
	if clamp_difficulty(difficulty) >= 3 and base_gold > 0:
		var scaled_penalty := int(round(
			float(base_gold) * D3_STARTING_GOLD_LEGACY_PENALTY / D3_STARTING_GOLD_LEGACY_BASE))
		var penalty := mini(D3_STARTING_GOLD_LEGACY_PENALTY, maxi(1, scaled_penalty))
		return maxi(0, base_gold - penalty)
	return base_gold


func get_enemy_count_mult(difficulty: int) -> float:
	return D4_ENEMY_COUNT_MULT if clamp_difficulty(difficulty) >= 4 else 1.0


func apply_enemy_count_modifier(units: Array, difficulty: int,
		rng: RandomNumberGenerator) -> Array:
	var mult := get_enemy_count_mult(difficulty)
	if mult <= 1.0 or units.is_empty():
		return units

	var extra_count := int(floor(units.size() * (mult - 1.0)))
	for _i in extra_count:
		var source: Dictionary = units[rng.randi_range(0, units.size() - 1)]
		units.append(source.duplicate(true))
	return units


func get_shop_size(base_size: int, difficulty: int) -> int:
	if clamp_difficulty(difficulty) >= 6:
		return mini(base_size, D6_SHOP_SIZE)
	return base_size


func get_reroll_cost(base_cost: int, difficulty: int) -> int:
	if clamp_difficulty(difficulty) >= 6:
		return maxi(base_cost, D6_REROLL_COST)
	return base_cost


func get_enemy_atk_mult(difficulty: int) -> float:
	return D7_ENEMY_ATK_MULT if clamp_difficulty(difficulty) >= 7 else 1.0


func get_player_hp(base_hp: int, difficulty: int) -> int:
	if clamp_difficulty(difficulty) >= 8:
		return mini(base_hp, D8_PLAYER_HP)
	return base_hp


func is_boss_round(round_num: int) -> bool:
	return round_num in Enums.BOSS_ROUNDS


func get_boss_upgrade_rarities(round_num: int, difficulty: int) -> Array[int]:
	var d := clamp_difficulty(difficulty)
	if d < 5 or not is_boss_round(round_num):
		return []

	var rarities: Array[int] = [Enums.UpgradeRarity.COMMON]
	if d >= 7:
		if round_num >= 15:
			rarities.append(Enums.UpgradeRarity.EPIC)
		elif round_num >= 12:
			rarities.append(Enums.UpgradeRarity.RARE)
	return rarities


func apply_enemy_modifiers(units: Array, round_num: int,
		rng: RandomNumberGenerator, difficulty: int) -> Array:
	var d := clamp_difficulty(difficulty)
	var hp_mult := get_enemy_hp_mult(d)
	var atk_mult := get_enemy_atk_mult(d)
	for unit in units:
		if hp_mult != 1.0:
			unit["hp"] = float(unit.get("hp", 0.0)) * hp_mult
		if atk_mult != 1.0:
			unit["atk"] = float(unit.get("atk", 0.0)) * atk_mult

	var rarities := get_boss_upgrade_rarities(round_num, d)
	if not rarities.is_empty():
		_apply_boss_upgrades(units, rarities, rng)
	return units


func _apply_boss_upgrades(units: Array, rarities: Array[int],
		rng: RandomNumberGenerator) -> void:
	for rarity in rarities:
		var ids := UpgradeDB.get_ids_by_rarity(rarity)
		if ids.is_empty():
			continue
		ids.sort()
		var upgrade_id: String = ids[rng.randi_range(0, ids.size() - 1)]
		for unit in units:
			_apply_upgrade_to_enemy_unit(unit, upgrade_id)


func _apply_upgrade_to_enemy_unit(unit: Dictionary, upgrade_id: String) -> void:
	var upgrade := UpgradeDB.get_upgrade(upgrade_id)
	if upgrade.is_empty():
		return

	var mods: Dictionary = upgrade.get("stat_mods", {})
	var atk_pct: float = float(mods.get("atk_pct", 0.0))
	var hp_pct: float = float(mods.get("hp_pct", 0.0))
	if atk_pct != 0.0:
		unit["atk"] = float(unit.get("atk", 0.0)) * (1.0 + atk_pct)
	if hp_pct != 0.0:
		unit["hp"] = float(unit.get("hp", 0.0)) * (1.0 + hp_pct)
	unit["def"] = int(unit.get("def", 0)) + int(mods.get("def", 0))
	unit["range"] = int(unit.get("range", 0)) + int(mods.get("range", 0))
	unit["move_speed"] = int(unit.get("move_speed", 0)) + int(mods.get("move_speed", 0))
	var as_mult: float = float(mods.get("as_mult", 0.0))
	if as_mult > 0.0:
		unit["attack_speed"] = float(unit.get("attack_speed", 1.0)) * as_mult

	var mechanics: Array = unit.get("mechanics", []).duplicate(true)
	for mechanic in upgrade.get("mechanics", []):
		mechanics.append((mechanic as Dictionary).duplicate(true))
	unit["mechanics"] = mechanics

	var enemy_upgrades: Array = unit.get("enemy_upgrades", []).duplicate()
	enemy_upgrades.append(upgrade_id)
	unit["enemy_upgrades"] = enemy_upgrades
