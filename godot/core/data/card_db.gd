# AUTO-GENERATED from data/cards/*.yaml — DO NOT EDIT
# Run: python3 scripts/codegen_card_db.py
extends Node
## Card database. Autoloaded as "CardDB".
##
## Schema (v2 block format):
##   _templates[id] = {
##     id, name, tier, theme, composition, card_tags, cost,
##     effects: [  # list of timing blocks (1+ per card)
##       {
##         trigger_timing, max_activations,
##         trigger_layer1, trigger_layer2,
##         require_tenure, require_other_card, is_threshold,
##         actions: [{action, target, ...}, ...],
##         conditional_effects: [...],
##         r_conditional_effects: [...],
##         post_threshold_effects: [...],
##       }
##     ],
##     star_overrides: {2: {name, composition, card_tags, effects}, 3: {...}},
##   }

var _templates: Dictionary = {}
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


## Return the effect blocks for the given (card_id, star_level).
## In v2 there is a single unified store; this replaces both the old
## get_template().effects access AND the old _theme_effects lookup.
func get_effect_blocks(card_id: String, star_level: int = 1) -> Array:
	var tmpl := get_star_template(card_id, star_level)
	return tmpl.get("effects", [])


## Return the first block whose trigger_timing matches. {} if none.
func get_block_for_timing(card_id: String, star_level: int, timing: int) -> Dictionary:
	for block in get_effect_blocks(card_id, star_level):
		if block.get("trigger_timing") == timing:
			return block
	return {}


## Flat view of a card's theme actions across ALL timing blocks.
## Theme actions have globally unique names (spawn_firearm, manufacture,
## range_bonus, hatch_scaled, train, …), so the flat list preserves meaning
## for `_find_eff(effs, action_name)` lookups regardless of which block the
## action lives in.
## Includes reconstructed r_conditional / conditional pseudo-actions so
## theme_systems can still iterate them alongside regular actions.
## Multi-block cards (e.g. sp_warmachine RS+PERSISTENT) are supported: every
## block contributes its actions to the view.
func get_theme_effects(card_id: String, star_level: int) -> Array:
	var blocks := get_effect_blocks(card_id, star_level)
	var result: Array = []
	for block in blocks:
		result.append_array(block.get("actions", []))
		for rc in block.get("r_conditional_effects", []):
			result.append({
				"action": "r_conditional",
				"condition": rc.get("condition", ""),
				"threshold": rc.get("threshold", 0),
				"effects": rc.get("effects", []),
			})
		for c in block.get("conditional_effects", []):
			result.append({
				"action": "conditional",
				"condition": c.get("condition", ""),
				"threshold": c.get("threshold", 0),
				"effects": c.get("effects", []),
			})
	return result


## Compact card registration (v2 block format).
##
## Template shape (v2):
##   _templates[id] = {
##     id, name, tier, theme, impl, composition, card_tags, cost,
##     effects: [block, block, ...],      # ← primary truth
##     star_overrides: {2: {...}, 3: {...}},
##     # ─── Backward-compat flat accessors (hoisted from effects[0]) ───
##     # Legacy read sites (tests, UI, sim harness, AI evaluator, some
##     # game_manager paths) still expect these top-level fields. They are
##     # a "first-block hoist": for a multi-block card, these reflect the
##     # FIRST block in YAML order (representative timing) only.
##     # Multi-block cards (e.g. sp_warmachine with RS + BS blocks) have
##     # these flat fields pointing to block[0]; block[1..n] are only
##     # reachable via template["effects"]. This is intentional backward-
##     # compat — see docs/design/backlog.md "flat hoist 전면 제거".
##     trigger_timing, max_activations,
##     trigger_layer1, trigger_layer2,
##     require_tenure, require_other_card, is_threshold,
##   }
##
## IMPLICIT CONTRACT (v2 multi-block, see docs/design/backlog.md):
##   - ``effects[0]`` is the *representative* block used for flat-hoist
##     fields above. Its trigger_timing is what the UI and descriptions
##     label as "the card's timing".
##   - A card may have **multiple blocks per star** (v2 supports this).
##     All blocks fire independently via chain_engine's block loop.
##   - ``impl: theme_system`` cards route to their *.gd handler; the
##     handler reads ``get_theme_effects()`` directly — the flat accessors
##     are irrelevant for dispatch but still present for UI compatibility.
##   - If a read site must know ALL timings, iterate template["effects"],
##     not just the flat ``trigger_timing`` field.
func _c(id: String, nm: String, tier: int, theme: int,
		comp: Array, effects: Array, tags: PackedStringArray,
		star_overrides: Dictionary = {},
		impl: String = "card_db") -> void:
	var first: Dictionary = effects[0] if effects.size() > 0 else {}
	_templates[id] = {
		"id": id, "name": nm, "tier": tier, "theme": theme,
		"impl": impl,
		"composition": comp,
		"effects": effects,
		"cost": _tier_cost.get(tier, 3),
		"card_tags": tags,
		"star_overrides": _hoist_override_fields(star_overrides),
		# ── Legacy flat accessors (hoisted from first block) ──
		"trigger_timing": first.get("trigger_timing", -1),
		"max_activations": first.get("max_activations", -1),
		"trigger_layer1": first.get("trigger_layer1", -1),
		"trigger_layer2": first.get("trigger_layer2", -1),
		"require_tenure": first.get("require_tenure", 0),
		"require_other_card": first.get("require_other_card", false),
		"is_threshold": first.get("is_threshold", false),
	}


## Apply the same hoist to each star override so merged templates stay
## consistent when chain_engine / UI still reads flat fields on ★2/★3.
func _hoist_override_fields(star_overrides: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for star_level in star_overrides:
		var ov: Dictionary = star_overrides[star_level]
		var effs: Array = ov.get("effects", [])
		var first: Dictionary = effs[0] if effs.size() > 0 else {}
		var hoisted := ov.duplicate()
		hoisted["trigger_timing"] = first.get("trigger_timing", -1)
		hoisted["max_activations"] = first.get("max_activations", -1)
		hoisted["trigger_layer1"] = first.get("trigger_layer1", -1)
		hoisted["trigger_layer2"] = first.get("trigger_layer2", -1)
		hoisted["require_tenure"] = first.get("require_tenure", 0)
		hoisted["require_other_card"] = first.get("require_other_card", false)
		hoisted["is_threshold"] = first.get("is_threshold", false)
		result[star_level] = hoisted
	return result


# --- Effect helpers (action-level dict builders) ---
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
	var ass_comp := [{"unit_id":"sp_spider","count":2},{"unit_id":"sp_sawblade","count":1},{"unit_id":"sp_rat","count":1}]
	var ass_tags := PackedStringArray(["steampunk", "production"])
	_c("sp_assembly", "증기 조립소", 1, T,
		ass_comp,
		[
			{
				"trigger_timing": RS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [_spawn("right_adj", 1, UA, MF)],
			}
		],
		ass_tags,
		{
			2: {
				"name": "증기 조립소 ★2",
				"composition": ass_comp,
				"card_tags": ass_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [_spawn("both_adj", 1, UA, MF)],
				}
			],
			},
			3: {
				"name": "증기 조립소 ★3",
				"composition": ass_comp,
				"card_tags": ass_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						_spawn("both_adj", 2, UA, MF),
						_enhance("both_adj", 0.05, 0.0, "", EN, UP)
					],
				}
			],
			},
		})

	var fur_comp := [{"unit_id":"sp_crab","count":1},{"unit_id":"sp_sawblade","count":1}]
	var fur_tags := PackedStringArray(["steampunk", "focus"])
	_c("sp_furnace", "증기 용광로", 1, T,
		fur_comp,
		[
			{
				"trigger_timing": RS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					_spawn("self", 1, UA, MF),
					_enhance("self", 0.03)
				],
			}
		],
		fur_tags,
		{
			2: {
				"name": "증기 용광로 ★2",
				"composition": fur_comp,
				"card_tags": fur_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						_spawn("self", 2, UA, MF),
						_enhance("self", 0.05)
					],
				}
			],
			},
			3: {
				"name": "증기 용광로 ★3",
				"composition": fur_comp,
				"card_tags": fur_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						_spawn("self", 2, UA, MF),
						_enhance("self", 0.05)
					],
					"conditional_effects": [
						{"condition": "unit_count_gte", "threshold": 8, "effects": [_enhance("self", 0.03)]}
					],
				}
			],
			},
		})

	var wor_comp := [{"unit_id":"sp_spider","count":2},{"unit_id":"sp_sawblade","count":1}]
	var wor_tags := PackedStringArray(["steampunk", "enhance"])
	_c("sp_workshop", "태엽 공방", 1, T,
		wor_comp,
		[
			{
				"trigger_timing": OE, "max_activations": 2,
				"trigger_layer1": UA, "trigger_layer2": MF,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					_enhance("event_target", 0.05, 0.0, "gear", EN, UP)
				],
			}
		],
		wor_tags,
		{
			2: {
				"name": "태엽 공방 ★2",
				"composition": wor_comp,
				"card_tags": wor_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 2,
					"trigger_layer1": UA, "trigger_layer2": MF,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						_enhance("event_target", 0.075, 0.0, "gear,electric", EN, UP)
					],
				}
			],
			},
			3: {
				"name": "태엽 공방 ★3",
				"composition": wor_comp,
				"card_tags": wor_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 4,
					"trigger_layer1": UA, "trigger_layer2": MF,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						_enhance("event_target", 0.075, 0.0, "gear,electric", EN, UP),
						_spawn("both_adj", 1, UA, MF)
					],
				}
			],
			},
		})

	var cir_comp := [{"unit_id":"sp_sawblade","count":2},{"unit_id":"sp_scout","count":2}]
	var cir_tags := PackedStringArray(["steampunk", "cycle"])
	_c("sp_circulator", "증기 순환기", 2, T,
		cir_comp,
		[
			{
				"trigger_timing": OE, "max_activations": 1,
				"trigger_layer1": -1, "trigger_layer2": UP,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [_spawn("event_target", 1, UA, MF)],
			}
		],
		cir_tags,
		{
			2: {
				"name": "증기 순환기 ★2",
				"composition": cir_comp,
				"card_tags": cir_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 2,
					"trigger_layer1": -1, "trigger_layer2": UP,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [_spawn("event_target", 1, UA, MF)],
				}
			],
			},
			3: {
				"name": "증기 순환기 ★3",
				"composition": cir_comp,
				"card_tags": cir_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 3,
					"trigger_layer1": -1, "trigger_layer2": UP,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "spawn", "target": "event_target", "spawn_count": 1, "output_layer1": UA, "output_layer2": MF, "breed_strongest": true}
					],
				}
			],
			},
		})

	var int_comp := [{"unit_id":"sp_scout","count":2},{"unit_id":"sp_sawblade","count":1},{"unit_id":"sp_rat","count":2}]
	var int_tags := PackedStringArray(["steampunk", "economy"])
	_c("sp_interest", "증기 이자기", 2, T,
		int_comp,
		[
			{
				"trigger_timing": REROLL, "max_activations": 3,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					_spawn("self", 1, -1, -1),
					_enhance("self", 0.03, 0.0, "", -1, -1)
				],
			}
		],
		int_tags,
		{
			2: {
				"name": "증기 이자기 ★2",
				"composition": int_comp,
				"card_tags": int_tags,
				"effects": [
				{
					"trigger_timing": REROLL, "max_activations": 3,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						_spawn("self", 2, -1, -1),
						_enhance("self", 0.05, 0.0, "", -1, -1)
					],
				}
			],
			},
			3: {
				"name": "증기 이자기 ★3",
				"composition": int_comp,
				"card_tags": int_tags,
				"effects": [
				{
					"trigger_timing": REROLL, "max_activations": 3,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						_spawn("self", 2, -1, -1),
						_spawn("both_adj", 1, -1, -1),
						_enhance("self", 0.05, 0.0, "", -1, -1)
					],
				}
			],
			},
		})

	var lin_comp := [{"unit_id":"sp_sawblade","count":2},{"unit_id":"sp_spider","count":1},{"unit_id":"sp_scorpion","count":1}]
	var lin_tags := PackedStringArray(["steampunk", "production"])
	_c("sp_line", "조립 라인", 3, T,
		lin_comp,
		[
			{
				"trigger_timing": OE, "max_activations": 3,
				"trigger_layer1": UA, "trigger_layer2": MF,
				"require_tenure": 0, "require_other_card": true, "is_threshold": false,
				"actions": [_spawn("both_adj", 1, UA, MF)],
			}
		],
		lin_tags,
		{
			2: {
				"name": "조립 라인 ★2",
				"composition": lin_comp,
				"card_tags": lin_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 4,
					"trigger_layer1": UA, "trigger_layer2": MF,
					"require_tenure": 0, "require_other_card": true, "is_threshold": false,
					"actions": [_spawn("both_adj", 2, UA, MF)],
				}
			],
			},
			3: {
				"name": "조립 라인 ★3",
				"composition": lin_comp,
				"card_tags": lin_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 4,
					"trigger_layer1": UA, "trigger_layer2": MF,
					"require_tenure": 0, "require_other_card": true, "is_threshold": false,
					"actions": [
						{"action": "spawn", "target": "both_adj", "spawn_count": 2, "output_layer1": UA, "output_layer2": MF, "breed_strongest": true}
					],
				}
			],
			},
		})

	var bar_comp := [{"unit_id":"sp_titan","count":2},{"unit_id":"sp_crab","count":1}]
	var bar_tags := PackedStringArray(["steampunk", "defense"])
	_c("sp_barrier", "증기 방벽", 3, T,
		bar_comp,
		[
			{
				"trigger_timing": BS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [_shield("self", 0.2)],
			}
		],
		bar_tags,
		{
			2: {
				"name": "증기 방벽 ★2",
				"composition": bar_comp,
				"card_tags": bar_tags,
				"effects": [
				{
					"trigger_timing": BS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [_shield("self", 0.4)],
				}
			],
			},
			3: {
				"name": "증기 방벽 ★3",
				"composition": bar_comp,
				"card_tags": bar_tags,
				"effects": [
				{
					"trigger_timing": BS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [_shield("all_allies", 0.4)],
				}
			],
			},
		})

	var war_comp := [{"unit_id":"sp_turret","count":2},{"unit_id":"sp_cannon","count":2},{"unit_id":"sp_drone","count":2}]
	var war_tags := PackedStringArray(["steampunk", "combat"])
	_c("sp_warmachine", "전쟁 기계", 4, T,
		war_comp,
		[
			{
				"trigger_timing": PERSISTENT, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [{"action": "range_bonus", "tag": "firearm", "unit_thresh": 8}],
			},
			{
				"trigger_timing": RS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [{"action": "manufacture", "target": "self", "count": 1}],
			}
		],
		war_tags,
				{
			2: {
				"name": "전쟁 기계 ★2",
				"composition": war_comp,
				"card_tags": war_tags,
				"effects": [
				{
					"trigger_timing": PERSISTENT, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "range_bonus", "tag": "firearm", "unit_thresh": 6, "atk_buff_pct": 0.3}
					],
				},
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [{"action": "manufacture", "target": "self", "count": 2}],
				}
			],
			},
			3: {
				"name": "전쟁 기계 ★3",
				"composition": war_comp,
				"card_tags": war_tags,
				"effects": [
				{
					"trigger_timing": PERSISTENT, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "range_bonus", "tag": "firearm", "unit_thresh": 4, "atk_buff_pct": 0.3, "attack_stack_pct": 0.12}
					],
				},
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [{"action": "manufacture", "target": "self", "count": 4}],
				}
			],
			},
		},
		"theme_system")

	var cha_comp := [{"unit_id":"sp_titan","count":2},{"unit_id":"sp_turret","count":2},{"unit_id":"sp_cannon","count":1}]
	var cha_tags := PackedStringArray(["steampunk", "power"])
	_c("sp_charger", "태엽 과급기", 4, T,
		cha_comp,
		[
			{
				"trigger_timing": OE, "max_activations": -1,
				"trigger_layer1": UA, "trigger_layer2": MF,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "counter_produce", "event": "MF", "threshold": 10, "rewards": {"terazin": 1, "enhance_atk_pct": 0.05}}
				],
			}
		],
		cha_tags,
				{
			2: {
				"name": "태엽 과급기 ★2",
				"composition": cha_comp,
				"card_tags": cha_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": -1,
					"trigger_layer1": UA, "trigger_layer2": MF,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "counter_produce", "event": "MF", "threshold": 10, "rewards": {"terazin": 1, "enhance_atk_pct": 0.05}},
						{"action": "rare_counter", "threshold": 20, "reward": "pending_rare_upgrade"}
					],
				}
			],
			},
			3: {
				"name": "태엽 과급기 ★3",
				"composition": cha_comp,
				"card_tags": cha_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": -1,
					"trigger_layer1": UA, "trigger_layer2": MF,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "counter_produce", "event": "MF", "threshold": 10, "rewards": {"terazin": 1, "enhance_atk_pct": 0.05}},
						{"action": "epic_counter", "threshold": 15, "reward": "pending_epic_upgrade"},
						{"action": "total_counter", "per_manufacture": 10, "reward_terazin": 1}
					],
				}
			],
			},
		},
		"theme_system")

	var ars_comp := [{"unit_id":"sp_titan","count":2},{"unit_id":"sp_scorpion","count":2},{"unit_id":"sp_crab","count":1}]
	var ars_tags := PackedStringArray(["steampunk", "arsenal"])
	_c("sp_arsenal", "제국 병기창", 5, T,
		ars_comp,
		[
			{
				"trigger_timing": SELL, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [{"action": "absorb", "target": "self", "count": 3}],
			}
		],
		ars_tags,
				{
			2: {
				"name": "제국 병기창 ★2",
				"composition": ars_comp,
				"card_tags": ars_tags,
				"effects": [
				{
					"trigger_timing": SELL, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [{"action": "absorb", "target": "self", "count": 5, "transfer_upgrades": true}],
				}
			],
			},
			3: {
				"name": "제국 병기창 ★3",
				"composition": ars_comp,
				"card_tags": ars_tags,
				"effects": [
				{
					"trigger_timing": SELL, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "absorb", "target": "self", "count": 7, "transfer_upgrades": true, "majority_atk_bonus": 0.3}
					],
				}
			],
			},
		},
		"theme_system")


# ═══════════════════════════════════════════════════════════════════
# NEUTRAL (15 cards)
# ═══════════════════════════════════════════════════════════════════
func _register_neutral() -> void:
	var T := Enums.CardTheme.NEUTRAL
	var BS := Enums.TriggerTiming.BATTLE_START
	var MERGE := Enums.TriggerTiming.ON_MERGE
	var OE := Enums.TriggerTiming.ON_EVENT
	var PC := Enums.TriggerTiming.POST_COMBAT
	var PCD := Enums.TriggerTiming.POST_COMBAT_DEFEAT
	var RS := Enums.TriggerTiming.ROUND_START
	var EN := Enums.Layer1.ENHANCED
	var UA := Enums.Layer1.UNIT_ADDED
	var ee_comp := [{"unit_id":"ne_scrap","count":2},{"unit_id":"ne_eagle","count":1}]
	var ee_tags := PackedStringArray(["neutral", "production"])
	_c("ne_earth_echo", "대지의 울림", 1, T,
		ee_comp,
		[
			{
				"trigger_timing": RS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [_spawn("right_adj")],
			}
		],
		ee_tags,
		{
			2: {
				"name": "대지의 울림 ★2",
				"composition": ee_comp,
				"card_tags": ee_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [_spawn("right_adj", 2)],
				}
			],
			},
			3: {
				"name": "대지의 울림 ★3",
				"composition": ee_comp,
				"card_tags": ee_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [_spawn("both_adj", 2)],
				}
			],
			},
		})

	var wp_comp := [{"unit_id":"ne_archer","count":1},{"unit_id":"ne_golem","count":1}]
	var wp_tags := PackedStringArray(["neutral", "production"])
	_c("ne_wild_pulse", "야생의 맥동", 1, T,
		wp_comp,
		[
			{
				"trigger_timing": RS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [_spawn("right_adj")],
			}
		],
		wp_tags,
		{
			2: {
				"name": "야생의 맥동 ★2",
				"composition": wp_comp,
				"card_tags": wp_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						_spawn("right_adj"),
						_enhance("right_adj", 0.02)
					],
				}
			],
			},
			3: {
				"name": "야생의 맥동 ★3",
				"composition": wp_comp,
				"card_tags": wp_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						_spawn("both_adj"),
						_enhance("both_adj", 0.03)
					],
				}
			],
			},
		})

	var rr_comp := [{"unit_id":"ne_guardian","count":1},{"unit_id":"ne_scrap","count":2}]
	var rr_tags := PackedStringArray(["neutral", "ancient"])
	_c("ne_ruin_resonance", "유적의 공명", 2, T,
		rr_comp,
		[
			{
				"trigger_timing": RS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					_spawn("self"),
					_enhance("self", 0.02)
				],
			}
		],
		rr_tags,
		{
			2: {
				"name": "유적의 공명 ★2",
				"composition": rr_comp,
				"card_tags": rr_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						_spawn("self"),
						_enhance("self", 0.04)
					],
				}
			],
			},
			3: {
				"name": "유적의 공명 ★3",
				"composition": rr_comp,
				"card_tags": rr_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						_spawn("self", 2),
						_enhance("self", 0.04)
					],
					"conditional_effects": [
						{"condition": "unit_count_gte", "threshold": 8, "effects": [_enhance("both_adj", 0.02)]}
					],
				}
			],
			},
		})

	var wan_comp := [{"unit_id":"ne_merc","count":1},{"unit_id":"ne_scrap","count":2}]
	var wan_tags := PackedStringArray(["neutral", "versatile"])
	_c("ne_wanderers", "떠돌이 무리", 2, T,
		wan_comp,
		[
			{
				"trigger_timing": OE, "max_activations": 2,
				"trigger_layer1": UA, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [_enhance("event_target", 0.03)],
			}
		],
		wan_tags,
		{
			2: {
				"name": "떠돌이 무리 ★2",
				"composition": wan_comp,
				"card_tags": wan_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 2,
					"trigger_layer1": UA, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [_enhance("event_target", 0.05)],
				}
			],
			},
			3: {
				"name": "떠돌이 무리 ★3",
				"composition": wan_comp,
				"card_tags": wan_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 3,
					"trigger_layer1": UA, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						_enhance("event_target", 0.05),
						_spawn("self")
					],
				}
			],
			},
		})

	var ma_comp := [{"unit_id":"ne_beast","count":1},{"unit_id":"ne_archer","count":1}]
	var ma_tags := PackedStringArray(["neutral", "mutant"])
	_c("ne_mutant_adapt", "돌연변이 적응", 3, T,
		ma_comp,
		[
			{
				"trigger_timing": OE, "max_activations": 2,
				"trigger_layer1": EN, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [_spawn("self")],
			}
		],
		ma_tags,
		{
			2: {
				"name": "돌연변이 적응 ★2",
				"composition": ma_comp,
				"card_tags": ma_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 2,
					"trigger_layer1": EN, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [_spawn("self", 2)],
				}
			],
			},
			3: {
				"name": "돌연변이 적응 ★3",
				"composition": ma_comp,
				"card_tags": ma_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 2,
					"trigger_layer1": EN, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [_spawn("self", 2)],
					"conditional_effects": [
						{"condition": "unit_count_gte", "threshold": 10, "effects": [_spawn("both_adj")]}
					],
				}
			],
			},
		})

	var mc_comp := [{"unit_id":"ne_spirit","count":2},{"unit_id":"ne_scrap","count":2}]
	var mc_tags := PackedStringArray(["neutral", "mana"])
	_c("ne_mana_crystal", "마력 결정", 2, T,
		mc_comp,
		[
			{
				"trigger_timing": OE, "max_activations": 2,
				"trigger_layer1": UA, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [_spawn("both_adj")],
			}
		],
		mc_tags,
		{
			2: {
				"name": "마력 결정 ★2",
				"composition": mc_comp,
				"card_tags": mc_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 2,
					"trigger_layer1": UA, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [_spawn("both_adj", 2)],
				}
			],
			},
			3: {
				"name": "마력 결정 ★3",
				"composition": mc_comp,
				"card_tags": mc_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 3,
					"trigger_layer1": UA, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						_spawn("event_target"),
						_spawn("both_adj", 2)
					],
				}
			],
			},
		})

	var ac_comp := [{"unit_id":"ne_guardian","count":2},{"unit_id":"ne_spirit","count":2}]
	var ac_tags := PackedStringArray(["neutral", "ancient"])
	_c("ne_ancient_catalyst", "고대 촉매", 3, T,
		ac_comp,
		[
			{
				"trigger_timing": OE, "max_activations": 2,
				"trigger_layer1": EN, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [_enhance("both_adj", 0.02)],
			}
		],
		ac_tags,
		{
			2: {
				"name": "고대 촉매 ★2",
				"composition": ac_comp,
				"card_tags": ac_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 2,
					"trigger_layer1": EN, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [_enhance("both_adj", 0.03)],
				}
			],
			},
			3: {
				"name": "고대 촉매 ★3",
				"composition": ac_comp,
				"card_tags": ac_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 3,
					"trigger_layer1": EN, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						_enhance("both_adj", 0.03),
						_enhance("self", 0.03)
					],
				}
			],
			},
		})

	var mer_comp := [{"unit_id":"ne_archer","count":1},{"unit_id":"ne_scrap","count":1}]
	var mer_tags := PackedStringArray(["neutral", "economy"])
	_c("ne_merchant", "방랑 상인", 1, T,
		mer_comp,
		[
			{
				"trigger_timing": PCD, "max_activations": 1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [_gold(3)],
			}
		],
		mer_tags,
		{
			2: {
				"name": "방랑 상인 ★2",
				"composition": mer_comp,
				"card_tags": mer_tags,
				"effects": [
				{
					"trigger_timing": PCD, "max_activations": 1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						_gold(4),
						{"action": "grant_terazin", "target": "self", "terazin_amount": 1}
					],
				}
			],
			},
			3: {
				"name": "방랑 상인 ★3",
				"composition": mer_comp,
				"card_tags": mer_tags,
				"effects": [
				{
					"trigger_timing": PC, "max_activations": 1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						_gold(3),
						_spawn("self")
					],
				}
			],
			},
		})

	var sb_comp := [{"unit_id":"ne_spirit","count":2},{"unit_id":"ne_archer","count":2},{"unit_id":"ne_eagle","count":1}]
	var sb_tags := PackedStringArray(["neutral", "mana"])
	_c("ne_spirit_blessing", "정령의 축복", 3, T,
		sb_comp,
		[
			{
				"trigger_timing": MERGE, "max_activations": 1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "grant_terazin", "target": "self", "terazin_amount": 1},
					_spawn("event_target", 2)
				],
			}
		],
		sb_tags,
		{
			2: {
				"name": "정령의 축복 ★2",
				"composition": sb_comp,
				"card_tags": sb_tags,
				"effects": [
				{
					"trigger_timing": MERGE, "max_activations": 1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "grant_terazin", "target": "self", "terazin_amount": 1},
						_gold(2),
						_spawn("event_target", 3)
					],
				}
			],
			},
			3: {
				"name": "정령의 축복 ★3",
				"composition": sb_comp,
				"card_tags": sb_tags,
				"effects": [
				{
					"trigger_timing": MERGE, "max_activations": 1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "grant_terazin", "target": "self", "terazin_amount": 1},
						_gold(2),
						_spawn("event_target", 3),
						_spawn("all_allies")
					],
				}
			],
			},
		})

	var scr_comp := [{"unit_id":"ne_scrap","count":5}]
	var scr_tags := PackedStringArray(["neutral", "economy", "scrap"])
	_c("ne_scrapyard", "폐품 상회", 2, T,
		scr_comp,
		[
			{
				"trigger_timing": RS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "scrap_adjacent", "target": "both_adj", "scrap_count": 1, "reroll_gain": 1, "gold_per_unit": 0}
				],
			}
		],
		scr_tags,
		{
			2: {
				"name": "폐품 상회 ★2",
				"composition": scr_comp,
				"card_tags": scr_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "scrap_adjacent", "target": "both_adj", "scrap_count": 2, "reroll_gain": 2, "gold_per_unit": 0}
					],
				}
			],
			},
			3: {
				"name": "폐품 상회 ★3",
				"composition": scr_comp,
				"card_tags": scr_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "scrap_adjacent", "target": "both_adj", "scrap_count": 2, "reroll_gain": 2, "gold_per_unit": 1}
					],
				}
			],
			},
		})

	var dm_comp := [{"unit_id":"ne_merc","count":2},{"unit_id":"ne_guardian","count":2}]
	var dm_tags := PackedStringArray(["neutral", "economy"])
	_c("ne_dim_merchant", "차원 행상인", 4, T,
		dm_comp,
		[
			{
				"trigger_timing": RS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [{"action": "diversity_gold", "target": "self"}],
			}
		],
		dm_tags,
		{
			2: {
				"name": "차원 행상인 ★2",
				"composition": dm_comp,
				"card_tags": dm_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [{"action": "diversity_gold", "target": "self", "gold_per_theme": 2}],
				}
			],
			},
			3: {
				"name": "차원 행상인 ★3",
				"composition": dm_comp,
				"card_tags": dm_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "diversity_gold", "target": "self", "gold_per_theme": 3, "terazin_threshold": 3, "terazin_per_theme": 1, "mercenary_spawn": 1}
					],
				}
			],
			},
		})

	var wil_comp := [{"unit_id":"ne_archer","count":1},{"unit_id":"ne_chimera","count":1}]
	var wil_tags := PackedStringArray(["neutral", "combat"])
	_c("ne_wildforce", "야생의 힘", 2, T,
		wil_comp,
		[
			{
				"trigger_timing": BS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [_buff("self", 0.1)],
			}
		],
		wil_tags,
		{
			2: {
				"name": "야생의 힘 ★2",
				"composition": wil_comp,
				"card_tags": wil_tags,
				"effects": [
				{
					"trigger_timing": BS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [_buff("self", 0.15)],
				}
			],
			},
			3: {
				"name": "야생의 힘 ★3",
				"composition": wil_comp,
				"card_tags": wil_tags,
				"effects": [
				{
					"trigger_timing": BS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [_buff("self", 0.15)],
					"conditional_effects": [
						{"condition": "unit_count_lte", "threshold": 3, "effects": [_buff("self", 0.15)]}
					],
				}
			],
			},
		})

	var cc_comp := [{"unit_id":"ne_chimera","count":1},{"unit_id":"ne_mutant","count":1}]
	var cc_tags := PackedStringArray(["neutral", "reversal"])
	_c("ne_chimera_cry", "키메라의 울부짖음", 3, T,
		cc_comp,
		[
			{
				"trigger_timing": PCD, "max_activations": 1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [_enhance("self", 0.08, 0.08)],
			}
		],
		cc_tags,
		{
			2: {
				"name": "키메라의 울부짖음 ★2",
				"composition": cc_comp,
				"card_tags": cc_tags,
				"effects": [
				{
					"trigger_timing": PCD, "max_activations": 1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [_enhance("self", 0.12, 0.12)],
				}
			],
			},
			3: {
				"name": "키메라의 울부짖음 ★3",
				"composition": cc_comp,
				"card_tags": cc_tags,
				"effects": [
				{
					"trigger_timing": PC, "max_activations": 1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						_enhance("self", 0.12, 0.12),
						_spawn("both_adj", 2),
						_shield("self", 0.15)
					],
				}
			],
			},
		})

	var rui_comp := [{"unit_id":"ne_golem","count":2},{"unit_id":"ne_spirit","count":1}]
	var rui_tags := PackedStringArray(["neutral", "time"])
	_c("ne_ruins", "고대의 잔해", 2, T,
		rui_comp,
		[
			{
				"trigger_timing": RS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 2, "require_other_card": false, "is_threshold": false,
				"actions": [
					_gold(2),
					_spawn("right_adj")
				],
			}
		],
		rui_tags,
		{
			2: {
				"name": "고대의 잔해 ★2",
				"composition": rui_comp,
				"card_tags": rui_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 2, "require_other_card": false, "is_threshold": false,
					"actions": [
						_gold(3),
						_spawn("right_adj", 2)
					],
				}
			],
			},
			3: {
				"name": "고대의 잔해 ★3",
				"composition": rui_comp,
				"card_tags": rui_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 2, "require_other_card": false, "is_threshold": false,
					"actions": [
						_gold(3),
						_spawn("both_adj", 2)
					],
					"conditional_effects": [
						{"condition": "tenure_gte", "threshold": 4, "effects": [_spawn("both_adj")]}
					],
				}
			],
			},
		})

	var awa_comp := [{"unit_id":"ne_guardian","count":2},{"unit_id":"ne_golem","count":2},{"unit_id":"ne_spirit","count":2}]
	var awa_tags := PackedStringArray(["neutral", "ancient"])
	_c("ne_awakening", "고대의 각성", 4, T,
		awa_comp,
		[
			{
				"trigger_timing": RS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 4, "require_other_card": false, "is_threshold": true,
				"actions": [
					_spawn("all_allies", 2),
					_enhance("all_allies", 0.1),
					_shield("all_allies", 0.2)
				],
			}
		],
		awa_tags,
		{
			2: {
				"name": "고대의 각성 ★2",
				"composition": awa_comp,
				"card_tags": awa_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 4, "require_other_card": false, "is_threshold": true,
					"actions": [
						_spawn("all_allies", 3),
						_enhance("all_allies", 0.15),
						_shield("all_allies", 0.3)
					],
				}
			],
			},
			3: {
				"name": "고대의 각성 ★3",
				"composition": awa_comp,
				"card_tags": awa_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 4, "require_other_card": false, "is_threshold": true,
					"actions": [
						_spawn("all_allies", 3),
						_shield("all_allies", 0.3)
					],
					"post_threshold_effects": [_spawn("all_allies"), _shield("all_allies", 0.1)],
				}
			],
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
	var cra_comp := [{"unit_id":"dr_turtle","count":1},{"unit_id":"dr_vine","count":1}]
	var cra_tags := PackedStringArray(["druid", "creation"])
	_c("dr_cradle", "숲의 요람", 1, T,
		cra_comp,
		[
			{
				"trigger_timing": RS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "tree_add", "target": "self", "count": 1},
					{"action": "tree_add", "target": "right_adj", "count": 1}
				],
			}
		],
		cra_tags,
				{
			2: {
				"name": "숲의 요람 ★2",
				"composition": cra_comp,
				"card_tags": cra_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "tree_add", "target": "self", "count": 2},
						{"action": "tree_add", "target": "both_adj", "count": 1}
					],
				}
			],
			},
			3: {
				"name": "숲의 요람 ★3",
				"composition": cra_comp,
				"card_tags": cra_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "tree_add", "target": "self", "count": 3},
						{"action": "tree_add", "target": "both_adj", "count": 2}
					],
				}
			],
			},
		},
		"theme_system")

	var lif_comp := [{"unit_id":"dr_rootguard","count":1},{"unit_id":"dr_vine","count":1}]
	var lif_tags := PackedStringArray(["druid", "guardian"])
	_c("dr_lifebeat", "생명의 맥동", 1, T,
		lif_comp,
		[
			{
				"trigger_timing": BS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "tree_add", "target": "self", "count": 1},
					{"action": "tree_shield", "target": "self_and_both_adj", "base_pct": 0.05, "tree_scale_pct": 0.03, "low_unit": {"thresh": 3, "mult": 1.5}}
				],
			}
		],
		lif_tags,
				{
			2: {
				"name": "생명의 맥동 ★2",
				"composition": lif_comp,
				"card_tags": lif_tags,
				"effects": [
				{
					"trigger_timing": BS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "tree_add", "target": "self", "count": 1},
						{"action": "tree_shield", "target": "self_and_both_adj", "base_pct": 0.08, "tree_scale_pct": 0.04, "low_unit": {"thresh": 4, "mult": 1.5}}
					],
				}
			],
			},
			3: {
				"name": "생명의 맥동 ★3",
				"composition": lif_comp,
				"card_tags": lif_tags,
				"effects": [
				{
					"trigger_timing": BS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "tree_add", "target": "self", "count": 2},
						{"action": "tree_shield", "target": "all_druid", "base_pct": 0.08, "tree_scale_pct": 0.05, "low_unit": {"thresh": 5, "mult": 1.5}}
					],
				}
			],
			},
		},
		"theme_system")

	var ori_comp := [{"unit_id":"dr_boar","count":1},{"unit_id":"dr_vine","count":1}]
	var ori_tags := PackedStringArray(["druid", "growth"])
	_c("dr_origin", "오래된 근원", 2, T,
		ori_comp,
		[
			{
				"trigger_timing": RS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "tree_add", "target": "self", "count": 1},
					{"action": "tree_absorb", "target": "adj_druids", "count": 1},
					{"action": "tree_enhance", "target": "all_druid", "base_pct": 0.004, "low_unit": {"thresh": 3, "pct": 0.006}}
				],
			}
		],
		ori_tags,
				{
			2: {
				"name": "오래된 근원 ★2",
				"composition": ori_comp,
				"card_tags": ori_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "tree_add", "target": "self", "count": 1},
						{"action": "tree_absorb", "target": "adj_druids", "count": 2},
						{"action": "tree_enhance", "target": "all_druid", "base_pct": 0.006, "low_unit": {"thresh": 4, "pct": 0.009}}
					],
				}
			],
			},
			3: {
				"name": "오래된 근원 ★3",
				"composition": ori_comp,
				"card_tags": ori_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "tree_add", "target": "self", "count": 2},
						{"action": "tree_absorb", "target": "adj_druids", "count": 2},
						{"action": "tree_enhance", "target": "all_druid", "base_pct": 0.006, "low_unit": {"thresh": 5, "pct": 0.009}, "tree_bonus": {"thresh": 8, "bonus_growth_pct": 0.08}}
					],
				}
			],
			},
		},
		"theme_system")

	var gra_comp := [{"unit_id":"dr_spore","count":1},{"unit_id":"dr_wolf","count":1}]
	var gra_tags := PackedStringArray(["druid", "economy"])
	_c("dr_grace", "숲의 은혜", 2, T,
		gra_comp,
		[
			{
				"trigger_timing": PC, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "tree_gold", "base_gold": 1, "tree_divisor": 3, "win_half": true, "terazin_thresh": 10, "terazin": 1}
				],
			}
		],
		gra_tags,
				{
			2: {
				"name": "숲의 은혜 ★2",
				"composition": gra_comp,
				"card_tags": gra_tags,
				"effects": [
				{
					"trigger_timing": PC, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "tree_gold", "base_gold": 2, "tree_divisor": 3, "win_half": false, "terazin_thresh": 8, "terazin": 1}
					],
				}
			],
			},
			3: {
				"name": "숲의 은혜 ★3",
				"composition": gra_comp,
				"card_tags": gra_tags,
				"effects": [
				{
					"trigger_timing": PC, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "tree_gold", "base_gold": 2, "tree_divisor": 3, "win_half": false, "terazin_thresh": 8, "terazin": 1},
						{"action": "free_reroll", "value": 1}
					],
				}
			],
			},
		},
		"theme_system")

	var pru_comp := [{"unit_id":"dr_rootguard","count":1},{"unit_id":"dr_wolf","count":1}]
	var pru_tags := PackedStringArray(["druid", "prune"])
	_c("dr_prune", "가지치기", 2, T,
		pru_comp,
		[
			{
				"trigger_timing": RS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "tree_add", "target": "self", "count": 1},
					{"action": "prune", "count": 2, "min_units": 3}
				],
			}
		],
		pru_tags,
				{
			2: {
				"name": "가지치기 ★2",
				"composition": pru_comp,
				"card_tags": pru_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "tree_add", "target": "self", "count": 1},
						{"action": "prune", "count": 2, "min_units": 3, "enhance_pct": 0.03}
					],
				}
			],
			},
			3: {
				"name": "가지치기 ★3",
				"composition": pru_comp,
				"card_tags": pru_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "tree_add", "target": "self", "count": 2},
						{"action": "prune", "count": 3, "min_units": 3, "enhance_pct": 0.05}
					],
				}
			],
			},
		},
		"theme_system")

	var dee_comp := [{"unit_id":"dr_treant_a","count":1},{"unit_id":"dr_wolf","count":1}]
	var dee_tags := PackedStringArray(["druid", "time"])
	_c("dr_deep", "뿌리깊은 자", 3, T,
		dee_comp,
		[
			{
				"trigger_timing": RS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "tree_add", "target": "self", "count": 1},
					{"action": "tree_enhance", "target": "self", "base_pct": 0.008, "low_unit": {"thresh": 3, "pct": 0.012}, "tree_bonus": {"thresh": 10, "mult": 1.3}}
				],
			}
		],
		dee_tags,
				{
			2: {
				"name": "뿌리깊은 자 ★2",
				"composition": dee_comp,
				"card_tags": dee_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "tree_add", "target": "self", "count": 1},
						{"action": "tree_enhance", "target": "self", "base_pct": 0.012, "low_unit": {"thresh": 3, "pct": 0.018}, "tree_bonus": {"thresh": 8, "mult": 1.3}}
					],
				}
			],
			},
			3: {
				"name": "뿌리깊은 자 ★3",
				"composition": dee_comp,
				"card_tags": dee_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "tree_add", "target": "self", "count": 2},
						{"action": "tree_enhance", "target": "self", "base_pct": 0.012, "low_unit": {"thresh": 3, "pct": 0.018}, "tree_bonus": {"thresh": 8, "mult": 1.5}}
					],
				}
			],
			},
		},
		"theme_system")

	var sc_comp := [{"unit_id":"dr_spore","count":2},{"unit_id":"dr_toad","count":1}]
	var sc_tags := PackedStringArray(["druid", "combat"])
	_c("dr_spore_cloud", "포자 구름", 3, T,
		sc_comp,
		[
			{
				"trigger_timing": BS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "debuff_store", "stat": "as", "base_pct": 0.15, "tree_scale_pct": 0.015, "cap": 0.5}
				],
			}
		],
		sc_tags,
				{
			2: {
				"name": "포자 구름 ★2",
				"composition": sc_comp,
				"card_tags": sc_tags,
				"effects": [
				{
					"trigger_timing": BS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "debuff_store", "stat": "as", "base_pct": 0.2, "tree_scale_pct": 0.02, "cap": 0.5},
						{"action": "debuff_store", "stat": "atk", "base_pct": 0.2, "tree_scale_pct": 0.02, "cap": 0.5}
					],
				}
			],
			},
			3: {
				"name": "포자 구름 ★3",
				"composition": sc_comp,
				"card_tags": sc_tags,
				"effects": [
				{
					"trigger_timing": BS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "debuff_store", "stat": "as", "base_pct": 0.3, "tree_scale_pct": 0.025, "cap": 0.5},
						{"action": "debuff_store", "stat": "atk", "base_pct": 0.3, "tree_scale_pct": 0.02, "cap": 0.5},
						{"action": "tree_shield", "target": "self", "base_pct": 0.1, "tree_scale_pct": 0.02}
					],
				}
			],
			},
		},
		"theme_system")

	var wra_comp := [{"unit_id":"dr_spore","count":1},{"unit_id":"dr_boar","count":1},{"unit_id":"dr_wolf","count":1}]
	var wra_tags := PackedStringArray(["druid", "combat"])
	_c("dr_wrath", "태고의 분노", 4, T,
		wra_comp,
		[
			{
				"trigger_timing": PERSISTENT, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "tree_temp_buff", "target": "self", "unit_cap": 5, "atk_base_pct": 0.8, "atk_tree_pct": 0.05}
				],
			}
		],
		wra_tags,
				{
			2: {
				"name": "태고의 분노 ★2",
				"composition": wra_comp,
				"card_tags": wra_tags,
				"effects": [
				{
					"trigger_timing": PERSISTENT, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "tree_temp_buff", "target": "self", "unit_cap": 6, "atk_base_pct": 1.2, "atk_tree_pct": 0.08, "hp_pct": 0.6}
					],
				}
			],
			},
			3: {
				"name": "태고의 분노 ★3",
				"composition": wra_comp,
				"card_tags": wra_tags,
				"effects": [
				{
					"trigger_timing": PERSISTENT, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "tree_temp_buff", "target": "self", "unit_cap": 7, "atk_mult": 1.5, "hp_mult": 1.3, "kill_hp_recover": true}
					],
				}
			],
			},
		},
		"theme_system")

	var wr_comp := [{"unit_id":"dr_treant_a","count":1},{"unit_id":"dr_turtle","count":1},{"unit_id":"dr_wolf","count":1}]
	var wr_tags := PackedStringArray(["druid", "ancient"])
	_c("dr_wt_root", "세계수의 뿌리", 4, T,
		wr_comp,
		[
			{
				"trigger_timing": RS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "tree_add", "target": "self", "count": 1},
					{"action": "tree_distribute", "target": "all_other_druid", "tiers": [{"tree_gte": 4, "amount": 1}, {"tree_gte": 8, "amount": 2}]}
				],
			}
		],
		wr_tags,
				{
			2: {
				"name": "세계수의 뿌리 ★2",
				"composition": wr_comp,
				"card_tags": wr_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "tree_add", "target": "self", "count": 1},
						{"action": "tree_distribute", "target": "all_other_druid", "tiers": [{"tree_gte": 3, "amount": 1}, {"tree_gte": 6, "amount": 2}]}
					],
				}
			],
			},
			3: {
				"name": "세계수의 뿌리 ★3",
				"composition": wr_comp,
				"card_tags": wr_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "tree_add", "target": "self", "count": 2},
						{"action": "tree_distribute", "target": "all_other_druid", "tiers": [{"tree_gte": 3, "amount": 1}, {"tree_gte": 6, "amount": 2}]},
						{"action": "epic_shop_unlock", "tree_thresh": 8}
					],
				}
			],
			},
		},
		"theme_system")

	var wor_comp := [{"unit_id":"dr_treant_a","count":2},{"unit_id":"dr_spirit","count":1}]
	var wor_tags := PackedStringArray(["druid", "worldtree"])
	_c("dr_world", "세계수", 5, T,
		wor_comp,
		[
			{
				"trigger_timing": RS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "tree_add", "target": "self", "count": 2},
					{"action": "tree_add", "target": "all_other_druid", "count": 1},
					{"action": "multiply_stats", "target": "self", "tree_source": "forest_depth", "atk_base": 1.1, "atk_per_tree": 0.1, "atk_tree_step": 30, "hp_base": 1.05, "hp_per_tree": 0.05, "hp_tree_step": 30, "as_base": 1.05, "as_per_tree": 0.05, "as_tree_step": 30, "unit_cap": 20}
				],
			}
		],
		wor_tags,
				{
			2: {
				"name": "세계수 ★2",
				"composition": wor_comp,
				"card_tags": wor_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "tree_add", "target": "self", "count": 3},
						{"action": "tree_add", "target": "all_other_druid", "count": 2},
						{"action": "multiply_stats", "target": "self", "tree_source": "forest_depth", "atk_base": 1.15, "atk_per_tree": 0.1, "atk_tree_step": 20, "hp_base": 1.05, "hp_per_tree": 0.05, "hp_tree_step": 30, "as_base": 1.05, "as_per_tree": 0.05, "as_tree_step": 30, "unit_cap": 40}
					],
				}
			],
			},
			3: {
				"name": "세계수 ★3",
				"composition": wor_comp,
				"card_tags": wor_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "tree_add", "target": "self", "count": 3},
						{"action": "tree_add", "target": "all_other_druid", "count": 2},
						{"action": "multiply_stats", "target": "self", "tree_source": "forest_depth", "atk_base": 1.3, "atk_per_tree": 0.1, "atk_tree_step": 10, "hp_base": 1.05, "hp_per_tree": 0.05, "hp_tree_step": 30, "as_base": 1.05, "as_per_tree": 0.05, "as_tree_step": 30, "unit_cap": 200}
					],
				}
			],
			},
		},
		"theme_system")


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
		nes_comp,
		[
			{
				"trigger_timing": RS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "hatch", "target": "self", "count": 2},
					{"action": "hatch", "target": "right_adj", "count": 1}
				],
			}
		],
		nes_tags,
				{
			2: {
				"name": "유충 둥지 ★2",
				"composition": nes_comp,
				"card_tags": nes_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "hatch", "target": "self", "count": 4},
						{"action": "hatch", "target": "right_adj", "count": 2}
					],
				}
			],
			},
			3: {
				"name": "유충 둥지 ★3",
				"composition": nes_comp,
				"card_tags": nes_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "hatch", "target": "self", "count": 4},
						{"action": "hatch", "target": "both_adj", "count": 2},
						{"action": "hatch_enhance", "target": "self", "atk_pct": 0.03}
					],
				}
			],
			},
		},
		"theme_system")

	var far_comp := [{"unit_id":"pr_sniper","count":1},{"unit_id":"pr_spider","count":1},{"unit_id":"pr_larva","count":1}]
	var far_tags := PackedStringArray(["predator", "economy"])
	_c("pr_farm", "독 양식장", 1, T,
		far_comp,
		[
			{
				"trigger_timing": RS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "hatch", "target": "self", "count": 1},
					{"action": "economy", "gold_base": 0, "gold_per": 0.2, "gold_per_unit": "units", "halve_on_loss": true, "max_gold": 3}
				],
			}
		],
		far_tags,
				{
			2: {
				"name": "독 양식장 ★2",
				"composition": far_comp,
				"card_tags": far_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "hatch", "target": "self", "count": 1},
						{"action": "economy", "gold_base": 0, "gold_per": 0.2, "gold_per_unit": "units", "halve_on_loss": false, "max_gold": 5}
					],
				}
			],
			},
			3: {
				"name": "독 양식장 ★3",
				"composition": far_comp,
				"card_tags": far_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "hatch", "target": "self", "count": 2},
						{"action": "economy", "gold_base": 0, "gold_per": 0.2, "gold_per_unit": "units", "halve_on_loss": false, "max_gold": 7, "terazin": {"condition": "always", "amount": 1}}
					],
				}
			],
			},
		},
		"theme_system")

	var mol_comp := [{"unit_id":"pr_larva","count":2},{"unit_id":"pr_guardian","count":1}]
	var mol_tags := PackedStringArray(["predator", "metamorphosis"])
	_c("pr_molt", "탈피의 방", 2, T,
		mol_comp,
		[
			{
				"trigger_timing": OE, "max_activations": 2,
				"trigger_layer1": -1, "trigger_layer2": HA,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [{"action": "meta_consume", "consume": 3}],
			}
		],
		mol_tags,
				{
			2: {
				"name": "탈피의 방 ★2",
				"composition": mol_comp,
				"card_tags": mol_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 3,
					"trigger_layer1": -1, "trigger_layer2": HA,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [{"action": "meta_consume", "consume": 2}],
				}
			],
			},
			3: {
				"name": "탈피의 방 ★3",
				"composition": mol_comp,
				"card_tags": mol_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 3,
					"trigger_layer1": -1, "trigger_layer2": HA,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "meta_consume", "consume": 2},
						{"action": "enhance", "target": "self", "atk_pct": 0.05}
					],
				}
			],
			},
		},
		"theme_system")

	var ss_comp := [{"unit_id":"pr_spider","count":3},{"unit_id":"pr_larva","count":3}]
	var ss_tags := PackedStringArray(["predator", "combat"])
	_c("pr_swarm_sense", "군체 감각", 2, T,
		ss_comp,
		[
			{
				"trigger_timing": BS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "swarm_buff", "target": "all_predator", "atk_per_unit": 0.1, "per_n": 3}
				],
			}
		],
		ss_tags,
				{
			2: {
				"name": "군체 감각 ★2",
				"composition": ss_comp,
				"card_tags": ss_tags,
				"effects": [
				{
					"trigger_timing": BS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "swarm_buff", "target": "all_predator", "atk_per_unit": 0.12, "per_n": 3}
					],
					"conditional_effects": [
						{"condition": "unit_count_gte", "threshold": 10, "effects": [{"action": "debuff_store", "stat": "as", "target": "all_enemy", "base_pct": 0.15, "cap": 0.3}]}
					],
				}
			],
			},
			3: {
				"name": "군체 감각 ★3",
				"composition": ss_comp,
				"card_tags": ss_tags,
				"effects": [
				{
					"trigger_timing": BS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "swarm_buff", "target": "all_predator", "atk_per_unit": 0.12, "per_n": 2}
					],
					"conditional_effects": [
						{"condition": "unit_count_gte", "threshold": 10, "effects": [{"action": "debuff_store", "stat": "as", "target": "all_enemy", "base_pct": 0.2, "cap": 0.4}, {"action": "debuff_store", "stat": "atk", "target": "all_enemy", "base_pct": 0.15, "cap": 0.3}]}
					],
				}
			],
			},
		},
		"theme_system")

	var har_comp := [{"unit_id":"pr_charger","count":1},{"unit_id":"pr_warrior","count":2},{"unit_id":"pr_sniper","count":1}]
	var har_tags := PackedStringArray(["predator", "economy"])
	_c("pr_harvest", "변태 수확", 2, T,
		har_comp,
		[
			{
				"trigger_timing": OE, "max_activations": 1,
				"trigger_layer1": -1, "trigger_layer2": MT,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "terazin", "value": 1},
					{"action": "hatch", "target": "self", "count": 1}
				],
			}
		],
		har_tags,
				{
			2: {
				"name": "변태 수확 ★2",
				"composition": har_comp,
				"card_tags": har_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 2,
					"trigger_layer1": -1, "trigger_layer2": MT,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "terazin", "value": 1},
						{"action": "hatch", "target": "self", "count": 1},
						{"action": "enhance", "target": "event_source", "atk_pct": 0.05}
					],
				}
			],
			},
			3: {
				"name": "변태 수확 ★3",
				"composition": har_comp,
				"card_tags": har_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 2,
					"trigger_layer1": -1, "trigger_layer2": MT,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "terazin", "value": 1},
						{"action": "hatch", "target": "self", "count": 2},
						{"action": "enhance", "target": "all_predator", "atk_pct": 0.03}
					],
				}
			],
			},
		},
		"theme_system")

	var que_comp := [{"unit_id":"pr_queen","count":1},{"unit_id":"pr_guardian","count":1},{"unit_id":"pr_charger","count":2},{"unit_id":"pr_worker","count":2}]
	var que_tags := PackedStringArray(["predator", "hatch"])
	_c("pr_queen", "여왕의 산란", 3, T,
		que_comp,
		[
			{
				"trigger_timing": RS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "hatch", "target": "self", "count": 2},
					{"action": "hatch", "target": "right_adj", "count": 1}
				],
			}
		],
		que_tags,
				{
			2: {
				"name": "여왕의 산란 ★2",
				"composition": que_comp,
				"card_tags": que_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "hatch", "target": "self", "count": 3},
						{"action": "hatch", "target": "both_adj", "count": 2}
					],
				}
			],
			},
			3: {
				"name": "여왕의 산란 ★3",
				"composition": que_comp,
				"card_tags": que_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "hatch", "target": "self", "count": 5},
						{"action": "hatch", "target": "both_adj", "count": 3},
						{"action": "enhance", "target": "tag:queen", "hp_pct": 0.05}
					],
				}
			],
			},
		},
		"theme_system")

	var car_comp := [{"unit_id":"pr_charger","count":2},{"unit_id":"pr_warrior","count":2},{"unit_id":"pr_guardian","count":1}]
	var car_tags := PackedStringArray(["predator", "enhance"])
	_c("pr_carapace", "적응 갑각", 3, T,
		car_comp,
		[
			{
				"trigger_timing": OE, "max_activations": 2,
				"trigger_layer1": -1, "trigger_layer2": MT,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "enhance", "target": "tag:carapace", "atk_pct": 0.05, "hp_pct": 0.05},
					{"action": "hatch", "target": "right_adj", "count": 1}
				],
			}
		],
		car_tags,
				{
			2: {
				"name": "적응 갑각 ★2",
				"composition": car_comp,
				"card_tags": car_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 2,
					"trigger_layer1": -1, "trigger_layer2": MT,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "enhance", "target": "tag:carapace", "atk_pct": 0.07, "hp_pct": 0.07},
						{"action": "hatch", "target": "right_adj", "count": 1}
					],
				}
			],
			},
			3: {
				"name": "적응 갑각 ★3",
				"composition": car_comp,
				"card_tags": car_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 3,
					"trigger_layer1": -1, "trigger_layer2": MT,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "enhance", "target": "all_predator", "atk_pct": 0.07, "hp_pct": 0.07},
						{"action": "hatch", "target": "both_adj", "count": 1},
						{"action": "shield", "target": "event_source", "hp_pct": 0.2}
					],
				}
			],
			},
		},
		"theme_system")

	var par_comp := [{"unit_id":"pr_apex","count":2},{"unit_id":"pr_flyer","count":3},{"unit_id":"pr_sniper","count":1}]
	var par_tags := PackedStringArray(["predator", "combat"])
	_c("pr_parasite", "기생 진화", 4, T,
		par_comp,
		[
			{
				"trigger_timing": PC, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "hatch_scaled", "target": "self", "per_units": 1, "cap": 3},
					{"action": "on_combat_result", "condition": "victory", "effects": [{"action": "meta_consume", "consume": 2}]}
				],
			}
		],
		par_tags,
				{
			2: {
				"name": "기생 진화 ★2",
				"composition": par_comp,
				"card_tags": par_tags,
				"effects": [
				{
					"trigger_timing": PC, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "hatch_scaled", "target": "self", "per_units": 2, "cap": 5},
						{"action": "on_combat_result", "condition": "victory", "effects": [{"action": "meta_consume", "consume": 2, "count": 2}, {"action": "enhance", "target": "self", "hp_pct": 0.15}]}
					],
				}
			],
			},
			3: {
				"name": "기생 진화 ★3",
				"composition": par_comp,
				"card_tags": par_tags,
				"effects": [
				{
					"trigger_timing": PC, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "hatch_scaled", "target": "self", "per_units": 2, "cap": 5},
						{"action": "on_combat_result", "condition": "always", "effects": [{"action": "meta_consume", "consume": 1, "count": 2}, {"action": "enhance", "target": "self", "hp_pct": 0.2}, {"action": "shield", "target": "self", "hp_pct": 0.3}]}
					],
				}
			],
			},
		},
		"theme_system")

	var ah_comp := [{"unit_id":"pr_apex","count":3},{"unit_id":"pr_guardian","count":1}]
	var ah_tags := PackedStringArray(["predator", "predation"])
	_c("pr_apex_hunt", "포식자의 사냥", 4, T,
		ah_comp,
		[
			{
				"trigger_timing": OE, "max_activations": 1,
				"trigger_layer1": -1, "trigger_layer2": MT,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [{"action": "meta_consume", "consume": 2}],
				"conditional_effects": [
					{"condition": "unit_count_lte", "threshold": 5, "effects": [{"action": "buff", "target": "self", "atk_pct": 0.3}]}
				],
			}
		],
		ah_tags,
				{
			2: {
				"name": "포식자의 사냥 ★2",
				"composition": ah_comp,
				"card_tags": ah_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 2,
					"trigger_layer1": -1, "trigger_layer2": MT,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [{"action": "meta_consume", "consume": 2}],
					"conditional_effects": [
						{"condition": "unit_count_lte", "threshold": 5, "effects": [{"action": "buff", "target": "self", "atk_pct": 0.5}]}
					],
				}
			],
			},
			3: {
				"name": "포식자의 사냥 ★3",
				"composition": ah_comp,
				"card_tags": ah_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 2,
					"trigger_layer1": -1, "trigger_layer2": MT,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [{"action": "meta_consume", "consume": 1}],
					"conditional_effects": [
						{"condition": "unit_count_lte", "threshold": 5, "effects": [{"action": "buff", "target": "self", "atk_mult": 2.0, "kill_hp_recover": true}]}
					],
				}
			],
			},
		},
		"theme_system")

	var tra_comp := [{"unit_id":"pr_apex","count":4},{"unit_id":"pr_guardian","count":2},{"unit_id":"pr_queen","count":2}]
	var tra_tags := PackedStringArray(["predator", "swarm"])
	_c("pr_transcend", "군체 초월", 5, T,
		tra_comp,
		[
			{
				"trigger_timing": RS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "hatch", "target": "self", "count": 3},
					{"action": "hatch", "target": "all_predator", "count": 1},
					{"action": "persistent", "death_atk_bonus": 0.03, "kill_hp_recover": 0.1}
				],
			}
		],
		tra_tags,
				{
			2: {
				"name": "군체 초월 ★2",
				"composition": tra_comp,
				"card_tags": tra_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "hatch", "target": "self", "count": 4},
						{"action": "hatch", "target": "all_predator", "count": 2},
						{"action": "persistent", "death_atk_bonus": 0.05, "kill_hp_recover": 0.15}
					],
				}
			],
			},
			3: {
				"name": "군체 초월 ★3",
				"composition": tra_comp,
				"card_tags": tra_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "hatch", "target": "self", "count": 4},
						{"action": "hatch", "target": "all_predator", "count": 2},
						{"action": "meta_consume", "consume": 1},
						{"action": "enhance", "target": "self", "atk_pct": 0.05},
						{"action": "persistent", "death_atk_bonus": 0.05, "kill_hp_recover": 0.15}
					],
				}
			],
			},
		},
		"theme_system")


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
	var bar_comp := [{"unit_id":"ml_recruit","count":2},{"unit_id":"ml_shield","count":1}]
	var bar_tags := PackedStringArray(["military", "training"])
	_c("ml_barracks", "신병 훈련소", 1, T,
		bar_comp,
		[
			{
				"trigger_timing": RS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "train", "target": "self", "amount": 1},
					{"action": "train", "target": "right_adj", "amount": 1}
				],
				"r_conditional_effects": [
					{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "train", "target": "left_adj", "amount": 1}]},
					{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "train", "target": "far_military", "amount": 1}]}
				],
			}
		],
		bar_tags,
				{
			2: {
				"name": "신병 훈련소 ★2",
				"composition": bar_comp,
				"card_tags": bar_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "train", "target": "self", "amount": 2},
						{"action": "train", "target": "right_adj", "amount": 1}
					],
					"r_conditional_effects": [
						{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "train", "target": "left_adj", "amount": 1}]},
						{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "train", "target": "far_military", "amount": 1}]}
					],
				}
			],
			},
			3: {
				"name": "신병 훈련소 ★3",
				"composition": bar_comp,
				"card_tags": bar_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "train", "target": "self", "amount": 2},
						{"action": "train", "target": "right_adj", "amount": 1},
						{"action": "high_rank_mult", "rank": 15, "atk_mult": 1.3}
					],
					"r_conditional_effects": [
						{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "train", "target": "left_adj", "amount": 1}]},
						{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "train", "target": "far_military", "amount": 1}]}
					],
				}
			],
			},
		},
		"theme_system")

	var con_comp := [{"unit_id":"ml_recruit","count":2},{"unit_id":"ml_drone","count":1}]
	var con_tags := PackedStringArray(["military", "conscript"])
	_c("ml_conscript", "징병국", 1, T,
		con_comp,
		[
			{
				"trigger_timing": RS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [{"action": "conscript", "target": "self", "count": 2}],
				"r_conditional_effects": [
					{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "conscript_pool_tier", "tier": "enhanced"}]},
					{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "conscript_pool_tier", "tier": "elite"}]}
				],
			}
		],
		con_tags,
				{
			2: {
				"name": "징병국 ★2",
				"composition": con_comp,
				"card_tags": con_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "conscript", "target": "self", "count": 2},
						{"action": "conscript", "target": "both_adj", "count": 1}
					],
					"r_conditional_effects": [
						{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "conscript_pool_tier", "tier": "enhanced"}]},
						{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "conscript_pool_tier", "tier": "elite"}]}
					],
				}
			],
			},
			3: {
				"name": "징병국 ★3",
				"composition": con_comp,
				"card_tags": con_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "conscript", "target": "self", "count": 3},
						{"action": "conscript", "target": "both_adj", "count": 1}
					],
					"conditional_effects": [
						{"condition": "unit_count_gte", "threshold": 12, "effects": [{"action": "buff", "target": "all_military", "atk_pct": 0.1}]}
					],
					"r_conditional_effects": [
						{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "conscript_pool_tier", "tier": "enhanced"}]},
						{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "conscript_pool_tier", "tier": "elite"}]}
					],
				}
			],
			},
		},
		"theme_system")

	var out_comp := [{"unit_id":"ml_recruit","count":2},{"unit_id":"ml_shield","count":1},{"unit_id":"ml_drone","count":1}]
	var out_tags := PackedStringArray(["military", "frontline"])
	_c("ml_outpost", "전진 기지", 2, T,
		out_comp,
		[
			{
				"trigger_timing": OE, "max_activations": 2,
				"trigger_layer1": -1, "trigger_layer2": CO,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [{"action": "conscript", "target": "event_target", "count": 1}],
				"r_conditional_effects": [
					{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "conscript", "target": "event_target_adj", "count": 1}]},
					{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "conscript", "target": "far_event_military", "count": 1}]}
				],
			}
		],
		out_tags,
				{
			2: {
				"name": "전진 기지 ★2",
				"composition": out_comp,
				"card_tags": out_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 3,
					"trigger_layer1": -1, "trigger_layer2": CO,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "conscript", "target": "event_target", "count": 2, "enhanced_count": 1}
					],
					"r_conditional_effects": [
						{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "conscript", "target": "event_target_adj", "count": 1, "enhanced_count": 1}]},
						{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "conscript", "target": "far_event_military", "count": 1, "enhanced_count": 1}]}
					],
				}
			],
			},
			3: {
				"name": "전진 기지 ★3",
				"composition": out_comp,
				"card_tags": out_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 3,
					"trigger_layer1": -1, "trigger_layer2": CO,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "conscript", "target": "event_target", "count": 2, "enhanced_count": 2}
					],
					"r_conditional_effects": [
						{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "conscript", "target": "event_target_adj", "count": 1, "enhanced_count": 1}]},
						{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "conscript", "target": "far_event_military", "count": 1, "enhanced_count": 1}]}
					],
				}
			],
			},
		},
		"theme_system")

	var aca_comp := [{"unit_id":"ml_commander","count":1},{"unit_id":"ml_infantry","count":1},{"unit_id":"ml_drone","count":1}]
	var aca_tags := PackedStringArray(["military", "training"])
	_c("ml_academy", "군사 학교", 2, T,
		aca_comp,
		[
			{
				"trigger_timing": OE, "max_activations": 2,
				"trigger_layer1": -1, "trigger_layer2": TR,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [{"action": "train", "target": "event_target", "amount": 1}],
				"r_conditional_effects": [
					{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "enhance_convert_target", "count": 1, "max_per_round": 1}]},
					{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "spawn_enhanced_random", "target": "event_target", "count": 2, "max_per_round": 1}]}
				],
			}
		],
		aca_tags,
				{
			2: {
				"name": "군사 학교 ★2",
				"composition": aca_comp,
				"card_tags": aca_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 3,
					"trigger_layer1": -1, "trigger_layer2": TR,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "train", "target": "event_target", "amount": 1},
						{"action": "enhance", "target": "event_target", "atk_pct": 0.02}
					],
					"r_conditional_effects": [
						{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "enhance_convert_target", "count": 1, "max_per_round": 1}]},
						{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "spawn_enhanced_random", "target": "event_target", "count": 2, "max_per_round": 1}]}
					],
				}
			],
			},
			3: {
				"name": "군사 학교 ★3",
				"composition": aca_comp,
				"card_tags": aca_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": 3,
					"trigger_layer1": -1, "trigger_layer2": TR,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "train", "target": "event_target", "amount": 2},
						{"action": "enhance", "target": "event_target", "atk_pct": 0.03}
					],
					"r_conditional_effects": [
						{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "enhance_convert_target", "count": 1, "max_per_round": 1}]},
						{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "spawn_enhanced_random", "target": "event_target", "count": 2, "max_per_round": 1}]}
					],
				}
			],
			},
		},
		"theme_system")

	var sup_comp := [{"unit_id":"ml_drone","count":2},{"unit_id":"ml_biker","count":1}]
	var sup_tags := PackedStringArray(["military", "supply"])
	_c("ml_supply", "보급 부대", 2, T,
		sup_comp,
		[
			{
				"trigger_timing": PC, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "economy", "gold_base": 1, "gold_per": 0.5, "gold_per_unit": "cards", "halve_on_loss": true}
				],
				"r_conditional_effects": [
					{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "grant_terazin", "amount": 1}]},
					{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "grant_terazin", "amount": 1}, {"action": "grant_gold", "amount": 1}]}
				],
			}
		],
		sup_tags,
				{
			2: {
				"name": "보급 부대 ★2",
				"composition": sup_comp,
				"card_tags": sup_tags,
				"effects": [
				{
					"trigger_timing": PC, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "economy", "gold_base": 2, "gold_per": 1.0, "gold_per_unit": "cards", "halve_on_loss": false}
					],
					"r_conditional_effects": [
						{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "grant_terazin", "amount": 1}]},
						{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "grant_terazin", "amount": 1}, {"action": "grant_gold", "amount": 1}]}
					],
				}
			],
			},
			3: {
				"name": "보급 부대 ★3",
				"composition": sup_comp,
				"card_tags": sup_tags,
				"effects": [
				{
					"trigger_timing": PC, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "economy", "gold_base": 2, "gold_per": 1.0, "gold_per_unit": "cards", "halve_on_loss": false}
					],
					"r_conditional_effects": [
						{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "grant_terazin", "amount": 1}]},
						{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "grant_terazin", "amount": 1}, {"action": "grant_gold", "amount": 1}]}
					],
				}
			],
			},
		},
		"theme_system")

	var tac_comp := [{"unit_id":"ml_commander","count":1},{"unit_id":"ml_plasma","count":1},{"unit_id":"ml_biker","count":1}]
	var tac_tags := PackedStringArray(["military", "command"])
	_c("ml_tactical", "전술 사령부", 3, T,
		tac_comp,
		[
			{
				"trigger_timing": BS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "rank_buff", "target": "all_military", "shield_per_rank": 0.02, "atk_per_unit": 0.005, "enhanced_shield_bonus": 0.03}
				],
				"r_conditional_effects": [
					{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "rank_buff_hp", "target": "all_military", "hp_per_rank": 0.03}]},
					{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "buff", "target": "all_military", "as_bonus": 0.15}]}
				],
			}
		],
		tac_tags,
				{
			2: {
				"name": "전술 사령부 ★2",
				"composition": tac_comp,
				"card_tags": tac_tags,
				"effects": [
				{
					"trigger_timing": BS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "rank_buff", "target": "all_military", "shield_per_rank": 0.03, "atk_per_unit": 0.008, "enhanced_shield_bonus": 0.05}
					],
					"r_conditional_effects": [
						{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "rank_buff_hp", "target": "all_military", "hp_per_rank": 0.03}]},
						{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "buff", "target": "all_military", "as_bonus": 0.15}]}
					],
				}
			],
			},
			3: {
				"name": "전술 사령부 ★3",
				"composition": tac_comp,
				"card_tags": tac_tags,
				"effects": [
				{
					"trigger_timing": BS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "rank_buff", "target": "all_military", "shield_per_rank": 0.04, "atk_per_unit": 0.01, "enhanced_shield_bonus": 0.08}
					],
					"r_conditional_effects": [
						{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "rank_buff_hp", "target": "all_military", "hp_per_rank": 0.03}]},
						{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "buff", "target": "all_military", "as_bonus": 0.15}]}
					],
				}
			],
			},
		},
		"theme_system")

	var ass_comp := [{"unit_id":"ml_biker","count":2},{"unit_id":"ml_drone","count":1}]
	var ass_tags := PackedStringArray(["military", "assault"])
	_c("ml_assault", "돌격 편대", 3, T,
		ass_comp,
		[
			{
				"trigger_timing": RS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [{"action": "spawn_unit", "target": "self", "unit": "ml_biker", "count": 1}],
				"r_conditional_effects": [
					{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "swarm_buff", "target": "all_military", "atk_per_unit": 0.005, "ms_bonus": {"unit_thresh": 15, "bonus": 1}, "enhanced_count": 2}]},
					{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "lifesteal", "target": "all_military", "pct": 0.1}]}
				],
			}
		],
		ass_tags,
				{
			2: {
				"name": "돌격 편대 ★2",
				"composition": ass_comp,
				"card_tags": ass_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [{"action": "spawn_unit", "target": "self", "unit": "ml_biker", "count": 2}],
					"r_conditional_effects": [
						{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "swarm_buff", "target": "all_military", "atk_per_unit": 0.005, "ms_bonus": {"unit_thresh": 12, "bonus": 1}, "enhanced_count": 2}]},
						{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "lifesteal", "target": "all_military", "pct": 0.1}]}
					],
				}
			],
			},
			3: {
				"name": "돌격 편대 ★3",
				"composition": ass_comp,
				"card_tags": ass_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [{"action": "spawn_unit", "target": "self", "unit": "ml_biker", "count": 4}],
					"r_conditional_effects": [
						{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "swarm_buff", "target": "all_military", "atk_per_unit": 0.005, "ms_bonus": {"unit_thresh": 10, "bonus": 1}, "enhanced_count": 2}]},
						{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "lifesteal", "target": "all_military", "pct": 0.1}]}
					],
				}
			],
			},
		},
		"theme_system")

	var so_comp := [{"unit_id":"ml_sniper","count":2},{"unit_id":"ml_walker","count":1},{"unit_id":"ml_biker","count":1}]
	var so_tags := PackedStringArray(["military", "elite"])
	_c("ml_special_ops", "특수 작전대", 4, T,
		so_comp,
		[
			{
				"trigger_timing": RS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [{"action": "crit_buff", "target": "self", "chance": 0.1, "mult": 2.0}],
				"r_conditional_effects": [
					{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "crit_buff", "target": "self", "chance": 0.2, "mult": 2.0}, {"action": "crit_splash", "target": "self", "splash_pct": 0.25}]},
					{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "crit_buff", "target": "self", "chance": 0.3, "mult": 2.0}, {"action": "crit_splash", "target": "self", "splash_pct": 0.5}]}
				],
			}
		],
		so_tags,
				{
			2: {
				"name": "특수 작전대 ★2",
				"composition": so_comp,
				"card_tags": so_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "crit_buff", "target": "self", "chance": 0.1, "mult": 3.0},
						{"action": "spawn_unit", "target": "self", "unit": "ml_sniper", "count": 1}
					],
					"r_conditional_effects": [
						{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "crit_buff", "target": "self", "chance": 0.2, "mult": 3.0}, {"action": "crit_splash", "target": "self", "splash_pct": 0.25}]},
						{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "crit_buff", "target": "self", "chance": 0.3, "mult": 3.0}, {"action": "crit_splash", "target": "self", "splash_pct": 0.5}]}
					],
				}
			],
			},
			3: {
				"name": "특수 작전대 ★3",
				"composition": so_comp,
				"card_tags": so_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "crit_buff", "target": "self", "chance": 0.1, "mult": 6.0},
						{"action": "spawn_unit", "target": "self", "unit": "ml_sniper", "count": 3}
					],
					"r_conditional_effects": [
						{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "crit_buff", "target": "self", "chance": 0.2, "mult": 6.0}, {"action": "crit_splash", "target": "self", "splash_pct": 0.25}]},
						{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "crit_buff", "target": "self", "chance": 0.3, "mult": 6.0}, {"action": "crit_splash", "target": "self", "splash_pct": 0.5}]}
					],
				}
			],
			},
		},
		"theme_system")

	var fac_comp := [{"unit_id":"ml_artillery","count":2},{"unit_id":"ml_sniper","count":1},{"unit_id":"ml_biker","count":1}]
	var fac_tags := PackedStringArray(["military", "supply"])
	_c("ml_factory", "군수 공장", 4, T,
		fac_comp,
		[
			{
				"trigger_timing": OE, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": CO,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "counter_produce", "event": "CO", "threshold": 10, "rewards": {"global_military_atk_pct": 0.05}}
				],
				"r_conditional_effects": [
					{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "upgrade_shop_bonus", "slot_delta": 1, "terazin_discount": 1}]},
					{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "upgrade_shop_bonus", "slot_delta": 1, "terazin_discount": 1}]}
				],
			}
		],
		fac_tags,
				{
			2: {
				"name": "군수 공장 ★2",
				"composition": fac_comp,
				"card_tags": fac_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": CO,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "counter_produce", "event": "CO", "threshold": 8, "rewards": {"global_military_atk_pct": 0.07}}
					],
					"r_conditional_effects": [
						{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "upgrade_shop_bonus", "slot_delta": 1, "terazin_discount": 1}]},
						{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "upgrade_shop_bonus", "slot_delta": 1, "terazin_discount": 1}]}
					],
				}
			],
			},
			3: {
				"name": "군수 공장 ★3",
				"composition": fac_comp,
				"card_tags": fac_tags,
				"effects": [
				{
					"trigger_timing": OE, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": CO,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "counter_produce", "event": "CO", "threshold": 6, "rewards": {"global_military_atk_pct": 0.1, "global_military_range_bonus": 1}}
					],
					"r_conditional_effects": [
						{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "upgrade_shop_bonus", "slot_delta": 1, "terazin_discount": 1}]},
						{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "upgrade_shop_bonus", "slot_delta": 1, "terazin_discount": 1}]}
					],
				}
			],
			},
		},
		"theme_system")

	var com_comp := [{"unit_id":"ml_commander","count":1},{"unit_id":"ml_walker","count":1},{"unit_id":"ml_artillery","count":1},{"unit_id":"ml_biker","count":1}]
	var com_tags := PackedStringArray(["military", "headquarters"])
	_c("ml_command", "통합 사령부", 5, T,
		com_comp,
		[
			{
				"trigger_timing": RS, "max_activations": -1,
				"trigger_layer1": -1, "trigger_layer2": -1,
				"require_tenure": 0, "require_other_card": false, "is_threshold": false,
				"actions": [
					{"action": "train", "target": "all_military", "amount": 1},
					{"action": "revive", "target": "self_enhanced", "hp_pct": 0.25, "limit_per_combat": 1}
				],
				"r_conditional_effects": [
					{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "revive_scope_override", "target": "self_all"}]},
					{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "revive_scope_override", "target": "self_and_adj_all"}]}
				],
			}
		],
		com_tags,
				{
			2: {
				"name": "통합 사령부 ★2",
				"composition": com_comp,
				"card_tags": com_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "train", "target": "all_military", "amount": 1},
						{"action": "revive", "target": "self_enhanced", "hp_pct": 0.5, "limit_per_combat": 1}
					],
					"r_conditional_effects": [
						{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "revive_scope_override", "target": "self_all"}]},
						{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "revive_scope_override", "target": "self_and_adj_all"}]}
					],
				}
			],
			},
			3: {
				"name": "통합 사령부 ★3",
				"composition": com_comp,
				"card_tags": com_tags,
				"effects": [
				{
					"trigger_timing": RS, "max_activations": -1,
					"trigger_layer1": -1, "trigger_layer2": -1,
					"require_tenure": 0, "require_other_card": false, "is_threshold": false,
					"actions": [
						{"action": "train", "target": "all_military", "amount": 2},
						{"action": "revive", "target": "self_enhanced", "hp_pct": 1.0, "limit_per_combat": 1}
					],
					"r_conditional_effects": [
						{"condition": "rank_gte", "threshold": 4, "effects": [{"action": "enhance_convert_card", "fraction": 0.5}, {"action": "revive_scope_override", "target": "self_all"}]},
						{"condition": "rank_gte", "threshold": 10, "effects": [{"action": "enhance_convert_card", "fraction": 1.0}, {"action": "revive_scope_override", "target": "self_and_adj_all"}]}
					],
				}
			],
			},
		},
		"theme_system")
