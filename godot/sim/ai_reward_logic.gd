class_name AIRewardLogic
extends RefCounted
## AI decision logic for boss rewards, upgrades, and merge bonuses.
## Separated from AIAgent to keep file sizes manageable.
##
## All methods are stateless — they take state + strategy and return decisions.

const _THEME_MAP := {
	"steampunk_focused": Enums.CardTheme.STEAMPUNK,
	"druid_focused": Enums.CardTheme.DRUID,
	"predator_focused": Enums.CardTheme.PREDATOR,
	"military_focused": Enums.CardTheme.MILITARY,
}

## Boss reward priority per strategy. Higher = better.
## Only includes permanent rewards (P1 tier) — P0 (★승급) is handled separately.
const _REWARD_PRIORITY := {
	"predator_focused": {
		"r4_3": 95, "r4_6": 90, "r12_6": 98,  # spawn/물량 핵심
		"r4_5": 70, "r8_3": 60, "r12_3": 65,
		"r8_6": 50, "r8_5": 40, "r12_5": 55,
	},
	"druid_focused": {
		"r4_5": 95, "r8_5": 90, "r12_3": 85,  # enhance/chain 핵심
		"r8_3": 80, "r4_3": 60, "r4_6": 50,
		"r8_6": 70, "r12_6": 40, "r12_5": 45,
	},
	"steampunk_focused": {
		"r8_3": 95, "r12_3": 98, "r4_5": 85,  # activation/chain 핵심
		"r8_5": 80, "r4_6": 50, "r4_3": 60,
		"r8_6": 70, "r12_5": 45, "r12_6": 40,
	},
	"military_focused": {
		"r8_6": 95, "r12_4": 90, "r8_3": 80,  # 승전+합성 핵심
		"r12_3": 75, "r4_5": 70, "r4_3": 60,
		"r8_5": 65, "r4_6": 50, "r12_5": 55,
	},
}

## Star upgrade rewards (P0 — always prioritized).
const _STAR_REWARDS := ["r4_1", "r8_1", "r12_1"]

## Direct buff rewards (P1.5 — strong single-card impact).
const _DIRECT_REWARDS := ["r4_7", "r4_8", "r8_7", "r12_7", "r12_8"]

## Economy/structure rewards (P2 — fallback).
const _ECONOMY_REWARDS := ["r4_2", "r4_9", "r8_2", "r8_9", "r12_2", "r12_9"]


# ================================================================
# Boss Reward Selection
# ================================================================

## Choose 1 boss reward from 4 choices. Returns decision dict.
## {"reward_id": String, "target_card": CardInstance|null, "target_cards": Array}
func choose_boss_reward(choices: Array[String], state: GameState,
		strategy: String) -> Dictionary:
	if choices.is_empty():
		return {"reward_id": "", "target_card": null, "target_cards": []}

	var best_id := ""
	var best_score := -1.0

	for id in choices:
		var score := _score_reward(id, state, strategy)
		if score > best_score:
			best_score = score
			best_id = id

	# Determine target card(s) if needed
	var data: Dictionary = BossRewardDB.get_data(best_id)
	var needs_target: int = data.get("needs_target", 0)
	var target_card: CardInstance = null
	var target_cards: Array = []

	if needs_target >= 1:
		target_card = _pick_best_target(state, strategy)
		target_cards.append(target_card)
	if needs_target >= 2:
		var second := _pick_best_target(state, strategy, [target_card])
		if second:
			target_cards.append(second)

	return {
		"reward_id": best_id,
		"target_card": target_card,
		"target_cards": target_cards,
	}


func _score_reward(id: String, state: GameState, strategy: String) -> float:
	# P0: ★승급 = highest priority
	if id in _STAR_REWARDS:
		var has_target := _pick_best_target(state, strategy)
		if has_target:
			return 200.0
		return 10.0  # No valid target → low score

	# Check strategy-specific priority map
	var prio_map: Dictionary = _REWARD_PRIORITY.get(strategy, {})
	if prio_map.has(id):
		return float(prio_map[id])

	# P1.5: Direct buffs
	if id in _DIRECT_REWARDS:
		var has_target := _pick_best_target(state, strategy)
		return 75.0 if has_target else 5.0

	# P2: Economy/structure
	if id in _ECONOMY_REWARDS:
		return 30.0

	return 20.0  # Unknown reward


## Pick the best target card for a reward. Prefers theme cards with highest CP.
func _pick_best_target(state: GameState, strategy: String,
		exclude: Array = []) -> CardInstance:
	var theme: int = _THEME_MAP.get(strategy, -1)
	var best: CardInstance = null
	var best_score := -999.0

	for card in state.get_active_board():
		if card == null or card in exclude:
			continue
		var c: CardInstance = card as CardInstance
		var score := 0.0

		# Prefer theme cards
		var card_theme: int = c.template.get("theme", 0)
		if theme >= 0 and card_theme == theme:
			score += 100.0
		elif card_theme == Enums.CardTheme.NEUTRAL:
			score += 10.0

		# Prefer higher CP (more units = more impact for buffs)
		score += c.get_total_units() * 2.0 + c.get_total_atk() * 0.1

		# Prefer higher star (★2 → ★3 is more valuable than ★1 → ★2)
		score += c.star_level * 20.0

		# Prefer cards that can still be starred up
		if c.star_level < 3:
			score += 30.0

		if score > best_score:
			best_score = score
			best = c

	return best


# ================================================================
# Upgrade Selection (for merge bonuses and boss reward upgrades)
# ================================================================

## Choose an upgrade of given rarity + target card.
## Returns {"upgrade_id": String, "target_card": CardInstance}
func choose_upgrade(rarity: int, state: GameState,
		strategy: String) -> Dictionary:
	var ids := UpgradeDB.get_ids_by_rarity(rarity)
	if ids.is_empty():
		return {"upgrade_id": "", "target_card": null}

	# Pick best target card (must have free upgrade slot)
	var target := _pick_upgrade_target(state, strategy)
	if target == null:
		return {"upgrade_id": ids[0], "target_card": null}

	# Score each upgrade for this target
	var best_id := ""
	var best_score := -999.0
	for uid in ids:
		var score := _score_upgrade_for_card(uid, target, strategy)
		if score > best_score:
			best_score = score
			best_id = uid

	return {"upgrade_id": best_id, "target_card": target}


## Pick the best card to receive an upgrade. Must have free slot.
func _pick_upgrade_target(state: GameState, strategy: String) -> CardInstance:
	var theme: int = _THEME_MAP.get(strategy, -1)
	var best: CardInstance = null
	var best_score := -999.0

	for card in state.get_active_board():
		if card == null:
			continue
		var c: CardInstance = card as CardInstance
		if not c.can_attach_upgrade():
			continue

		var score := 0.0
		var card_theme: int = c.template.get("theme", 0)
		if theme >= 0 and card_theme == theme:
			score += 50.0
		elif card_theme == Enums.CardTheme.NEUTRAL:
			score += 5.0

		# More units = upgrade affects more units
		score += c.get_total_units() * 1.5
		score += c.star_level * 15.0
		# Fewer existing upgrades = more valuable slot
		score += (5 - c.upgrades.size()) * 3.0

		if score > best_score:
			best_score = score
			best = c

	return best


## Score an upgrade for a specific card.
func _score_upgrade_for_card(upgrade_id: String, card: CardInstance,
		_strategy: String) -> float:
	var tmpl := UpgradeDB.get_upgrade(upgrade_id)
	if tmpl.is_empty():
		return 0.0

	var mods: Dictionary = tmpl.get("stat_mods", {})
	var score := 0.0
	var units := float(card.get_total_units())

	# ATK% is best for high-unit-count cards
	score += mods.get("atk_pct", 0.0) * units * 10.0
	# HP% for survivability
	score += mods.get("hp_pct", 0.0) * units * 5.0
	# AS improvement
	var as_m: float = mods.get("as_mult", 0.0)
	if as_m > 0.0 and as_m < 1.0:
		score += (1.0 - as_m) * units * 8.0  # Lower = faster = better
	# DEF
	score += mods.get("def", 0.0) * units * 3.0
	# Range (valuable for few-unit high-atk cards)
	score += mods.get("range", 0.0) * 5.0

	# Mechanics bonus (rough heuristic)
	var mechs: Array = tmpl.get("mechanics", [])
	score += mechs.size() * 10.0

	return score


# ================================================================
# Upgrade Purchasing (Terazin Shop)
# ================================================================

## Buy upgrades from offered list. Modifies state.terazin and card.upgrades.
func buy_upgrades(state: GameState, offered: Array,
		strategy: String) -> Array[Dictionary]:
	var purchased: Array[Dictionary] = []

	# Sort by value: rare > common (higher rarity first)
	var sorted_offers := offered.duplicate()
	sorted_offers.sort_custom(func(a, b):
		return a.get("rarity", 0) > b.get("rarity", 0))

	for item in sorted_offers:
		var cost: int = item.get("cost", 99)
		var uid: String = item.get("id", "")

		# Budget check: keep some terazin for future rounds
		if state.terazin < cost:
			continue
		# Don't spend last 2 terazin (save for rerolls)
		if state.terazin - cost < 2 and state.round_num < 12:
			continue

		# Find a target card with free slot
		var target := _pick_upgrade_target(state, strategy)
		if target == null:
			continue

		# Buy and attach
		state.terazin -= cost
		target.attach_upgrade(uid)
		purchased.append({
			"id": uid,
			"target": target.get_base_id(),
			"cost": cost,
		})

	return purchased


# ================================================================
# Upgrade Shop Roll (pure function, no UI dependency)
# ================================================================

## Roll 2 upgrades for the terazin shop. ShopLv >= 2 required.
static func roll_upgrade_shop(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var offered: Array[Dictionary] = []
	for _i in 2:
		var roll := rng.randf()
		var rarity: int
		if roll < 0.70:
			rarity = Enums.UpgradeRarity.COMMON
		else:
			rarity = Enums.UpgradeRarity.RARE
		var ids := UpgradeDB.get_ids_by_rarity(rarity)
		if ids.is_empty():
			continue
		var chosen: String = ids[rng.randi_range(0, ids.size() - 1)]
		var tmpl := UpgradeDB.get_upgrade(chosen)
		offered.append({
			"id": chosen,
			"cost": tmpl.get("cost", 4),
			"rarity": rarity,
		})
	return offered
