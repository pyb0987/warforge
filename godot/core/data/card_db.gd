extends Node
## Card database. Autoloaded as "CardDB".
## 54장 ★1 + T4/T5 ★2/★3 카드. 테마별 등록 메서드로 분리.

var _templates: Dictionary = {}
var _s2_map: Dictionary = {}  # base_id → ★2 id
var _s3_map: Dictionary = {}  # s2_id → ★3 id
var _tier_cost := {1: 2, 2: 3, 3: 4, 4: 5, 5: 6}


func _ready() -> void:
	_register_steampunk()
	_register_neutral()
	_register_druid()
	_register_predator()
	_register_military()
	_register_steampunk_stars()
	_register_neutral_stars()
	_register_druid_stars()
	_register_predator_stars()
	_register_military_stars()
	print("[CardDB] Registered %d cards." % _templates.size())


func get_template(id: String) -> Dictionary:
	return _templates.get(id, {})

func get_s2_id(base_id: String) -> String:
	return _s2_map.get(base_id, "")

func get_s3_id(s2_id: String) -> String:
	return _s3_map.get(s2_id, "")

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


## Compact card registration.
## effects: Array of Dicts, each with {action, target, ...params}
func _c(id: String, nm: String, tier: int, theme: int,
		comp: Array, timing: int, max_act: int,
		effects: Array, tags: PackedStringArray,
		l1: int = -1, l2: int = -1,
		require_other: bool = false, require_tenure: int = 0,
		is_threshold: bool = false) -> void:
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
	}
	# Auto-register ★ mappings
	if not id.ends_with("_s2") and not id.ends_with("_s3"):
		_s2_map[id] = id + "_s2"
		_s3_map[id + "_s2"] = id + "_s3"


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
	var RS := Enums.TriggerTiming.ROUND_START
	var OE := Enums.TriggerTiming.ON_EVENT
	var BS := Enums.TriggerTiming.BATTLE_START
	var CA := Enums.TriggerTiming.ON_COMBAT_ATTACK
	var MF := Enums.Layer2.MANUFACTURE
	var UP := Enums.Layer2.UPGRADE

	_c("sp_assembly", "증기 조립소", 1, T,
		[{"unit_id":"sp_spider","count":2},{"unit_id":"sp_rat","count":1}], RS, -1,
		[_spawn("right_adj", 1, Enums.Layer1.UNIT_ADDED, MF)],
		PackedStringArray(["steampunk","production"]))

	_c("sp_furnace", "증기 용광로", 1, T,
		[{"unit_id":"sp_crab","count":1},{"unit_id":"sp_sawblade","count":1}], RS, -1,
		[_spawn("self", 1, Enums.Layer1.UNIT_ADDED, MF), _enhance("self", 0.03)],
		PackedStringArray(["steampunk","focus"]))

	_c("sp_workshop", "태엽 공방", 1, T,
		[{"unit_id":"sp_spider","count":2},{"unit_id":"sp_sawblade","count":1}], OE, 2,
		[_enhance("event_target", 0.05, 0.0, "gear", Enums.Layer1.ENHANCED, UP)],
		PackedStringArray(["steampunk","enhance"]),
		Enums.Layer1.UNIT_ADDED, MF)

	_c("sp_circulator", "증기 순환기", 2, T,
		[{"unit_id":"sp_sawblade","count":1},{"unit_id":"sp_scout","count":1}], OE, 1,
		[_spawn("event_target", 1, Enums.Layer1.UNIT_ADDED, MF)],
		PackedStringArray(["steampunk","cycle"]),
		-1, UP)

	# 이자기: 설계상 "이벤트 미방출". spawn/enhance의 output_layer를 -1로 설정.
	_c("sp_interest", "증기 이자기", 2, T,
		[{"unit_id":"sp_scout","count":2},{"unit_id":"sp_rat","count":1}], Enums.TriggerTiming.ON_REROLL, 3,
		[_spawn("self", 1, -1, -1), _enhance("self", 0.03, 0.0, "", -1, -1)],
		PackedStringArray(["steampunk","economy"]))

	_c("sp_line", "조립 라인", 3, T,
		[{"unit_id":"sp_sawblade","count":2},{"unit_id":"sp_spider","count":1}], OE, 3,
		[_spawn("both_adj", 1, Enums.Layer1.UNIT_ADDED, MF)],
		PackedStringArray(["steampunk","production"]),
		Enums.Layer1.UNIT_ADDED, MF, true)

	_c("sp_barrier", "증기 방벽", 3, T,
		[{"unit_id":"sp_titan","count":1},{"unit_id":"sp_crab","count":1}], BS, -1,
		[_shield("self", 0.20)],
		PackedStringArray(["steampunk","defense"]))

	# 전쟁 기계: [지속 효과] #화기 8기당 사거리+1. steampunk_system에서 구현 예정.
	_c("sp_warmachine", "전쟁 기계", 4, T,
		[{"unit_id":"sp_turret","count":1},{"unit_id":"sp_cannon","count":1},{"unit_id":"sp_drone","count":2}],
		Enums.TriggerTiming.PERSISTENT, -1, [],
		PackedStringArray(["steampunk","combat"]))

	# 태엽 과급기: 제조 카운터 10마다 테라진+개량. steampunk_system에서 구현 예정.
	_c("sp_charger", "태엽 과급기", 4, T,
		[{"unit_id":"sp_titan","count":1},{"unit_id":"sp_turret","count":1}], OE, -1, [],
		PackedStringArray(["steampunk","power"]),
		Enums.Layer1.UNIT_ADDED, MF)

	_c("sp_arsenal", "제국 병기창", 5, T,
		[{"unit_id":"sp_titan","count":1},{"unit_id":"sp_scorpion","count":1},{"unit_id":"sp_crab","count":1}],
		Enums.TriggerTiming.ON_SELL, -1,
		[{"action": "absorb_units", "target": "self", "absorb_count": 3}],
		PackedStringArray(["steampunk","arsenal"]))


# ═══════════════════════════════════════════════════════════════════
# NEUTRAL (14 cards)
# ═══════════════════════════════════════════════════════════════════
func _register_neutral() -> void:
	var T := Enums.CardTheme.NEUTRAL
	var RS := Enums.TriggerTiming.ROUND_START
	var OE := Enums.TriggerTiming.ON_EVENT
	var BS := Enums.TriggerTiming.BATTLE_START
	var PD := Enums.TriggerTiming.POST_COMBAT_DEFEAT
	var UA := Enums.Layer1.UNIT_ADDED
	var EN := Enums.Layer1.ENHANCED

	# ① 시작기 3장
	_c("ne_earth_echo", "대지의 울림", 1, T,
		[{"unit_id":"ne_scrap","count":2},{"unit_id":"ne_eagle","count":1}], RS, -1,
		[_spawn("right_adj")], PackedStringArray(["neutral","production"]))

	_c("ne_wild_pulse", "야생의 맥동", 1, T,
		[{"unit_id":"ne_archer","count":1},{"unit_id":"ne_golem","count":1}], RS, -1,
		[_enhance("self", 0.03)], PackedStringArray(["neutral","enhance"]))

	_c("ne_ruin_resonance", "유적의 공명", 2, T,
		[{"unit_id":"ne_guardian","count":1},{"unit_id":"ne_scrap","count":1}], RS, -1,
		[_spawn("self"), _enhance("self", 0.02)], PackedStringArray(["neutral","ancient"]))

	# ② 브릿지 2장
	_c("ne_wanderers", "떠돌이 무리", 2, T,
		[{"unit_id":"ne_merc","count":1},{"unit_id":"ne_scrap","count":2}], OE, 2,
		[_enhance("event_target", 0.03)],
		PackedStringArray(["neutral","versatile"]), UA)

	_c("ne_mutant_adapt", "돌연변이 적응", 3, T,
		[{"unit_id":"ne_beast","count":1},{"unit_id":"ne_mutant","count":1}], OE, 2,
		[_spawn("self")],
		PackedStringArray(["neutral","mutant"]), EN)

	# ③ 증폭기 2장
	_c("ne_mana_crystal", "마력 결정", 2, T,
		[{"unit_id":"ne_spirit","count":1},{"unit_id":"ne_scrap","count":1}], OE, 2,
		[_spawn("both_adj")],
		PackedStringArray(["neutral","mana"]), UA)

	_c("ne_ancient_catalyst", "고대 촉매", 3, T,
		[{"unit_id":"ne_guardian","count":1},{"unit_id":"ne_spirit","count":1}], OE, 2,
		[_enhance("both_adj", 0.02)],
		PackedStringArray(["neutral","ancient"]), EN)

	# ⑤ 경제 3장
	_c("ne_merchant", "방랑 상인", 1, T,
		[{"unit_id":"ne_archer","count":1},{"unit_id":"ne_scrap","count":1}], PD, 1,
		[_gold(3)], PackedStringArray(["neutral","economy"]))

	_c("ne_spirit_blessing", "정령의 축복", 3, T,
		[{"unit_id":"ne_spirit","count":2},{"unit_id":"ne_archer","count":1}], Enums.TriggerTiming.ON_MERGE, 1,
		[{"action": "grant_terazin", "target": "self", "terazin_amount": 1}, _spawn("event_target", 2)],
		PackedStringArray(["neutral","mana"]))

	_c("ne_dim_merchant", "차원 행상인", 4, T,
		[{"unit_id":"ne_merc","count":1},{"unit_id":"ne_guardian","count":1}], RS, -1,
		[{"action": "diversity_gold", "target": "self"}],
		PackedStringArray(["neutral","economy"]))

	# ⑥ 전투 2장
	_c("ne_wildforce", "야생의 힘", 2, T,
		[{"unit_id":"ne_beast","count":1},{"unit_id":"ne_chimera","count":1}], BS, -1,
		[_buff("self", 0.10)], PackedStringArray(["neutral","combat"]))

	_c("ne_chimera_cry", "키메라의 울부짖음", 3, T,
		[{"unit_id":"ne_chimera","count":1},{"unit_id":"ne_mutant","count":1}], PD, 1,
		[_enhance("self", 0.08, 0.08)],
		PackedStringArray(["neutral","reversal"]))

	# ⑦ 인내 2장
	_c("ne_ruins", "고대의 잔해", 2, T,
		[{"unit_id":"ne_golem","count":1},{"unit_id":"ne_spirit","count":1}], RS, -1,
		[_gold(2), _spawn("right_adj")],
		PackedStringArray(["neutral","time"]),
		-1, -1, false, 2)

	_c("ne_awakening", "고대의 각성", 4, T,
		[{"unit_id":"ne_guardian","count":1},{"unit_id":"ne_golem","count":1}], RS, -1,
		[_spawn("all_allies", 2), _enhance("all_allies", 0.10), _shield("all_allies", 0.20)],
		PackedStringArray(["neutral","ancient"]),
		-1, -1, false, 4, true)


# ═══════════════════════════════════════════════════════════════════
# DRUID (10 cards) — 효과는 druid_system.gd에서 처리
# ═══════════════════════════════════════════════════════════════════
func _register_druid() -> void:
	var T := Enums.CardTheme.DRUID
	var RS := Enums.TriggerTiming.ROUND_START
	var BS := Enums.TriggerTiming.BATTLE_START

	_c("dr_cradle", "숲의 요람", 1, T,
		[{"unit_id":"dr_treant_y","count":1},{"unit_id":"dr_wolf","count":1}], RS, -1, [],
		PackedStringArray(["druid","creation"]))
	_c("dr_lifebeat", "생명의 맥동", 1, T,
		[{"unit_id":"dr_boar","count":1},{"unit_id":"dr_wolf","count":1}], BS, -1, [],
		PackedStringArray(["druid","guardian"]))
	_c("dr_origin", "오래된 근원", 2, T,
		[{"unit_id":"dr_turtle","count":1},{"unit_id":"dr_vine","count":1}], RS, -1, [],
		PackedStringArray(["druid","breed"]))
	# 숲의 은혜: 설계상 "전투 종료 시" 경제 효과
	_c("dr_grace", "숲의 은혜", 2, T,
		[{"unit_id":"dr_spore","count":1},{"unit_id":"dr_wolf","count":1}],
		Enums.TriggerTiming.POST_COMBAT, -1, [],
		PackedStringArray(["druid","economy"]))
	_c("dr_earth", "대지의 축복", 2, T,
		[{"unit_id":"dr_turtle","count":1},{"unit_id":"dr_wolf","count":1}], RS, -1, [],
		PackedStringArray(["druid","earth"]))
	_c("dr_deep", "뿌리깊은 자", 3, T,
		[{"unit_id":"dr_treant_a","count":1},{"unit_id":"dr_rootguard","count":1}], RS, -1, [],
		PackedStringArray(["druid","time"]))
	_c("dr_spore_cloud", "포자 구름", 3, T,
		[{"unit_id":"dr_spore","count":1},{"unit_id":"dr_toad","count":1}], BS, -1, [],
		PackedStringArray(["druid","combat"]))
	# 태고의 분노: [지속 효과] 유닛 ≤5기일 때 ATK 버프. druid_system에서 처리.
	_c("dr_wrath", "태고의 분노", 4, T,
		[{"unit_id":"dr_spore","count":1},{"unit_id":"dr_boar","count":1}],
		Enums.TriggerTiming.PERSISTENT, -1, [],
		PackedStringArray(["druid","combat"]))
	_c("dr_wt_root", "세계수의 뿌리", 4, T,
		[{"unit_id":"dr_treant_a","count":1},{"unit_id":"dr_turtle","count":1}], RS, -1, [],
		PackedStringArray(["druid","ancient"]))
	_c("dr_world", "세계수", 5, T,
		[{"unit_id":"dr_treant_a","count":1},{"unit_id":"dr_turtle","count":1},{"unit_id":"dr_spirit","count":1}], RS, -1, [],
		PackedStringArray(["druid","worldtree"]))


# ═══════════════════════════════════════════════════════════════════
# PREDATOR (10 cards) — 부화/변태는 predator_system에서 처리
# ═══════════════════════════════════════════════════════════════════
func _register_predator() -> void:
	var T := Enums.CardTheme.PREDATOR
	var RS := Enums.TriggerTiming.ROUND_START
	var BS := Enums.TriggerTiming.BATTLE_START
	var OE := Enums.TriggerTiming.ON_EVENT
	var PC := Enums.TriggerTiming.POST_COMBAT
	var HT := Enums.Layer2.HATCH
	var MT := Enums.Layer2.METAMORPHOSIS

	_c("pr_nest", "유충 둥지", 1, T,
		[{"unit_id":"pr_larva","count":3},{"unit_id":"pr_worker","count":1}], RS, -1, [],
		PackedStringArray(["predator","hatch"]))
	# 독 양식장: RS(부화) + POST_COMBAT(골드). 이중 트리거는 predator_system에서 처리.
	_c("pr_farm", "독 양식장", 1, T,
		[{"unit_id":"pr_sniper","count":1},{"unit_id":"pr_spider","count":1}], RS, -1, [],
		PackedStringArray(["predator","economy"]))
	_c("pr_molt", "탈피의 방", 2, T,
		[{"unit_id":"pr_larva","count":2},{"unit_id":"pr_guardian","count":1}], OE, 2, [],
		PackedStringArray(["predator","metamorphosis"]),
		-1, HT)
	_c("pr_swarm_sense", "군체 감각", 2, T,
		[{"unit_id":"pr_spider","count":2},{"unit_id":"pr_larva","count":1}], BS, -1, [],
		PackedStringArray(["predator","combat"]))
	_c("pr_harvest", "변태 수확", 2, T,
		[{"unit_id":"pr_spider","count":1},{"unit_id":"pr_sniper","count":1}], OE, 1, [],
		PackedStringArray(["predator","economy"]),
		-1, MT)
	_c("pr_queen", "여왕의 산란", 3, T,
		[{"unit_id":"pr_queen","count":1},{"unit_id":"pr_worker","count":2},{"unit_id":"pr_larva","count":2}], RS, -1, [],
		PackedStringArray(["predator","hatch"]))
	_c("pr_carapace", "적응 갑각", 3, T,
		[{"unit_id":"pr_charger","count":1},{"unit_id":"pr_warrior","count":1},{"unit_id":"pr_worker","count":1}], OE, 2, [],
		PackedStringArray(["predator","enhance"]),
		-1, MT)
	_c("pr_parasite", "기생 진화", 4, T,
		[{"unit_id":"pr_flyer","count":2},{"unit_id":"pr_sniper","count":1}], PC, -1, [],
		PackedStringArray(["predator","combat"]))
	_c("pr_apex_hunt", "포식자의 사냥", 4, T,
		[{"unit_id":"pr_apex","count":1},{"unit_id":"pr_charger","count":1}], OE, 1, [],
		PackedStringArray(["predator","predation"]),
		-1, MT)
	_c("pr_transcend", "군체 초월", 5, T,
		[{"unit_id":"pr_apex","count":1},{"unit_id":"pr_queen","count":1},{"unit_id":"pr_guardian","count":1}], RS, -1, [],
		PackedStringArray(["predator","swarm"]))


# ═══════════════════════════════════════════════════════════════════
# MILITARY (10 cards) — 계급/징집은 military_system에서 처리
# ═══════════════════════════════════════════════════════════════════
func _register_military() -> void:
	var T := Enums.CardTheme.MILITARY
	var RS := Enums.TriggerTiming.ROUND_START
	var BS := Enums.TriggerTiming.BATTLE_START
	var OE := Enums.TriggerTiming.ON_EVENT
	var PC := Enums.TriggerTiming.POST_COMBAT
	var TR := Enums.Layer2.TRAIN
	var CO := Enums.Layer2.CONSCRIPT

	_c("ml_barracks", "신병 훈련소", 1, T,
		[{"unit_id":"ml_recruit","count":2},{"unit_id":"ml_infantry","count":1}], RS, -1, [],
		PackedStringArray(["military","training"]))
	_c("ml_outpost", "전진 기지", 1, T,
		[{"unit_id":"ml_recruit","count":3},{"unit_id":"ml_drone","count":1}], RS, -1, [],
		PackedStringArray(["military","frontline"]))
	_c("ml_academy", "군사 학교", 2, T,
		[{"unit_id":"ml_commander","count":1},{"unit_id":"ml_infantry","count":1}], OE, 2, [],
		PackedStringArray(["military","training"]),
		-1, TR)
	_c("ml_conscript", "징병국", 2, T,
		[{"unit_id":"ml_recruit","count":2},{"unit_id":"ml_shield","count":1}], OE, 2, [],
		PackedStringArray(["military","conscript"]),
		-1, CO)
	_c("ml_supply", "보급 부대", 2, T,
		[{"unit_id":"ml_drone","count":1},{"unit_id":"ml_biker","count":1}], PC, -1, [],
		PackedStringArray(["military","supply"]))
	_c("ml_tactical", "전술 사령부", 3, T,
		[{"unit_id":"ml_commander","count":1},{"unit_id":"ml_plasma","count":1}], BS, -1, [],
		PackedStringArray(["military","command"]))
	_c("ml_assault", "돌격 편대", 3, T,
		[{"unit_id":"ml_biker","count":2},{"unit_id":"ml_recruit","count":1}], BS, -1, [],
		PackedStringArray(["military","assault"]))
	_c("ml_special_ops", "특수 작전대", 4, T,
		[{"unit_id":"ml_sniper","count":1},{"unit_id":"ml_walker","count":1}], RS, -1, [],
		PackedStringArray(["military","elite"]))
	_c("ml_factory", "군수 공장", 4, T,
		[{"unit_id":"ml_artillery","count":1},{"unit_id":"ml_sniper","count":1}], OE, -1, [],
		PackedStringArray(["military","supply"]),
		-1, CO)
	_c("ml_command", "통합 사령부", 5, T,
		[{"unit_id":"ml_commander","count":1},{"unit_id":"ml_walker","count":1},{"unit_id":"ml_artillery","count":1}], RS, -1, [],
		PackedStringArray(["military","headquarters"]))


# ═══════════════════════════════════════════════════════════════════
# T4/T5 ★2/★3 VARIANTS
# ═══════════════════════════════════════════════════════════════════

# --- STEAMPUNK ★2/★3 ---
func _register_steampunk_stars() -> void:
	var T := Enums.CardTheme.STEAMPUNK
	var OE := Enums.TriggerTiming.ON_EVENT
	var MF := Enums.Layer2.MANUFACTURE

	# 전쟁 기계 ★2: 6기당 사거리+1, #화기 ATK +30%. steampunk_system에서 구현.
	_c("sp_warmachine_s2", "전쟁 기계 ★2", 4, T,
		[{"unit_id":"sp_turret","count":1},{"unit_id":"sp_cannon","count":1},{"unit_id":"sp_drone","count":2}],
		Enums.TriggerTiming.PERSISTENT, -1, [],
		PackedStringArray(["steampunk","combat"]))
	# 전쟁 기계 ★3: 4기당 사거리+1, 공격마다 ATK+12%(전투). steampunk_system에서 구현.
	_c("sp_warmachine_s3", "전쟁 기계 ★3", 4, T,
		[{"unit_id":"sp_turret","count":1},{"unit_id":"sp_cannon","count":1},{"unit_id":"sp_drone","count":2}],
		Enums.TriggerTiming.PERSISTENT, -1, [],
		PackedStringArray(["steampunk","combat"]))

	# 태엽 과급기 ★2: +제조20이상→20제거, 레어3택1. steampunk_system에서 구현.
	_c("sp_charger_s2", "태엽 과급기 ★2", 4, T,
		[{"unit_id":"sp_titan","count":1},{"unit_id":"sp_turret","count":1}], OE, -1, [],
		PackedStringArray(["steampunk","power"]),
		Enums.Layer1.UNIT_ADDED, MF)
	# 태엽 과급기 ★3: 합성시 에픽1개+테라진3. 제조10회마다 테라진1. steampunk_system에서 구현.
	_c("sp_charger_s3", "태엽 과급기 ★3", 4, T,
		[{"unit_id":"sp_titan","count":1},{"unit_id":"sp_turret","count":1}], OE, -1, [],
		PackedStringArray(["steampunk","power"]),
		Enums.Layer1.UNIT_ADDED, MF)

	# 제국 병기창 ★2: 유닛5기흡수, 업그레이드이전. steampunk_system에서 구현.
	_c("sp_arsenal_s2", "제국 병기창 ★2", 5, T,
		[{"unit_id":"sp_titan","count":1},{"unit_id":"sp_scorpion","count":1},{"unit_id":"sp_crab","count":1}],
		Enums.TriggerTiming.ON_SELL, -1,
		[{"action": "absorb_units", "target": "self", "absorb_count": 5, "transfer_upgrades": true}],
		PackedStringArray(["steampunk","arsenal"]))
	# 제국 병기창 ★3: 유닛7기흡수, 최다유닛타입 ATK+30%. steampunk_system에서 구현.
	_c("sp_arsenal_s3", "제국 병기창 ★3", 5, T,
		[{"unit_id":"sp_titan","count":1},{"unit_id":"sp_scorpion","count":1},{"unit_id":"sp_crab","count":1}],
		Enums.TriggerTiming.ON_SELL, -1,
		[{"action": "absorb_units", "target": "self", "absorb_count": 7, "majority_atk_bonus": 0.30}],
		PackedStringArray(["steampunk","arsenal"]))


# --- NEUTRAL ★2/★3 ---
func _register_neutral_stars() -> void:
	var T := Enums.CardTheme.NEUTRAL
	var RS := Enums.TriggerTiming.ROUND_START

	# 차원 행상인 ★2: 테마수×2골드
	_c("ne_dim_merchant_s2", "차원 행상인 ★2", 4, T,
		[{"unit_id":"ne_merc","count":1},{"unit_id":"ne_guardian","count":1}], RS, -1,
		[{"action": "diversity_gold", "target": "self", "gold_per_theme": 2}],
		PackedStringArray(["neutral","economy"]))
	# 차원 행상인 ★3: 테마수×3골드, 3종+시 테마당1테라진, 용병카드마다 유닛1기
	_c("ne_dim_merchant_s3", "차원 행상인 ★3", 4, T,
		[{"unit_id":"ne_merc","count":1},{"unit_id":"ne_guardian","count":1}], RS, -1,
		[{"action": "diversity_gold", "target": "self", "gold_per_theme": 3,
		  "terazin_threshold": 3, "terazin_per_theme": 1, "mercenary_spawn": 1}],
		PackedStringArray(["neutral","economy"]))

	# 고대의 각성 ★2: 유닛3기, ATK+15%, 방어막30% (tenure 4)
	_c("ne_awakening_s2", "고대의 각성 ★2", 4, T,
		[{"unit_id":"ne_guardian","count":1},{"unit_id":"ne_golem","count":1}], RS, -1,
		[_spawn("all_allies", 3), _enhance("all_allies", 0.15), _shield("all_allies", 0.30)],
		PackedStringArray(["neutral","ancient"]),
		-1, -1, false, 4, true)
	# 고대의 각성 ★3: +발동후 매라운드 전체유닛1기+방어막10%. awakening_system에서 구현.
	_c("ne_awakening_s3", "고대의 각성 ★3", 4, T,
		[{"unit_id":"ne_guardian","count":1},{"unit_id":"ne_golem","count":1}], RS, -1,
		[_spawn("all_allies", 3), _enhance("all_allies", 0.15), _shield("all_allies", 0.30)],
		PackedStringArray(["neutral","ancient"]),
		-1, -1, false, 4, true)
		# ★3 추가효과(매라운드 유닛1기+방어막10%)는 awakening_system에서 구현 예정


# --- DRUID ★2/★3 — 모든 효과 druid_system에서 구현 ---
func _register_druid_stars() -> void:
	var T := Enums.CardTheme.DRUID
	var RS := Enums.TriggerTiming.ROUND_START

	# 태고의 분노 ★2: ≤5기 ATK+(120%+🌳×8%), HP+60%
	_c("dr_wrath_s2", "태고의 분노 ★2", 4, T,
		[{"unit_id":"dr_spore","count":1},{"unit_id":"dr_boar","count":1}],
		Enums.TriggerTiming.PERSISTENT, -1, [],
		PackedStringArray(["druid","combat"]))
	# 태고의 분노 ★3: ≤5기 ATK×1.5,HP×1.3(곱연산), 처치HP15%
	_c("dr_wrath_s3", "태고의 분노 ★3", 4, T,
		[{"unit_id":"dr_spore","count":1},{"unit_id":"dr_boar","count":1}],
		Enums.TriggerTiming.PERSISTENT, -1, [],
		PackedStringArray(["druid","combat"]))

	# 세계수의 뿌리 ★2: 🌳+1, 🌳3→전체+1, 🌳6→전체+2
	_c("dr_wt_root_s2", "세계수의 뿌리 ★2", 4, T,
		[{"unit_id":"dr_treant_a","count":1},{"unit_id":"dr_turtle","count":1}], RS, -1, [],
		PackedStringArray(["druid","ancient"]))
	# 세계수의 뿌리 ★3: 🌳+2, 🌳3→전체+1, 🌳6→전체+2, 🌳8→에픽상점추가
	_c("dr_wt_root_s3", "세계수의 뿌리 ★3", 4, T,
		[{"unit_id":"dr_treant_a","count":1},{"unit_id":"dr_turtle","count":1}], RS, -1, [],
		PackedStringArray(["druid","ancient"]))

	# 세계수 ★2: 🌳+3자기, 전체+2. ATK×1.15, 🌳20개당+0.1. ≤20기
	_c("dr_world_s2", "세계수 ★2", 5, T,
		[{"unit_id":"dr_treant_a","count":1},{"unit_id":"dr_turtle","count":1},{"unit_id":"dr_spirit","count":1}], RS, -1, [],
		PackedStringArray(["druid","worldtree"]))
	# 세계수 ★3: ×1.3시작, 🌳10개당+0.1, ≤30기. 상한없음.
	_c("dr_world_s3", "세계수 ★3", 5, T,
		[{"unit_id":"dr_treant_a","count":1},{"unit_id":"dr_turtle","count":1},{"unit_id":"dr_spirit","count":1}], RS, -1, [],
		PackedStringArray(["druid","worldtree"]))


# --- PREDATOR ★2/★3 — 모든 효과 predator_system에서 구현 ---
func _register_predator_stars() -> void:
	var T := Enums.CardTheme.PREDATOR
	var OE := Enums.TriggerTiming.ON_EVENT
	var PC := Enums.TriggerTiming.POST_COMBAT
	var RS := Enums.TriggerTiming.ROUND_START
	var HT := Enums.Layer2.HATCH
	var MT := Enums.Layer2.METAMORPHOSIS

	# 기생 진화 ★2: 생존유닛당 부화2기(최대5), 승리시 변태2+HP15%
	_c("pr_parasite_s2", "기생 진화 ★2", 4, T,
		[{"unit_id":"pr_flyer","count":2},{"unit_id":"pr_sniper","count":1}], PC, -1, [],
		PackedStringArray(["predator","combat"]))
	# 기생 진화 ★3: 부화2기(최대5), 승패무관 변태2, HP20%, 변태방어막30%
	_c("pr_parasite_s3", "기생 진화 ★3", 4, T,
		[{"unit_id":"pr_flyer","count":2},{"unit_id":"pr_sniper","count":1}], PC, -1, [],
		PackedStringArray(["predator","combat"]))

	# 포식자의 사냥 ★2: 변태2기, ≤5기 ATK+50%, 상한2회
	_c("pr_apex_hunt_s2", "포식자의 사냥 ★2", 4, T,
		[{"unit_id":"pr_apex","count":1},{"unit_id":"pr_charger","count":1}], OE, 2, [],
		PackedStringArray(["predator","predation"]),
		-1, MT)
	# 포식자의 사냥 ★3: 변태1기, ≤5기 ATK×2곱연산, 처치HP30%, 상한2회
	_c("pr_apex_hunt_s3", "포식자의 사냥 ★3", 4, T,
		[{"unit_id":"pr_apex","count":1},{"unit_id":"pr_charger","count":1}], OE, 2, [],
		PackedStringArray(["predator","predation"]),
		-1, MT)

	# 군체 초월 ★2: 부화4기+전체2기. 사망ATK+5%, 처치HP15%
	_c("pr_transcend_s2", "군체 초월 ★2", 5, T,
		[{"unit_id":"pr_apex","count":1},{"unit_id":"pr_queen","count":1},{"unit_id":"pr_guardian","count":1}], RS, -1, [],
		PackedStringArray(["predator","swarm"]))
	# 군체 초월 ★3: +자동변태1회, 변태시ATK+5%영구
	_c("pr_transcend_s3", "군체 초월 ★3", 5, T,
		[{"unit_id":"pr_apex","count":1},{"unit_id":"pr_queen","count":1},{"unit_id":"pr_guardian","count":1}], RS, -1, [],
		PackedStringArray(["predator","swarm"]))


# --- MILITARY ★2/★3 — 모든 효과 military_system에서 구현 ---
func _register_military_stars() -> void:
	var T := Enums.CardTheme.MILITARY
	var RS := Enums.TriggerTiming.ROUND_START
	var OE := Enums.TriggerTiming.ON_EVENT
	var CO := Enums.Layer2.CONSCRIPT

	# 특수 작전대 ★2: 계급6→리더, ATK+30%, 방어막20%
	_c("ml_special_ops_s2", "특수 작전대 ★2", 4, T,
		[{"unit_id":"ml_sniper","count":1},{"unit_id":"ml_walker","count":1}], RS, -1, [],
		PackedStringArray(["military","elite"]))
	# 특수 작전대 ★3: 계급5→리더2기, ATK+40%,방어막25%, 계급15인접확대
	_c("ml_special_ops_s3", "특수 작전대 ★3", 4, T,
		[{"unit_id":"ml_sniper","count":1},{"unit_id":"ml_walker","count":1}], RS, -1, [],
		PackedStringArray(["military","elite"]))

	# 군수 공장 ★2: 카운터8→8제거,테라진1+ATK3%. 레어25%할인
	_c("ml_factory_s2", "군수 공장 ★2", 4, T,
		[{"unit_id":"ml_artillery","count":1},{"unit_id":"ml_sniper","count":1}], OE, -1, [],
		PackedStringArray(["military","supply"]),
		-1, CO)
	# 군수 공장 ★3: 카운터6→6제거,테라진2+ATK5%. 레어/에픽25%할인
	_c("ml_factory_s3", "군수 공장 ★3", 4, T,
		[{"unit_id":"ml_artillery","count":1},{"unit_id":"ml_sniper","count":1}], OE, -1, [],
		PackedStringArray(["military","supply"]),
		-1, CO)

	# 통합 사령부 ★2: 부활HP75%, ATK+15%
	_c("ml_command_s2", "통합 사령부 ★2", 5, T,
		[{"unit_id":"ml_commander","count":1},{"unit_id":"ml_walker","count":1},{"unit_id":"ml_artillery","count":1}], RS, -1, [],
		PackedStringArray(["military","headquarters"]))
	# 통합 사령부 ★3: 훈련+2, 3회/전투부활, HP100%+방어막20%, 계급8전체확대
	_c("ml_command_s3", "통합 사령부 ★3", 5, T,
		[{"unit_id":"ml_commander","count":1},{"unit_id":"ml_walker","count":1},{"unit_id":"ml_artillery","count":1}], RS, -1, [],
		PackedStringArray(["military","headquarters"]))
