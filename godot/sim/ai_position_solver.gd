class_name AIPositionSolver
extends RefCounted
## Adjacency-aware board positioning.
## Places RS sources left, chains flow left→right.
## Stateless — all methods use only their arguments.


# ================================================================
# Static adjacency hints for theme-delegated cards (effects=[])
# ================================================================

# Cards whose theme system uses adjacency (not readable from effects array,
# since theme_system cards store effects in CardDB._theme_effects separately).
# adj_type:
#   "right" — spawns/enhances right neighbor only
#   "both" — both neighbors (or ★별 right/left 혼합)
#   "all" — all same-theme (spatial-agnostic, but central position helpful)
# {card_id: {adj_type: ...}}
# Source: data/cards/*.yaml target fields (2026-04-18 audit).
const _THEME_ADJ_HINTS := {
	# Druid
	"dr_cradle":   {"adj_type": "both"},   # tree_add right_adj(★1)/both_adj(★2+)
	"dr_origin":   {"adj_type": "both"},   # tree_absorb adj_druids, tree_breed both_adj_or_self
	"dr_lifebeat": {"adj_type": "both"},   # tree_shield self_and_both_adj
	"dr_wt_root":  {"adj_type": "all"},    # tree_distribute all_other_druid
	"dr_world":    {"adj_type": "all"},    # tree_add all_other_druid, multiply_stats self
	# Predator
	"pr_nest":     {"adj_type": "both"},   # hatch right_adj(★1)/both_adj(★2+)
	"pr_queen":    {"adj_type": "both"},   # hatch both_adj
	"pr_carapace": {"adj_type": "both"},   # hatch right_adj(★1)/both_adj(★2+)
	# Steampunk
	"sp_assembly": {"adj_type": "both"},   # spawn both_adj/right_adj
	"sp_workshop": {"adj_type": "both"},   # spawn both_adj
	"sp_interest": {"adj_type": "both"},
	"sp_line":     {"adj_type": "both"},
	# Military (재설계 2026-04-16)
	"ml_barracks":  {"adj_type": "both"},  # train right_adj(★1)/left_adj(★2+)/far_military(★3)
	"ml_conscript": {"adj_type": "both"},  # conscript both_adj
	"ml_outpost":   {"adj_type": "both"},  # conscript event_target_adj (OE — 인접 이벤트 카드에 붙음)
}


# ================================================================
# Main API
# ================================================================

## Reorder cards for optimal adjacency and chain flow.
## Returns Array[CardInstance] in optimal order (no nulls).
func solve_positions(cards: Array) -> Array:
	if cards.size() <= 1:
		return cards.duplicate()

	var infos: Array = []
	for card in cards:
		infos.append(_analyze_card(card))

	# Score pairwise adjacency benefit
	var n: int = infos.size()
	# Use greedy chain ordering:
	# 1. Start with best "source" (lowest position score)
	# 2. Greedily pick next card that benefits most from being right

	# Sort by role priority: sources first, then reactors, then independent
	var scored: Array = []
	for i in n:
		scored.append({"idx": i, "info": infos[i], "card": cards[i]})

	scored.sort_custom(func(a, b): return a["info"]["position_score"] < b["info"]["position_score"])

	# Greedy adjacency optimization: try to place adj-benefit pairs together
	var result: Array = []
	var used: Array[bool] = []
	used.resize(n)
	used.fill(false)

	# Place cards with right_adj effects first (they need right neighbors)
	for entry in scored:
		if used[entry["idx"]]:
			continue
		var info: Dictionary = entry["info"]
		if info["has_right_adj"]:
			result.append(entry["card"])
			used[entry["idx"]] = true
			# Find best right neighbor
			var best_neighbor := _find_best_right_neighbor(
				entry["card"], info, scored, used, infos)
			if best_neighbor >= 0:
				result.append(cards[best_neighbor])
				used[best_neighbor] = true

	# Place both_adj cards (want neighbors on both sides)
	for entry in scored:
		if used[entry["idx"]]:
			continue
		if entry["info"]["has_both_adj"]:
			result.append(entry["card"])
			used[entry["idx"]] = true

	# Place remaining by position score
	for entry in scored:
		if used[entry["idx"]]:
			continue
		result.append(entry["card"])
		used[entry["idx"]] = true

	return result


# ================================================================
# Card analysis
# ================================================================

func _analyze_card(card: CardInstance) -> Dictionary:
	var tmpl: Dictionary = card.template
	var cid: String = card.get_base_id()
	var timing: int = tmpl.get("trigger_timing", -1)
	var effects: Array = tmpl.get("effects", [])

	var has_right_adj := false
	var has_both_adj := false
	var output_layers: Array = []  # [{layer1, layer2}]
	var listen_l1: int = tmpl.get("trigger_layer1", -1)
	var listen_l2: int = tmpl.get("trigger_layer2", -1)

	# Read effect targets
	for eff in effects:
		var target: String = eff.get("target", "self")
		if target == "right_adj":
			has_right_adj = true
		elif target == "both_adj":
			has_both_adj = true
		var ol1: int = eff.get("output_layer1", -1)
		if ol1 != -1:
			output_layers.append({
				"layer1": ol1,
				"layer2": eff.get("output_layer2", -1),
			})

	# Theme adjacency hints
	if _THEME_ADJ_HINTS.has(cid):
		var hint: Dictionary = _THEME_ADJ_HINTS[cid]
		match hint["adj_type"]:
			"right": has_right_adj = true
			"both", "all": has_both_adj = true  # "all" also benefits central placement

	# Position score: lower = more left
	var score := 50  # default middle
	if timing == Enums.TriggerTiming.ROUND_START:
		score = 10
		if has_right_adj:
			score = 5  # Leftmost: RS + right_adj
		elif has_both_adj:
			score = 15
	elif timing == Enums.TriggerTiming.ON_EVENT:
		score = 30  # After sources
		# OE cards that also emit events (chain propagators) slightly left
		if not output_layers.is_empty():
			score = 25
	elif timing == Enums.TriggerTiming.BATTLE_START:
		score = 60
	elif timing == Enums.TriggerTiming.PERSISTENT:
		score = 65
	elif timing in [Enums.TriggerTiming.POST_COMBAT,
			Enums.TriggerTiming.POST_COMBAT_VICTORY,
			Enums.TriggerTiming.POST_COMBAT_DEFEAT]:
		score = 70

	return {
		"has_right_adj": has_right_adj,
		"has_both_adj": has_both_adj,
		"output_layers": output_layers,
		"listen_l1": listen_l1,
		"listen_l2": listen_l2,
		"timing": timing,
		"position_score": score,
		"theme": tmpl.get("theme", 0),
		"cid": cid,
	}


## Find the best card to place immediately right of a source card.
func _find_best_right_neighbor(source_card: CardInstance,
		source_info: Dictionary, scored: Array,
		used: Array[bool], all_infos: Array) -> int:
	var best_idx := -1
	var best_score := -1.0

	for entry in scored:
		var idx: int = entry["idx"]
		if used[idx]:
			continue
		var info: Dictionary = all_infos[idx]
		var benefit := _adjacency_benefit(source_info, info)
		if benefit > best_score:
			best_score = benefit
			best_idx = idx

	if best_score > 0.0:
		return best_idx
	return -1


## Score the benefit of placing left_info's card directly left of right_info's.
func _adjacency_benefit(left: Dictionary, right: Dictionary) -> float:
	var score := 0.0

	# Source spawns right_adj → right card receives units
	if left["has_right_adj"]:
		score += 10.0

	# Chain connection: left emits events that right listens to
	for ol in left["output_layers"]:
		if right["listen_l1"] != -1 and ol["layer1"] == right["listen_l1"]:
			score += 8.0
			if right["listen_l2"] != -1 and ol["layer2"] == right["listen_l2"]:
				score += 4.0  # Exact layer2 match

	# Same theme adjacency for druids (tree sharing)
	if left["theme"] == Enums.CardTheme.DRUID and right["theme"] == Enums.CardTheme.DRUID:
		if left.get("has_both_adj", false) or left.get("has_right_adj", false):
			score += 5.0

	return score
