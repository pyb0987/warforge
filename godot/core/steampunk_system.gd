class_name SteampunkSystem
extends RefCounted
## Steampunk theme system.
## Growth chain: sp_charger (manufacture counter → terazin + enhance).
## Combat/sell: sp_warmachine (persistent range), sp_arsenal (on_sell absorb).


# --- Chain integration ---


func process_rs_card(_card: CardInstance, _idx: int, _board: Array,
		_rng: RandomNumberGenerator) -> Dictionary:
	# Steampunk T1-T3 RS cards use generic effects. No RS delegation needed.
	return _empty()


func process_event_card(card: CardInstance, idx: int, _board: Array,
		_event: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
	match card.get_base_id():
		"sp_charger":
			return _charger(card, idx)
	return _empty()


# --- External hooks (called by combat/game systems) ---


## Apply persistent combat effects (sp_warmachine range scaling).
func apply_persistent(card: CardInstance) -> void:
	if card.get_base_id() != "sp_warmachine":
		return
	var threshold := 8
	match card.star_level:
		2: threshold = 6
		3: threshold = 4
	var firearm_count := 0
	for s in card.stacks:
		if "firearm" in s["unit_type"].get("tags", PackedStringArray()):
			firearm_count += s["count"]
	card.theme_state["range_bonus"] = firearm_count / threshold
	# ★2+: #firearm ATK +30% combat buff
	if card.star_level >= 2:
		card.temp_buff("firearm", 0.30)


## Handle sell event for sp_arsenal (absorb strongest units from sold card).
func on_sell_trigger(arsenal: CardInstance, sold_card: CardInstance) -> void:
	if arsenal.get_base_id() != "sp_arsenal":
		return
	# Sold card must be steampunk (design: "업그레이드가 있는 스팀펑크 카드를 판매할 때")
	if sold_card.template.get("theme", -1) != Enums.CardTheme.STEAMPUNK:
		return
	# TODO: 업그레이드 보유 여부 체크 (Sprint 12 업그레이드 시스템 구현 후 추가)

	var absorb := 3
	match arsenal.star_level:
		2: absorb = 5
		3: absorb = 7
	var best_id := _strongest_unit_id(sold_card)
	if best_id != "":
		arsenal.add_specific_unit(best_id, absorb)

	# ★3: 최다 유닛 타입 ATK +30%
	if arsenal.star_level >= 3:
		var most_id := ""
		var most_count := 0
		for s in arsenal.stacks:
			if s["count"] > most_count:
				most_count = s["count"]
				most_id = s["unit_type"].get("id", "")
		if most_id != "":
			# Find the tag for majority unit and apply buff
			for s in arsenal.stacks:
				if s["unit_type"].get("id", "") == most_id:
					s["upgrade_atk_mult"] *= 1.30
					break


# --- Internal ---


func _charger(card: CardInstance, idx: int) -> Dictionary:
	var events: Array = []
	var terazin := 0
	var counter: int = card.theme_state.get("manufacture_counter", 0)
	counter += 1

	var threshold := 10
	var enhance_atk := 0.05
	match card.star_level:
		2:
			threshold = 20
			# ★2: 20+ → remove 20, rare upgrade 3-choice (UI system)
		3:
			threshold = 10
			# ★3: auto 1 terazin per 10 manufactures

	if counter >= threshold:
		counter -= threshold
		terazin += 1
		card.enhance(null, enhance_atk, 0.0)
		events.append({
			"layer1": Enums.Layer1.ENHANCED,
			"layer2": Enums.Layer2.UPGRADE,
			"source_idx": idx, "target_idx": idx,
		})

	card.theme_state["manufacture_counter"] = counter
	return {"events": events, "gold": 0, "terazin": terazin}


func _strongest_unit_id(card: CardInstance) -> String:
	var best_id := ""
	var best_cp := -1.0
	for s in card.stacks:
		var ut: Dictionary = s["unit_type"]
		var as_val: float = maxf(ut["attack_speed"], 0.01)
		var cp: float = float(ut["atk"]) / as_val * float(ut["hp"])
		if cp > best_cp:
			best_cp = cp
			best_id = ut.get("id", "")
	return best_id


func _empty() -> Dictionary:
	return {"events": [], "gold": 0, "terazin": 0}
