# AUTO-GENERATED from data/cards/*.yaml — DO NOT EDIT
# Run: python3 scripts/codegen_card_db.py
extends Node
## Card database. Autoloaded as "CardDB".

var _templates: Dictionary = {}
var _theme_effects: Dictionary = {}  # card_id → {star_level → Array of effect dicts}
var _tier_cost := {1: 2, 2: 3, 3: 4, 4: 5, 5: 6}


func _ready() -> void:
	_register_steampunk()
	_register_neutral()
	_register_druid()
	_register_predator()
	_register_military()
	print("[CardDB] Registered %d cards." % _templates.size())


func get_template(id: String) -> Dictionary:
	return _templates.get(id, {})


## ★ 레벨별 템플릿 반환. base + star_overrides 병합.
## star_level <= 1 이면 기본 템플릿 반환.
func get_star_template(base_id: String, star_level: int) -> Dictionary:
	var base: Dictionary = _templates.get(base_id, {})
	if base.is_empty():
		return {}
	if star_level <= 1:
		return base.duplicate(true)
	var overrides: Dictionary = base.get("star_overrides", {})
	if not overrides.has(star_level):
		return base.duplicate(true)
	var result := base.duplicate(true)
	var ov: Dictionary = overrides[star_level]
	for key in ov:
		result[key] = ov[key]
	result.erase("star_overrides")
	return result

func get_all_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_templates.keys())
	return ids

func get_ids_by_theme(theme: int) -> Array[String]:
	var ids: Array[String] = []
	for id in _templates:
		if _templates[id].get("theme", -1) == theme:
			ids.append(id)
	return ids


## Theme system cards: per-star effect parameters from YAML DSL.
## Returns Array of dicts, each with "action" key + parameters.
func get_theme_effects(card_id: String, star_level: int) -> Array:
	var card_data: Dictionary = _theme_effects.get(card_id, {})
	return card_data.get(star_level, [])


## Compact card registration.
## effects: Array of Dicts, each with {action, target, ...params}
func _c(id: String, nm: String, tier: int, theme: int,
		comp: Array, timing: int, max_act: int,
		effects: Array, tags: PackedStringArray,
		l1: int = -1, l2: int = -1,
		require_other: bool = false, require_tenure: int = 0,
		is_threshold: bool = false,
		star_overrides: Dictionary = {}) -> void:
	_templates[id] = {
		"id": id, "name": nm, "tier": tier, "theme": theme,
		"composition": comp,
		"trigger_timing": timing,
		"trigger_layer1": l1, "trigger_layer2": l2,
		"require_other_card": require_other,
		"require_tenure": require_tenure,
		"is_threshold": is_threshold,
		"max_activations": max_act,
		"effects": effects,
		"cost": _tier_cost.get(tier, 3),
		"card_tags": tags,
		"star_overrides": star_overrides,
	}


## Star override dict builder.
func _star(nm: String, comp: Array, timing: int, max_act: int,
		effects: Array, tags: PackedStringArray,
		l1: int = -1, l2: int = -1,
		require_other: bool = false, require_tenure: int = 0,
		is_threshold: bool = false) -> Dictionary:
	return {
		"name": nm, "composition": comp,
		"trigger_timing": timing, "max_activations": max_act,
		"effects": effects, "card_tags": tags,
		"trigger_layer1": l1, "trigger_layer2": l2,
		"require_other_card": require_other,
		"require_tenure": require_tenure,
		"is_threshold": is_threshold,
	}


# --- Effect helpers ---
func _spawn(target: String, count: int = 1, ol1: int = Enums.Layer1.UNIT_ADDED, ol2: int = -1) -> Dictionary:
	return {"action": "spawn", "target": target, "spawn_count": count, "output_layer1": ol1, "output_layer2": ol2}

func _enhance(target: String, atk_pct: float, hp_pct: float = 0.0, tag: String = "", ol1: int = Enums.Layer1.ENHANCED, ol2: int = -1) -> Dictionary:
	return {"action": "enhance_pct", "target": target, "enhance_atk_pct": atk_pct, "enhance_hp_pct": hp_pct, "unit_tag_filter": tag, "output_layer1": ol1, "output_layer2": ol2}

func _buff(target: String, atk_pct: float, tag: String = "") -> Dictionary:
	return {"action": "buff_pct", "target": target, "buff_atk_pct": atk_pct, "unit_tag_filter": tag}

func _gold(amount: int) -> Dictionary:
	return {"action": "grant_gold", "target": "self", "gold_amount": amount}

func _shield(target: String, hp_pct: float) -> Dictionary:
	return {"action": "shield_pct", "target": target, "shield_hp_pct": hp_pct}



# ═══════════════════════════════════════════════════════════════════
# STEAMPUNK (10 cards)
# ═══════════════════════════════════════════════════════════════════
func _register_steampunk() -> void:
	var T := Enums.CardTheme.STEAMPUNK
	var BS := Enums.TriggerTiming.BATTLE_START
	var OE := Enums.TriggerTiming.ON_EVENT
	var PERSISTENT := Enums.TriggerTiming.PERSISTENT
	var REROLL := Enums.TriggerTiming.ON_REROLL
	var RS := Enums.TriggerTiming.ROUND_START
	var SELL := Enums.TriggerTiming.ON_SELL
	var UA := Enums.Layer1.UNIT_ADDED
	var MF := Enums.Layer2.MANUFACTURE
	var UP := Enums.Layer2.UPGRADE
	var EN := Enums.Layer1.ENHANCED
	var ass_comp := [{"unit_id":"sp_spider","count":2},{"unit_id":"sp_rat","count":1}]
	var ass_tags := PackedStringArray(["steampunk", "production"])
	_c("sp_assembly", "증기 조립소", 1, T,
		ass_comp, RS, -1,
		[_spawn("right_adj", 1, UA, MF)],
		ass_tags, -1, -1, false, 0, false, {
			2: _star("증기 조립소 ★2", ass_comp, RS, -1, [_spawn("both_adj", 1, UA, MF)], ass_tags),
			3: _star("증기 조립소 ★3", ass_comp, RS, -1, [_spawn("both_adj", 2, UA, MF),
					 _enhance("both_adj", 0.05, 0.0, "", EN, UP)], ass_tags),
		})

	var fur_comp := [{"unit_id":"sp_crab","count":1},{"unit_id":"sp_sawblade","count":1}]
	var fur_tags := PackedStringArray(["steampunk", "focus"])
	_c("sp_furnace", "증기 용광로", 1, T,
		fur_comp, RS, -1,
		[_spawn("self", 1, UA, MF),
			 _enhance("self", 0.03)],
		fur_tags, -1, -1, false, 0, false, {
			2: _star("증기 용광로 ★2", fur_comp, RS, -1, [_spawn("self", 2, UA, MF),
					 _enhance("self", 0.05)], fur_tags),
			3: {
				"name": "증기 용광로 ★3",
				"composition": fur_comp,
				"trigger_timing": RS, "max_activations": -1,
				"effects": [_spawn("self", 2, UA, MF),
					 _enhance("self", 0.05)],
				"card_tags": fur_tags,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_other_card": false, "require_tenure": 0,
				"is_threshold": false,
				"conditional_effects": [
					{"condition": "unit_count_gte", "threshold": 8,
					 "effects": [_enhance("self", 0.03)]},
				],
			},
		})

	var wor_comp := [{"unit_id":"sp_spider","count":2},{"unit_id":"sp_sawblade","count":1}]
	var wor_tags := PackedStringArray(["steampunk", "enhance"])
	_c("sp_workshop", "태엽 공방", 1, T,
		wor_comp, OE, 2,
		[_enhance("event_target", 0.05, 0.0, "gear", EN, UP)],
		wor_tags, UA, MF, false, 0, false, {
			2: _star("태엽 공방 ★2", wor_comp, OE, 2, [_enhance("event_target", 0.075, 0.0, "gear,electric", EN, UP)], wor_tags, UA, MF),
			3: _star("태엽 공방 ★3", wor_comp, OE, 4, [_enhance("event_target", 0.075, 0.0, "gear,electric", EN, UP),
					 _spawn("both_adj", 1, UA, MF)], wor_tags, UA, MF),
		})

	var cir_comp := [{"unit_id":"sp_sawblade","count":1},{"unit_id":"sp_scout","count":1}]
	var cir_tags := PackedStringArray(["steampunk", "cycle"])
	_c("sp_circulator", "증기 순환기", 2, T,
		cir_comp, OE, 1,
		[_spawn("event_target", 1, UA, MF)],
		cir_tags, -1, UP, false, 0, false, {
			2: _star("증기 순환기 ★2", cir_comp, OE, 2, [_spawn("event_target", 1, UA, MF)], cir_tags, -1, UP),
			3: _star("증기 순환기 ★3", cir_comp, OE, 3, [{"action": "spawn", "target": "event_target", "spawn_count": 1, "output_layer1": UA, "output_layer2": MF, "breed_strongest": true}], cir_tags, -1, UP),
		})

	var int_comp := [{"unit_id":"sp_scout","count":2},{"unit_id":"sp_rat","count":1}]
	var int_tags := PackedStringArray(["steampunk", "economy"])
	_c("sp_interest", "증기 이자기", 2, T,
		int_comp, REROLL, 3,
		[_spawn("self", 1, -1, -1),
			 _enhance("self", 0.03, 0.0, "", -1, -1)],
		int_tags, -1, -1, false, 0, false, {
			2: _star("증기 이자기 ★2", int_comp, REROLL, 3, [_spawn("self", 2, -1, -1),
					 _enhance("self", 0.05, 0.0, "", -1, -1)], int_tags),
			3: _star("증기 이자기 ★3", int_comp, REROLL, 3, [_spawn("self", 2, -1, -1),
					 _spawn("both_adj", 1, -1, -1),
					 _enhance("self", 0.05, 0.0, "", -1, -1)], int_tags),
		})

	var lin_comp := [{"unit_id":"sp_sawblade","count":2},{"unit_id":"sp_spider","count":1}]
	var lin_tags := PackedStringArray(["steampunk", "production"])
	_c("sp_line", "조립 라인", 3, T,
		lin_comp, OE, 3,
		[_spawn("both_adj", 1, UA, MF)],
		lin_tags, UA, MF, true, 0, false, {
			2: _star("조립 라인 ★2", lin_comp, OE, 4, [_spawn("both_adj", 2, UA, MF)], lin_tags, UA, MF, true),
			3: _star("조립 라인 ★3", lin_comp, OE, 4, [{"action": "spawn", "target": "both_adj", "spawn_count": 2, "output_layer1": UA, "output_layer2": MF, "breed_strongest": true}], lin_tags, UA, MF, true),
		})

	var bar_comp := [{"unit_id":"sp_titan","count":1},{"unit_id":"sp_crab","count":1}]
	var bar_tags := PackedStringArray(["steampunk", "defense"])
	_c("sp_barrier", "증기 방벽", 3, T,
		bar_comp, BS, -1,
		[_shield("self", 0.2)],
		bar_tags, -1, -1, false, 0, false, {
			2: _star("증기 방벽 ★2", bar_comp, BS, -1, [_shield("self", 0.4)], bar_tags),
			3: _star("증기 방벽 ★3", bar_comp, BS, -1, [_shield("all_allies", 0.4)], bar_tags),
		})

	var war_comp := [{"unit_id":"sp_turret","count":1},{"unit_id":"sp_cannon","count":1},{"unit_id":"sp_drone","count":2}]
	var war_tags := PackedStringArray(["steampunk", "combat"])
	_c("sp_warmachine", "전쟁 기계", 4, T,
		war_comp, PERSISTENT, -1,
		[],
		war_tags, -1, -1, false, 0, false, {
			2: _star("전쟁 기계 ★2", war_comp, PERSISTENT, -1, [], war_tags),
			3: _star("전쟁 기계 ★3", war_comp, PERSISTENT, -1, [], war_tags),
		})
	_theme_effects["sp_warmachine"] = {
		1: [{"action": "range_bonus", "tag": "firearm", "unit_thresh": 8}],
		2: [
			{"action": "range_bonus", "tag": "firearm", "unit_thresh": 6, "atk_buff_pct": 0.3},
		],
		3: [
			{"action": "range_bonus", "tag": "firearm", "unit_thresh": 4, "atk_buff_pct": 0.3, "attack_stack_pct": 0.12},
		],
	}

	var cha_comp := [{"unit_id":"sp_titan","count":1},{"unit_id":"sp_turret","count":1}]
	var cha_tags := PackedStringArray(["steampunk", "power"])
	_c("sp_charger", "태엽 과급기", 4, T,
		cha_comp, OE, -1,
		[],
		cha_tags, UA, MF, false, 0, false, {
			2: _star("태엽 과급기 ★2", cha_comp, OE, -1, [], cha_tags, UA, MF),
			3: _star("태엽 과급기 ★3", cha_comp, OE, -1, [], cha_tags, UA, MF),
		})
	_theme_effects["sp_charger"] = {
		1: [
			{"action": "counter_produce", "event": "MF", "threshold": 10, "rewards": {"terazin": 1, "enhance_atk_pct": 0.05}},
		],
		2: [
			{"action": "counter_produce", "event": "MF", "threshold": 10, "rewards": {"terazin": 1, "enhance_atk_pct": 0.05}},
			{"action": "rare_counter", "threshold": 20, "reward": "pending_rare_upgrade"},
		],
		3: [
			{"action": "counter_produce", "event": "MF", "threshold": 10, "rewards": {"terazin": 1, "enhance_atk_pct": 0.05}},
			{"action": "epic_counter", "threshold": 15, "reward": "pending_epic_upgrade"},
			{"action": "total_counter", "per_manufacture": 10, "reward_terazin": 1},
		],
	}

	var ars_comp := [{"unit_id":"sp_titan","count":1},{"unit_id":"sp_scorpion","count":1},{"unit_id":"sp_crab","count":1}]
	var ars_tags := PackedStringArray(["steampunk", "arsenal"])
	_c("sp_arsenal", "제국 병기창", 5, T,
		ars_comp, SELL, -1,
		[],
		ars_tags, -1, -1, false, 0, false, {
			2: _star("제국 병기창 ★2", ars_comp, SELL, -1, [], ars_tags),
			3: _star("제국 병기창 ★3", ars_comp, SELL, -1, [], ars_tags),
		})
	_theme_effects["sp_arsenal"] = {
		1: [{"action": "absorb", "target": "self", "count": 3}],
		2: [
			{"action": "absorb", "target": "self", "count": 5, "transfer_upgrades": true},
		],
		3: [
			{"action": "absorb", "target": "self", "count": 7, "majority_atk_bonus": 0.3},
		],
	}


# ═══════════════════════════════════════════════════════════════════
# NEUTRAL (15 cards)
# ═══════════════════════════════════════════════════════════════════
func _register_neutral() -> void:
	var T := Enums.CardTheme.NEUTRAL
	var BS := Enums.TriggerTiming.BATTLE_START
	var MERGE := Enums.TriggerTiming.ON_MERGE
	var OE := Enums.TriggerTiming.ON_EVENT
	var PCD := Enums.TriggerTiming.POST_COMBAT_DEFEAT
	var RS := Enums.TriggerTiming.ROUND_START
	var EN := Enums.Layer1.ENHANCED
	var UA := Enums.Layer1.UNIT_ADDED
	var PC := Enums.TriggerTiming.POST_COMBAT
	var ee_comp := [{"unit_id":"ne_scrap","count":2},{"unit_id":"ne_eagle","count":1}]
	var ee_tags := PackedStringArray(["neutral", "production"])
	_c("ne_earth_echo", "대지의 울림", 1, T,
		ee_comp, RS, -1,
		[_spawn("right_adj")],
		ee_tags, -1, -1, false, 0, false, {
			2: _star("대지의 울림 ★2", ee_comp, RS, -1, [_spawn("right_adj", 2)], ee_tags),
			3: _star("대지의 울림 ★3", ee_comp, RS, -1, [_spawn("both_adj", 2)], ee_tags),
		})

	var wp_comp := [{"unit_id":"ne_archer","count":1},{"unit_id":"ne_golem","count":1}]
	var wp_tags := PackedStringArray(["neutral", "enhance"])
	_c("ne_wild_pulse", "야생의 맥동", 1, T,
		wp_comp, RS, -1,
		[_enhance("self", 0.03)],
		wp_tags, -1, -1, false, 0, false, {
			2: _star("야생의 맥동 ★2", wp_comp, RS, -1, [_enhance("self", 0.05)], wp_tags),
			3: _star("야생의 맥동 ★3", wp_comp, RS, -1, [_enhance("self", 0.05),
					 _enhance("both_adj", 0.03)], wp_tags),
		})

	var rr_comp := [{"unit_id":"ne_guardian","count":1},{"unit_id":"ne_scrap","count":1}]
	var rr_tags := PackedStringArray(["neutral", "ancient"])
	_c("ne_ruin_resonance", "유적의 공명", 2, T,
		rr_comp, RS, -1,
		[_spawn("self"),
			 _enhance("self", 0.02)],
		rr_tags, -1, -1, false, 0, false, {
			2: _star("유적의 공명 ★2", rr_comp, RS, -1, [_spawn("self"),
					 _enhance("self", 0.04)], rr_tags),
			3: {
				"name": "유적의 공명 ★3",
				"composition": rr_comp,
				"trigger_timing": RS, "max_activations": -1,
				"effects": [_spawn("self", 2),
					 _enhance("self", 0.04)],
				"card_tags": rr_tags,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_other_card": false, "require_tenure": 0,
				"is_threshold": false,
				"conditional_effects": [
					{"condition": "unit_count_gte", "threshold": 8,
					 "effects": [_enhance("both_adj", 0.02)]},
				],
			},
		})

	var wan_comp := [{"unit_id":"ne_merc","count":1},{"unit_id":"ne_scrap","count":2}]
	var wan_tags := PackedStringArray(["neutral", "versatile"])
	_c("ne_wanderers", "떠돌이 무리", 2, T,
		wan_comp, OE, 2,
		[_enhance("event_target", 0.03)],
		wan_tags, UA, -1, false, 0, false, {
			2: _star("떠돌이 무리 ★2", wan_comp, OE, 2, [_enhance("event_target", 0.05)], wan_tags, UA, -1),
			3: _star("떠돌이 무리 ★3", wan_comp, OE, 3, [_enhance("event_target", 0.05),
					 _spawn("self")], wan_tags, UA, -1),
		})

	var ma_comp := [{"unit_id":"ne_beast","count":1},{"unit_id":"ne_mutant","count":1}]
	var ma_tags := PackedStringArray(["neutral", "mutant"])
	_c("ne_mutant_adapt", "돌연변이 적응", 3, T,
		ma_comp, OE, 2,
		[_spawn("self")],
		ma_tags, EN, -1, false, 0, false, {
			2: _star("돌연변이 적응 ★2", ma_comp, OE, 2, [_spawn("self", 2)], ma_tags, EN, -1),
			3: {
				"name": "돌연변이 적응 ★3",
				"composition": ma_comp,
				"trigger_timing": OE, "max_activations": 2,
				"effects": [_spawn("self", 2)],
				"card_tags": ma_tags,
				"trigger_layer1": EN, "trigger_layer2": -1,
				"require_other_card": false, "require_tenure": 0,
				"is_threshold": false,
				"conditional_effects": [
					{"condition": "unit_count_gte", "threshold": 10,
					 "effects": [_spawn("both_adj")]},
				],
			},
		})

	var mc_comp := [{"unit_id":"ne_spirit","count":1},{"unit_id":"ne_scrap","count":1}]
	var mc_tags := PackedStringArray(["neutral", "mana"])
	_c("ne_mana_crystal", "마력 결정", 2, T,
		mc_comp, OE, 2,
		[_spawn("both_adj")],
		mc_tags, UA, -1, false, 0, false, {
			2: _star("마력 결정 ★2", mc_comp, OE, 2, [_spawn("both_adj", 2)], mc_tags, UA, -1),
			3: _star("마력 결정 ★3", mc_comp, OE, 3, [_spawn("event_target"),
					 _spawn("both_adj", 2)], mc_tags, UA, -1),
		})

	var ac_comp := [{"unit_id":"ne_guardian","count":1},{"unit_id":"ne_spirit","count":1}]
	var ac_tags := PackedStringArray(["neutral", "ancient"])
	_c("ne_ancient_catalyst", "고대 촉매", 3, T,
		ac_comp, OE, 2,
		[_enhance("both_adj", 0.02)],
		ac_tags, EN, -1, false, 0, false, {
			2: _star("고대 촉매 ★2", ac_comp, OE, 2, [_enhance("both_adj", 0.03)], ac_tags, EN, -1),
			3: _star("고대 촉매 ★3", ac_comp, OE, 3, [_enhance("both_adj", 0.03),
					 _enhance("self", 0.03)], ac_tags, EN, -1),
		})

	var mer_comp := [{"unit_id":"ne_archer","count":1},{"unit_id":"ne_scrap","count":1}]
	var mer_tags := PackedStringArray(["neutral", "economy"])
	_c("ne_merchant", "방랑 상인", 1, T,
		mer_comp, PCD, 1,
		[_gold(3)],
		mer_tags, -1, -1, false, 0, false, {
			2: _star("방랑 상인 ★2", mer_comp, PCD, 1, [_gold(4),
					 {"action": "grant_terazin", "target": "self", "terazin_amount": 1}], mer_tags),
			3: _star("방랑 상인 ★3", mer_comp, PC, 1, [_gold(3),
					 _spawn("self")], mer_tags),
		})

	var sb_comp := [{"unit_id":"ne_spirit","count":2},{"unit_id":"ne_archer","count":1}]
	var sb_tags := PackedStringArray(["neutral", "mana"])
	_c("ne_spirit_blessing", "정령의 축복", 3, T,
		sb_comp, MERGE, 1,
		[{"action": "grant_terazin", "target": "self", "terazin_amount": 1},
			 _spawn("event_target", 2)],
		sb_tags, -1, -1, false, 0, false, {
			2: _star("정령의 축복 ★2", sb_comp, MERGE, 1, [{"action": "grant_terazin", "target": "self", "terazin_amount": 1},
					 _gold(2),
					 _spawn("event_target", 3)], sb_tags),
			3: _star("정령의 축복 ★3", sb_comp, MERGE, 1, [{"action": "grant_terazin", "target": "self", "terazin_amount": 1},
					 _gold(2),
					 _spawn("event_target", 3),
					 _spawn("all_allies")], sb_tags),
		})

	var scr_comp := [{"unit_id":"ne_scrap","count":3}]
	var scr_tags := PackedStringArray(["neutral", "economy", "scrap"])
	_c("ne_scrapyard", "폐품 상회", 2, T,
		scr_comp, RS, -1,
		[{"action": "scrap_adjacent", "target": "self", "scrap_count": 1, "reroll_gain": 1, "gold_per_unit": 0}],
		scr_tags, -1, -1, false, 0, false, {
			2: _star("폐품 상회 ★2", scr_comp, RS, -1, [{"action": "scrap_adjacent", "target": "self", "scrap_count": 2, "reroll_gain": 2, "gold_per_unit": 0}], scr_tags),
			3: _star("폐품 상회 ★3", scr_comp, RS, -1, [{"action": "scrap_adjacent", "target": "self", "scrap_count": 2, "reroll_gain": 2, "gold_per_unit": 1}], scr_tags),
		})

	var dm_comp := [{"unit_id":"ne_merc","count":1},{"unit_id":"ne_guardian","count":1}]
	var dm_tags := PackedStringArray(["neutral", "economy"])
	_c("ne_dim_merchant", "차원 행상인", 4, T,
		dm_comp, RS, -1,
		[{"action": "diversity_gold", "target": "self"}],
		dm_tags, -1, -1, false, 0, false, {
			2: _star("차원 행상인 ★2", dm_comp, RS, -1, [{"action": "diversity_gold", "target": "self", "gold_per_theme": 2}], dm_tags),
			3: _star("차원 행상인 ★3", dm_comp, RS, -1, [{"action": "diversity_gold", "target": "self", "gold_per_theme": 3, "terazin_threshold": 3, "terazin_per_theme": 1, "mercenary_spawn": 1}], dm_tags),
		})

	var wil_comp := [{"unit_id":"ne_beast","count":1},{"unit_id":"ne_chimera","count":1}]
	var wil_tags := PackedStringArray(["neutral", "combat"])
	_c("ne_wildforce", "야생의 힘", 2, T,
		wil_comp, BS, -1,
		[_buff("self", 0.1)],
		wil_tags, -1, -1, false, 0, false, {
			2: _star("야생의 힘 ★2", wil_comp, BS, -1, [_buff("self", 0.15)], wil_tags),
			3: {
				"name": "야생의 힘 ★3",
				"composition": wil_comp,
				"trigger_timing": BS, "max_activations": -1,
				"effects": [_buff("self", 0.15)],
				"card_tags": wil_tags,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_other_card": false, "require_tenure": 0,
				"is_threshold": false,
				"conditional_effects": [
					{"condition": "unit_count_lte", "threshold": 3,
					 "effects": [_buff("self", 0.15)]},
				],
			},
		})

	var cc_comp := [{"unit_id":"ne_chimera","count":1},{"unit_id":"ne_mutant","count":1}]
	var cc_tags := PackedStringArray(["neutral", "reversal"])
	_c("ne_chimera_cry", "키메라의 울부짖음", 3, T,
		cc_comp, PCD, 1,
		[_enhance("self", 0.08, 0.08)],
		cc_tags, -1, -1, false, 0, false, {
			2: _star("키메라의 울부짖음 ★2", cc_comp, PCD, 1, [_enhance("self", 0.12, 0.12)], cc_tags),
			3: _star("키메라의 울부짖음 ★3", cc_comp, PC, 1, [_enhance("self", 0.12, 0.12),
					 _spawn("both_adj", 2),
					 _shield("self", 0.15)], cc_tags),
		})

	var rui_comp := [{"unit_id":"ne_golem","count":1},{"unit_id":"ne_spirit","count":1}]
	var rui_tags := PackedStringArray(["neutral", "time"])
	_c("ne_ruins", "고대의 잔해", 2, T,
		rui_comp, RS, -1,
		[_gold(2),
			 _spawn("right_adj")],
		rui_tags, -1, -1, false, 2, false, {
			2: _star("고대의 잔해 ★2", rui_comp, RS, -1, [_gold(3),
					 _spawn("right_adj", 2)], rui_tags, -1, -1, false, 2),
			3: {
				"name": "고대의 잔해 ★3",
				"composition": rui_comp,
				"trigger_timing": RS, "max_activations": -1,
				"effects": [_gold(3),
					 _spawn("both_adj", 2)],
				"card_tags": rui_tags,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_other_card": false, "require_tenure": 2,
				"is_threshold": false,
				"conditional_effects": [
					{"condition": "tenure_gte", "threshold": 4,
					 "effects": [_spawn("both_adj")]},
				],
			},
		})

	var awa_comp := [{"unit_id":"ne_guardian","count":1},{"unit_id":"ne_golem","count":1}]
	var awa_tags := PackedStringArray(["neutral", "ancient"])
	_c("ne_awakening", "고대의 각성", 4, T,
		awa_comp, RS, -1,
		[_spawn("all_allies", 2),
			 _enhance("all_allies", 0.1),
			 _shield("all_allies", 0.2)],
		awa_tags, -1, -1, false, 4, true, {
			2: _star("고대의 각성 ★2", awa_comp, RS, -1, [_spawn("all_allies", 3),
					 _enhance("all_allies", 0.15),
					 _shield("all_allies", 0.3)], awa_tags, -1, -1, false, 4, true),
			3: {
				"name": "고대의 각성 ★3",
				"composition": awa_comp,
				"trigger_timing": RS, "max_activations": -1,
				"effects": [_spawn("all_allies", 3),
					 _enhance("all_allies", 0.15),
					 _shield("all_allies", 0.3)],
				"card_tags": awa_tags,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_other_card": false, "require_tenure": 4,
				"is_threshold": true,
				"post_threshold_effects": [_spawn("all_allies"), _shield("all_allies", 0.1)],
			},
		})


# ═══════════════════════════════════════════════════════════════════
# DRUID (10 cards)
# ═══════════════════════════════════════════════════════════════════
func _register_druid() -> void:
	var T := Enums.CardTheme.DRUID
	var BS := Enums.TriggerTiming.BATTLE_START
	var PC := Enums.TriggerTiming.POST_COMBAT
	var PERSISTENT := Enums.TriggerTiming.PERSISTENT
	var RS := Enums.TriggerTiming.ROUND_START
	var cra_comp := [{"unit_id":"dr_treant_y","count":1},{"unit_id":"dr_wolf","count":1}]
	var cra_tags := PackedStringArray(["druid", "creation"])
	_c("dr_cradle", "숲의 요람", 1, T,
		cra_comp, RS, -1,
		[],
		cra_tags, -1, -1, false, 0, false, {
			2: _star("숲의 요람 ★2", cra_comp, RS, -1, [], cra_tags),
			3: _star("숲의 요람 ★3", cra_comp, RS, -1, [], cra_tags),
		})
	_theme_effects["dr_cradle"] = {
		1: [
			{"action": "tree_add", "target": "self", "count": 1},
			{"action": "tree_add", "target": "right_adj", "count": 1},
		],
		2: [
			{"action": "tree_add", "target": "self", "count": 2},
			{"action": "tree_add", "target": "both_adj", "count": 1},
		],
		3: [
			{"action": "tree_add", "target": "self", "count": 3},
			{"action": "tree_add", "target": "both_adj", "count": 2},
		],
	}

	var lif_comp := [{"unit_id":"dr_boar","count":1},{"unit_id":"dr_wolf","count":1}]
	var lif_tags := PackedStringArray(["druid", "guardian"])
	_c("dr_lifebeat", "생명의 맥동", 1, T,
		lif_comp, BS, -1,
		[],
		lif_tags, -1, -1, false, 0, false, {
			2: _star("생명의 맥동 ★2", lif_comp, BS, -1, [], lif_tags),
			3: _star("생명의 맥동 ★3", lif_comp, BS, -1, [], lif_tags),
		})
	_theme_effects["dr_lifebeat"] = {
		1: [
			{"action": "tree_add", "target": "self", "count": 1},
			{"action": "tree_shield", "target": "self_and_both_adj", "base_pct": 0.05, "tree_scale_pct": 0.03, "low_unit": {"thresh": 3, "mult": 1.5}},
		],
		2: [
			{"action": "tree_add", "target": "self", "count": 1},
			{"action": "tree_shield", "target": "self_and_both_adj", "base_pct": 0.08, "tree_scale_pct": 0.04, "low_unit": {"thresh": 4, "mult": 1.5}},
		],
		3: [
			{"action": "tree_add", "target": "self", "count": 2},
			{"action": "tree_shield", "target": "all_druid", "base_pct": 0.08, "tree_scale_pct": 0.05, "low_unit": {"thresh": 5, "mult": 1.5}},
		],
	}

	var ori_comp := [{"unit_id":"dr_turtle","count":1},{"unit_id":"dr_vine","count":1}]
	var ori_tags := PackedStringArray(["druid", "breed"])
	_c("dr_origin", "오래된 근원", 2, T,
		ori_comp, RS, -1,
		[],
		ori_tags, -1, -1, false, 0, false, {
			2: _star("오래된 근원 ★2", ori_comp, RS, -1, [], ori_tags),
			3: _star("오래된 근원 ★3", ori_comp, RS, -1, [], ori_tags),
		})
	_theme_effects["dr_origin"] = {
		1: [
			{"action": "tree_add", "target": "self", "count": 1},
			{"action": "tree_absorb", "target": "adj_druids", "count": 1},
			{"action": "tree_breed", "target": "adj_or_self", "count": 1, "tree_thresh": 6, "penalty_pct": 0.04},
		],
		2: [
			{"action": "tree_add", "target": "self", "count": 1},
			{"action": "tree_absorb", "target": "adj_druids", "count": 2},
			{"action": "tree_breed", "target": "adj_or_self", "count": 2, "tree_thresh": 5, "penalty_pct": 0.03},
		],
		3: [
			{"action": "tree_add", "target": "self", "count": 2},
			{"action": "tree_absorb", "target": "adj_druids", "count": 2},
			{"action": "tree_breed", "target": "both_adj_or_self", "count": 2, "tree_thresh": 5, "penalty_pct": 0.0},
		],
	}

	var gra_comp := [{"unit_id":"dr_spore","count":1},{"unit_id":"dr_wolf","count":1}]
	var gra_tags := PackedStringArray(["druid", "economy"])
	_c("dr_grace", "숲의 은혜", 2, T,
		gra_comp, PC, -1,
		[],
		gra_tags, -1, -1, false, 0, false, {
			2: _star("숲의 은혜 ★2", gra_comp, PC, -1, [], gra_tags),
			3: _star("숲의 은혜 ★3", gra_comp, PC, -1, [], gra_tags),
		})
	_theme_effects["dr_grace"] = {
		1: [
			{"action": "tree_gold", "base_gold": 1, "tree_divisor": 3, "win_half": true, "terazin_thresh": 10, "terazin": 1},
		],
		2: [
			{"action": "tree_gold", "base_gold": 2, "tree_divisor": 3, "win_half": false, "terazin_thresh": 8, "terazin": 1},
		],
		3: [
			{"action": "tree_gold", "base_gold": 2, "tree_divisor": 3, "win_half": false, "terazin_thresh": 8, "terazin": 1},
		],
	}

	var ear_comp := [{"unit_id":"dr_turtle","count":1},{"unit_id":"dr_wolf","count":1}]
	var ear_tags := PackedStringArray(["druid", "earth"])
	_c("dr_earth", "대지의 축복", 2, T,
		ear_comp, RS, -1,
		[],
		ear_tags, -1, -1, false, 0, false, {
			2: _star("대지의 축복 ★2", ear_comp, RS, -1, [], ear_tags),
			3: _star("대지의 축복 ★3", ear_comp, RS, -1, [], ear_tags),
		})
	_theme_effects["dr_earth"] = {
		1: [
			{"action": "tree_add", "target": "self", "count": 1},
			{"action": "druid_unit_enhance", "target": "all_druid", "divisor": 5},
		],
		2: [
			{"action": "tree_add", "target": "self", "count": 1},
			{"action": "druid_unit_enhance", "target": "all_druid", "divisor": 4, "bonus_tiers": [{"unit_gte": 8, "bonus_pct": 0.02}, {"unit_gte": 12, "bonus_pct": 0.03}]},
		],
		3: [
			{"action": "tree_add", "target": "self", "count": 2},
			{"action": "druid_unit_enhance", "target": "all_druid", "divisor": 3, "bonus_tiers": [{"unit_gte": 8, "bonus_pct": 0.02}, {"unit_gte": 12, "bonus_pct": 0.03}]},
		],
	}

	var dee_comp := [{"unit_id":"dr_treant_a","count":1},{"unit_id":"dr_rootguard","count":1}]
	var dee_tags := PackedStringArray(["druid", "time"])
	_c("dr_deep", "뿌리깊은 자", 3, T,
		dee_comp, RS, -1,
		[],
		dee_tags, -1, -1, false, 0, false, {
			2: _star("뿌리깊은 자 ★2", dee_comp, RS, -1, [], dee_tags),
			3: _star("뿌리깊은 자 ★3", dee_comp, RS, -1, [], dee_tags),
		})
	_theme_effects["dr_deep"] = {
		1: [
			{"action": "tree_add", "target": "self", "count": 1},
			{"action": "tree_enhance", "target": "self", "base_pct": 0.008, "low_unit": {"thresh": 3, "pct": 0.012}, "tree_bonus": {"thresh": 10, "mult": 1.3}},
		],
		2: [
			{"action": "tree_add", "target": "self", "count": 1},
			{"action": "tree_enhance", "target": "self", "base_pct": 0.012, "low_unit": {"thresh": 3, "pct": 0.018}, "tree_bonus": {"thresh": 8, "mult": 1.3}},
		],
		3: [
			{"action": "tree_add", "target": "self", "count": 2},
			{"action": "tree_enhance", "target": "self", "base_pct": 0.012, "low_unit": {"thresh": 3, "pct": 0.018}, "tree_bonus": {"thresh": 8, "mult": 1.5}},
		],
	}

	var sc_comp := [{"unit_id":"dr_spore","count":1},{"unit_id":"dr_toad","count":1}]
	var sc_tags := PackedStringArray(["druid", "combat"])
	_c("dr_spore_cloud", "포자 구름", 3, T,
		sc_comp, BS, -1,
		[],
		sc_tags, -1, -1, false, 0, false, {
			2: _star("포자 구름 ★2", sc_comp, BS, -1, [], sc_tags),
			3: _star("포자 구름 ★3", sc_comp, BS, -1, [], sc_tags),
		})
	_theme_effects["dr_spore_cloud"] = {
		1: [
			{"action": "debuff_store", "stat": "as", "base_pct": 0.15, "tree_scale_pct": 0.015, "cap": 0.5},
		],
		2: [
			{"action": "debuff_store", "stat": "as", "base_pct": 0.2, "tree_scale_pct": 0.02, "cap": 0.5},
			{"action": "debuff_store", "stat": "atk", "base_pct": 0.2, "tree_scale_pct": 0.02, "cap": 0.5},
		],
		3: [
			{"action": "debuff_store", "stat": "as", "base_pct": 0.3, "tree_scale_pct": 0.025, "cap": 0.5},
			{"action": "debuff_store", "stat": "atk", "base_pct": 0.3, "tree_scale_pct": 0.02, "cap": 0.5},
		],
	}

	var wra_comp := [{"unit_id":"dr_spore","count":1},{"unit_id":"dr_boar","count":1}]
	var wra_tags := PackedStringArray(["druid", "combat"])
	_c("dr_wrath", "태고의 분노", 4, T,
		wra_comp, PERSISTENT, -1,
		[],
		wra_tags, -1, -1, false, 0, false, {
			2: _star("태고의 분노 ★2", wra_comp, PERSISTENT, -1, [], wra_tags),
			3: _star("태고의 분노 ★3", wra_comp, PERSISTENT, -1, [], wra_tags),
		})
	_theme_effects["dr_wrath"] = {
		1: [
			{"action": "tree_temp_buff", "target": "self", "unit_cap": 5, "atk_base_pct": 0.8, "atk_tree_pct": 0.05},
		],
		2: [
			{"action": "tree_temp_buff", "target": "self", "unit_cap": 6, "atk_base_pct": 1.2, "atk_tree_pct": 0.08, "hp_pct": 0.6},
		],
		3: [
			{"action": "tree_temp_buff", "target": "self", "unit_cap": 7, "atk_mult": 1.5, "hp_mult": 1.3, "kill_hp_recover": true},
		],
	}

	var wr_comp := [{"unit_id":"dr_treant_a","count":1},{"unit_id":"dr_turtle","count":1}]
	var wr_tags := PackedStringArray(["druid", "ancient"])
	_c("dr_wt_root", "세계수의 뿌리", 4, T,
		wr_comp, RS, -1,
		[],
		wr_tags, -1, -1, false, 0, false, {
			2: _star("세계수의 뿌리 ★2", wr_comp, RS, -1, [], wr_tags),
			3: _star("세계수의 뿌리 ★3", wr_comp, RS, -1, [], wr_tags),
		})
	_theme_effects["dr_wt_root"] = {
		1: [
			{"action": "tree_add", "target": "self", "count": 1},
			{"action": "tree_distribute", "target": "all_other_druid", "tiers": [{"tree_gte": 4, "amount": 1}, {"tree_gte": 8, "amount": 2}]},
		],
		2: [
			{"action": "tree_add", "target": "self", "count": 1},
			{"action": "tree_distribute", "target": "all_other_druid", "tiers": [{"tree_gte": 3, "amount": 1}, {"tree_gte": 6, "amount": 2}]},
		],
		3: [
			{"action": "tree_add", "target": "self", "count": 2},
			{"action": "tree_distribute", "target": "all_other_druid", "tiers": [{"tree_gte": 3, "amount": 1}, {"tree_gte": 6, "amount": 2}]},
			{"action": "epic_shop_unlock", "tree_thresh": 8},
		],
	}

	var wor_comp := [{"unit_id":"dr_treant_a","count":1},{"unit_id":"dr_turtle","count":1},{"unit_id":"dr_spirit","count":1}]
	var wor_tags := PackedStringArray(["druid", "worldtree"])
	_c("dr_world", "세계수", 5, T,
		wor_comp, RS, -1,
		[],
		wor_tags, -1, -1, false, 0, false, {
			2: _star("세계수 ★2", wor_comp, RS, -1, [], wor_tags),
			3: _star("세계수 ★3", wor_comp, RS, -1, [], wor_tags),
		})
	_theme_effects["dr_world"] = {
		1: [
			{"action": "tree_add", "target": "self", "count": 2},
			{"action": "tree_add", "target": "all_other_druid", "count": 1},
			{"action": "multiply_stats", "target": "self", "atk_base": 1.1, "atk_per_tree": 0.1, "atk_tree_step": 30, "hp_base": 1.05, "hp_per_tree": 0.05, "hp_tree_step": 30, "as_base": 1.05, "as_per_tree": 0.05, "as_tree_step": 30, "unit_cap": 20},
		],
		2: [
			{"action": "tree_add", "target": "self", "count": 3},
			{"action": "tree_add", "target": "all_other_druid", "count": 2},
			{"action": "multiply_stats", "target": "self", "atk_base": 1.15, "atk_per_tree": 0.1, "atk_tree_step": 20, "unit_cap": 40},
		],
		3: [
			{"action": "tree_add", "target": "self", "count": 3},
			{"action": "tree_add", "target": "all_other_druid", "count": 2},
			{"action": "multiply_stats", "target": "self", "atk_base": 1.3, "atk_per_tree": 0.1, "atk_tree_step": 10, "unit_cap": 200},
		],
	}


# ═══════════════════════════════════════════════════════════════════
# PREDATOR (10 cards)
# ═══════════════════════════════════════════════════════════════════
func _register_predator() -> void:
	var T := Enums.CardTheme.PREDATOR
	var BS := Enums.TriggerTiming.BATTLE_START
	var OE := Enums.TriggerTiming.ON_EVENT
	var PC := Enums.TriggerTiming.POST_COMBAT
	var RS := Enums.TriggerTiming.ROUND_START
	var HA := Enums.Layer2.HATCH
	var MT := Enums.Layer2.METAMORPHOSIS
	var nes_comp := [{"unit_id":"pr_larva","count":3},{"unit_id":"pr_worker","count":1}]
	var nes_tags := PackedStringArray(["predator", "hatch"])
	_c("pr_nest", "유충 둥지", 1, T,
		nes_comp, RS, -1,
		[],
		nes_tags, -1, -1, false, 0, false, {
			2: _star("유충 둥지 ★2", nes_comp, RS, -1, [], nes_tags),
			3: _star("유충 둥지 ★3", nes_comp, RS, -1, [], nes_tags),
		})
	_theme_effects["pr_nest"] = {
		1: [
			{"action": "hatch", "target": "self", "count": 2},
			{"action": "hatch", "target": "right_adj", "count": 1},
		],
		2: [
			{"action": "hatch", "target": "self", "count": 4},
			{"action": "hatch", "target": "right_adj", "count": 2},
		],
		3: [
			{"action": "hatch", "target": "self", "count": 4},
			{"action": "hatch", "target": "both_adj", "count": 2},
		],
	}

	var far_comp := [{"unit_id":"pr_sniper","count":1},{"unit_id":"pr_spider","count":1}]
	var far_tags := PackedStringArray(["predator", "economy"])
	_c("pr_farm", "독 양식장", 1, T,
		far_comp, RS, -1,
		[],
		far_tags, -1, -1, false, 0, false, {
			2: _star("독 양식장 ★2", far_comp, RS, -1, [], far_tags),
			3: _star("독 양식장 ★3", far_comp, RS, -1, [], far_tags),
		})
	_theme_effects["pr_farm"] = {
		1: [
			{"action": "hatch", "target": "self", "count": 1},
			{"action": "economy", "gold_base": 0, "gold_per": 0.2, "gold_per_unit": "units", "halve_on_loss": true, "max_gold": 3},
		],
		2: [
			{"action": "hatch", "target": "self", "count": 1},
			{"action": "economy", "gold_base": 0, "gold_per": 0.2, "gold_per_unit": "units", "halve_on_loss": false, "max_gold": 5},
		],
		3: [
			{"action": "hatch", "target": "self", "count": 2},
			{"action": "economy", "gold_base": 0, "gold_per": 0.2, "gold_per_unit": "units", "halve_on_loss": false, "max_gold": 7, "terazin": {"condition": "always", "amount": 1}},
		],
	}

	var mol_comp := [{"unit_id":"pr_larva","count":2},{"unit_id":"pr_guardian","count":1}]
	var mol_tags := PackedStringArray(["predator", "metamorphosis"])
	_c("pr_molt", "탈피의 방", 2, T,
		mol_comp, OE, 2,
		[],
		mol_tags, -1, HA, false, 0, false, {
			2: _star("탈피의 방 ★2", mol_comp, OE, 2, [], mol_tags, -1, HA),
			3: _star("탈피의 방 ★3", mol_comp, OE, 2, [], mol_tags, -1, HA),
		})
	_theme_effects["pr_molt"] = {
		1: [{"action": "meta_consume", "consume": 3}],
		2: [{"action": "meta_consume", "consume": 2}],
		3: [
			{"action": "meta_consume", "consume": 2},
			{"action": "enhance", "target": "self", "atk_pct": 0.05},
		],
	}

	var ss_comp := [{"unit_id":"pr_spider","count":2},{"unit_id":"pr_larva","count":1}]
	var ss_tags := PackedStringArray(["predator", "combat"])
	_c("pr_swarm_sense", "군체 감각", 2, T,
		ss_comp, BS, -1,
		[],
		ss_tags, -1, -1, false, 0, false, {
			2: _star("군체 감각 ★2", ss_comp, BS, -1, [], ss_tags),
			3: _star("군체 감각 ★3", ss_comp, BS, -1, [], ss_tags),
		})
	_theme_effects["pr_swarm_sense"] = {
		1: [
			{"action": "swarm_buff", "target": "all_predator", "atk_per_unit": 0.1, "per_n": 3},
		],
		2: [
			{"action": "swarm_buff", "target": "all_predator", "atk_per_unit": 0.12, "per_n": 3},
		],
		3: [
			{"action": "swarm_buff", "target": "all_predator", "atk_per_unit": 0.12, "per_n": 2},
		],
	}

	var har_comp := [{"unit_id":"pr_spider","count":1},{"unit_id":"pr_sniper","count":1}]
	var har_tags := PackedStringArray(["predator", "economy"])
	_c("pr_harvest", "변태 수확", 2, T,
		har_comp, OE, 1,
		[],
		har_tags, -1, MT, false, 0, false, {
			2: _star("변태 수확 ★2", har_comp, OE, 1, [], har_tags, -1, MT),
			3: _star("변태 수확 ★3", har_comp, OE, 1, [], har_tags, -1, MT),
		})
	_theme_effects["pr_harvest"] = {
		1: [
			{"action": "terazin", "value": 1},
			{"action": "hatch", "target": "self", "count": 1},
		],
		2: [
			{"action": "terazin", "value": 1},
			{"action": "hatch", "target": "self", "count": 1},
			{"action": "enhance", "target": "event_source", "atk_pct": 0.05},
		],
		3: [
			{"action": "terazin", "value": 1},
			{"action": "hatch", "target": "self", "count": 2},
			{"action": "enhance", "target": "all_predator", "atk_pct": 0.03},
		],
	}

	var que_comp := [{"unit_id":"pr_queen","count":1},{"unit_id":"pr_worker","count":2},{"unit_id":"pr_larva","count":2}]
	var que_tags := PackedStringArray(["predator", "hatch"])
	_c("pr_queen", "여왕의 산란", 3, T,
		que_comp, RS, -1,
		[],
		que_tags, -1, -1, false, 0, false, {
			2: _star("여왕의 산란 ★2", que_comp, RS, -1, [], que_tags),
			3: _star("여왕의 산란 ★3", que_comp, RS, -1, [], que_tags),
		})
	_theme_effects["pr_queen"] = {
		1: [
			{"action": "hatch", "target": "self", "count": 3},
			{"action": "hatch", "target": "right_adj", "count": 1},
		],
		2: [
			{"action": "hatch", "target": "self", "count": 4},
			{"action": "hatch", "target": "both_adj", "count": 2},
		],
		3: [
			{"action": "hatch", "target": "self", "count": 5},
			{"action": "hatch", "target": "both_adj", "count": 3},
		],
	}

	var car_comp := [{"unit_id":"pr_charger","count":1},{"unit_id":"pr_warrior","count":1},{"unit_id":"pr_worker","count":1}]
	var car_tags := PackedStringArray(["predator", "enhance"])
	_c("pr_carapace", "적응 갑각", 3, T,
		car_comp, OE, 2,
		[],
		car_tags, -1, MT, false, 0, false, {
			2: _star("적응 갑각 ★2", car_comp, OE, 2, [], car_tags, -1, MT),
			3: _star("적응 갑각 ★3", car_comp, OE, 2, [], car_tags, -1, MT),
		})
	_theme_effects["pr_carapace"] = {
		1: [
			{"action": "enhance", "target": "tag:carapace", "atk_pct": 0.05, "hp_pct": 0.05},
			{"action": "hatch", "target": "right_adj", "count": 1},
		],
		2: [
			{"action": "enhance", "target": "tag:carapace", "atk_pct": 0.07, "hp_pct": 0.07},
			{"action": "hatch", "target": "right_adj", "count": 1},
		],
		3: [
			{"action": "enhance", "target": "all_predator", "atk_pct": 0.07, "hp_pct": 0.07},
			{"action": "hatch", "target": "both_adj", "count": 1},
			{"action": "shield", "target": "event_source", "hp_pct": 0.2},
		],
	}

	var par_comp := [{"unit_id":"pr_flyer","count":2},{"unit_id":"pr_sniper","count":1}]
	var par_tags := PackedStringArray(["predator", "combat"])
	_c("pr_parasite", "기생 진화", 4, T,
		par_comp, PC, -1,
		[],
		par_tags, -1, -1, false, 0, false, {
			2: _star("기생 진화 ★2", par_comp, PC, -1, [], par_tags),
			3: _star("기생 진화 ★3", par_comp, PC, -1, [], par_tags),
		})
	_theme_effects["pr_parasite"] = {
		1: [
			{"action": "hatch_scaled", "target": "self", "per_units": 1, "cap": 3},
			{"action": "on_combat_result", "condition": "victory", "effects": [{"action": "meta_consume", "consume": 2}]},
		],
		2: [
			{"action": "hatch_scaled", "target": "self", "per_units": 2, "cap": 5},
			{"action": "on_combat_result", "condition": "victory", "effects": [{"action": "meta_consume", "consume": 2}, {"action": "enhance", "target": "self", "hp_pct": 0.15}]},
		],
		3: [
			{"action": "hatch_scaled", "target": "self", "per_units": 2, "cap": 5},
			{"action": "on_combat_result", "condition": "always", "effects": [{"action": "meta_consume", "consume": 2}, {"action": "enhance", "target": "self", "hp_pct": 0.2}, {"action": "shield", "target": "self", "hp_pct": 0.3}]},
		],
	}

	var ah_comp := [{"unit_id":"pr_apex","count":1},{"unit_id":"pr_charger","count":1}]
	var ah_tags := PackedStringArray(["predator", "predation"])
	_c("pr_apex_hunt", "포식자의 사냥", 4, T,
		ah_comp, OE, 1,
		[],
		ah_tags, -1, MT, false, 0, false, {
			2: _star("포식자의 사냥 ★2", ah_comp, OE, 2, [], ah_tags, -1, MT),
			3: _star("포식자의 사냥 ★3", ah_comp, OE, 2, [], ah_tags, -1, MT),
		})
	_theme_effects["pr_apex_hunt"] = {
		1: [
			{"action": "meta_consume", "consume": 2},
			{"action": "conditional", "condition": "unit_count_lte", "threshold": 5, "effects": [{"action": "buff", "target": "self", "atk_pct": 0.3}]},
		],
		2: [
			{"action": "meta_consume", "consume": 2},
			{"action": "conditional", "condition": "unit_count_lte", "threshold": 5, "effects": [{"action": "buff", "target": "self", "atk_pct": 0.5}]},
		],
		3: [
			{"action": "meta_consume", "consume": 1},
			{"action": "conditional", "condition": "unit_count_lte", "threshold": 5, "effects": [{"action": "buff", "target": "self", "atk_mult": 2.0}]},
		],
	}

	var tra_comp := [{"unit_id":"pr_apex","count":1},{"unit_id":"pr_queen","count":1},{"unit_id":"pr_guardian","count":1}]
	var tra_tags := PackedStringArray(["predator", "swarm"])
	_c("pr_transcend", "군체 초월", 5, T,
		tra_comp, RS, -1,
		[],
		tra_tags, -1, -1, false, 0, false, {
			2: _star("군체 초월 ★2", tra_comp, RS, -1, [], tra_tags),
			3: _star("군체 초월 ★3", tra_comp, RS, -1, [], tra_tags),
		})
	_theme_effects["pr_transcend"] = {
		1: [
			{"action": "hatch", "target": "self", "count": 3},
			{"action": "hatch", "target": "all_predator", "count": 1},
			{"action": "persistent", "death_atk_bonus": 0.03, "kill_hp_recover": 0.1},
		],
		2: [
			{"action": "hatch", "target": "self", "count": 4},
			{"action": "hatch", "target": "all_predator", "count": 2},
			{"action": "persistent", "death_atk_bonus": 0.05, "kill_hp_recover": 0.15},
		],
		3: [
			{"action": "hatch", "target": "self", "count": 4},
			{"action": "hatch", "target": "all_predator", "count": 2},
			{"action": "meta_consume", "consume": 1},
			{"action": "enhance", "target": "self", "atk_pct": 0.05},
			{"action": "persistent", "death_atk_bonus": 0.05, "kill_hp_recover": 0.15},
		],
	}


# ═══════════════════════════════════════════════════════════════════
# MILITARY (10 cards)
# ═══════════════════════════════════════════════════════════════════
func _register_military() -> void:
	var T := Enums.CardTheme.MILITARY
	var BS := Enums.TriggerTiming.BATTLE_START
	var OE := Enums.TriggerTiming.ON_EVENT
	var PC := Enums.TriggerTiming.POST_COMBAT
	var RS := Enums.TriggerTiming.ROUND_START
	var CO := Enums.Layer2.CONSCRIPT
	var TR := Enums.Layer2.TRAIN
	var bar_comp := [{"unit_id":"ml_recruit","count":2},{"unit_id":"ml_infantry","count":1}]
	var bar_tags := PackedStringArray(["military", "training"])
	_c("ml_barracks", "신병 훈련소", 1, T,
		bar_comp, RS, -1,
		[],
		bar_tags, -1, -1, false, 0, false, {
			2: _star("신병 훈련소 ★2", bar_comp, RS, -1, [], bar_tags),
			3: _star("신병 훈련소 ★3", bar_comp, RS, -1, [], bar_tags),
		})
	_theme_effects["ml_barracks"] = {
		1: [
			{"action": "train", "target": "self", "amount": 1},
			{"action": "train", "target": "both_adj", "amount": 1},
			{"action": "rank_threshold", "tiers": [{"rank": 3, "unit": "ml_infantry", "count": 1}, {"rank": 5, "unit": "ml_plasma", "count": 1}, {"rank": 8, "unit": "ml_walker", "count": 1}]},
		],
		2: [
			{"action": "train", "target": "self", "amount": 2},
			{"action": "train", "target": "both_adj", "amount": 1},
			{"action": "rank_threshold", "tiers": [{"rank": 3, "unit": "ml_infantry", "count": 1}, {"rank": 5, "unit": "ml_plasma", "count": 1}, {"rank": 8, "unit": "ml_walker", "count": 1}]},
		],
		3: [
			{"action": "train", "target": "self", "amount": 2},
			{"action": "train", "target": "both_adj", "amount": 1},
			{"action": "rank_threshold", "tiers": [{"rank": 3, "unit": "ml_infantry", "count": 1}, {"rank": 5, "unit": "ml_plasma", "count": 1}, {"rank": 8, "unit": "ml_walker", "count": 1}]},
		],
	}

	var out_comp := [{"unit_id":"ml_recruit","count":3},{"unit_id":"ml_drone","count":1}]
	var out_tags := PackedStringArray(["military", "frontline"])
	_c("ml_outpost", "전진 기지", 1, T,
		out_comp, RS, -1,
		[],
		out_tags, -1, -1, false, 0, false, {
			2: _star("전진 기지 ★2", out_comp, RS, -1, [], out_tags),
			3: _star("전진 기지 ★3", out_comp, RS, -1, [], out_tags),
		})
	_theme_effects["ml_outpost"] = {
		1: [{"action": "conscript", "target": "self", "count": 2}],
		2: [
			{"action": "conscript", "target": "self", "count": 2},
			{"action": "conscript", "target": "right_adj", "count": 1},
		],
		3: [
			{"action": "conscript", "target": "self", "count": 3},
			{"action": "conscript", "target": "both_adj", "count": 1},
		],
	}

	var aca_comp := [{"unit_id":"ml_commander","count":1},{"unit_id":"ml_infantry","count":1}]
	var aca_tags := PackedStringArray(["military", "training"])
	_c("ml_academy", "군사 학교", 2, T,
		aca_comp, OE, 2,
		[],
		aca_tags, -1, TR, false, 0, false, {
			2: _star("군사 학교 ★2", aca_comp, OE, 2, [], aca_tags, -1, TR),
			3: _star("군사 학교 ★3", aca_comp, OE, 3, [], aca_tags, -1, TR),
		})
	_theme_effects["ml_academy"] = {
		1: [{"action": "train", "target": "event_target", "amount": 1}],
		2: [
			{"action": "train", "target": "event_target", "amount": 1},
			{"action": "enhance", "target": "event_target", "atk_pct": 0.02},
		],
		3: [
			{"action": "train", "target": "event_target", "amount": 2},
			{"action": "enhance", "target": "event_target", "atk_pct": 0.03},
		],
	}

	var con_comp := [{"unit_id":"ml_recruit","count":2},{"unit_id":"ml_shield","count":1}]
	var con_tags := PackedStringArray(["military", "conscript"])
	_c("ml_conscript", "징병국", 2, T,
		con_comp, OE, 2,
		[],
		con_tags, -1, CO, false, 0, false, {
			2: _star("징병국 ★2", con_comp, OE, 3, [], con_tags, -1, CO),
			3: _star("징병국 ★3", con_comp, OE, 3, [], con_tags, -1, CO),
		})
	_theme_effects["ml_conscript"] = {
		1: [{"action": "conscript", "target": "event_target", "count": 1}],
		2: [{"action": "conscript", "target": "event_target", "count": 2}],
		3: [{"action": "conscript", "target": "event_target", "count": 2}],
	}

	var sup_comp := [{"unit_id":"ml_drone","count":1},{"unit_id":"ml_biker","count":1}]
	var sup_tags := PackedStringArray(["military", "supply"])
	_c("ml_supply", "보급 부대", 2, T,
		sup_comp, PC, -1,
		[],
		sup_tags, -1, -1, false, 0, false, {
			2: _star("보급 부대 ★2", sup_comp, PC, -1, [], sup_tags),
			3: _star("보급 부대 ★3", sup_comp, PC, -1, [], sup_tags),
		})
	_theme_effects["ml_supply"] = {
		1: [
			{"action": "economy", "gold_base": 1, "gold_per": 0.5, "gold_per_unit": "cards", "halve_on_loss": true},
		],
		2: [
			{"action": "economy", "gold_base": 2, "gold_per": 1.0, "gold_per_unit": "cards", "halve_on_loss": false},
		],
		3: [
			{"action": "economy", "gold_base": 2, "gold_per": 1.0, "gold_per_unit": "cards", "halve_on_loss": false, "terazin": {"condition": "rank_gte", "thresh": 5, "amount": 1}},
		],
	}

	var tac_comp := [{"unit_id":"ml_commander","count":1},{"unit_id":"ml_plasma","count":1}]
	var tac_tags := PackedStringArray(["military", "command"])
	_c("ml_tactical", "전술 사령부", 3, T,
		tac_comp, BS, -1,
		[],
		tac_tags, -1, -1, false, 0, false, {
			2: _star("전술 사령부 ★2", tac_comp, BS, -1, [], tac_tags),
			3: _star("전술 사령부 ★3", tac_comp, BS, -1, [], tac_tags),
		})
	_theme_effects["ml_tactical"] = {
		1: [
			{"action": "rank_buff", "target": "all_military", "shield_per_rank": 0.02, "atk_per_unit": 0.005},
		],
		2: [
			{"action": "rank_buff", "target": "all_military", "shield_per_rank": 0.03, "atk_per_unit": 0.008},
		],
		3: [
			{"action": "rank_buff", "target": "all_military", "shield_per_rank": 0.04, "atk_per_unit": 0.01},
		],
	}

	var ass_comp := [{"unit_id":"ml_biker","count":2},{"unit_id":"ml_recruit","count":1}]
	var ass_tags := PackedStringArray(["military", "assault"])
	_c("ml_assault", "돌격 편대", 3, T,
		ass_comp, BS, -1,
		[],
		ass_tags, -1, -1, false, 0, false, {
			2: _star("돌격 편대 ★2", ass_comp, BS, -1, [], ass_tags),
			3: _star("돌격 편대 ★3", ass_comp, BS, -1, [], ass_tags),
		})
	_theme_effects["ml_assault"] = {
		1: [
			{"action": "swarm_buff", "target": "all_military", "atk_per_unit": 0.01, "ms_bonus": {"unit_thresh": 15, "bonus": 1}},
		],
		2: [
			{"action": "swarm_buff", "target": "all_military", "atk_per_unit": 0.015, "ms_bonus": {"unit_thresh": 12, "bonus": 1}},
		],
		3: [
			{"action": "swarm_buff", "target": "all_military", "atk_per_unit": 0.02, "ms_bonus": {"unit_thresh": 10, "bonus": 1}},
		],
	}

	var so_comp := [{"unit_id":"ml_sniper","count":1},{"unit_id":"ml_walker","count":1}]
	var so_tags := PackedStringArray(["military", "elite"])
	_c("ml_special_ops", "특수 작전대", 4, T,
		so_comp, RS, -1,
		[],
		so_tags, -1, -1, false, 0, false, {
			2: _star("특수 작전대 ★2", so_comp, RS, -1, [], so_tags),
			3: _star("특수 작전대 ★3", so_comp, RS, -1, [], so_tags),
		})
	_theme_effects["ml_special_ops"] = {
		1: [
			{"action": "train", "target": "self", "amount": 1},
			{"action": "train", "target": "both_adj", "amount": 1},
			{"action": "rank_threshold", "tiers": [{"rank": 8, "unit": "ml_commander", "count": 1}]},
		],
		2: [
			{"action": "train", "target": "self", "amount": 1},
			{"action": "train", "target": "both_adj", "amount": 1},
			{"action": "rank_threshold", "tiers": [{"rank": 6, "unit": "ml_commander", "count": 1}]},
		],
		3: [
			{"action": "train", "target": "self", "amount": 1},
			{"action": "train", "target": "both_adj", "amount": 1},
			{"action": "rank_threshold", "tiers": [{"rank": 5, "unit": "ml_commander", "count": 2}]},
		],
	}

	var fac_comp := [{"unit_id":"ml_artillery","count":1},{"unit_id":"ml_sniper","count":1}]
	var fac_tags := PackedStringArray(["military", "supply"])
	_c("ml_factory", "군수 공장", 4, T,
		fac_comp, OE, -1,
		[],
		fac_tags, -1, CO, false, 0, false, {
			2: _star("군수 공장 ★2", fac_comp, OE, -1, [], fac_tags, -1, CO),
			3: _star("군수 공장 ★3", fac_comp, OE, -1, [], fac_tags, -1, CO),
		})
	_theme_effects["ml_factory"] = {
		1: [
			{"action": "counter_produce", "event": "CO", "threshold": 10, "rewards": {"terazin": 1}},
		],
		2: [
			{"action": "counter_produce", "event": "CO", "threshold": 8, "rewards": {"terazin": 1, "enhance_atk_pct": 0.03}},
		],
		3: [
			{"action": "counter_produce", "event": "CO", "threshold": 6, "rewards": {"terazin": 2, "enhance_atk_pct": 0.05}},
		],
	}

	var com_comp := [{"unit_id":"ml_commander","count":1},{"unit_id":"ml_walker","count":1},{"unit_id":"ml_artillery","count":1}]
	var com_tags := PackedStringArray(["military", "headquarters"])
	_c("ml_command", "통합 사령부", 5, T,
		com_comp, RS, -1,
		[],
		com_tags, -1, -1, false, 0, false, {
			2: _star("통합 사령부 ★2", com_comp, RS, -1, [], com_tags),
			3: _star("통합 사령부 ★3", com_comp, RS, -1, [], com_tags),
		})
	_theme_effects["ml_command"] = {
		1: [
			{"action": "train", "target": "all_military", "amount": 1},
			{"action": "revive", "target": "enhanced_units", "hp_pct": 0.5, "limit_per_combat": 1},
		],
		2: [
			{"action": "train", "target": "all_military", "amount": 1},
			{"action": "revive", "target": "enhanced_units", "hp_pct": 0.75, "limit_per_combat": 1},
		],
		3: [
			{"action": "train", "target": "all_military", "amount": 2},
			{"action": "revive", "target": "enhanced_units", "hp_pct": 1.0, "limit_per_combat": 3},
		],
	}
