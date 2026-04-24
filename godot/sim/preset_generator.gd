class_name PresetGenerator
extends RefCounted
## Preset generator — target_cp → theme-based army composition.
##
## Mirrors scripts/preset_generator.py — keep in sync.
##
## Phase 2 (2026-04-24): Parameterized CP formula (autoresearch-tunable).
##
##   CP = FORMULA_BASE + (atk/as)^FORMULA_ALPHA × hp^FORMULA_BETA
##
##   - FORMULA_BASE: presence CP (every unit occupies a slot)
##   - FORMULA_ALPHA: DPS exponent (sub-linear damage returns)
##   - FORMULA_BETA: HP exponent (sub-linear survival returns)
##
##   Tuned via cp_formula_autoresearch.py + parity_evaluator.py.


# ═══════════════════════════════════════════════════════════════════
# CP Formula Coefficients — AUTORESEARCH-TUNABLE
# ═══════════════════════════════════════════════════════════════════

const FORMULA_BASE := 19.35
const FORMULA_ALPHA := 0.249
const FORMULA_BETA := 0.905


# ═══════════════════════════════════════════════════════════════════
# UNIT_STATS — mirror of godot/core/data/unit_db.gd (IMMUTABLE)
# ═══════════════════════════════════════════════════════════════════

const UNIT_STATS := {
	# ── Steampunk (10) ──
	"sp_spider":   {"atk": 2, "hp": 20,  "as": 0.5},
	"sp_rat":      {"atk": 2, "hp": 15,  "as": 0.5},
	"sp_sawblade": {"atk": 4, "hp": 40,  "as": 1.0},
	"sp_scorpion": {"atk": 6, "hp": 55,  "as": 1.0},
	"sp_crab":     {"atk": 5, "hp": 70,  "as": 1.5},
	"sp_titan":    {"atk": 4, "hp": 100, "as": 1.5},
	"sp_cannon":   {"atk": 5, "hp": 35,  "as": 1.0},
	"sp_drone":    {"atk": 4, "hp": 20,  "as": 0.5},
	"sp_turret":   {"atk": 8, "hp": 30,  "as": 1.5},
	"sp_scout":    {"atk": 2, "hp": 25,  "as": 0.5},

	# ── Druid (10) ──
	"dr_wolf":      {"atk": 7,  "hp": 40,  "as": 0.5},
	"dr_boar":      {"atk": 9,  "hp": 60,  "as": 1.0},
	"dr_treant_y":  {"atk": 8,  "hp": 80,  "as": 1.0},
	"dr_spirit":    {"atk": 7,  "hp": 60,  "as": 1.0},
	"dr_turtle":    {"atk": 4,  "hp": 100, "as": 1.5},
	"dr_treant_a":  {"atk": 6,  "hp": 150, "as": 1.5},
	"dr_rootguard": {"atk": 5,  "hp": 70,  "as": 1.0},
	"dr_vine":      {"atk": 8,  "hp": 50,  "as": 1.0},
	"dr_toad":      {"atk": 7,  "hp": 45,  "as": 1.0},
	"dr_spore":     {"atk": 14, "hp": 40,  "as": 1.5},

	# ── Predator (10) ──
	"pr_larva":    {"atk": 2, "hp": 15, "as": 0.5},
	"pr_worker":   {"atk": 2, "hp": 20, "as": 1.0},
	"pr_spider":   {"atk": 2, "hp": 12, "as": 0.5},
	"pr_warrior":  {"atk": 3, "hp": 25, "as": 1.0},
	"pr_charger":  {"atk": 4, "hp": 30, "as": 1.0},
	"pr_sniper":   {"atk": 3, "hp": 15, "as": 1.0},
	"pr_flyer":    {"atk": 3, "hp": 20, "as": 0.5},
	"pr_queen":    {"atk": 2, "hp": 40, "as": 1.5},
	"pr_guardian": {"atk": 6, "hp": 45, "as": 1.5},
	"pr_apex":     {"atk": 8, "hp": 30, "as": 1.0},

	# ── Military (10) ──
	"ml_recruit":   {"atk": 3,  "hp": 30, "as": 0.5},
	"ml_infantry":  {"atk": 6,  "hp": 50, "as": 1.0},
	"ml_shield":    {"atk": 3,  "hp": 75, "as": 1.5},
	"ml_drone":     {"atk": 3,  "hp": 20, "as": 0.5},
	"ml_biker":     {"atk": 5,  "hp": 40, "as": 0.5},
	"ml_plasma":    {"atk": 6,  "hp": 35, "as": 1.0},
	"ml_sniper":    {"atk": 8,  "hp": 25, "as": 1.5},
	"ml_artillery": {"atk": 12, "hp": 40, "as": 1.5},
	"ml_commander": {"atk": 4,  "hp": 55, "as": 1.0},
	"ml_walker":    {"atk": 9,  "hp": 85, "as": 1.5},

	# ── Neutral (10) — player cards only ──
	"ne_scrap":    {"atk": 2,  "hp": 25,  "as": 0.5},
	"ne_golem":    {"atk": 3,  "hp": 70,  "as": 1.5},
	"ne_spirit":   {"atk": 6,  "hp": 20,  "as": 1.0},
	"ne_eagle":    {"atk": 5,  "hp": 15,  "as": 0.5},
	"ne_guardian": {"atk": 10, "hp": 35,  "as": 1.5},
	"ne_merc":     {"atk": 5,  "hp": 45,  "as": 1.0},
	"ne_archer":   {"atk": 5,  "hp": 30,  "as": 1.0},
	"ne_chimera":  {"atk": 7,  "hp": 50,  "as": 1.0},
	"ne_beast":    {"atk": 8,  "hp": 35,  "as": 0.5},
	"ne_mutant":   {"atk": 6,  "hp": 100, "as": 1.5},

	# ── Military Enhanced (6) — player cards only ──
	"ml_recruit_enhanced":  {"atk": 5, "hp": 45,  "as": 0.7},
	"ml_infantry_enhanced": {"atk": 9, "hp": 70,  "as": 1.0},
	"ml_shield_enhanced":   {"atk": 4, "hp": 110, "as": 1.5},
	"ml_drone_enhanced":    {"atk": 5, "hp": 30,  "as": 0.7},
	"ml_biker_enhanced":    {"atk": 8, "hp": 55,  "as": 0.7},
	"ml_plasma_enhanced":   {"atk": 9, "hp": 50,  "as": 1.0},
}


## Enemy preset → weighted unit pool.
const THEME_RECIPES := {
	"predator": {
		"pr_larva": 0.10, "pr_worker": 0.10, "pr_spider": 0.10, "pr_warrior": 0.10,
		"pr_charger": 0.10, "pr_sniper": 0.10, "pr_flyer": 0.10, "pr_queen": 0.10,
		"pr_guardian": 0.10, "pr_apex": 0.10,
	},
	"druid": {
		"dr_wolf": 0.10, "dr_boar": 0.10, "dr_treant_y": 0.10, "dr_spirit": 0.10,
		"dr_turtle": 0.10, "dr_treant_a": 0.10, "dr_rootguard": 0.10, "dr_vine": 0.10,
		"dr_toad": 0.10, "dr_spore": 0.10,
	},
	"military": {
		"ml_recruit": 0.10, "ml_infantry": 0.10, "ml_shield": 0.10, "ml_drone": 0.10,
		"ml_biker": 0.10, "ml_plasma": 0.10, "ml_sniper": 0.10, "ml_artillery": 0.10,
		"ml_commander": 0.10, "ml_walker": 0.10,
	},
	"steampunk": {
		"sp_spider": 0.10, "sp_rat": 0.10, "sp_sawblade": 0.10, "sp_scorpion": 0.10,
		"sp_crab": 0.10, "sp_titan": 0.10, "sp_cannon": 0.10, "sp_drone": 0.10,
		"sp_turret": 0.10, "sp_scout": 0.10,
	},
}


## Formula CP: BASE + (atk/as)^ALPHA × hp^BETA, scaled by stat_mult².
static func unit_intrinsic_cp(unit_id: String, stat_mult: float = 1.0) -> float:
	var stats: Dictionary = UNIT_STATS.get(unit_id, {})
	if stats.is_empty():
		return FORMULA_BASE * stat_mult * stat_mult
	var atk: float = float(stats.get("atk", 3))
	var hp: float = float(stats.get("hp", 20))
	var as_val: float = maxf(float(stats.get("as", 1.0)), 0.01)
	var dps: float = atk / as_val
	var cp: float = FORMULA_BASE + pow(dps, FORMULA_ALPHA) * pow(hp, FORMULA_BETA)
	return cp * stat_mult * stat_mult


## Derive unit counts per unit_id so Σ(CP × count) ≈ target_cp.
## Returns sparse Dictionary {unit_id: count}.
static func derive_comp(preset_name: String, target_cp: float, stat_mult: float = 1.0) -> Dictionary:
	var weights: Dictionary = THEME_RECIPES.get(preset_name, {})
	if weights.is_empty():
		return {}

	var avg_cp_per_unit := 0.0
	for uid in weights:
		avg_cp_per_unit += float(weights[uid]) * unit_intrinsic_cp(uid, stat_mult)

	if avg_cp_per_unit <= 0.0:
		return {}

	var total_raw: float = target_cp / avg_cp_per_unit
	var target_total: int = maxi(1, roundi(total_raw))

	var raw: Dictionary = {}
	var counts: Dictionary = {}
	var assigned := 0
	for uid in weights:
		var r: float = total_raw * float(weights[uid])
		raw[uid] = r
		var f: int = int(r)
		counts[uid] = f
		assigned += f

	var remaining: int = target_total - assigned
	if remaining > 0:
		var keys: Array = raw.keys()
		keys.sort_custom(func(a, b):
			var fa: float = raw[a] - float(int(raw[a]))
			var fb: float = raw[b] - float(int(raw[b]))
			return fa > fb
		)
		for i in remaining:
			var uid: String = keys[i]
			counts[uid] = int(counts[uid]) + 1

	var result: Dictionary = {}
	for uid in counts:
		if int(counts[uid]) > 0:
			result[uid] = counts[uid]
	return result


## Total army CP = Σ unit_intrinsic_cp × count. ADDITIVE.
static func army_effective_cp(counts: Dictionary, stat_mult: float = 1.0) -> float:
	var total := 0.0
	for uid in counts:
		total += unit_intrinsic_cp(uid, stat_mult) * float(counts[uid])
	return total


static func preset_cp_estimate(preset_name: String, target_cp: float, stat_mult: float = 1.0) -> float:
	var counts: Dictionary = derive_comp(preset_name, target_cp, stat_mult)
	return army_effective_cp(counts, stat_mult)
