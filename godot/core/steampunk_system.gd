class_name SteampunkSystem
extends "res://core/theme_system.gd"
## Steampunk theme system.
## Growth chain: sp_charger (manufacture counter → terazin + enhance).
## Combat/sell: sp_warmachine (persistent range), sp_arsenal (on_sell absorb).


# --- Chain integration ---


func process_rs_card(_card: CardInstance, _idx: int, _board: Array,
		_rng: RandomNumberGenerator) -> Dictionary:
	# Steampunk T1-T3 RS cards use generic effects. No RS delegation needed.
	return Enums.empty_result()


func process_event_card(card: CardInstance, idx: int, _board: Array,
		_event: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
	match card.get_base_id():
		"sp_charger":
			return _charger(card, idx)
	return Enums.empty_result()


# --- External hooks (called by combat/game systems) ---


## Apply persistent combat effects (sp_warmachine range scaling).
func apply_persistent(card: CardInstance) -> void:
	if card.get_base_id() != "sp_warmachine":
		return
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var rb := _find_eff(effs, "range_bonus")
	var threshold: int = rb.get("unit_thresh", 8)
	var atk_buff_pct: float = rb.get("atk_buff_pct", 0.0)
	var attack_stack_pct: float = rb.get("attack_stack_pct", 0.0)

	var firearm_count := 0
	for s in card.stacks:
		if "firearm" in s["unit_type"].get("tags", PackedStringArray()):
			firearm_count += s["count"]
	card.theme_state["range_bonus"] = firearm_count / threshold
	# ★2+: #firearm ATK buff (combat buff)
	if atk_buff_pct > 0.0:
		card.temp_buff("firearm", atk_buff_pct)
	# ★3: #firearm 유닛 공격 시마다 ATK stack (combat engine에서 처리)
	if attack_stack_pct > 0.0:
		card.theme_state["attack_stack_pct"] = attack_stack_pct


## Handle sell event for sp_arsenal (absorb strongest units from sold card).
func on_sell_trigger(arsenal: CardInstance, sold_card: CardInstance) -> void:
	if arsenal.get_base_id() != "sp_arsenal":
		return
	# Sold card must be steampunk (design: "업그레이드가 있는 스팀펑크 카드를 판매할 때")
	if sold_card.template.get("theme", -1) != Enums.CardTheme.STEAMPUNK:
		return
	if sold_card.upgrades.is_empty():
		return

	var effs := CardDB.get_theme_effects("sp_arsenal", arsenal.star_level)
	var abs_eff := _find_eff(effs, "absorb")
	var absorb: int = abs_eff.get("count", 3)

	var best_id := _strongest_unit_id(sold_card)
	if best_id != "":
		var added := arsenal.add_specific_unit(best_id, absorb)
		var bonus := CardInstance.roll_bonus_count(added, bonus_spawn_chance, bonus_rng)
		if bonus > 0:
			arsenal.add_specific_unit(best_id, bonus)

	# 업그레이드 이전 (transfer_upgrades: true인 star에서만)
	if abs_eff.get("transfer_upgrades", false):
		for upg in sold_card.upgrades:
			var uid: String = upg.get("id", "")
			if uid != "" and arsenal.can_attach_upgrade():
				arsenal.attach_upgrade(uid)

	# 최다 유닛 타입 ATK 보너스 (majority_atk_bonus가 있는 star에서만)
	var majority_bonus: float = abs_eff.get("majority_atk_bonus", 0.0)
	if majority_bonus > 0.0:
		var most_id := ""
		var most_count := 0
		for s in arsenal.stacks:
			if s["count"] > most_count:
				most_count = s["count"]
				most_id = s["unit_type"].get("id", "")
		if most_id != "":
			for s in arsenal.stacks:
				if s["unit_type"].get("id", "") == most_id:
					s["upgrade_atk_mult"] *= 1.0 + majority_bonus
					break


# --- Internal ---


func _find_eff(effs: Array, action: String, target: String = "") -> Dictionary:
	for e in effs:
		if e.get("action") == action:
			if target == "" or e.get("target", "") == target:
				return e
	return {}


func _charger(card: CardInstance, idx: int) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var cp := _find_eff(effs, "counter_produce")
	var threshold: int = cp.get("threshold", 10)
	var rewards: Dictionary = cp.get("rewards", {})
	var terazin_reward: int = rewards.get("terazin", 1)
	var enhance_atk: float = card_effects.get("sp_charger_enhance_atk",
			rewards.get("enhance_atk_pct", 0.05))

	var events: Array = []
	var terazin := 0

	# Base counter: threshold → terazin + enhance (all star levels)
	var counter: int = card.theme_state.get("manufacture_counter", 0)
	counter += 1
	if counter >= threshold:
		counter -= threshold
		terazin += terazin_reward
		card.enhance(null, enhance_atk, 0.0)
		events.append({
			"layer1": Enums.Layer1.ENHANCED,
			"layer2": Enums.Layer2.UPGRADE,
			"source_idx": idx, "target_idx": idx,
		})
	card.theme_state["manufacture_counter"] = counter

	# ★2: separate rare counter — 20 → pending rare upgrade 3-choice (UI)
	if card.star_level == 2:
		var rc := _find_eff(effs, "rare_counter")
		var rc_thresh: int = rc.get("threshold", 20)
		var rare_cnt: int = card.theme_state.get("rare_counter", 0) + 1
		if rare_cnt >= rc_thresh:
			rare_cnt -= rc_thresh
			card.theme_state["pending_rare_upgrade"] = true
		card.theme_state["rare_counter"] = rare_cnt

	# ★3: epic counter — 15 → pending epic upgrade 3-choice (UI)
	if card.star_level >= 3:
		var ec := _find_eff(effs, "epic_counter")
		var ec_thresh: int = ec.get("threshold", 15)
		var epic_cnt: int = card.theme_state.get("epic_counter", 0) + 1
		if epic_cnt >= ec_thresh:
			epic_cnt -= ec_thresh
			card.theme_state["pending_epic_upgrade"] = true
		card.theme_state["epic_counter"] = epic_cnt

	# ★3 영구: 제조 N회마다 +1 테라진 자동 획득 (기본 카운터와 별도 추적)
	if card.star_level >= 3:
		var tc := _find_eff(effs, "total_counter")
		var tc_interval: int = tc.get("per_manufacture", 10)
		var tc_reward: int = tc.get("reward_terazin", 1)
		var total_mfg: int = card.theme_state.get("total_manufacture_count", 0) + 1
		card.theme_state["total_manufacture_count"] = total_mfg
		if total_mfg % tc_interval == 0:
			terazin += tc_reward

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
