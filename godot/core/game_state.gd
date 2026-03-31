class_name GameState
extends RefCounted
## Manages player state: board, bench, economy, HP, round.

signal state_changed
signal card_moved(from_zone, from_idx, to_zone, to_idx)

# --- Board & Bench ---
var board: Array = []  # Array[CardInstance | null], size = MAX_FIELD_SLOTS
var bench: Array = []  # Array[CardInstance | null], size = MAX_BENCH_SLOTS

# --- Economy ---
var gold: int = 0
var terazin: int = 0

# --- Player ---
var hp: int = 30
var round_num: int = 0

# --- Shop ---
var shop_cards: Array = []  # Array[String] card template IDs
var shop_level: int = 1  # 상점 레벨 (티어 확률 영향)


func _init() -> void:
	board.resize(Enums.MAX_FIELD_SLOTS)
	board.fill(null)
	bench.resize(Enums.MAX_BENCH_SLOTS)
	bench.fill(null)


## Get the number of non-null cards on the board.
func board_count() -> int:
	var count := 0
	for card in board:
		if card != null:
			count += 1
	return count


## Get all non-null cards on the board (for chain engine).
func get_active_board() -> Array:
	var result: Array = []
	for card in board:
		if card != null:
			result.append(card)
	return result


## Move a card between zones (board/bench).
func move_card(from_zone: String, from_idx: int, to_zone: String, to_idx: int) -> bool:
	var from_arr := _get_zone(from_zone)
	var to_arr := _get_zone(to_zone)
	if from_arr.is_empty() or to_arr.is_empty():
		return false
	if from_idx < 0 or from_idx >= from_arr.size():
		return false
	if to_idx < 0 or to_idx >= to_arr.size():
		return false

	var card = from_arr[from_idx]
	if card == null:
		return false

	# Swap if target occupied, otherwise just move
	var target = to_arr[to_idx]
	to_arr[to_idx] = card
	from_arr[from_idx] = target  # null or swapped card

	card_moved.emit(from_zone, from_idx, to_zone, to_idx)
	state_changed.emit()
	return true


## Add card to first empty bench slot. Returns slot index or -1.
func add_to_bench(card: CardInstance) -> int:
	for i in bench.size():
		if bench[i] == null:
			bench[i] = card
			state_changed.emit()
			return i
	return -1  # bench full


## Remove card from zone. Returns the card or null.
func remove_card(zone: String, idx: int) -> CardInstance:
	var arr := _get_zone(zone)
	if arr.is_empty() or idx < 0 or idx >= arr.size():
		return null
	var card = arr[idx]
	arr[idx] = null
	if card != null:
		state_changed.emit()
	return card


## Sell a card: remove + refund gold.
func sell_card(zone: String, idx: int) -> int:
	var card := remove_card(zone, idx)
	if card == null:
		return 0
	var cost: int = card.template.get("cost", 0)
	var refund := int(cost * Enums.SELL_REFUND_RATE)
	gold += refund
	state_changed.emit()
	return refund


## Calculate interest: 1 per 5 gold, max 2.
func calc_interest() -> int:
	return mini(gold / 5, Enums.MAX_INTEREST)


## Try to merge 3 copies of same card (same star level) → next ★.
## Called after purchasing or placing a card.
## Returns the merged card or null if no merge happened.
## Try to merge 3 copies of same card (same star level) → next ★.
## Returns {card, old_star, new_star} on success, {} on no merge.
func try_merge(template_id: String) -> Dictionary:
	# Find all copies with same template_id, then group by star_level
	var all_copies: Array[Dictionary] = []  # [{zone, idx, card}]
	for i in board.size():
		if board[i] != null and board[i].template_id == template_id:
			all_copies.append({"zone": "board", "idx": i, "card": board[i]})
	for i in bench.size():
		if bench[i] != null and bench[i].template_id == template_id:
			all_copies.append({"zone": "bench", "idx": i, "card": bench[i]})

	# Group by star_level — only merge copies at the same ★
	var copies: Array[Dictionary] = []
	if not all_copies.is_empty():
		var target_star: int = all_copies[0]["card"].star_level
		for entry in all_copies:
			if entry["card"].star_level == target_star:
				copies.append(entry)

	if copies.size() < 3:
		return {}

	var survivor: CardInstance = copies[0]["card"]
	var old_star := survivor.star_level

	# Absorb units from other 2 copies (add their units to survivor)
	for i in range(1, 3):
		var donor: CardInstance = copies[i]["card"]
		for si in donor.stacks.size():
			if si < survivor.stacks.size():
				survivor.stacks[si]["count"] += donor.stacks[si]["count"]
		# Remove donor from board/bench
		var zone_arr := _get_zone(copies[i]["zone"])
		zone_arr[copies[i]["idx"]] = null

	# Evolve to next star level
	survivor.evolve_star()

	# ★2 bonus: ×1.30 ATK/HP (합성 보상의 스탯 증가 부분)
	if old_star == 1:
		survivor.multiply_stats(0.30, 0.30)

	state_changed.emit()
	return {"card": survivor, "old_star": old_star, "new_star": survivor.star_level}


func _get_zone(zone: String) -> Array:
	match zone:
		"board": return board
		"bench": return bench
	return []
