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
## Reroll-trigger cards:
##   - ne_pawnbroker (T1): REROLL levelup_discount (chain_engine action),
##     ★3 RS free_reroll 1 (이 시스템이 처리)
##
## Phase 3b-2b deferred (엔진 확장 필요):
##   - ne_masquerade (T4): SELL transform_theme + omni-theme
##   - ne_council (T5): PERSISTENT all_themes_field_bonus (field_slots 동적 변경)
##
## 기존 15장 중립 카드는 모두 impl: card_db이므로 이 시스템을 거치지 않음.


# --- Chain integration ---


func process_rs_card(card: CardInstance, idx: int, _board: Array,
		_rng: RandomNumberGenerator) -> Dictionary:
	match card.get_base_id():
		"ne_envoy": return _envoy_rs(card, idx)
		"ne_pawnbroker": return _pawnbroker_rs(card)
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
	match card.get_base_id():
		"ne_legion": _legion_aura(card, board)
		"ne_council": _council_aura(card, board)


## Self-sell hook: card 본인의 SELL block 효과를 처리.
## chain_engine.process_sell_triggers 에서 sold_card.theme이 NEUTRAL일 때 호출.
## sold_card.tenure 가 0일 수도 있으므로 require_tenure 체크는 호출 측에서.
##
## 반환 dict 확장 필드 (Phase 3b-2b — game_manager 가 처리):
##   - transform_theme: Dict{target_idx, new_theme, omni} — ne_masquerade SELL
func process_self_sell(sold_card: CardInstance, board: Array) -> Dictionary:
	match sold_card.get_base_id():
		"ne_hoarder": return _hoarder_sell(sold_card)
		"ne_masquerade": return _masquerade_sell(sold_card, board)
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
## (정확한 field_slots 값은 game_state 접근 필요 — 현재는 MAX 기준 근사.)
## ★3 as_div_per_e: AS / (1 + E × 0.05) — 전투 더 빠름 (Phase 4 temp_as_mult 적용).
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
	# ★3: AS 가속 — temp_as_mult 누적
	var as_div_per: float = eff.get("as_div_per_e", 0.0)
	if as_div_per > 0.0:
		var divisor: float = 1.0 + as_div_per * empty_count
		if divisor > 0.0:
			card.temp_as_mult /= divisor
	return Enums.empty_result()


# --- ne_fusion_end (T4) — BS ★3 + ★2×weight count scaling ---


## M = 보드의 ★3 카드 수 + ★2 카드 수 × star2_weight (self 포함).
## 이 카드 ATK/HP × M 스케일.
## ★3는 ★3 카드 수가 allies_threshold 이상일 때 모든 아군에게 ATK +M×% 추가 buff (오라).
func _fusion_end_bs(card: CardInstance, _idx: int, board: Array) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var eff := _find_eff(effs, "star3_count_scaling")
	if eff.is_empty():
		return Enums.empty_result()
	var s2_weight: float = eff.get("star2_weight", 0.0)
	# M = ★3 카드 수 + ★2 카드 수 × star2_weight. star3_count는 aura threshold 용으로 별도.
	var m: float = 0.0
	var star3_count: int = 0
	for c in board:
		if c == null:
			continue
		var lvl: int = (c as CardInstance).star_level
		if lvl >= 3:
			m += 1.0
			star3_count += 1
		elif lvl == 2 and s2_weight > 0.0:
			m += s2_weight
	if m <= 0.0:
		return Enums.empty_result()
	var atk_per: float = eff.get("atk_pct_per_m", 0.0)
	var hp_per: float = eff.get("hp_pct_per_m", 0.0)
	var atk_mult: float = 1.0 + atk_per * m
	var hp_mult: float = 1.0 + hp_per * m
	if atk_mult != 1.0 or hp_mult != 1.0:
		card.temp_mult_buff(atk_mult, hp_mult)

	# ★3: ★3 카드 수 ≥ allies_threshold 시 모든 아군에게 ATK +★3수 × allies_atk_pct_per_m
	# (threshold 와 aura 배율 모두 정수 ★3 카운트 기준 — ★2 는 self buff 에만 기여)
	var threshold: int = eff.get("allies_threshold", 0)
	var allies_atk_per: float = eff.get("allies_atk_pct_per_m", 0.0)
	if threshold > 0 and star3_count >= threshold and allies_atk_per > 0.0:
		var allies_mult: float = 1.0 + allies_atk_per * star3_count
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
	# Target이 neutral이면 무시 (filter: non_neutral_target). omni-theme 도 neutral 매치.
	var target_idx: int = event.get("target_idx", -1)
	if target_idx >= 0 and target_idx < board.size() and board[target_idx] != null:
		var target: CardInstance = board[target_idx]
		if target.is_omni_theme or target.template.get("theme", -1) == Enums.CardTheme.NEUTRAL:
			return Enums.empty_result()

	# 두 OE block 중 현재 event 의 layer1 에 매칭되는 block 의 mirror_l1 액션 추출.
	# codegen 출력은 block 직접에 trigger_layer1 키 (listen 중첩 dict 아님 — multi-
	# review C-A/C-B veto 사항). _trigger_matches_block 과 동일 규약 사용.
	var l1: int = event.get("layer1", -1)
	var template: Dictionary = card.template
	var matched_eff: Dictionary = {}
	for block in template.get("effects", []):
		if block.get("trigger_timing", -1) != Enums.TriggerTiming.ON_EVENT:
			continue
		if block.get("trigger_layer1", -1) != l1:
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


# --- ne_council (T5) — PERSISTENT all_themes_field_bonus ---


## ★2/★3에서 모든 아군에 ATK/HP 추가 buff (5테마 조건 충족 시).
## field_slots +1 자체는 game_manager._evaluate_council_field_bonus 에서 처리.
## 5테마 조건은 game_state.council_field_bonus_active 와 동일 — board 로 재평가.
func _council_aura(card: CardInstance, board: Array) -> void:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var eff := _find_eff(effs, "all_themes_field_bonus")
	if eff.is_empty():
		return
	var allies_atk: float = eff.get("allies_atk_pct", 0.0)
	var allies_hp: float = eff.get("allies_hp_pct", 0.0)
	if allies_atk <= 0.0 and allies_hp <= 0.0:
		return  # ★1 은 field_slots 만, 추가 스탯 없음
	# 5테마 조건 재검사 (process_persistent 시점) — omni-theme 카드는 모두 매치
	var themes_seen: Dictionary = {}
	for c in board:
		if c == null:
			continue
		var ci: CardInstance = c
		if ci.is_omni_theme:
			themes_seen[Enums.CardTheme.NEUTRAL] = true
			themes_seen[Enums.CardTheme.STEAMPUNK] = true
			themes_seen[Enums.CardTheme.MILITARY] = true
			themes_seen[Enums.CardTheme.DRUID] = true
			themes_seen[Enums.CardTheme.PREDATOR] = true
		else:
			var t: int = ci.template.get("theme", -1)
			if t >= 0:
				themes_seen[t] = true
	if themes_seen.size() < 5:
		return
	var atk_mult: float = 1.0 + allies_atk
	var hp_mult: float = 1.0 + allies_hp
	for c in board:
		if c == null:
			continue
		(c as CardInstance).temp_mult_buff(atk_mult, hp_mult)


# --- ne_pawnbroker (T1) — REROLL levelup_discount + ★3 RS free_reroll ---


## RS (★3 only): YAML free_reroll 액션을 result dict 의 "free_rerolls" 필드로
## 신호. ChainEngine 가 누적해 pending_free_reroll_callback 으로 game_state 에
## 전달. ★1/★2 는 RS block 자체가 없으므로 호출되지 않음.
## REROLL trigger 의 levelup_discount 액션은 chain_engine._execute_actions 가 처리.
func _pawnbroker_rs(card: CardInstance) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var fr := _find_eff(effs, "free_reroll")
	var amount := 0
	if not fr.is_empty():
		amount = int(fr.get("value", 0))
	return {
		"events": [], "gold": 0, "terazin": 0,
		"free_rerolls": amount,
	}


# --- ne_masquerade (T4) — SELL transform_theme ---


## SELL (tenure ≥ 1): 필드 카드 1장 선택 → theme 변경.
## ★1: 5개 중 무작위 3개 offering, ★2: 5개 전체, ★3: omni-theme.
## game_manager 가 결과 dict의 "transform_theme" 필드를 처리.
## sim 결정성: target = 첫 비-self 필드 카드, theme = 5개 중 첫 번째 비-NEUTRAL theme
## (NEUTRAL 디폴트는 diversity 효과 무용 — 의미 있는 변환 위해 STEAMPUNK 우선).
##
## CardInstance 참조를 직접 반환 (active_board↔board sparse-compact 인덱스 불일치 방지).
func _masquerade_sell(card: CardInstance, board: Array) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var eff := _find_eff(effs, "transform_theme")
	if eff.is_empty():
		return Enums.empty_result()
	# 대상 카드 선택 (sim 결정성) — board는 active(compact) 또는 sparse 둘 다 처리.
	var target: CardInstance = null
	for c in board:
		if c == null or c == card:
			continue
		target = c
		break
	if target == null:
		return Enums.empty_result()
	# theme 선택 (sim 은 첫 비-NEUTRAL — 다양성에 의미 있는 변환).
	# 첫 비-NEUTRAL 이면서 target 의 현재 theme 와 다른 것을 우선.
	var omni: bool = eff.get("omni", false)
	var current: int = target.template.get("theme", -1)
	var new_theme: int = Enums.CardTheme.STEAMPUNK
	if current == Enums.CardTheme.STEAMPUNK:
		new_theme = Enums.CardTheme.PREDATOR
	return {
		"events": [],
		"gold": 0,
		"terazin": 0,
		"transform_theme": {
			"target_card": target,
			"new_theme": new_theme,
			"omni": omni,
		},
	}
