class_name Genome
extends RefCounted
## Autoresearch genome v2: mutable parameters for game tuning.
## Loaded from JSON, injected into HeadlessRunner / ShopLogic / AIAgent.
##
## Fixed (NOT in genome): commander bonuses, talisman effects,
## upgrade values, boss reward values, game structure (rounds/field/bench/HP).
## Card effects: Tier A params only (dr_deep_rate, pr_swarm_sense_buff, etc.).

## Per-round enemy CP multiplier (indices 0-14 = R1-R15).
var enemy_cp_curve: Array = []

## Economy parameters.
var economy: Dictionary = {}

## Per-card activation cap overrides. Empty = use CardDB defaults.
## Format: {"card_id": max_activations}
var activation_caps: Dictionary = {}

## Shop tier weights per level. Format: {"1": [100,0,0,0,0], "2": [70,28,2,0,0], ...}
var shop_tier_weights: Dictionary = {}

## Enemy unit composition per preset. Format:
## {"swarm": {"swarm_base":8, "swarm_per_r":2.5, "ranged_base":2, "ranged_per_r":0.5}, ...}
var enemy_composition: Dictionary = {}

## Enemy base stats per type. Format: {"swarm": {"atk":2.0, "hp":12.0, "as":0.8}, ...}
var enemy_stats: Dictionary = {}

## Boss scaling multipliers. Format: {"atk_mult": 1.3, "hp_mult": 1.3}
var boss_scaling: Dictionary = {}

## Starting resources. Format: {"gold": 10, "terazin": 2}
var starting_resources: Dictionary = {}

## 카드 풀 크기 오버라이드 (OBS-049). Format: {1: 22, 2: 18, 3: 15, 4: 13, 5: 11}
var pool_sizes: Dictionary = {}

## Card effect overrides (Tier A). Format: {"dr_deep_rate": 0.008, ...}
var card_effects: Dictionary = {}

## AI agent decision parameters (Tier 1 — autoresearch tunable).
## These control *how* the AI plays, separate from game balance (genome proper).
var ai_params: Dictionary = {}


# ============================================================
# Defaults (matching current hardcoded values)
# ============================================================

const DEFAULT_SHOP_TIER_WEIGHTS := {
	"1": [100, 0, 0, 0, 0],
	"2": [70, 28, 2, 0, 0],
	"3": [35, 45, 18, 2, 0],
	"4": [10, 25, 42, 20, 3],
	"5": [0, 10, 25, 45, 20],
	"6": [0, 0, 10, 40, 50],
}

const DEFAULT_ENEMY_COMPOSITION := {
	"swarm": {"swarm_base": 8, "swarm_per_r": 2.5, "ranged_base": 2, "ranged_per_r": 0.5},
	"heavy": {"heavy_base": 3, "heavy_per_r": 0.8, "melee_base": 4, "melee_per_r": 1.0, "ranged_base": 2, "ranged_per_r": 0.5},
	"sniper": {"sniper_base": 3, "sniper_per_r": 0.6, "melee_base": 5, "melee_per_r": 1.2},
	"balanced": {"melee_base": 4, "melee_per_r": 1.0, "ranged_base": 3, "ranged_per_r": 0.7, "swarm_base": 3, "swarm_per_r": 0.5},
}

const DEFAULT_ENEMY_STATS := {
	"swarm": {"atk": 2.0, "hp": 12.0, "as": 0.8},
	"melee": {"atk": 4.0, "hp": 30.0, "as": 1.2},
	"ranged": {"atk": 3.0, "hp": 15.0, "as": 1.5},
	"heavy": {"atk": 5.0, "hp": 60.0, "as": 2.0},
	"sniper": {"atk": 6.0, "hp": 10.0, "as": 2.0},
}

const DEFAULT_BOSS_SCALING := {"atk_mult": 1.3, "hp_mult": 1.3}

const DEFAULT_STARTING_RESOURCES := {"gold": 10, "terazin": 2}
const STARTING_RESOURCES_RANGE := {"gold": [5, 15], "terazin": [0, 5]}

const DEFAULT_CARD_EFFECTS := {
	"dr_deep_rate": 0.008,
	"pr_swarm_sense_buff": 0.10,
	"sp_charger_enhance_atk": 0.05,
	"pr_carapace_growth": 0.05,
	"pr_transcend_death_atk": 0.03,
}

const CARD_EFFECTS_RANGE := {
	"dr_deep_rate": [0.004, 0.020],
	"pr_swarm_sense_buff": [0.05, 0.25],
	"sp_charger_enhance_atk": [0.02, 0.12],
	"pr_carapace_growth": [0.02, 0.15],
	"pr_transcend_death_atk": [0.01, 0.10],
}

## AI decision parameters — Tier 1 "Big Knobs" for autoresearch Phase 2.
## These control AI agent behavior, not game balance.
const DEFAULT_AI_PARAMS := {
	# --- Card valuation ---
	"theme_match_bonus": 15.0,       # Purchase score: on-theme card
	"off_theme_penalty": 20.0,       # Purchase score: off-theme card
	"merge_imminent_bonus": 30.0,    # Purchase score: 3rd copy → ★2
	"merge_progress_bonus": 8.0,     # Purchase score: 2nd copy
	"core_card_bonus": 12.0,         # Purchase score: strategy core card
	"critical_path_bonus": 8.0,      # Purchase score: theme critical path card
	"synergy_pair_bonus": 6.0,       # Purchase score: per chain/theme synergy
	"late_tier_bonus": 6.0,          # Purchase score: T4+ after R10

	# --- Leveling ---
	"slow_roll_min_round": 5,        # Don't slow-roll before this round
	"slow_roll_board_cp_ratio": 1.5, # Slow-roll if avg card CP > enemy CP × this

	# --- Economy ---
	"interest_all_start": 4,         # Round to start interest banking (all strategies)
	"aggro_transition_round": 10,    # Round to stop banking and go all-in

	# --- Reroll ---
	"chain_pair_reroll_bonus": 3,    # Extra rerolls when key chain pair incomplete
	"foundation_urgency_rerolls": 5, # Extra rerolls in R1-4 without foundation
	"capstone_urgency_rerolls": 3,   # Extra rerolls for capstone when ShopLv4+

	# --- Sell ---
	"bench_sell_threshold": 12.0,    # Bench cleanup: sell below this value
	"arsenal_fuel_bonus": 15.0,      # Sell bonus for SP cards when arsenal on board
}

const AI_PARAMS_RANGE := {
	"theme_match_bonus": [5.0, 30.0],
	"off_theme_penalty": [5.0, 35.0],
	"merge_imminent_bonus": [15.0, 50.0],
	"merge_progress_bonus": [2.0, 20.0],
	"core_card_bonus": [4.0, 25.0],
	"critical_path_bonus": [2.0, 20.0],
	"synergy_pair_bonus": [2.0, 15.0],
	"late_tier_bonus": [2.0, 15.0],
	"slow_roll_min_round": [3, 8],
	"slow_roll_board_cp_ratio": [0.8, 3.0],
	"interest_all_start": [2, 8],
	"aggro_transition_round": [7, 14],
	"chain_pair_reroll_bonus": [0, 8],
	"foundation_urgency_rerolls": [0, 10],
	"capstone_urgency_rerolls": [0, 8],
	"bench_sell_threshold": [5.0, 25.0],
	"arsenal_fuel_bonus": [5.0, 30.0],
}

const DEFAULT_LEVELUP_COST := {2: 5, 3: 7, 4: 8, 5: 11, 6: 13}


# ============================================================
# Loading
# ============================================================

## Load genome from JSON file path. Returns null on failure.
static func load_file(path: String) -> Genome:
	if not FileAccess.file_exists(path):
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(json_text)
	if err != OK:
		push_error("Genome: JSON parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return null

	var data: Dictionary = json.data
	return _from_dict(data)


## Load genome from a Dictionary (for programmatic creation / tests).
static func from_dict(data: Dictionary) -> Genome:
	return _from_dict(data)


## Build a default Genome with all baseline values populated.
## Used by EnemyDB / ShopPicker / game_manager when no best_genome is available.
static func create_default() -> Genome:
	var g := Genome.new()
	g.enemy_cp_curve = [1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.4, 2.7, 3.0, 3.3, 3.6, 3.9, 4.2, 4.5]
	g.economy = {
		"base_income": [5, 5, 5, 5, 5, 6, 6, 6, 6, 6, 7, 7, 7, 7, 7],
		"reroll_cost": 1,
		"interest_per_5g": 1,
		"max_interest": 2,
		"terazin_win": 2,
		"terazin_lose": 1,
		"levelup_cost": DEFAULT_LEVELUP_COST.duplicate(),
	}
	g.activation_caps = {}
	g.shop_tier_weights = DEFAULT_SHOP_TIER_WEIGHTS.duplicate(true)
	g.enemy_composition = DEFAULT_ENEMY_COMPOSITION.duplicate(true)
	g.enemy_stats = DEFAULT_ENEMY_STATS.duplicate(true)
	g.boss_scaling = DEFAULT_BOSS_SCALING.duplicate()
	g.starting_resources = DEFAULT_STARTING_RESOURCES.duplicate()
	g.card_effects = DEFAULT_CARD_EFFECTS.duplicate()
	g.ai_params = DEFAULT_AI_PARAMS.duplicate()
	return g


static func _from_dict(data: Dictionary) -> Genome:
	var g := Genome.new()

	# --- Enemy CP curve (required, 15 values) ---
	g.enemy_cp_curve = data.get("enemy_cp_curve", [])
	if g.enemy_cp_curve.size() != 15:
		push_error("Genome: enemy_cp_curve must have 15 values, got %d" % g.enemy_cp_curve.size())
		return null

	# --- Economy (with defaults for new fields) ---
	var econ: Dictionary = data.get("economy", {})
	# Ensure levelup_cost exists with defaults
	if not econ.has("levelup_cost"):
		econ["levelup_cost"] = DEFAULT_LEVELUP_COST.duplicate()
	else:
		# JSON keys are strings; convert to int keys
		var lc: Dictionary = {}
		for k in econ["levelup_cost"]:
			lc[int(k)] = int(econ["levelup_cost"][k])
		econ["levelup_cost"] = lc
	g.economy = econ

	# --- Activation caps ---
	g.activation_caps = data.get("activation_caps", {})

	# --- Shop tier weights (default if absent) ---
	var raw_stw: Dictionary = data.get("shop_tier_weights", {})
	if raw_stw.is_empty():
		g.shop_tier_weights = DEFAULT_SHOP_TIER_WEIGHTS.duplicate(true)
	else:
		g.shop_tier_weights = {}
		for k in raw_stw:
			g.shop_tier_weights[str(k)] = raw_stw[k]

	# --- Enemy composition (default if absent) ---
	g.enemy_composition = data.get("enemy_composition", DEFAULT_ENEMY_COMPOSITION.duplicate(true))

	# --- Enemy stats (default if absent) ---
	g.enemy_stats = data.get("enemy_stats", DEFAULT_ENEMY_STATS.duplicate(true))

	# --- Boss scaling (default if absent) ---
	g.boss_scaling = data.get("boss_scaling", DEFAULT_BOSS_SCALING.duplicate())

	# --- Starting resources (default if absent) ---
	var raw_sr: Dictionary = data.get("starting_resources", {})
	g.starting_resources = DEFAULT_STARTING_RESOURCES.duplicate()
	for k in raw_sr:
		if g.starting_resources.has(k):
			g.starting_resources[k] = int(raw_sr[k])

	# --- Card effects (default if absent) ---
	var raw_ce: Dictionary = data.get("card_effects", {})
	g.card_effects = DEFAULT_CARD_EFFECTS.duplicate()
	for k in raw_ce:
		if g.card_effects.has(k):
			g.card_effects[k] = float(raw_ce[k])

	# --- AI params (Tier 1 — default if absent) ---
	var raw_ap: Dictionary = data.get("ai_params", {})
	g.ai_params = DEFAULT_AI_PARAMS.duplicate()
	for k in raw_ap:
		if g.ai_params.has(k):
			g.ai_params[k] = float(raw_ap[k])

	# --- Pool sizes (OBS-049, default empty = use CardPool defaults) ---
	var raw_ps: Dictionary = data.get("pool_sizes", {})
	for k in raw_ps:
		g.pool_sizes[int(k)] = int(raw_ps[k])

	# --- Validation ---
	var err: String = g.validate()
	if err != "":
		push_error("Genome validation failed: %s" % err)
		return null

	return g


# ============================================================
# Accessors
# ============================================================

## Get CP scale factor for a given round (1-indexed).
func get_cp_scale(round_num: int) -> float:
	if round_num < 1 or round_num > 15:
		return 1.0
	var genome_mult: float = enemy_cp_curve[round_num - 1]
	var original_mult: float = _original_round_mult(round_num)
	if original_mult <= 0.0:
		return 1.0
	return genome_mult / original_mult


## Get activation cap for a card. Returns -1 if no override.
func get_activation_cap(card_id: String) -> int:
	return activation_caps.get(card_id, -1)


## Get shop tier weights for a given shop level (1-6).
## Returns Array of 5 ints summing to 100.
func get_tier_weights(shop_level: int) -> Array:
	var key := str(shop_level)
	if shop_tier_weights.has(key):
		return shop_tier_weights[key]
	if DEFAULT_SHOP_TIER_WEIGHTS.has(key):
		return DEFAULT_SHOP_TIER_WEIGHTS[key]
	return [100, 0, 0, 0, 0]


## Get levelup cost for a given level (2-6).
func get_levelup_cost(level: int) -> int:
	var lc: Dictionary = economy.get("levelup_cost", DEFAULT_LEVELUP_COST)
	return lc.get(level, 99)


## Get reroll cost.
func get_reroll_cost() -> int:
	return economy.get("reroll_cost", 1)


## Get enemy composition for a preset name. Returns dict of base/per_r pairs.
func get_enemy_comp(preset: String) -> Dictionary:
	return enemy_composition.get(preset, {})


## Get enemy base stats for a unit type. Returns {"atk":f, "hp":f, "as":f}.
func get_enemy_stat(unit_type: String) -> Dictionary:
	return enemy_stats.get(unit_type, {"atk": 3.0, "hp": 20.0, "as": 1.0})


## Get boss ATK/HP multipliers.
func get_boss_mult() -> Dictionary:
	return boss_scaling


## Get starting gold.
func get_starting_gold() -> int:
	return starting_resources.get("gold", 10)


## Get starting terazin.
func get_starting_terazin() -> int:
	return starting_resources.get("terazin", 2)


## Get AI decision parameter (Tier 1).
func get_ai_param(key: String) -> float:
	return ai_params.get(key, DEFAULT_AI_PARAMS.get(key, 0.0))


# ============================================================
# Validation
# ============================================================

## Validate genome constraints. Returns "" if valid, error message if not.
func validate() -> String:
	# 1. CP curve: monotonically increasing, range [0.5, 8.0]
	for i in 15:
		var v: float = enemy_cp_curve[i]
		if v < 0.5 or v > 8.0:
			return "enemy_cp_curve[%d] = %.2f out of range [0.5, 8.0]" % [i, v]
		if i > 0 and enemy_cp_curve[i] < enemy_cp_curve[i - 1]:
			return "enemy_cp_curve not monotonic: [%d]=%.2f < [%d]=%.2f" % [i, enemy_cp_curve[i], i - 1, enemy_cp_curve[i - 1]]

	# 2. Base income: monotonically increasing, range [3, 10]
	var inc: Array = economy.get("base_income", [])
	if inc.size() == 15:
		for i in 15:
			var v: int = int(inc[i])
			if v < 3 or v > 10:
				return "base_income[%d] = %d out of range [3, 10]" % [i, v]
			if i > 0 and int(inc[i]) < int(inc[i - 1]):
				return "base_income not monotonic at index %d" % i

	# 3. Terazin: win > lose
	var tw: int = economy.get("terazin_win", 2)
	var tl: int = economy.get("terazin_lose", 1)
	if tw <= tl:
		return "terazin_win (%d) must be > terazin_lose (%d)" % [tw, tl]

	# 4. Interest: max >= per_5g
	var ip: int = economy.get("interest_per_5g", 1)
	var mi: int = economy.get("max_interest", 2)
	if mi < ip:
		return "max_interest (%d) must be >= interest_per_5g (%d)" % [mi, ip]

	# 5. Levelup cost: monotonically increasing, range [2, 20]
	var lc: Dictionary = economy.get("levelup_cost", DEFAULT_LEVELUP_COST)
	var prev_cost := 0
	for lv in [2, 3, 4, 5, 6]:
		var c: int = lc.get(lv, 99)
		if c < 2 or c > 20:
			return "levelup_cost[%d] = %d out of range [2, 20]" % [lv, c]
		if c <= prev_cost:
			return "levelup_cost not monotonic: lv%d (%d) <= lv%d (%d)" % [lv, c, lv - 1, prev_cost]
		prev_cost = c

	# 6. Shop tier weights: each level sums to 100, Lv1 = [100,0,0,0,0]
	for lv in ["1", "2", "3", "4", "5", "6"]:
		var w: Array = shop_tier_weights.get(lv, [])
		if w.size() != 5:
			return "shop_tier_weights[%s] must have 5 values" % lv
		var s := 0
		for v in w:
			s += int(v)
		if s != 100:
			return "shop_tier_weights[%s] sums to %d, must be 100" % [lv, s]
	var lv1: Array = shop_tier_weights.get("1", [])
	if lv1.size() == 5 and (int(lv1[0]) != 100):
		return "shop_tier_weights Lv1 must be [100,0,0,0,0]"
	# Weighted tier must be monotonically increasing
	var prev_wt := 0.0
	for lv_i in [1, 2, 3, 4, 5, 6]:
		var w: Array = shop_tier_weights.get(str(lv_i), [100, 0, 0, 0, 0])
		var wt := 0.0
		for ti in 5:
			wt += (ti + 1) * float(w[ti]) / 100.0
		if lv_i > 1 and wt < prev_wt:
			return "shop_tier_weights weighted_tier not monotonic: Lv%d (%.2f) < Lv%d (%.2f)" % [lv_i, wt, lv_i - 1, prev_wt]
		prev_wt = wt

	# 7. Starting resources: within range
	for k in starting_resources:
		if not STARTING_RESOURCES_RANGE.has(k):
			return "starting_resources: unknown key '%s'" % k
		var v: int = starting_resources[k]
		var r: Array = STARTING_RESOURCES_RANGE[k]
		if v < r[0] or v > r[1]:
			return "starting_resources[%s] = %d out of range [%d, %d]" % [k, v, r[0], r[1]]

	# 8. Card effects: each value within allowed range
	for k in card_effects:
		if not CARD_EFFECTS_RANGE.has(k):
			return "card_effects: unknown key '%s'" % k
		var v: float = card_effects[k]
		var r: Array = CARD_EFFECTS_RANGE[k]
		if v < r[0] or v > r[1]:
			return "card_effects[%s] = %.4f out of range [%.4f, %.4f]" % [k, v, r[0], r[1]]

	# 8a. AI params: each value within allowed range
	for k in ai_params:
		if not AI_PARAMS_RANGE.has(k):
			return "ai_params: unknown key '%s'" % k
		var v: float = ai_params[k]
		var r: Array = AI_PARAMS_RANGE[k]
		if v < r[0] or v > r[1]:
			return "ai_params[%s] = %.4f out of range [%.4f, %.4f]" % [k, v, r[0], r[1]]

	# 8. Enemy stats: heavy must have highest HP
	if not enemy_stats.is_empty():
		var hv_hp: float = enemy_stats.get("heavy", {}).get("hp", 60.0)
		for t in ["swarm", "melee", "ranged", "sniper"]:
			var hp: float = enemy_stats.get(t, {}).get("hp", 20.0)
			if hv_hp < hp:
				return "heavy.hp (%.1f) must be >= %s.hp (%.1f)" % [hv_hp, t, hp]

	return ""


# ============================================================
# Internal
# ============================================================

## Mirror of EnemyDB._round_mult() for computing scale ratios.
static func _original_round_mult(r: int) -> float:
	return 1.0 + (r - 1) * 0.2 + maxf(0.0, (r - 8)) * 0.1
