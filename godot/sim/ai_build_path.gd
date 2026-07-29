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
	"soft_steampunk": [
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
			"anti_penalty": 36.0,
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
			"anti_penalty": 36.0,
		},
	],
	"soft_druid": [
		{
			"id": "druid_world_tree",
			"requires_branch_card": true,
			"branch_cards": ["dr_deep", "dr_wt_root"],
			"anti_cards": ["dr_origin", "dr_prune"],
			"phases": {
				"foundation": ["dr_cradle", "dr_lifebeat"],
				"engine": ["dr_grace", "dr_deep", "dr_wt_root"],
				"payoff": ["dr_spore_cloud", "dr_wrath"],
				"capstone": ["dr_world"],
			},
			"shared_cards": ["dr_grace", "dr_spore_cloud", "dr_wrath"],
		},
		{
			"id": "druid_garden",
			"requires_branch_card": true,
			"branch_cards": ["dr_origin", "dr_prune"],
			"anti_cards": ["dr_deep", "dr_wt_root"],
			"phases": {
				"foundation": ["dr_cradle", "dr_lifebeat"],
				"engine": ["dr_origin", "dr_prune", "dr_grace"],
				"payoff": ["dr_spore_cloud", "dr_wrath"],
				"capstone": ["dr_wrath"],
			},
			"shared_cards": ["dr_grace", "dr_spore_cloud"],
		},
	],
	"soft_predator": [
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
	# 재설계 (trace 012, 2026-04-16): 징병국↔전진기지 스왑 반영.
	# 정예형: 훈련소(T1) → 군사학교(T2) → 보급(T2) → 전술사령부(T3) → 특수작전대(T4) → 통합사령부(T5)
	# 물량형: 징병국(T1) → 전진기지(T2) → 보급(T2) → 돌격편대(T3) → 군수공장(T4) → 통합사령부(T5)
	# 공유: ml_supply(T2), ml_tactical(T3). 양쪽 캡스톤: ml_command(T5).
	"soft_military": [
		{
			"id": "military_elite",
			"branch_cards": ["ml_barracks"],
			"anti_cards": ["ml_conscript"],
			"strict_anti": true,  # TR vs CO 체인 이벤트 배타 → 하드 veto
			"phases": {
				"foundation": ["ml_barracks"],
				"engine": ["ml_academy", "ml_tactical"],
				"payoff": ["ml_special_ops"],
				"capstone": ["ml_command"],
			},
			"shared_cards": ["ml_supply", "ml_tactical"],
		},
		{
			"id": "military_mass",
			"branch_cards": ["ml_conscript"],
			"anti_cards": ["ml_barracks"],
			"strict_anti": true,
			"phases": {
				"foundation": ["ml_conscript"],
				"engine": ["ml_outpost", "ml_supply"],
				"payoff": ["ml_assault", "ml_factory"],
				"capstone": ["ml_command"],
			},
			"shared_cards": ["ml_supply", "ml_tactical"],
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
		if path.get("requires_branch_card", false) and not _has_any_branch_card(path, board_ids):
			continue
		var score := _score_path_match(path, board_ids)
		if score > best_score:
			best_score = score
			best_path = path

	return best_path


func get_path_progress(strategy: String, board_ids: Dictionary, round_num: int) -> Array:
	var rows: Array = []
	if not _BUILD_PATHS.has(strategy):
		return rows

	var phase := get_phase(round_num)
	var current_key: String = _PHASE_KEYS[phase]
	for path in _BUILD_PATHS[strategy]:
		var phases: Dictionary = path["phases"]
		rows.append({
			"id": path["id"],
			"branch_owned": _count_owned(path.get("branch_cards", []), board_ids),
			"branch_total": path.get("branch_cards", []).size(),
			"foundation_owned": _count_owned(phases.get("foundation", []), board_ids),
			"foundation_total": phases.get("foundation", []).size(),
			"engine_owned": _count_owned(phases.get("engine", []), board_ids),
			"engine_total": phases.get("engine", []).size(),
			"payoff_owned": _count_owned(phases.get("payoff", []), board_ids),
			"payoff_total": phases.get("payoff", []).size(),
			"capstone_owned": _count_owned(phases.get("capstone", []), board_ids),
			"capstone_total": phases.get("capstone", []).size(),
			"current_phase": current_key,
			"current_owned": _count_owned(phases.get(current_key, []), board_ids),
			"current_total": phases.get(current_key, []).size(),
		})
	return rows


func get_representative_progress(strategy: String,
		board_ids: Dictionary, round_num: int) -> Dictionary:
	var rows: Array = get_path_progress(strategy, board_ids, round_num)
	if rows.is_empty():
		return {}

	var detected_path: Dictionary = detect_build_path(strategy, board_ids)
	var detected_id: String = detected_path.get("id", "") if not detected_path.is_empty() else ""
	if detected_id != "":
		for row in rows:
			if row.get("id", "") == detected_id:
				return row

	var best_row: Dictionary = rows[0]
	var best_score := _score_progress_row(best_row)
	for i in range(1, rows.size()):
		var row: Dictionary = rows[i]
		var score := _score_progress_row(row)
		if score > best_score:
			best_score = score
			best_row = row
	return best_row


func get_current_phase_lag(strategy: String,
		board_ids: Dictionary, round_num: int) -> float:
	var row: Dictionary = get_representative_progress(strategy, board_ids, round_num)
	if row.is_empty():
		return 0.0
	var total: int = row.get("current_total", 0)
	if total <= 0:
		return 0.0
	var owned: int = row.get("current_owned", 0)
	return 1.0 - clampf(float(owned) / float(total), 0.0, 1.0)


func get_phase_card_focus(strategy: String,
		board_ids: Dictionary, round_num: int) -> Dictionary:
	var row: Dictionary = get_representative_progress(strategy, board_ids, round_num)
	if row.is_empty():
		return {}
	var path: Dictionary = _find_path_by_id(strategy, row.get("id", ""))
	if path.is_empty():
		return {}

	var phase_idx: int = get_phase(round_num)
	var current_key: String = _PHASE_KEYS[phase_idx]
	var next_key: String = _PHASE_KEYS[mini(phase_idx + 1, _PHASE_KEYS.size() - 1)]
	var phases: Dictionary = path["phases"]
	var current_cards: Array = phases.get(current_key, [])
	var next_cards: Array = phases.get(next_key, [])
	var focus_cards: Array = current_cards.duplicate()
	for cid in next_cards:
		if cid not in focus_cards:
			focus_cards.append(cid)

	return {
		"path_id": path.get("id", ""),
		"current_phase": current_key,
		"current": current_cards,
		"next": next_cards,
		"focus": focus_cards,
	}


func _score_progress_row(row: Dictionary) -> float:
	return (
		float(row.get("branch_owned", 0)) * 4.0 +
		float(row.get("foundation_owned", 0)) * 3.0 +
		float(row.get("engine_owned", 0)) * 3.0 +
		float(row.get("payoff_owned", 0)) * 2.0 +
		float(row.get("capstone_owned", 0)) * 2.0
	)


func _find_path_by_id(strategy: String, path_id: String) -> Dictionary:
	if not _BUILD_PATHS.has(strategy):
		return {}
	for path in _BUILD_PATHS[strategy]:
		if path.get("id", "") == path_id:
			return path
	return {}


func _has_any_branch_card(path: Dictionary, board_ids: Dictionary) -> bool:
	for cid in path["branch_cards"]:
		if cid in board_ids:
			return true
	return false


func _count_owned(card_ids: Array, board_ids: Dictionary) -> int:
	var count := 0
	for cid in card_ids:
		if cid in board_ids:
			count += 1
	return count


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

## Strategy-level purchase modifier.
## If a build path is already detected, use its normal path-scoped modifier.
## If no path is detected yet, apply only positive seed pressure from all
## candidate paths so soft themes can find foundation/branch cards without
## prematurely penalizing the other branch.
func score_strategy_card_modifier(card_id: String, strategy: String,
		board_ids: Dictionary, round_num: int) -> float:
	var path: Dictionary = detect_build_path(strategy, board_ids)
	if not path.is_empty():
		return score_card_modifier(card_id, path, board_ids, round_num)
	if not _BUILD_PATHS.has(strategy):
		return 0.0

	var best_mod := 0.0
	for candidate in _BUILD_PATHS[strategy]:
		best_mod = maxf(best_mod,
			_seed_score_card_modifier(card_id, candidate, board_ids, round_num))
	return best_mod


func _seed_score_card_modifier(card_id: String, path: Dictionary,
		board_ids: Dictionary, round_num: int) -> float:
	if card_id in board_ids:
		return 0.0

	var mod := 0.0
	var phase := get_phase(round_num)
	var phases: Dictionary = path["phases"]
	var cur_key: String = _PHASE_KEYS[phase]
	var cur_cards: Array = phases.get(cur_key, [])

	if card_id in path.get("branch_cards", []):
		mod += 8.0
	if card_id in cur_cards:
		mod += 16.0
	if phase < CAPSTONE:
		var next_key: String = _PHASE_KEYS[phase + 1]
		var next_cards: Array = phases.get(next_key, [])
		if card_id in next_cards:
			mod += 8.0
	if card_id in path.get("shared_cards", []):
		mod += 3.0

	return mod


## Additive modifier for card purchase scoring.
func score_card_modifier(card_id: String, path: Dictionary,
		board_ids: Dictionary, round_num: int) -> float:
	var mod := 0.0
	var phase := get_phase(round_num)
	var phases: Dictionary = path["phases"]

	# Anti card penalty — path의 strict_anti 플래그에 따라 강도 조정.
	# 군대는 elite/mass가 TR/CO 이벤트 체인이 달라 진짜 배타적 → strict veto(-50).
	# 타 테마는 분기가 부드러운 선호이지 배타 아님 → 기본 약한 페널티(-12).
	# 스팀펑크는 T1 분기 후 양쪽 core를 섞으면 설계상 공유/방어/경제 슬롯을
	# 밀어내므로 path별 anti_penalty로 더 강한 branch-lock을 적용한다.
	# 트레이스 증거(2026-04-18): -50 군대만 적용 시 military WR 35→50%,
	# 타 테마 영향 최소화.
	if card_id in path["anti_cards"]:
		var strict: bool = path.get("strict_anti", false)
		mod -= 50.0 if strict else float(path.get("anti_penalty", 12.0))
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
