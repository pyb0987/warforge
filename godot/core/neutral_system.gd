class_name NeutralSystem
extends "res://core/theme_system.gd"
## Neutral theme system: cross-theme utility & build-around capstones.
##
## Phase 3b-1 cards (구현 완료):
##   - ne_envoy (T2): RS +Ng, ★3 BS +1g — 무조건 골드 부스터
##   - ne_hoarder (T3): SELL tenure × Ng — 저축형 판매
##
## Phase 3b-2a cards (구현 완료):
##   - ne_legion (T3): PERSISTENT duplicate_buff_aura — 보드 중복 카드 buff
##   - ne_void_force (T4): BS empty_slot_scaling — 빈칸 × 스케일
##   - ne_fusion_end (T4): BS star3_count_scaling — ★3 카드 수 × 스케일
##   - ne_nexus (T5): OE mirror_l1 — 비-neutral 이벤트 미러
##
## Phase 3b-2b deferred (엔진 확장 필요):
##   - ne_clone_seed (T1): RS clone_self_to_bench + SELL transfer_upgrade
##   - ne_masquerade (T4): SELL transform_theme + omni-theme
##   - ne_council (T5): PERSISTENT all_themes_field_bonus (field_slots 동적 변경)
##
## 기존 15장 중립 카드는 모두 impl: card_db이므로 이 시스템을 거치지 않음.


# --- Chain integration ---


func process_rs_card(card: CardInstance, idx: int, _board: Array,
		_rng: RandomNumberGenerator) -> Dictionary:
	match card.get_base_id():
		"ne_envoy": return _envoy_rs(card, idx)
	return Enums.empty_result()


func process_event_card(card: CardInstance, idx: int, board: Array,
		event: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
	if card.get_base_id() == "ne_nexus":
		return _nexus(card, idx, board, event)
	return Enums.empty_result()


# --- External hooks (combat engine / game state) ---


func apply_battle_start(card: CardInstance, idx: int, board: Array) -> Dictionary:
	match card.get_base_id():
		"ne_envoy": return _envoy_bs(card)
		"ne_void_force": return _void_force_bs(card, idx, board)
		"ne_fusion_end": return _fusion_end_bs(card, idx, board)
	return Enums.empty_result()


func apply_post_combat(_card: CardInstance, _idx: int, _board: Array,
		_won: bool) -> Dictionary:
	return Enums.empty_result()


func apply_persistent(card: CardInstance, board: Array = []) -> void:
	if card.get_base_id() == "ne_legion":
		_legion_aura(card, board)


## Self-sell hook: card 본인의 SELL block 효과를 처리.
## chain_engine.process_sell_triggers 에서 sold_card.theme이 NEUTRAL일 때 호출.
## sold_card.tenure 가 0일 수도 있으므로 require_tenure 체크는 호출 측에서.
func process_self_sell(sold_card: CardInstance, _board: Array) -> Dictionary:
	match sold_card.get_base_id():
		"ne_hoarder": return _hoarder_sell(sold_card)
	return {"events": [], "gold": 0, "terazin": 0}


# --- Helpers ---


func _find_eff(effs: Array, action: String) -> Dictionary:
	for e in effs:
		if e.get("action") == action:
			return e
	return {}


# --- ne_envoy (T2) ---


func _envoy_rs(card: CardInstance, _idx: int) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var eff := _find_eff(effs, "grant_gold")
	if eff.is_empty():
		return Enums.empty_result()
	var amount: int = eff.get("amount", 0)
	return {"events": [], "gold": amount, "terazin": 0}


## ★3에서만 BS block 존재 (RS block의 grant_gold 외 추가 BS grant_gold).
func _envoy_bs(card: CardInstance) -> Dictionary:
	if card.star_level < 3:
		return Enums.empty_result()
	# BS block은 multi-block의 두 번째 block — find primary timing 우회 필요
	# 단순화: ★3은 1g 고정 (YAML 매핑)
	var template: Dictionary = card.template
	var effects: Array = template.get("effects", [])
	for block in effects:
		if block.get("trigger_timing", -1) != Enums.TriggerTiming.BATTLE_START:
			continue
		for action in block.get("actions", []):
			if action.get("action", "") == "grant_gold":
				var amount: int = action.get("amount", 0)
				return {"events": [], "gold": amount, "terazin": 0}
	return Enums.empty_result()


# --- ne_hoarder (T3) ---


## SELL 시 tenure × gold_per_tenure 만큼 골드 지급. ★3은 5% 확률 업그레이드.
## (업그레이드 지급은 game_state 접근 필요 — Phase 3b-2b deferred, 골드만 지급)
func _hoarder_sell(card: CardInstance) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var eff := _find_eff(effs, "tenure_gold")
	if eff.is_empty():
		return Enums.empty_result()
	var per_tenure: int = eff.get("gold_per_tenure", 0)
	var gold: int = card.tenure * per_tenure
	return {"events": [], "gold": gold, "terazin": 0}


# --- ne_legion (T3) — PERSISTENT duplicate buff aura ---


## ne_legion이 보드에 있으면, template_id가 보드에 N≥2장 존재하는
## 모든 카드(ne_legion 자기 자신 포함)에 ATK +X% × N_excl, HP +Y% × N_excl
## (N_excl = 같은 template_id 카드 수, self 제외).
## ★3은 추가로 각 중복 카드에 유닛 1기 spawn (★3 spawn_per_card).
##
## 호출 패턴: chain_engine.process_persistent 가 보드 카드 각각에 대해
## apply_persistent(card, board) 호출. ne_legion 인스턴스마다 한 번씩 fire.
## 같은 ★ 의 ne_legion 이 보드에 2장 있으면 효과가 두 번 누적되는 점 의도됨.
func _legion_aura(card: CardInstance, board: Array) -> void:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var eff := _find_eff(effs, "duplicate_buff_aura")
	if eff.is_empty():
		return
	var atk_per: float = eff.get("atk_pct_per_n", 0.0)
	var hp_per: float = eff.get("hp_pct_per_n", 0.0)
	var spawn_per_card: int = eff.get("spawn_per_card", 0)

	# 보드에서 template_id 별 카운트 집계
	var counts: Dictionary = {}
	for c in board:
		if c == null:
			continue
		var tid: String = (c as CardInstance).template_id
		counts[tid] = counts.get(tid, 0) + 1

	# 각 중복 카드 (count ≥ 2) 에 buff 적용
	for c in board:
		if c == null:
			continue
		var ci: CardInstance = c
		var tid: String = ci.template_id
		var n_total: int = counts.get(tid, 0)
		if n_total < 2:
			continue
		var n_excl: int = n_total - 1
		var atk_mult: float = 1.0 + atk_per * n_excl
		var hp_mult: float = 1.0 + hp_per * n_excl
		if atk_mult != 1.0 or hp_mult != 1.0:
			ci.temp_mult_buff(atk_mult, hp_mult)
		# spawn_per_card (★3): 한 번만 — ne_legion 자기 한 번에 한해 모든 중복 카드에 1기씩 spawn
		# 다중 ne_legion 보드 시 중복 spawn 가능 — 의도된 power scaling
		if spawn_per_card > 0 and ci.get_total_units() < ci.get_unit_cap():
			# spawn_random 은 RNG 필요 — apply_persistent signature에 rng 없음
			# 대안: 첫 stack의 unit_id 직접 추가 (deterministic)
			if ci.stacks.size() > 0:
				var unit_id: String = ci.stacks[0]["unit_type"].get("id", "")
				if unit_id != "":
					ci.add_specific_unit(unit_id, spawn_per_card)


# --- ne_void_force (T4) — BS empty slot scaling ---


## E = 빈 필드 슬롯 수. self ATK/HP/AS 가 E에 비례 강화.
## board는 active_board (non-null만), 따라서 empty = MAX_FIELD_SLOTS - board.size().
## (정확한 field_slots 값은 game_state 접근 필요 — 현재는 MAX 기준 근사,
## Phase 4에서 game_state 전달로 정확화 가능)
## AS 스케일링 (★3 as_div_per_e)은 temp_as_mult 미지원 — 현재 ATK/HP 만,
## AS는 Phase 4 deferred (combat engine AS pipeline 확장 시).
func _void_force_bs(card: CardInstance, _idx: int, board: Array) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var eff := _find_eff(effs, "empty_slot_scaling")
	if eff.is_empty():
		return Enums.empty_result()
	var empty_count: int = Enums.MAX_FIELD_SLOTS - board.size()
	if empty_count <= 0:
		return Enums.empty_result()
	var atk_per: float = eff.get("atk_pct_per_e", 0.0)
	var hp_per: float = eff.get("hp_pct_per_e", 0.0)
	var atk_mult: float = 1.0 + atk_per * empty_count
	var hp_mult: float = 1.0 + hp_per * empty_count
	if atk_mult != 1.0 or hp_mult != 1.0:
		card.temp_mult_buff(atk_mult, hp_mult)
	return Enums.empty_result()


# --- ne_fusion_end (T4) — BS ★3 count scaling ---


## M = 보드의 ★3 카드 수 (self 포함). self ATK/HP × M 스케일.
## ★3는 M≥3 시 모든 아군에게 ATK +M×% 추가 buff (오라).
func _fusion_end_bs(card: CardInstance, _idx: int, board: Array) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var eff := _find_eff(effs, "star3_count_scaling")
	if eff.is_empty():
		return Enums.empty_result()
	# M = ★3 카드 수
	var m: int = 0
	for c in board:
		if c == null:
			continue
		if (c as CardInstance).star_level >= 3:
			m += 1
	if m <= 0:
		return Enums.empty_result()
	var atk_per: float = eff.get("atk_pct_per_m", 0.0)
	var hp_per: float = eff.get("hp_pct_per_m", 0.0)
	var atk_mult: float = 1.0 + atk_per * m
	var hp_mult: float = 1.0 + hp_per * m
	if atk_mult != 1.0 or hp_mult != 1.0:
		card.temp_mult_buff(atk_mult, hp_mult)

	# ★3: M ≥ allies_threshold 시 모든 아군에게 ATK +M × allies_atk_pct_per_m
	var threshold: int = eff.get("allies_threshold", 0)
	var allies_atk_per: float = eff.get("allies_atk_pct_per_m", 0.0)
	if threshold > 0 and m >= threshold and allies_atk_per > 0.0:
		var allies_mult: float = 1.0 + allies_atk_per * m
		for c in board:
			if c == null or c == card:
				continue
			(c as CardInstance).temp_mult_buff(allies_mult, 1.0)
	return Enums.empty_result()


# --- ne_nexus (T5) — OE mirror_l1 ---


## listen l1: EN or UA, filter non_neutral_target — 다른 테마 카드가 대상인
## EN/UA 이벤트마다 self 누적 enhance. ★3은 추가 spawn.
## YAML에 두 개의 OE block (EN listen + UA listen) 존재 — chain_engine이
## 각각 별도 dispatch. 본 handler는 어느 block에서 호출됐는지 event.layer1 으로
## 분기.
func _nexus(card: CardInstance, idx: int, board: Array, event: Dictionary) -> Dictionary:
	# 자기 source 무시 (자체 spawn으로 인한 cyclic 방지)
	if event.get("source_idx", -1) == idx:
		return Enums.empty_result()
	# Target이 neutral이면 무시 (filter: non_neutral_target)
	var target_idx: int = event.get("target_idx", -1)
	if target_idx >= 0 and target_idx < board.size() and board[target_idx] != null:
		var target: CardInstance = board[target_idx]
		if target.template.get("theme", -1) == Enums.CardTheme.NEUTRAL:
			return Enums.empty_result()

	# 두 OE block 중 현재 event 의 layer1 에 매칭되는 block 의 mirror_l1 액션 추출
	var l1: int = event.get("layer1", -1)
	var template: Dictionary = card.template
	var matched_eff: Dictionary = {}
	for block in template.get("effects", []):
		if block.get("trigger_timing", -1) != Enums.TriggerTiming.ON_EVENT:
			continue
		var listen: Dictionary = block.get("listen", {})
		if listen.get("l1", -1) != l1:
			continue
		for action in block.get("actions", []):
			if action.get("action", "") == "mirror_l1":
				matched_eff = action
				break
		if not matched_eff.is_empty():
			break
	if matched_eff.is_empty():
		return Enums.empty_result()

	var atk_pct: float = matched_eff.get("atk_pct", 0.0)
	var hp_pct: float = matched_eff.get("hp_pct", 0.0)
	if atk_pct > 0.0 or hp_pct > 0.0:
		card.enhance(null, atk_pct, hp_pct)
	var events: Array = [{
		"layer1": Enums.Layer1.ENHANCED,
		"layer2": -1,
		"source_idx": idx, "target_idx": idx,
	}]

	# ★3: spawn_unit
	var spawn_count: int = matched_eff.get("spawn_unit", 0)
	if spawn_count > 0 and card.get_total_units() < card.get_unit_cap():
		# RNG 없는 환경 — 첫 stack의 unit 직접 추가
		if card.stacks.size() > 0:
			var unit_id: String = card.stacks[0]["unit_type"].get("id", "")
			if unit_id != "":
				card.add_specific_unit(unit_id, spawn_count)
				events.append({
					"layer1": Enums.Layer1.UNIT_ADDED,
					"layer2": -1,
					"source_idx": idx, "target_idx": idx,
				})
	return {"events": events, "gold": 0, "terazin": 0}
