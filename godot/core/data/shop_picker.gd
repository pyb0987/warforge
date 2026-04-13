class_name ShopPicker
extends RefCounted
## Shared shop logic — tier rolling and card picking.
## Used by both play (scripts/build/shop.gd) and sim (sim/shop_logic.gd)
## so that any change here propagates to both.

const DEFAULT_TIER_WEIGHTS := {
	1: [100, 0, 0, 0, 0],
	2: [70, 28, 2, 0, 0],
	3: [35, 45, 18, 2, 0],
	4: [10, 25, 42, 20, 3],
	5: [0, 10, 25, 45, 20],
	6: [0, 0, 10, 40, 50],
}


## Roll a tier (1-5) for the given shop level.
## If genome is provided, uses genome.get_tier_weights(level); otherwise uses DEFAULT_TIER_WEIGHTS.
static func roll_tier(level: int, rng: RandomNumberGenerator, genome = null) -> int:
	var weights: Array
	if genome != null:
		weights = genome.get_tier_weights(level)
	else:
		weights = DEFAULT_TIER_WEIGHTS.get(level, DEFAULT_TIER_WEIGHTS[1])

	var total := 0
	for w in weights:
		total += int(w)
	if total <= 0:
		return 1
	var roll := rng.randi_range(0, total - 1)
	var cumul := 0
	for ti in 5:
		cumul += int(weights[ti])
		if roll < cumul:
			return ti + 1
	return 1


## Pick a random card id of a given tier, applying glass-eye weight multiplier
## (Talisman.get_owned_card_weight_mult).
## pool이 제공되면 풀에서 잔여 > 0인 카드만 후보로 사용하고, 선택 후 draw().
## pool이 null이면 기존 동작 (무한 풀).
static func pick_card(tier: int, rng: RandomNumberGenerator, state: GameState, pool: CardPool = null) -> String:
	var candidates: Array[String] = []
	if pool != null:
		candidates = pool.available_of_tier(tier)
	else:
		for id in CardDB.get_all_ids():
			var tmpl := CardDB.get_template(id)
			if tmpl.get("tier", 0) == tier:
				candidates.append(id)
	if candidates.is_empty():
		if pool != null:
			return ""  # 풀 고갈 → 빈 슬롯
		return pick_card(1, rng, state) if tier != 1 else "sp_assembly"

	var picked: String = ""
	var weight_mult: float = Talisman.get_owned_card_weight_mult(state)
	if weight_mult > 1.0:
		var owned_ids: Dictionary = {}
		for card in state.board:
			if card != null:
				owned_ids[(card as CardInstance).get_base_id()] = true
		for card in state.bench:
			if card != null:
				owned_ids[(card as CardInstance).get_base_id()] = true
		var weights: Array[float] = []
		for id in candidates:
			weights.append(weight_mult if owned_ids.has(id) else 1.0)
		var total := 0.0
		for w in weights:
			total += w
		var roll := rng.randf() * total
		var cumul := 0.0
		for i in candidates.size():
			cumul += weights[i]
			if roll <= cumul:
				picked = candidates[i]
				break
		if picked.is_empty():
			picked = candidates[-1]
	else:
		picked = candidates[rng.randi_range(0, candidates.size() - 1)]

	if pool != null and not picked.is_empty():
		pool.draw(picked)
	return picked
