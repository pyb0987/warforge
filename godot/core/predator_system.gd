class_name PredatorSystem
extends "res://core/theme_system.gd"
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
	return Enums.empty_result()


func process_event_card(card: CardInstance, idx: int, board: Array,
		event: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
	match card.get_base_id():
		"pr_molt": return _molt(card, idx)
		"pr_harvest": return _harvest(card, idx, board, event)
		"pr_carapace": return _carapace(card, idx, board)
		"pr_apex_hunt": return _apex_hunt(card, idx)
	return Enums.empty_result()


# --- External hooks (combat engine) ---


func apply_battle_start(card: CardInstance, _idx: int, board: Array) -> Dictionary:
	if card.get_base_id() == "pr_swarm_sense":
		return _swarm_sense_battle(card, board)
	return Enums.empty_result()


func apply_post_combat(card: CardInstance, idx: int, _board: Array,
		won: bool) -> Dictionary:
	match card.get_base_id():
		"pr_parasite": return _parasite_post(card, idx, won)
		"pr_farm": return _farm_post(card, won)
	return Enums.empty_result()


## Persistent combat: pr_transcend death/kill tracking stored for combat engine.
func apply_persistent(card: CardInstance) -> void:
	if card.get_base_id() != "pr_transcend":
		return
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var p := _find_eff(effs, "persistent")
	var base_death_atk: float = card_effects.get("pr_transcend_death_atk", p.get("death_atk_bonus", 0.03))
	card.theme_state["death_atk_bonus"] = base_death_atk
	card.theme_state["kill_hp_recover"] = p.get("kill_hp_recover", 0.10)


# --- Helpers ---


func _find_eff(effs: Array, action: String, target: String = "") -> Dictionary:
	for e in effs:
		if e.get("action") == action:
			if target == "" or e.get("target", "") == target:
				return e
	return {}


# --- Hatch / Meta helpers ---


func _hatch(target: CardInstance, count: int) -> int:
	var added := target.add_specific_unit(LARVA_ID, count)
	var bonus := CardInstance.roll_bonus_count(added, bonus_spawn_chance, bonus_rng)
	if bonus > 0:
		target.add_specific_unit(LARVA_ID, bonus)
	return added


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
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var self_eff := _find_eff(effs, "hatch", "self")
	var adj_eff_right := _find_eff(effs, "hatch", "right_adj")
	var adj_eff_both := _find_eff(effs, "hatch", "both_adj")

	var self_n: int = self_eff.get("count", 2)
	var both := not adj_eff_both.is_empty()
	var adj_n: int = adj_eff_both.get("count", adj_eff_right.get("count", 1)) if both else adj_eff_right.get("count", 1)

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
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var hatch_eff := _find_eff(effs, "hatch", "self")
	var count: int = hatch_eff.get("count", 1)
	_hatch(card, count)
	return {"events": [_hatch_evt(idx, idx)], "gold": 0, "terazin": 0}


func _queen(card: CardInstance, idx: int, board: Array) -> Dictionary:
	# ★1: hatch 3 self, 1 right  |  ★2: 4 self, 2 both  |  ★3: 5 self, 3 both
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var self_eff := _find_eff(effs, "hatch", "self")
	var adj_eff_right := _find_eff(effs, "hatch", "right_adj")
	var adj_eff_both := _find_eff(effs, "hatch", "both_adj")

	var self_n: int = self_eff.get("count", 3)
	var both := not adj_eff_both.is_empty()
	var adj_n: int = adj_eff_both.get("count", adj_eff_right.get("count", 1)) if both else adj_eff_right.get("count", 1)

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
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var self_eff := _find_eff(effs, "hatch", "self")
	var all_eff := _find_eff(effs, "hatch", "all_predator")

	var self_n: int = self_eff.get("count", 3)
	var all_n: int = all_eff.get("count", 1)

	var events: Array = []
	_hatch(card, self_n)
	events.append(_hatch_evt(idx, idx))

	for pi in _predator_indices(board):
		if pi != idx:
			_hatch(board[pi], all_n)
			events.append(_hatch_evt(idx, pi))

	# ★3: auto metamorphosis 1/round + ATK+5% permanent
	var meta_eff := _find_eff(effs, "meta_consume")
	var enhance_eff := _find_eff(effs, "enhance", "self")
	if not meta_eff.is_empty():
		if card.metamorphosis(meta_eff.get("consume", 1)):
			card.enhance(null, enhance_eff.get("atk_pct", 0.05), 0.0)
			events.append(_meta_evt(idx, idx))

	return {"events": events, "gold": 0, "terazin": 0}


# --- OE cards ---


func _molt(card: CardInstance, idx: int) -> Dictionary:
	# ★1: meta 3  |  ★2: meta 2  |  ★3: meta 2 + ATK+5% growth
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var meta_eff := _find_eff(effs, "meta_consume")
	var consume: int = meta_eff.get("consume", 3)

	var events: Array = []
	if card.metamorphosis(consume):
		events.append(_meta_evt(idx, idx))
		var enhance_eff := _find_eff(effs, "enhance", "self")
		if not enhance_eff.is_empty():
			card.enhance(null, enhance_eff.get("atk_pct", 0.05), 0.0)

	return {"events": events, "gold": 0, "terazin": 0}


func _harvest(card: CardInstance, idx: int, board: Array,
		event: Dictionary) -> Dictionary:
	# ★1: 1 terazin, hatch 1  |  ★2: +meta unit ATK+5%  |  ★3: hatch 2, all pred +3%
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var terazin_eff := _find_eff(effs, "terazin")
	var hatch_eff := _find_eff(effs, "hatch", "self")

	var terazin: int = terazin_eff.get("value", 1)
	var hatch_n: int = hatch_eff.get("count", 1)

	var events: Array = []
	_hatch(card, hatch_n)
	events.append(_hatch_evt(idx, idx))

	# ★2: growth for the card that metamorphosed
	var enhance_event_eff := _find_eff(effs, "enhance", "event_source")
	if not enhance_event_eff.is_empty():
		var target_idx: int = event.get("target_idx", -1)
		if target_idx >= 0 and target_idx < board.size():
			(board[target_idx] as CardInstance).enhance(null, enhance_event_eff.get("atk_pct", 0.05), 0.0)

	# ★3: all predator ATK+3%
	var enhance_all_eff := _find_eff(effs, "enhance", "all_predator")
	if not enhance_all_eff.is_empty():
		for pi in _predator_indices(board):
			(board[pi] as CardInstance).enhance(null, enhance_all_eff.get("atk_pct", 0.03), 0.0)

	return {"events": events, "gold": 0, "terazin": terazin}


func _carapace(card: CardInstance, idx: int, board: Array) -> Dictionary:
	# ★1: #carapace cards ATK+HP 5% growth, right adj hatch 1
	# ★2: 7% growth, adj hatch 1  |  ★3: all pred 7%, both adj hatch 1 + shield
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var enhance_carapace_eff := _find_eff(effs, "enhance", "tag:carapace")
	var enhance_all_eff := _find_eff(effs, "enhance", "all_predator")
	var shield_eff := _find_eff(effs, "shield", "event_source")

	# Apply growth — override with card_effects if present
	var base_growth: float = card_effects.get("pr_carapace_growth", 0.05)
	if not enhance_all_eff.is_empty():
		# ★3: all predator cards
		var growth: float = card_effects.get("pr_carapace_growth",
				enhance_all_eff.get("atk_pct", base_growth))
		for pi in _predator_indices(board):
			(board[pi] as CardInstance).enhance(null, growth, growth)
	elif not enhance_carapace_eff.is_empty():
		# ★1/★2: only cards with #carapace units
		var growth: float = card_effects.get("pr_carapace_growth",
				enhance_carapace_eff.get("atk_pct", base_growth))
		for pi in _predator_indices(board):
			var pc: CardInstance = board[pi]
			if _has_carapace_unit(pc):
				pc.enhance(null, growth, growth)

	# Adjacent hatch
	var hatch_right_eff := _find_eff(effs, "hatch", "right_adj")
	var hatch_both_eff := _find_eff(effs, "hatch", "both_adj")
	var events: Array = []
	var hatch_both := not hatch_both_eff.is_empty()
	var hatch_count: int = hatch_both_eff.get("count", hatch_right_eff.get("count", 1)) if hatch_both else hatch_right_eff.get("count", 1)

	if hatch_both:
		for di in [-1, 1]:
			var ni: int = idx + di
			if ni >= 0 and ni < board.size():
				_hatch(board[ni], hatch_count)
				events.append(_hatch_evt(idx, ni))
	else:
		if idx + 1 < board.size():
			_hatch(board[idx + 1], hatch_count)
			events.append(_hatch_evt(idx, idx + 1))

	# ★3: shield on original meta card
	if not shield_eff.is_empty():
		card.shield_hp_pct += shield_eff.get("hp_pct", 0.20)

	return {"events": events, "gold": 0, "terazin": 0}


func _apex_hunt(card: CardInstance, idx: int) -> Dictionary:
	# ★1: meta 2, ≤5u ATK+30%  |  ★2: meta 2, +50%  |  ★3: meta 1, ATK×2 mult
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var meta_eff := _find_eff(effs, "meta_consume")
	var cond_eff := _find_eff(effs, "conditional")

	var consume: int = meta_eff.get("consume", 2)

	var events: Array = []
	if card.metamorphosis(consume):
		events.append(_meta_evt(idx, idx))

	if not cond_eff.is_empty() and card.get_total_units() <= cond_eff.get("threshold", 5):
		var inner_effs: Array = cond_eff.get("effects", [])
		var buff_eff: Dictionary = {}
		for e in inner_effs:
			if e.get("action") == "buff":
				buff_eff = e
				break
		if not buff_eff.is_empty():
			if buff_eff.has("atk_mult"):
				card.temp_mult_buff(buff_eff.get("atk_mult", 2.0))
			else:
				card.temp_buff(null, buff_eff.get("atk_pct", 0.3))

	return {"events": events, "gold": 0, "terazin": 0}


# --- Battle hooks ---


func _swarm_sense_battle(card: CardInstance, board: Array) -> Dictionary:
	# ★1: per 3 units ATK+10%  |  ★2: 3u→12%  |  ★3: 2u→12%
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var swarm_eff := _find_eff(effs, "swarm_buff")

	var per_n: int = swarm_eff.get("per_n", 3)
	var buff: float = card_effects.get("pr_swarm_sense_buff", swarm_eff.get("atk_per_unit", 0.10))

	for pi in _predator_indices(board):
		var pc: CardInstance = board[pi]
		var stacks_n := pc.get_total_units() / per_n
		if stacks_n > 0:
			pc.temp_buff(null, buff * stacks_n)
	return Enums.empty_result()


func _parasite_post(card: CardInstance, idx: int, won: bool) -> Dictionary:
	# ★1: per surviving unit hatch 1 (max 3), victory meta 2
	# ★2: hatch 2 (max 5), victory meta 2 + HP 15%
	# ★3: hatch 2 (max 5), any meta 2 + HP 20%, shield 30%
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var hatch_scaled_eff := _find_eff(effs, "hatch_scaled")
	var combat_result_eff := _find_eff(effs, "on_combat_result")

	var hatch_per: int = hatch_scaled_eff.get("per_units", 1)
	var max_hatch: int = hatch_scaled_eff.get("cap", 3)

	var events: Array = []
	var total_hatch := mini(card.get_total_units() * hatch_per, max_hatch)
	if total_hatch > 0:
		_hatch(card, total_hatch)
		events.append(_hatch_evt(idx, idx))

	var condition: String = combat_result_eff.get("condition", "victory")
	var do_meta := won or condition == "always"
	if do_meta:
		var inner_effs: Array = combat_result_eff.get("effects", [])
		var meta_eff: Dictionary = {}
		var shield_eff: Dictionary = {}
		for e in inner_effs:
			if e.get("action") == "meta_consume":
				meta_eff = e
			elif e.get("action") == "shield":
				shield_eff = e
		if not meta_eff.is_empty() and card.metamorphosis(meta_eff.get("consume", 2)):
			events.append(_meta_evt(idx, idx))
			if not shield_eff.is_empty():
				card.shield_hp_pct += shield_eff.get("hp_pct", 0.30)

	return {"events": events, "gold": 0, "terazin": 0}


func _farm_post(card: CardInstance, won: bool) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var econ_eff := _find_eff(effs, "economy")

	var units := card.get_total_units()
	var gold_per: float = econ_eff.get("gold_per", 0.2)
	var max_gold: int = econ_eff.get("max_gold", 3)
	var halve_on_loss: bool = econ_eff.get("halve_on_loss", false)
	var gold := units / 4
	gold = mini(gold, max_gold)
	if not won and halve_on_loss:
		gold /= 2
	var terazin_dict = econ_eff.get("terazin", null)
	var terazin := 1 if terazin_dict != null else 0
	return {"events": [], "gold": gold, "terazin": terazin}
