class_name SteampunkSystem
extends "res://core/theme_system.gd"
## Steampunk theme system.
## Growth chain: sp_charger (manufacture counter → terazin + enhance).
## Combat/sell: sp_warmachine (persistent range), sp_arsenal (on_sell absorb).


# --- Chain integration ---


func process_rs_card(card: CardInstance, idx: int, board: Array,
		rng: RandomNumberGenerator) -> Dictionary:
	match card.get_base_id():
		"sp_warmachine":
			return _warmachine_manufacture(card, idx, board, rng)
		"sp_arsenal":
			return _arsenal_rs_growth(card)
		"sp_global_workshop":
			return _global_workshop(card, idx, board, rng)
	# Other steampunk cards use generic card_db effects or other hooks.
	return Enums.empty_result()


## sp_arsenal ★3 RS block: 본인의 성장률을 (1 + pct) 배로 증폭 (복리).
## ★1/★2 에는 growth_multiply action 이 없으므로 no-op.
func _arsenal_rs_growth(card: CardInstance) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var eff := _find_eff(effs, "growth_multiply")
	if eff.is_empty():
		return Enums.empty_result()
	var pct: float = eff.get("pct", 0.2)
	var mult: float = 1.0 + pct
	card.growth_atk_pct *= mult
	card.growth_hp_pct *= mult
	for tag in card.tag_growth_atk:
		card.tag_growth_atk[tag] *= mult
	for tag in card.tag_growth_hp:
		card.tag_growth_hp[tag] *= mult
	card.stats_changed.emit()
	return Enums.empty_result()


## sp_warmachine RS 블록: comp 유닛 중 랜덤 N기 제조.
## ★1=1기, ★2=2기, ★3=4기. 각 제조마다 UA+MF 이벤트 emit (sp_charger 등 체인).
## 보드 전체 유닛 MAX_BOARD_UNITS 초과 시 중단 (chain_engine.gd spawn 과 일관).
func _warmachine_manufacture(card: CardInstance, idx: int, board: Array,
		rng: RandomNumberGenerator) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var eff := _find_eff(effs, "manufacture")
	if eff.is_empty():
		return Enums.empty_result()
	var count: int = eff.get("count", 1)
	var comp: Array = card.template.get("composition", [])
	if comp.is_empty():
		return Enums.empty_result()

	var events: Array = []
	for _n in count:
		if _count_board_units(board) >= Enums.MAX_BOARD_UNITS:
			break
		var pick: Dictionary = comp[rng.randi_range(0, comp.size() - 1)]
		var unit_id: String = pick.get("unit_id", "")
		if unit_id == "":
			continue
		card.add_specific_unit(unit_id, 1)
		events.append({
			"layer1": Enums.Layer1.UNIT_ADDED,
			"layer2": Enums.Layer2.MANUFACTURE,
			"source_idx": idx,
			"target_idx": idx,
		})
	return {"events": events, "gold": 0, "terazin": 0}


func _count_board_units(board: Array) -> int:
	var total := 0
	for c in board:
		if c != null:
			total += (c as CardInstance).get_total_units()
	return total


func process_event_card(card: CardInstance, idx: int, _board: Array,
		event: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
	match card.get_base_id():
		"sp_charger":
			return _charger(card, idx, event)
	return Enums.empty_result()


# --- External hooks (called by combat/game systems) ---


## Apply persistent combat effects (sp_warmachine range scaling).
func apply_persistent(card: CardInstance, _board: Array = []) -> void:
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


## sp_arsenal 판매 반응 (2026-04-21 재설계):
## 판매된 스팀펑크 카드의 모든 유닛을 흡수하고, 성장률(개량)의 일부를 이식.
## max_act: 1 — 한 라운드 1회만 발동 (arsenal.activations_used 로 제어).
## ★2+: 판매 카드의 upgrade 도 함께 이전.
func on_sell_trigger(arsenal: CardInstance, sold_card: CardInstance) -> void:
	if arsenal.get_base_id() != "sp_arsenal":
		return
	if sold_card.template.get("theme", -1) != Enums.CardTheme.STEAMPUNK:
		return

	var effs := CardDB.get_theme_effects("sp_arsenal", arsenal.star_level)
	var eff := _find_eff(effs, "absorb_steampunk")
	if eff.is_empty():
		return

	# SELL 은 chain_engine 외부에서 호출되므로 max_act 를 수동으로 체크/증가.
	# reset_round 가 매 라운드 activations_used 를 0 으로 리셋해 "라운드 1회" 보장.
	var max_act := _arsenal_sell_max_act(arsenal)
	if not arsenal.can_activate_with(max_act, 0):
		return
	arsenal.activations_used += 1

	var growth_ratio: float = eff.get("growth_ratio", 0.5)
	var transfer_upgrades: bool = eff.get("transfer_upgrades", false)

	# 1) 판매된 카드의 모든 유닛을 arsenal 에 이식 (카드 cap 60 + 보드 cap 체크는 add_specific_unit 이 담당).
	for s in sold_card.stacks:
		var unit_id: String = s["unit_type"].get("id", "")
		if unit_id == "":
			continue
		var count: int = s["count"]
		var added := arsenal.add_specific_unit(unit_id, count)
		var bonus := CardInstance.roll_bonus_count(added, bonus_spawn_chance, bonus_rng)
		if bonus > 0:
			arsenal.add_specific_unit(unit_id, bonus)

	# 2) 성장률(개량) 이식 — 전체 필드 + tag별 growth 를 growth_ratio 배율로 누적.
	arsenal.growth_atk_pct += sold_card.growth_atk_pct * growth_ratio
	arsenal.growth_hp_pct += sold_card.growth_hp_pct * growth_ratio
	for tag in sold_card.tag_growth_atk:
		arsenal.tag_growth_atk[tag] = arsenal.tag_growth_atk.get(tag, 0.0) \
			+ sold_card.tag_growth_atk[tag] * growth_ratio
	for tag in sold_card.tag_growth_hp:
		arsenal.tag_growth_hp[tag] = arsenal.tag_growth_hp.get(tag, 0.0) \
			+ sold_card.tag_growth_hp[tag] * growth_ratio

	# 3) Upgrade 이전 (★2+).
	if transfer_upgrades:
		for upg in sold_card.upgrades:
			var uid: String = upg.get("id", "")
			if uid != "" and arsenal.can_attach_upgrade():
				arsenal.attach_upgrade(uid)

	arsenal.stats_changed.emit()


## SELL block 의 max_activations (1) 을 arsenal template 에서 읽음.
func _arsenal_sell_max_act(arsenal: CardInstance) -> int:
	for block in arsenal.template.get("effects", []):
		if block.get("trigger_timing", -1) == Enums.TriggerTiming.ON_SELL:
			return block.get("max_activations", -1)
	return -1


# --- Internal ---


## First-match lookup on theme_effects by (action, target). See predator_system
## for the rationale — duplicates indicate either a copy-paste bug or a
## consumer that should be iterating instead.
func _find_eff(effs: Array, action: String, target: String = "") -> Dictionary:
	var first := {}
	var matches := 0
	for e in effs:
		if e.get("action") == action:
			if target == "" or e.get("target", "") == target:
				matches += 1
				if matches == 1:
					first = e
	if matches > 1:
		push_error("_find_eff shadowed duplicates: action=%s target=%s matches=%d — use explicit loop" % [action, target, matches])
	return first


## sp_charger: MF 이벤트 감지 → 카운터 누적, threshold 도달 시 terazin +
## self ATK 개량. ★↑ 시 threshold 하향 + terazin 보상/enhance 수치 증가.
## 2026-04-21: self-target bonus — MF 이벤트의 target_idx 가 이 카드이면
## 카운터 증가분이 self_target_multiplier 배 (기본 2배).
func _charger(card: CardInstance, idx: int, event: Dictionary) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var cp := _find_eff(effs, "counter_produce")
	var threshold: int = cp.get("threshold", 8)
	var self_mult: int = cp.get("self_target_multiplier", 1)
	var rewards: Dictionary = cp.get("rewards", {})
	var terazin_reward: int = rewards.get("terazin", 1)
	var enhance_atk: float = card_effects.get("sp_charger_enhance_atk",
			rewards.get("enhance_atk_pct", 0.05))

	# MF 이벤트의 target 이 이 카드면 카운터 증가분을 self_target_multiplier 배.
	var increment: int = self_mult if event.get("target_idx", -1) == idx else 1

	var events: Array = []
	var terazin := 0

	# Counter: threshold 도달 시 terazin 보상 + self ATK 개량.
	var counter: int = card.theme_state.get("manufacture_counter", 0) + increment
	while counter >= threshold:
		counter -= threshold
		terazin += terazin_reward
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


## sp_global_workshop: 보드에 비-스팀펑크 카드가 1장 이상 있을 때 RS마다
## gear 태그 유닛에 누적 enhance. ★3은 비-스팀펑크 ≥3장 시 추가 spawn.
## 다테마 인센티브 — 단테마 덱에서는 발동 안 함.
func _global_workshop(card: CardInstance, idx: int, board: Array,
		rng: RandomNumberGenerator) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var eff := _find_eff(effs, "gear_diversity_enhance")
	if eff.is_empty():
		return Enums.empty_result()

	# 보드의 비-스팀펑크 카드 수 카운트
	var non_sp_count := 0
	for c in board:
		if c == null:
			continue
		var ci: CardInstance = c
		if ci.template.get("theme", -1) != Enums.CardTheme.STEAMPUNK:
			non_sp_count += 1

	var min_required: int = eff.get("min_non_steampunk", 1)
	if non_sp_count < min_required:
		return Enums.empty_result()

	var atk_pct: float = eff.get("atk_pct", 0.0)
	var hp_pct: float = eff.get("hp_pct", 0.0)
	if atk_pct > 0.0 or hp_pct > 0.0:
		card.enhance("gear", atk_pct, hp_pct)

	var events: Array = [{
		"layer1": Enums.Layer1.ENHANCED,
		"layer2": Enums.Layer2.UPGRADE,
		"source_idx": idx, "target_idx": idx,
	}]

	# ★3 추가: 비-스팀펑크 ≥ spawn_threshold 시 gear 유닛 spawn
	var spawn_thresh: int = eff.get("spawn_threshold", 0)
	var spawn_count: int = eff.get("spawn_unit", 0)
	if spawn_thresh > 0 and spawn_count > 0 and non_sp_count >= spawn_thresh:
		if card.get_total_units() < card.get_unit_cap():
			# gear 태그 유닛 중 weighted random — 카드 comp에서 gear 태그 유닛만 추출
			var gear_unit_ids: Array = []
			for s in card.stacks:
				var tags: PackedStringArray = s["unit_type"].get("tags", PackedStringArray())
				if "gear" in tags:
					gear_unit_ids.append(s["unit_type"].get("id", ""))
			if gear_unit_ids.size() > 0:
				var picked: String = gear_unit_ids[rng.randi_range(0, gear_unit_ids.size() - 1)]
				card.add_specific_unit(picked, spawn_count)
				events.append({
					"layer1": Enums.Layer1.UNIT_ADDED,
					"layer2": Enums.Layer2.MANUFACTURE,
					"source_idx": idx, "target_idx": idx,
				})

	return {"events": events, "gold": 0, "terazin": 0}
