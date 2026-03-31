class_name PredatorSystem
extends RefCounted
## Predator theme system: hatch (add blade larvae) + metamorphosis (consume weak → add strong).
## RS cards (nest, farm, queen, transcend) produce hatch events;
## OE cards (molt, harvest, carapace, apex_hunt) react to hatch/meta events.

const LARVA_ID := "pr_larva"


# --- Chain integration ---


func process_rs_card(card: CardInstance, idx: int, board: Array,
		_rng: RandomNumberGenerator) -> Dictionary:
	match card.get_base_id():
		"pr_nest": return _nest(card, idx, board)
		"pr_farm": return _farm(card, idx)
		"pr_queen": return _queen(card, idx, board)
		"pr_transcend": return _transcend(card, idx, board)
	return _empty()


func process_event_card(card: CardInstance, idx: int, board: Array,
		event: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
	match card.get_base_id():
		"pr_molt": return _molt(card, idx)
		"pr_harvest": return _harvest(card, idx, board, event)
		"pr_carapace": return _carapace(card, idx, board)
		"pr_apex_hunt": return _apex_hunt(card, idx)
	return _empty()


# --- External hooks (combat engine) ---


func apply_battle_start(card: CardInstance, _idx: int, board: Array) -> Dictionary:
	if card.get_base_id() == "pr_swarm_sense":
		return _swarm_sense_battle(card, board)
	return _empty()


func apply_post_combat(card: CardInstance, idx: int, _board: Array,
		won: bool) -> Dictionary:
	match card.get_base_id():
		"pr_parasite": return _parasite_post(card, idx, won)
		"pr_farm": return _farm_post(card, won)
	return _empty()


## Persistent combat: pr_transcend death/kill tracking stored for combat engine.
func apply_persistent(card: CardInstance) -> void:
	if card.get_base_id() != "pr_transcend":
		return
	var death_atk := 0.03
	match card.star_level:
		2: death_atk = 0.05
		3: death_atk = 0.05
	card.theme_state["death_atk_bonus"] = death_atk
	card.theme_state["kill_hp_recover"] = 0.10 if card.star_level < 2 else 0.15


# --- Hatch / Meta helpers ---


func _hatch(target: CardInstance, count: int) -> int:
	return target.add_specific_unit(LARVA_ID, count)


func _hatch_evt(src: int, tgt: int) -> Dictionary:
	return {
		"layer1": Enums.Layer1.UNIT_ADDED,
		"layer2": Enums.Layer2.HATCH,
		"source_idx": src, "target_idx": tgt,
	}


func _meta_evt(src: int, tgt: int) -> Dictionary:
	return {
		"layer1": Enums.Layer1.ENHANCED,
		"layer2": Enums.Layer2.METAMORPHOSIS,
		"source_idx": src, "target_idx": tgt,
	}


func _has_carapace_unit(card: CardInstance) -> bool:
	for s in card.stacks:
		if "carapace" in s["unit_type"].get("tags", PackedStringArray()):
			return true
	return false


func _predator_indices(board: Array) -> Array[int]:
	var result: Array[int] = []
	for i in board.size():
		if (board[i] as CardInstance).template.get("theme", -1) == Enums.CardTheme.PREDATOR:
			result.append(i)
	return result


# --- RS cards ---


func _nest(card: CardInstance, idx: int, board: Array) -> Dictionary:
	# ★1: hatch 2 self, 1 right  |  ★2: 4 self, 2 right  |  ★3: 4 self, 2 both
	var self_n := 2
	var adj_n := 1
	var both := false
	match card.star_level:
		2:
			self_n = 4
			adj_n = 2
		3:
			self_n = 4
			adj_n = 2
			both = true

	var events: Array = []
	_hatch(card, self_n)
	events.append(_hatch_evt(idx, idx))

	if both:
		for di in [-1, 1]:
			var ni: int = idx + di
			if ni >= 0 and ni < board.size():
				_hatch(board[ni], adj_n)
				events.append(_hatch_evt(idx, ni))
	else:
		if idx + 1 < board.size():
			_hatch(board[idx + 1], adj_n)
			events.append(_hatch_evt(idx, idx + 1))

	return {"events": events, "gold": 0, "terazin": 0}


func _farm(card: CardInstance, idx: int) -> Dictionary:
	# RS part only: hatch 1 (★3: hatch 2). Post-combat gold is separate hook.
	var count := 1
	if card.star_level >= 3:
		count = 2
	_hatch(card, count)
	return {"events": [_hatch_evt(idx, idx)], "gold": 0, "terazin": 0}


func _queen(card: CardInstance, idx: int, board: Array) -> Dictionary:
	# ★1: hatch 3 self, 1 right  |  ★2: 4 self, 2 both  |  ★3: 5 self, 3 both
	var self_n := 3
	var adj_n := 1
	var both := false
	match card.star_level:
		2:
			self_n = 4
			adj_n = 2
			both = true
		3:
			self_n = 5
			adj_n = 3
			both = true

	var events: Array = []
	_hatch(card, self_n)
	events.append(_hatch_evt(idx, idx))

	if both:
		for di in [-1, 1]:
			var ni: int = idx + di
			if ni >= 0 and ni < board.size():
				_hatch(board[ni], adj_n)
				events.append(_hatch_evt(idx, ni))
	else:
		if idx + 1 < board.size():
			_hatch(board[idx + 1], adj_n)
			events.append(_hatch_evt(idx, idx + 1))

	return {"events": events, "gold": 0, "terazin": 0}


func _transcend(card: CardInstance, idx: int, board: Array) -> Dictionary:
	# ★1: hatch 3 self, 1 each predator  |  ★2: 4 self, 2 each  |  ★3: +auto meta 1
	var self_n := 3
	var all_n := 1
	match card.star_level:
		2:
			self_n = 4
			all_n = 2
		3:
			self_n = 4
			all_n = 2

	var events: Array = []
	_hatch(card, self_n)
	events.append(_hatch_evt(idx, idx))

	for pi in _predator_indices(board):
		if pi != idx:
			_hatch(board[pi], all_n)
			events.append(_hatch_evt(idx, pi))

	# ★3: auto metamorphosis 1/round + ATK+5% permanent
	if card.star_level >= 3:
		if card.metamorphosis(1):
			card.enhance(null, 0.05, 0.0)
			events.append(_meta_evt(idx, idx))

	return {"events": events, "gold": 0, "terazin": 0}


# --- OE cards ---


func _molt(card: CardInstance, idx: int) -> Dictionary:
	# ★1: meta 3  |  ★2: meta 2  |  ★3: meta 2 + ATK+5% growth
	var consume := 3
	match card.star_level:
		2: consume = 2
		3: consume = 2

	var events: Array = []
	if card.metamorphosis(consume):
		events.append(_meta_evt(idx, idx))
		if card.star_level >= 3:
			card.enhance(null, 0.05, 0.0)

	return {"events": events, "gold": 0, "terazin": 0}


func _harvest(card: CardInstance, idx: int, board: Array,
		event: Dictionary) -> Dictionary:
	# ★1: 1 terazin, hatch 1  |  ★2: +meta unit ATK+5%  |  ★3: hatch 2, all pred +3%
	var terazin := 1
	var hatch_n := 1
	if card.star_level >= 3:
		hatch_n = 2

	var events: Array = []
	_hatch(card, hatch_n)
	events.append(_hatch_evt(idx, idx))

	# ★2: growth for the card that metamorphosed
	if card.star_level >= 2:
		var target_idx: int = event.get("target_idx", -1)
		if target_idx >= 0 and target_idx < board.size():
			(board[target_idx] as CardInstance).enhance(null, 0.05, 0.0)

	# ★3: all predator ATK+3%
	if card.star_level >= 3:
		for pi in _predator_indices(board):
			(board[pi] as CardInstance).enhance(null, 0.03, 0.0)

	return {"events": events, "gold": 0, "terazin": terazin}


func _carapace(card: CardInstance, idx: int, board: Array) -> Dictionary:
	# ★1: #carapace cards ATK+HP 5% growth, right adj hatch 1
	# ★2: 7% growth, adj hatch 1  |  ★3: all pred 7%, both adj hatch 1 + shield
	var growth := 0.05
	match card.star_level:
		2: growth = 0.07
		3: growth = 0.07

	# Apply growth to predator cards that have #carapace units
	if card.star_level >= 3:
		# ★3: all predator cards
		for pi in _predator_indices(board):
			(board[pi] as CardInstance).enhance(null, growth, growth)
	else:
		# ★1/★2: only cards with #carapace units
		for pi in _predator_indices(board):
			var pc: CardInstance = board[pi]
			if _has_carapace_unit(pc):
				pc.enhance(null, growth, growth)

	# Adjacent hatch
	var events: Array = []
	var hatch_both := card.star_level >= 3
	if hatch_both:
		for di in [-1, 1]:
			var ni: int = idx + di
			if ni >= 0 and ni < board.size():
				_hatch(board[ni], 1)
				events.append(_hatch_evt(idx, ni))
	else:
		if idx + 1 < board.size():
			_hatch(board[idx + 1], 1)
			events.append(_hatch_evt(idx, idx + 1))

	# ★3: shield on original meta card
	if card.star_level >= 3:
		card.shield_hp_pct += 0.20

	return {"events": events, "gold": 0, "terazin": 0}


func _apex_hunt(card: CardInstance, idx: int) -> Dictionary:
	# ★1: meta 2, ≤5u ATK+30%  |  ★2: meta 2, +50%  |  ★3: meta 1, ATK×2 mult
	var consume := 2
	if card.star_level >= 3:
		consume = 1

	var events: Array = []
	if card.metamorphosis(consume):
		events.append(_meta_evt(idx, idx))

	if card.get_total_units() <= 5:
		match card.star_level:
			1: card.temp_buff(null, 0.30)
			2: card.temp_buff(null, 0.50)
			3: card.temp_mult_buff(2.0)

	return {"events": events, "gold": 0, "terazin": 0}


# --- Battle hooks ---


func _swarm_sense_battle(card: CardInstance, board: Array) -> Dictionary:
	# ★1: per 3 units ATK+10%  |  ★2: 3u→12%  |  ★3: 2u→12%
	var per_n := 3
	var buff := 0.10
	match card.star_level:
		2: buff = 0.12
		3:
			per_n = 2
			buff = 0.12

	for pi in _predator_indices(board):
		var pc: CardInstance = board[pi]
		var stacks_n := pc.get_total_units() / per_n
		if stacks_n > 0:
			pc.temp_buff(null, buff * stacks_n)
	return _empty()


func _parasite_post(card: CardInstance, idx: int, won: bool) -> Dictionary:
	# ★1: per surviving unit hatch 1 (max 3), victory meta 2
	# ★2: hatch 2 (max 5), victory meta 2 + HP 15%
	# ★3: hatch 2 (max 5), any meta 2 + HP 20%, shield 30%
	var hatch_per := 1
	var max_hatch := 3
	match card.star_level:
		2:
			hatch_per = 2
			max_hatch = 5
		3:
			hatch_per = 2
			max_hatch = 5

	var events: Array = []
	var total_hatch := mini(card.get_total_units() * hatch_per, max_hatch)
	if total_hatch > 0:
		_hatch(card, total_hatch)
		events.append(_hatch_evt(idx, idx))

	var do_meta := won or card.star_level >= 3
	if do_meta and card.metamorphosis(2):
		events.append(_meta_evt(idx, idx))
		if card.star_level >= 3:
			card.shield_hp_pct += 0.30

	return {"events": events, "gold": 0, "terazin": 0}


func _farm_post(card: CardInstance, won: bool) -> Dictionary:
	var units := card.get_total_units()
	var gold := units / 5
	var max_gold := 3
	match card.star_level:
		2: max_gold = 5
		3: max_gold = 7
	gold = mini(gold, max_gold)
	if not won and card.star_level < 2:
		gold /= 2
	var terazin := 1 if card.star_level >= 3 else 0
	return {"events": [], "gold": gold, "terazin": terazin}


func _empty() -> Dictionary:
	return {"events": [], "gold": 0, "terazin": 0}
