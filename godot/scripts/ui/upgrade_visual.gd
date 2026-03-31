extends Panel
## Visual representation of a single upgrade item.

var _upgrade_id: String = ""

@onready var rarity_label: Label = $RarityLabel
@onready var name_label: Label = $NameLabel
@onready var desc_label: Label = $DescLabel
@onready var cost_label: Label = $CostLabel

var _rarity_colors := {
	Enums.UpgradeRarity.COMMON: Color(0.6, 0.6, 0.6),
	Enums.UpgradeRarity.RARE: Color(0.3, 0.5, 0.9),
	Enums.UpgradeRarity.EPIC: Color(0.7, 0.3, 0.9),
}

var _rarity_names := {
	Enums.UpgradeRarity.COMMON: "COMMON",
	Enums.UpgradeRarity.RARE: "RARE",
	Enums.UpgradeRarity.EPIC: "EPIC",
}


func get_upgrade_id() -> String:
	return _upgrade_id


func setup_upgrade(upgrade_id: String, show_cost: bool = true) -> void:
	_upgrade_id = upgrade_id
	var tmpl := UpgradeDB.get_upgrade(upgrade_id)
	if tmpl.is_empty():
		clear()
		return

	visible = true
	var rarity: int = tmpl["rarity"]

	rarity_label.text = _rarity_names.get(rarity, "???")
	name_label.text = tmpl["name"]
	desc_label.text = _format_desc(tmpl)

	if show_cost and tmpl["cost"] > 0:
		cost_label.text = "%dT" % tmpl["cost"]
		cost_label.visible = true
	else:
		cost_label.visible = false

	# Rarity-colored style
	var base_color: Color = _rarity_colors.get(rarity, Color.GRAY)
	var style := StyleBoxFlat.new()
	style.bg_color = base_color.darkened(0.5)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = base_color
	add_theme_stylebox_override("panel", style)


func clear() -> void:
	_upgrade_id = ""
	visible = false


func _format_desc(tmpl: Dictionary) -> String:
	var parts: PackedStringArray = []
	var mods: Dictionary = tmpl.get("stat_mods", {})
	if mods.has("atk_pct"):
		parts.append("ATK +%d%%" % int(mods["atk_pct"] * 100))
	if mods.has("hp_pct"):
		parts.append("HP +%d%%" % int(mods["hp_pct"] * 100))
	if mods.has("def"):
		parts.append("DEF +%d" % mods["def"])
	if mods.has("range"):
		parts.append("Range +%d" % mods["range"])
	if mods.has("move_speed"):
		parts.append("MS +%d" % mods["move_speed"])
	if mods.has("as_mult"):
		var pct := int((1.0 - mods["as_mult"]) * 100)
		parts.append("AS +%d%%" % pct)

	for m in tmpl.get("mechanics", []):
		parts.append(_format_mechanic(m))

	return "\n".join(parts)


func _format_mechanic(m: Dictionary) -> String:
	match m.get("type", ""):
		"thorns": return "반사 %d%%" % int(m["reflect_pct"] * 100)
		"battle_start_heal": return "전투 시작 HP +%d%%" % int(m["heal_hp_pct"] * 100)
		"armor_pierce": return "DEF %d%% 무시" % int(m["ignore_def_pct"] * 100)
		"focus_fire": return "집중 ATK +%d%%/타" % int(m["stack_atk_pct"] * 100)
		"battle_start_shield": return "방어막 HP %d%%" % int(m["shield_hp_pct"] * 100)
		"lifesteal": return "흡혈 %d%%" % int(m["steal_pct"] * 100)
		"splash": return "스플래시 %d%%" % int(m["splash_pct"] * 100)
		"phase_shift": return "첫 피격 무효"
		"tactical_retreat": return "HP %d%%↓ 후퇴+무적" % int(m["hp_threshold"] * 100)
		"chain_discharge": return "처치 시 ATK %d%% 연쇄" % int(m["chain_dmg_pct"] * 100)
		"regen": return "%.0f초마다 HP %d%% 회복" % [m["interval_sec"], int(m["heal_hp_pct"] * 100)]
		"slow_aura": return "적 MS -%d%%" % int(m["slow_pct"] * 100)
		"critical": return "크리티컬 %d%% ×%.1f" % [int(m["crit_chance"] * 100), m["crit_mult"]]
		"berserk": return "HP %d%%↓ ATK×%d AS×%d" % [int(m["hp_threshold"] * 100), int(m["atk_mult"]), int(m["as_mult"])]
		"chain_explosion": return "스플래시 %d%% + 처치 폭발" % int(m["splash_pct"] * 100)
		"immortal_core": return "치명타 생존 + 무적"
		"soul_harvest": return "처치 ATK +%d%% 누적" % int(m["kill_atk_pct"] * 100)
		"fission": return "사망 시 %d기 분열" % m["clone_count"]
		"hp_percent_dmg": return "현재 HP %d%% 추가뎀" % int(m["dmg_pct"] * 100)
	return m.get("type", "???")
