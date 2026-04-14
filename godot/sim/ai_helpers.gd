extends RefCounted
## AI Agent helper utilities — pure state-query functions.
## Extracted from ai_agent.gd for file size management.

const _Syn = preload("res://sim/ai_synergy_data.gd")


static func has_space(state: GameState) -> bool:
	for b in state.bench:
		if b == null:
			return true
	for b in state.board:
		if b == null:
			return true
	return false


static func count_copies(state: GameState, card_id: String) -> int:
	var count := 0
	for card in state.board:
		if card != null and (card as CardInstance).get_base_id() == card_id:
			count += 1
	for card in state.bench:
		if card != null and (card as CardInstance).get_base_id() == card_id:
			count += 1
	return count


static func get_board_ids(state: GameState) -> Dictionary:
	var ids := {}
	for card in state.board:
		if card != null:
			ids[(card as CardInstance).get_base_id()] = true
	for card in state.bench:
		if card != null:
			ids[(card as CardInstance).get_base_id()] = true
	return ids


static func get_board_cards(state: GameState) -> Array:
	var cards: Array = []
	for card in state.board:
		if card != null:
			cards.append(card)
	for card in state.bench:
		if card != null:
			cards.append(card)
	return cards


static func count_synergies(card_id: String, board_ids: Dictionary) -> int:
	var count := 0
	if _Syn.CHAIN_PAIRS.has(card_id):
		for pid in _Syn.CHAIN_PAIRS[card_id]:
			if pid in board_ids:
				count += 1
	if _Syn.THEME_SYNERGY.has(card_id):
		for pid in _Syn.THEME_SYNERGY[card_id]:
			if pid in board_ids:
				count += 1
	return count


static func has_merge_candidate(state: GameState) -> bool:
	var counts := {}
	for card in state.board:
		if card != null:
			var c := card as CardInstance
			if c.star_level == 1:
				var cid: String = c.get_base_id()
				counts[cid] = counts.get(cid, 0) + 1
	for card in state.bench:
		if card != null:
			var c := card as CardInstance
			if c.star_level == 1:
				var cid: String = c.get_base_id()
				counts[cid] = counts.get(cid, 0) + 1
	for cid in counts:
		if counts[cid] >= 2:
			return true
	return false


## Count ★1 copies of a card (purchases are always ★1 → merge needs 3 ★1).
static func count_star1_copies(state: GameState, card_id: String) -> int:
	var count := 0
	for card in state.board:
		if card != null:
			var c := card as CardInstance
			if c.get_base_id() == card_id and c.star_level == 1:
				count += 1
	for card in state.bench:
		if card != null:
			var c := card as CardInstance
			if c.get_base_id() == card_id and c.star_level == 1:
				count += 1
	return count


## Probability of finding at least one merge completion in a single shop roll.
## Uses tier weights × (card remaining / tier pool total) per slot, then 1-(1-p)^N.
static func merge_find_probability(state: GameState, genome: Genome) -> float:
	if state.card_pool == null:
		return 0.5  # no pool = assume moderate

	# Tier weights for current shop level
	var lv_key := str(state.shop_level)
	var tier_weights: Array
	if genome and genome.shop_tier_weights.has(lv_key):
		tier_weights = genome.shop_tier_weights[lv_key]
	else:
		tier_weights = Genome.DEFAULT_SHOP_TIER_WEIGHTS.get(lv_key, [100, 0, 0, 0, 0])

	var total_weight := 0.0
	for w in tier_weights:
		total_weight += float(w)
	if total_weight <= 0.0:
		return 0.0

	# Collect ★1 merge targets (owned 2+ copies, pool > 0)
	var star1_counts := {}
	for card in state.board:
		if card != null:
			var c := card as CardInstance
			if c.star_level == 1:
				var cid := c.get_base_id()
				star1_counts[cid] = star1_counts.get(cid, 0) + 1
	for card in state.bench:
		if card != null:
			var c := card as CardInstance
			if c.star_level == 1:
				var cid := c.get_base_id()
				star1_counts[cid] = star1_counts.get(cid, 0) + 1

	var tier_totals: Dictionary = state.card_pool.remaining_per_tier()

	# P(any merge target in one slot)
	var p_slot := 0.0
	for cid in star1_counts:
		if star1_counts[cid] < 2:
			continue
		var remaining := state.card_pool.get_remaining(cid)
		if remaining <= 0:
			continue
		var tmpl := CardDB.get_template(cid)
		var tier: int = tmpl.get("tier", 1)
		if tier < 1 or tier > tier_weights.size():
			continue
		var tier_w: float = float(tier_weights[tier - 1]) / total_weight
		var tier_pool: int = tier_totals.get(tier, 0)
		if tier_pool <= 0:
			continue
		p_slot += tier_w * (float(remaining) / float(tier_pool))

	if p_slot <= 0.0:
		return 0.0

	# P(at least one in shop_size slots) = 1 - (1 - p_slot)^shop_size
	var shop_size := 6
	return 1.0 - pow(maxf(1.0 - p_slot, 0.0), float(shop_size))


## Pool-aware merge: has 2+ ★1 copies AND pool has remaining copies.
static func has_achievable_merge(state: GameState) -> bool:
	var counts := {}
	for card in state.board:
		if card != null:
			var c := card as CardInstance
			if c.star_level == 1:
				var cid: String = c.get_base_id()
				counts[cid] = counts.get(cid, 0) + 1
	for card in state.bench:
		if card != null:
			var c := card as CardInstance
			if c.star_level == 1:
				var cid: String = c.get_base_id()
				counts[cid] = counts.get(cid, 0) + 1
	for cid in counts:
		if counts[cid] >= 2:
			if state.card_pool == null or state.card_pool.get_remaining(cid) > 0:
				return true
	return false


static func has_any_card(state: GameState, card_ids: Array) -> bool:
	for card in state.board:
		if card != null and (card as CardInstance).get_base_id() in card_ids:
			return true
	for card in state.bench:
		if card != null and (card as CardInstance).get_base_id() in card_ids:
			return true
	return false


static func count_theme_cards(state: GameState, theme: int) -> int:
	var count := 0
	for card in state.board:
		if card != null and (card as CardInstance).template.get("theme", 0) == theme:
			count += 1
	for card in state.bench:
		if card != null and (card as CardInstance).template.get("theme", 0) == theme:
			count += 1
	return count


static func count_all_cards(state: GameState) -> int:
	var count := 0
	for card in state.board:
		if card != null:
			count += 1
	for card in state.bench:
		if card != null:
			count += 1
	return count


## M4: Check if any owned card has chain partners NOT on board.
static func has_incomplete_chain_pair(board_ids: Dictionary, preferred_theme: int) -> bool:
	for owned_id in board_ids:
		if not _Syn.CHAIN_PAIRS.has(owned_id):
			continue
		var tmpl: Dictionary = CardDB.get_template(owned_id)
		var ct: int = tmpl.get("theme", Enums.CardTheme.NEUTRAL)
		if preferred_theme >= 0 and ct != preferred_theme and ct != Enums.CardTheme.NEUTRAL:
			continue
		var all_present := true
		for partner_id in _Syn.CHAIN_PAIRS[owned_id]:
			if partner_id not in board_ids:
				all_present = false
				break
		if not all_present:
			return true
	return false


static func detect_dominant_theme(state: GameState) -> int:
	var counts := {}
	for card in state.board:
		if card == null:
			continue
		var theme: int = (card as CardInstance).template.get("theme", 0)
		if theme != Enums.CardTheme.NEUTRAL and theme != 0:
			counts[theme] = counts.get(theme, 0) + 1
	for card in state.bench:
		if card == null:
			continue
		var theme: int = (card as CardInstance).template.get("theme", 0)
		if theme != Enums.CardTheme.NEUTRAL and theme != 0:
			counts[theme] = counts.get(theme, 0) + 1

	var best_theme := -1
	var best_count := 1
	for t in counts:
		if counts[t] > best_count:
			best_count = counts[t]
			best_theme = t
	return best_theme
