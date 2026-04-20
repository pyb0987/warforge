class_name CardInstance
extends RefCounted
## A card on the player's board. Ported from sim/engine/cards.py.
##
## Stat formula (3-layer multiplicative):
##   ATK = base * (1 + growth%) * upgrade_mult * temp_mult + temp_atk

const BASE_UNIT_CAP := 60

# --- Commander bonuses (set at creation time) ---
var unit_cap_bonus: int = 0
var upgrade_slot_bonus: int = 0

# --- Template reference ---
var template_id: String
var template: Dictionary
var star_level: int = 1  # 1=★1, 2=★2, 3=★3

# --- Unit stacks ---
var stacks: Array = []

# --- Round state ---
var activations_used: int = 0
var tenure: int = 0
var threshold_fired: bool = false

# --- Layer 1: card-level growth modifier ---
var growth_atk_pct: float = 0.0
var growth_hp_pct: float = 0.0
var tag_growth_atk: Dictionary = {}
var tag_growth_hp: Dictionary = {}

# --- Shield ---
var shield_hp_pct: float = 0.0

# --- Theme-specific state ---
var theme_state: Dictionary = {}

# --- Upgrade slots ---
var upgrades: Array[Dictionary] = []  # attached upgrade templates, max 5

# --- Upgrade stat mods (combat engine reads these) ---
var upgrade_def: int = 0
var upgrade_range: int = 0
var upgrade_move_speed: int = 0
var upgrade_as_mult: float = 1.0

# --- Signals ---
signal stats_changed


static func create(tmpl_id: String) -> CardInstance:
	var inst := CardInstance.new()
	inst.template_id = tmpl_id
	inst.template = CardDB.get_template(tmpl_id).duplicate(true)
	if inst.template.is_empty():
		push_error("CardInstance.create: unknown template '%s'" % tmpl_id)
		return null
	inst._init_stacks()
	return inst


## Evolve to star 2/3: increment star level, keep stacks/growth/theme_state.
## star_overrides가 있으면 template을 교체. template_id는 항상 base ID 유지.
func evolve_star() -> void:
	star_level = mini(star_level + 1, 3)
	var star_tmpl := CardDB.get_star_template(template_id, star_level)
	if not star_tmpl.is_empty():
		template = star_tmpl
	# Reset threshold for tenure-based cards (e.g., ne_awakening resets on merge)
	threshold_fired = false


func _init_stacks() -> void:
	stacks.clear()
	for comp in template.get("composition", []):
		var ut := UnitDB.get_unit(comp["unit_id"])
		if ut.is_empty():
			push_warning("Unknown unit: " + comp["unit_id"])
			continue
		stacks.append({
			"unit_type": ut,
			"count": comp["count"],
			"upgrade_atk_mult": 1.0,
			"upgrade_hp_mult": 1.0,
			"temp_atk": 0.0,
			"temp_atk_mult": 1.0,
			"temp_hp_mult": 1.0,
		})


# --- Growth calculation ---

func _growth_atk_for(stack: Dictionary) -> float:
	var pct := growth_atk_pct
	var tags: PackedStringArray = stack["unit_type"].get("tags", PackedStringArray())
	for tag in tag_growth_atk:
		if tag in tags:
			pct += tag_growth_atk[tag]
	return pct


func _growth_hp_for(stack: Dictionary) -> float:
	var pct := growth_hp_pct
	var tags: PackedStringArray = stack["unit_type"].get("tags", PackedStringArray())
	for tag in tag_growth_hp:
		if tag in tags:
			pct += tag_growth_hp[tag]
	return pct


# --- Effective stats ---

func eff_atk_for(stack: Dictionary) -> float:
	var base: float = stack["unit_type"]["atk"]
	var layer1 := 1.0 + _growth_atk_for(stack)
	var layer2: float = stack["upgrade_atk_mult"]
	return (base * layer1 * layer2) * stack["temp_atk_mult"] + stack["temp_atk"]


func eff_hp_for(stack: Dictionary) -> float:
	var base: float = stack["unit_type"]["hp"]
	var layer1 := 1.0 + _growth_hp_for(stack)
	var layer2: float = stack["upgrade_hp_mult"]
	var shield := base * shield_hp_pct
	return base * layer1 * layer2 * stack.get("temp_hp_mult", 1.0) + shield


func get_total_units() -> int:
	var total := 0
	for s in stacks:
		total += s["count"]
	return total


func get_total_atk() -> float:
	var total := 0.0
	for s in stacks:
		total += s["count"] * eff_atk_for(s)
	return total


func get_total_hp() -> float:
	var total := 0.0
	for s in stacks:
		total += s["count"] * eff_hp_for(s)
	return total


## Total Combat Power = Σ(count × ATK/AS × HP) across all stacks.
func get_total_cp() -> float:
	var total := 0.0
	for s in stacks:
		var as_val: float = maxf(s["unit_type"].get("attack_speed", 1.0), 0.01)
		total += s["count"] * eff_atk_for(s) / as_val * eff_hp_for(s)
	return total


# --- Actions ---

## 유닛 상한 (기본 60 + 커맨더 보너스).
func get_unit_cap() -> int:
	return BASE_UNIT_CAP + unit_cap_bonus


## 업그레이드 슬롯 상한 (기본 5 + 커맨더 보너스).
func get_max_upgrade_slots() -> int:
	return Enums.MAX_UPGRADE_SLOTS + upgrade_slot_bonus


## Add 1 unit (random type weighted by current count).
func spawn_random(rng: RandomNumberGenerator) -> bool:
	if stacks.is_empty() or get_total_units() >= get_unit_cap():
		return false
	var weights: Array[float] = []
	for s in stacks:
		weights.append(maxf(s["count"], 1.0))
	var chosen_idx := _weighted_choice(weights, rng)
	stacks[chosen_idx]["count"] += 1
	stats_changed.emit()
	return true


## 양성가 보너스 포함 스폰: 유닛 1기 추가 + bonus_chance 확률로 1기 동시 생성.
## 보너스 유닛은 이벤트를 방출하지 않음 (무한루프 방지).
func spawn_random_with_bonus(rng: RandomNumberGenerator, bonus_chance: float) -> bool:
	if not spawn_random(rng):
		return false
	if bonus_chance > 0.0 and rng.randf() < bonus_chance:
		if get_total_units() < get_unit_cap() and not stacks.is_empty():
			var weights: Array[float] = []
			for s in stacks:
				weights.append(maxf(s["count"], 1.0))
			var chosen_idx := _weighted_choice(weights, rng)
			stacks[chosen_idx]["count"] += 1
	return true




## Enhance card's growth modifier (Layer 1, card-level).
## tag_filter: null = all units, String = tag-specific.
## Returns number of matching stacks.
func enhance(tag_filter, atk_pct: float, hp_pct: float) -> int:
	if tag_filter == null:
		if atk_pct != 0.0:
			growth_atk_pct += atk_pct
		if hp_pct != 0.0:
			growth_hp_pct += hp_pct
		stats_changed.emit()
		return stacks.size()
	else:
		var tags: PackedStringArray
		if "," in str(tag_filter):
			tags = str(tag_filter).split(",")
		else:
			tags = PackedStringArray([str(tag_filter)])
		var match_count := 0
		for s in stacks:
			var ut_tags: PackedStringArray = s["unit_type"].get("tags", PackedStringArray())
			for t in tags:
				if t in ut_tags:
					match_count += 1
					break
		if match_count > 0:
			for tag in tags:
				if atk_pct != 0.0:
					tag_growth_atk[tag] = tag_growth_atk.get(tag, 0.0) + atk_pct
				if hp_pct != 0.0:
					tag_growth_hp[tag] = tag_growth_hp.get(tag, 0.0) + hp_pct
			stats_changed.emit()
		return match_count


## Multiplicative upgrade (Layer 2).
func multiply_stats(atk_pct: float, hp_pct: float) -> void:
	for s in stacks:
		s["upgrade_atk_mult"] *= (1.0 + atk_pct)
		s["upgrade_hp_mult"] *= (1.0 + hp_pct)
	stats_changed.emit()


## Apply temporary combat buff (cleared after combat).
func temp_buff(tag_filter, atk_pct: float) -> void:
	for s in stacks:
		if tag_filter != null:
			var ut_tags: PackedStringArray = s["unit_type"].get("tags", PackedStringArray())
			if str(tag_filter) not in ut_tags:
				continue
		s["temp_atk"] += s["unit_type"]["atk"] * atk_pct


## Apply temporary multiplicative combat buff.
func temp_mult_buff(atk_mult: float, hp_mult: float = 1.0) -> void:
	for s in stacks:
		s["temp_atk_mult"] *= atk_mult
		s["temp_hp_mult"] *= hp_mult


func clear_temp_buffs() -> void:
	for s in stacks:
		s["temp_atk"] = 0.0
		s["temp_atk_mult"] = 1.0
		s["temp_hp_mult"] = 1.0


## Add 1 copy of the strongest unit (by CP) in this card.
func breed_strongest() -> bool:
	if stacks.is_empty() or get_total_units() >= get_unit_cap():
		return false
	var best_idx := 0
	var best_cp := 0.0
	for i in stacks.size():
		var s: Dictionary = stacks[i]
		var ut: Dictionary = s["unit_type"]
		var as_val: float = maxf(ut["attack_speed"], 0.01)
		var cp: float = float(ut["atk"]) / as_val * float(ut["hp"])
		if cp > best_cp:
			best_cp = cp
			best_idx = i
	stacks[best_idx]["count"] += 1
	stats_changed.emit()
	return true


## Remove 1 copy of the weakest unit (by CP). Returns true if removed.
func remove_weakest_unit() -> bool:
	if stacks.is_empty() or get_total_units() <= 0:
		return false
	var worst_idx := 0
	var worst_cp := INF
	for i in stacks.size():
		var s: Dictionary = stacks[i]
		if s["count"] <= 0:
			continue
		var ut: Dictionary = s["unit_type"]
		var as_val: float = maxf(ut.get("attack_speed", 1.0), 0.01)
		var cp: float = float(ut["atk"]) / as_val * float(ut["hp"])
		if cp < worst_cp:
			worst_cp = cp
			worst_idx = i
	stacks[worst_idx]["count"] -= 1
	if stacks[worst_idx]["count"] <= 0:
		stacks.remove_at(worst_idx)
	stats_changed.emit()
	return true


## Get the base template ID. template_id는 항상 base ID.
func get_base_id() -> String:
	return template_id


## Add N units of a specific type. Creates new stack if needed.
## Returns actual count added.
func add_specific_unit(unit_id: String, count: int) -> int:
	var cap_remain := get_unit_cap() - get_total_units()
	if cap_remain <= 0:
		return 0
	var actual := mini(count, cap_remain)
	for s in stacks:
		if s["unit_type"].get("id", "") == unit_id:
			s["count"] += actual
			stats_changed.emit()
			return actual
	var ut := UnitDB.get_unit(unit_id)
	if ut.is_empty():
		return 0
	stacks.append({
		"unit_type": ut, "count": actual,
		"upgrade_atk_mult": 1.0, "upgrade_hp_mult": 1.0,
		"temp_atk": 0.0, "temp_atk_mult": 1.0, "temp_hp_mult": 1.0,
	})
	stats_changed.emit()
	return actual


## Remove up to N weakest units (by CP). Does NOT add any replacement.
## Returns actual number of units removed (can be less than N if card ran dry).
func remove_weakest(count: int) -> int:
	if count <= 0 or get_total_units() == 0:
		return 0
	var sorted_stacks: Array = []
	for i in stacks.size():
		var s: Dictionary = stacks[i]
		var ut: Dictionary = s["unit_type"]
		var as_val: float = maxf(ut["attack_speed"], 0.01)
		var cp: float = float(ut["atk"]) / as_val * float(ut["hp"])
		sorted_stacks.append({"idx": i, "cp": cp})
	sorted_stacks.sort_custom(func(a, b): return a["cp"] < b["cp"])
	var to_remove := count
	var removed := 0
	for entry in sorted_stacks:
		if to_remove <= 0:
			break
		var s: Dictionary = stacks[entry["idx"]]
		var take := mini(s["count"], to_remove)
		s["count"] -= take
		to_remove -= take
		removed += take
	stacks = stacks.filter(func(s): return s["count"] > 0)
	if removed > 0:
		stats_changed.emit()
	return removed


## Consume N weakest units (by CP), add 1 of strongest type.
## Returns true if metamorphosis succeeded.
func metamorphosis(consume_count: int) -> bool:
	if get_total_units() < consume_count + 1:
		return false
	# Identify strongest stack BEFORE removal (so we know where to add the result).
	var strongest_idx := 0
	var best_cp := -1.0
	for i in stacks.size():
		var ut: Dictionary = stacks[i]["unit_type"]
		var as_val: float = maxf(ut["attack_speed"], 0.01)
		var cp: float = float(ut["atk"]) / as_val * float(ut["hp"])
		if cp > best_cp:
			best_cp = cp
			strongest_idx = i
	var strongest_unit_type: Dictionary = stacks[strongest_idx]["unit_type"]
	remove_weakest(consume_count)
	# Re-find strongest stack post-removal (may have shifted) or add new stack.
	var found := false
	for i in stacks.size():
		if stacks[i]["unit_type"] == strongest_unit_type:
			stacks[i]["count"] += 1
			found = true
			break
	if not found:
		stacks.append({"unit_type": strongest_unit_type, "count": 1})
	stats_changed.emit()
	return true


func reset_round() -> void:
	activations_used = 0
	tenure += 1


func can_activate(bonus: int = 0) -> bool:
	var max_act: int = template.get("max_activations", -1)
	if max_act == -1:
		return true
	return activations_used < max_act + bonus


func get_name() -> String:
	return template.get("name", template_id)


func _to_string() -> String:
	return "%s(%du A%.0f H%.0f g+%.0f%%)" % [
		get_name(), get_total_units(), get_total_atk(), get_total_hp(),
		growth_atk_pct * 100.0
	]


# --- Upgrades ---


## Check if this card can receive another upgrade.
func can_attach_upgrade() -> bool:
	return upgrades.size() < get_max_upgrade_slots()


## Attach an upgrade by ID. Applies immediate stat mods.
## Returns true on success, false if slots full or unknown ID.
func attach_upgrade(upgrade_id: String) -> bool:
	if not can_attach_upgrade():
		return false
	var tmpl := UpgradeDB.get_upgrade(upgrade_id)
	if tmpl.is_empty():
		return false
	upgrades.append(tmpl)
	_apply_stat_mods(tmpl.get("stat_mods", {}))
	stats_changed.emit()
	return true


## Check if any attached upgrade has the given mechanic type.
func has_mechanic(mechanic_type: String) -> bool:
	for upg in upgrades:
		for m in upg.get("mechanics", []):
			if m.get("type", "") == mechanic_type:
				return true
	return false


## Get the first matching mechanic dict, or {} if not found.
func get_mechanic(mechanic_type: String) -> Dictionary:
	for upg in upgrades:
		for m in upg.get("mechanics", []):
			if m.get("type", "") == mechanic_type:
				return m
	return {}


## Get all mechanic dicts from all attached upgrades (flat array).
func get_all_mechanics() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for upg in upgrades:
		for m in upg.get("mechanics", []):
			result.append(m)
	return result


func _apply_stat_mods(mods: Dictionary) -> void:
	if mods.is_empty():
		return
	var atk_pct: float = mods.get("atk_pct", 0.0)
	var hp_pct: float = mods.get("hp_pct", 0.0)
	if atk_pct != 0.0 or hp_pct != 0.0:
		multiply_stats(atk_pct, hp_pct)
	upgrade_def += int(mods.get("def", 0))
	upgrade_range += int(mods.get("range", 0))
	upgrade_move_speed += int(mods.get("move_speed", 0))
	var as_m: float = mods.get("as_mult", 0.0)
	if as_m > 0.0:
		upgrade_as_mult *= as_m


# --- Utility ---


## 양성가 보너스 롤링: added개 유닛 각각 chance 확률로 보너스 1기.
## 보너스 총 수를 반환. 호출자가 add_specific_unit 등으로 적용.
static func roll_bonus_count(added: int, chance: float, rng: RandomNumberGenerator) -> int:
	if chance <= 0.0 or rng == null or added <= 0:
		return 0
	var bonus := 0
	for _i in added:
		if rng.randf() < chance:
			bonus += 1
	return bonus


func _weighted_choice(weights: Array[float], rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w in weights:
		total += w
	var r := rng.randf() * total
	var cumulative := 0.0
	for i in weights.size():
		cumulative += weights[i]
		if r <= cumulative:
			return i
	return weights.size() - 1
