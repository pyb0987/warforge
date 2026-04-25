class_name ThemeSystem
extends RefCounted
## 테마 시스템 기본 클래스.
## 4개 테마 시스템(Steampunk/Druid/Predator/Military)이 구현해야 할 프로토콜.
##
## Protocol contract:
##   Any ``impl: theme_system`` card with timing T routes through the
##   corresponding derived class's hook. If the derived class does not
##   override the hook, the base-class push_error below flags at runtime.
##   Current coverage:
##     - druid_system / military_system / predator_system: all hooks overridden.
##     - steampunk_system: process_rs_card (sp_warmachine only, multi-block)
##       + process_event_card + apply_persistent + on_sell_trigger.
##   Any future sp_* card with BATTLE_START / POST_COMBAT timing and
##   ``impl: theme_system`` MUST add a matching override in
##   steampunk_system.gd, or push_error will flag the missing handler.

## 양성가 보너스 (ChainEngine에서 전파).
var bonus_spawn_chance: float = 0.0
var bonus_rng: RandomNumberGenerator

## Genome card effect overrides (ChainEngine에서 전파).
var card_effects: Dictionary = {}


func process_rs_card(card: CardInstance, _idx: int, _board: Array,
		_rng: RandomNumberGenerator) -> Dictionary:
	_warn_missing_override(card, "process_rs_card")
	return {"events": [], "gold": 0, "terazin": 0}


func process_event_card(card: CardInstance, _idx: int, _board: Array,
		_event: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
	_warn_missing_override(card, "process_event_card")
	return {"events": [], "gold": 0, "terazin": 0}


func apply_persistent(_card: CardInstance, _board: Array = []) -> void:
	# Quiet no-op: chain_engine.process_persistent iterates ALL board cards
	# and dispatches any PERSISTENT-timed one through its theme_system, even
	# card_db impl cards. Rather than fire push_error on every PERSISTENT
	# card whose theme didn't override, silent inheritance is accepted.
	# Derived classes that care (druid, predator, steampunk, neutral) override.
	# board param 추가 (Phase 3b-2a) — ne_legion 처럼 보드 전체를 보는 aura
	# 카드를 위해. 기존 override 들은 board 무시 가능 (default = [] 안전).
	pass


func apply_battle_start(card: CardInstance, _idx: int, _board: Array) -> Dictionary:
	_warn_missing_override(card, "apply_battle_start")
	return {"events": [], "gold": 0, "terazin": 0}


func apply_post_combat(card: CardInstance, _idx: int, _board: Array,
		_won: bool) -> Dictionary:
	_warn_missing_override(card, "apply_post_combat")
	return {"events": [], "gold": 0, "terazin": 0}


## Self-sell hook: 카드 본인이 판매될 때 발동되는 효과 처리.
## chain_engine.process_sell_triggers 가 sold_card의 ON_SELL block 존재 시 호출.
## 기본 no-op — neutral_system 등이 override (예: ne_hoarder tenure_gold).
## 반환값: {gold, terazin, events} — game_state에 자원 적용.
func process_self_sell(_sold_card: CardInstance, _board: Array) -> Dictionary:
	return {"events": [], "gold": 0, "terazin": 0}


## Fires when an ``impl: theme_system`` card reaches the base no-op — the
## derived theme class did not override the hook for this card_id.
## card_db-impl cards hit the base class legitimately (via the effects.is_empty
## card_db fallback routed through apply_battle_start/apply_post_combat), so
## the filter limits the warning to actual protocol violations.
func _warn_missing_override(card: CardInstance, hook: String) -> void:
	if card.template.get("impl", "card_db") == "theme_system":
		push_error("%s: theme_system missing override for %s (card_id=%s)" % [
			get_script().get_path().get_file(), hook, card.get_base_id()])
