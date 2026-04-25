class_name NeutralSystem
extends "res://core/theme_system.gd"
## Neutral theme system: cross-theme utility & build-around capstones.
##
## Phase 3b-1 cards (구현 완료):
##   - ne_envoy (T2): RS +Ng, ★3 BS +1g — 무조건 골드 부스터
##   - ne_hoarder (T3): SELL tenure × Ng — 저축형 판매
##
## Phase 3b-2 deferred (구현 예정):
##   - ne_clone_seed (T1): RS clone_self_to_bench + SELL gold/transfer
##   - ne_legion (T3): PERSISTENT duplicate_buff_aura
##   - ne_masquerade (T4): SELL transform_theme
##   - ne_void_force (T4): BS empty_slot_scaling
##   - ne_fusion_end (T4): BS star3_count_scaling
##   - ne_council (T5): PERSISTENT all_themes_field_bonus
##   - ne_nexus (T5): OE mirror_l1
##
## 기존 15장 중립 카드는 모두 impl: card_db이므로 이 시스템을 거치지 않음.


# --- Chain integration ---


func process_rs_card(card: CardInstance, idx: int, _board: Array,
		_rng: RandomNumberGenerator) -> Dictionary:
	match card.get_base_id():
		"ne_envoy": return _envoy_rs(card, idx)
	return Enums.empty_result()


func process_event_card(_card: CardInstance, _idx: int, _board: Array,
		_event: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
	# Phase 3b-1: neutral OE listeners 미구현 (ne_nexus는 3b-2)
	return Enums.empty_result()


# --- External hooks (combat engine / game state) ---


func apply_battle_start(card: CardInstance, _idx: int, _board: Array) -> Dictionary:
	if card.get_base_id() == "ne_envoy":
		return _envoy_bs(card)
	return Enums.empty_result()


func apply_post_combat(_card: CardInstance, _idx: int, _board: Array,
		_won: bool) -> Dictionary:
	return Enums.empty_result()


func apply_persistent(_card: CardInstance) -> void:
	# Phase 3b-2: ne_legion, ne_council 처리 예정
	pass


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
## (업그레이드 지급은 game_state 접근 필요 — Phase 3b-2 deferred, 골드만 지급)
func _hoarder_sell(card: CardInstance) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var eff := _find_eff(effs, "tenure_gold")
	if eff.is_empty():
		return Enums.empty_result()
	var per_tenure: int = eff.get("gold_per_tenure", 0)
	var gold: int = card.tenure * per_tenure
	return {"events": [], "gold": gold, "terazin": 0}
