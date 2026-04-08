class_name AIBuildPath
extends RefCounted
## Theme-specific build path detection and scoring modifiers.
## Stateless — all methods use only their arguments.

# Phase constants
const FOUNDATION := 0
const ENGINE := 1
const PAYOFF := 2
const CAPSTONE := 3

const _PHASE_KEYS: Array[String] = ["foundation", "engine", "payoff", "capstone"]

# ================================================================
# Build path registry — derived from docs/design/cards-*.md
# ================================================================

const _BUILD_PATHS := {
	"steampunk_focused": [
		{
			"id": "steampunk_spread",
			"branch_cards": ["sp_assembly"],
			"anti_cards": ["sp_furnace"],
			"phases": {
				"foundation": ["sp_assembly", "sp_workshop"],
				"engine": ["sp_circulator", "sp_line"],
				"payoff": ["sp_warmachine", "sp_barrier"],
				"capstone": ["sp_warmachine"],
			},
			"shared_cards": ["sp_interest", "sp_barrier"],
		},
		{
			"id": "steampunk_focus",
			"branch_cards": ["sp_furnace"],
			"anti_cards": ["sp_assembly"],
			"phases": {
				"foundation": ["sp_furnace", "sp_workshop"],
				"engine": ["sp_circulator", "sp_interest"],
				"payoff": ["sp_charger", "sp_barrier"],
				"capstone": ["sp_arsenal"],
			},
			"shared_cards": ["sp_interest", "sp_barrier"],
		},
	],
	"druid_focused": [
		{
			"id": "druid_world_tree",
			"branch_cards": ["dr_deep", "dr_wt_root"],
			"anti_cards": ["dr_origin", "dr_earth"],
			"phases": {
				"foundation": ["dr_cradle", "dr_lifebeat"],
				"engine": ["dr_grace", "dr_deep", "dr_wt_root"],
				"payoff": ["dr_spore_cloud", "dr_wrath"],
				"capstone": ["dr_world"],
			},
			"shared_cards": ["dr_grace", "dr_spore_cloud", "dr_wrath"],
		},
		{
			"id": "druid_spread",
			"branch_cards": ["dr_origin", "dr_earth"],
			"anti_cards": ["dr_deep", "dr_wt_root"],
			"phases": {
				"foundation": ["dr_cradle", "dr_lifebeat"],
				"engine": ["dr_origin", "dr_earth", "dr_grace"],
				"payoff": ["dr_spore_cloud", "dr_wrath"],
				"capstone": ["dr_wrath"],
			},
			"shared_cards": ["dr_grace", "dr_spore_cloud"],
		},
	],
	"predator_focused": [
		{
			"id": "predator_swarm",
			"branch_cards": ["pr_farm", "pr_swarm_sense"],
			"anti_cards": ["pr_molt", "pr_harvest"],
			"phases": {
				"foundation": ["pr_nest", "pr_farm"],
				"engine": ["pr_queen", "pr_swarm_sense"],
				"payoff": ["pr_parasite"],
				"capstone": ["pr_transcend"],
			},
			"shared_cards": ["pr_carapace"],
		},
		{
			"id": "predator_evolution",
			"branch_cards": ["pr_molt", "pr_harvest"],
			"anti_cards": ["pr_farm", "pr_swarm_sense"],
			"phases": {
				"foundation": ["pr_nest", "pr_molt"],
				"engine": ["pr_harvest", "pr_carapace"],
				"payoff": ["pr_apex_hunt"],
				"capstone": ["pr_transcend"],
			},
			"shared_cards": ["pr_queen"],
		},
	],
	"military_focused": [
		{
			"id": "military_elite",
			"branch_cards": ["ml_barracks"],
			"anti_cards": ["ml_outpost"],
			"phases": {
				"foundation": ["ml_barracks"],
				"engine": ["ml_academy", "ml_tactical"],
				"payoff": ["ml_special_ops"],
				"capstone": ["ml_command"],
			},
			"shared_cards": ["ml_supply"],
		},
		{
			"id": "military_mass",
			"branch_cards": ["ml_outpost"],
			"anti_cards": ["ml_barracks"],
			"phases": {
				"foundation": ["ml_outpost"],
				"engine": ["ml_conscript", "ml_supply"],
				"payoff": ["ml_assault", "ml_factory"],
				"capstone": ["ml_command"],
			},
			"shared_cards": ["ml_supply"],
		},
	],
}


# ================================================================
# Phase mapping
# ================================================================

static func get_phase(round_num: int) -> int:
	if round_num <= 4:
		return FOUNDATION
	elif round_num <= 8:
		return ENGINE
	elif round_num <= 11:
		return PAYOFF
	else:
		return CAPSTONE


# ================================================================
# Build path detection
# ================================================================

## Detect which sub-strategy best matches the current board.
## Returns the best-matching path dict, or empty dict if undecided.
func detect_build_path(strategy: String, board_ids: Dictionary) -> Dictionary:
	if not _BUILD_PATHS.has(strategy):
		return {}

	var paths: Array = _BUILD_PATHS[strategy]
	var best_path := {}
	var best_score := 0.0

	for path in paths:
		var score := _score_path_match(path, board_ids)
		if score > best_score:
			best_score = score
			best_path = path

	return best_path


func _score_path_match(path: Dictionary, board_ids: Dictionary) -> float:
	var score := 0.0

	for cid in path["branch_cards"]:
		if cid in board_ids:
			score += 10.0

	for cid in path["anti_cards"]:
		if cid in board_ids:
			score -= 8.0

	var phases: Dictionary = path["phases"]
	for phase_key in _PHASE_KEYS:
		if phases.has(phase_key):
			for cid in phases[phase_key]:
				if cid in board_ids:
					score += 3.0

	return score


# ================================================================
# Score modifiers
# ================================================================

## Additive modifier for card purchase scoring.
func score_card_modifier(card_id: String, path: Dictionary,
		board_ids: Dictionary, round_num: int) -> float:
	var mod := 0.0
	var phase := get_phase(round_num)
	var phases: Dictionary = path["phases"]

	# Anti card penalty
	if card_id in path["anti_cards"]:
		mod -= 12.0
		return mod

	# Shared card bonus
	if card_id in path.get("shared_cards", []):
		mod += 5.0

	var cur_key: String = _PHASE_KEYS[phase]
	var cur_cards: Array = phases.get(cur_key, [])

	# Current phase: missing card bonus
	if card_id in cur_cards and card_id not in board_ids:
		mod += 20.0

	# Next phase: prep bonus
	if phase < CAPSTONE:
		var next_key: String = _PHASE_KEYS[phase + 1]
		var next_cards: Array = phases.get(next_key, [])
		if card_id in next_cards and card_id not in board_ids:
			mod += 10.0

	# Capstone urgency (PAYOFF phase or later)
	if phase >= PAYOFF:
		var cap_cards: Array = phases.get("capstone", [])
		if card_id in cap_cards and card_id not in board_ids:
			mod += 15.0

	# Completion acceleration: all current phase cards owned → next phase bonus
	if phase < CAPSTONE and not cur_cards.is_empty():
		var all_owned := true
		for cid in cur_cards:
			if cid not in board_ids:
				all_owned = false
				break
		if all_owned:
			var next_key: String = _PHASE_KEYS[phase + 1]
			var next_cards: Array = phases.get(next_key, [])
			if card_id in next_cards and card_id not in board_ids:
				mod += 8.0

	return mod


## Additive modifier for card value (sell/promote decisions).
func card_value_modifier(card_id: String, path: Dictionary,
		board_ids: Dictionary, round_num: int) -> float:
	var mod := 0.0
	var phase := get_phase(round_num)

	# Anti card: encourage selling
	if card_id in path["anti_cards"]:
		mod -= 10.0
		return mod

	# Protect engine infrastructure (current + previous phases)
	var phases: Dictionary = path["phases"]
	for p in range(0, phase + 1):
		var key: String = _PHASE_KEYS[p]
		if phases.has(key) and card_id in phases[key]:
			mod += 15.0
			break

	return mod


# ================================================================
# Utility
# ================================================================

## Returns all card IDs referenced in any build path (for data integrity tests).
func get_all_card_ids() -> Array[String]:
	var ids: Array[String] = []
	for strategy in _BUILD_PATHS:
		for path in _BUILD_PATHS[strategy]:
			for cid in path["branch_cards"]:
				if cid not in ids:
					ids.append(cid)
			for cid in path["anti_cards"]:
				if cid not in ids:
					ids.append(cid)
			for cid in path.get("shared_cards", []):
				if cid not in ids:
					ids.append(cid)
			var phases: Dictionary = path["phases"]
			for phase_key in _PHASE_KEYS:
				if phases.has(phase_key):
					for cid in phases[phase_key]:
						if cid not in ids:
							ids.append(cid)
	return ids
