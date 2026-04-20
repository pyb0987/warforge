class_name ThemeSystem
extends RefCounted
## 테마 시스템 기본 클래스.
## 4개 테마 시스템(Steampunk/Druid/Predator/Military)이 구현해야 할 프로토콜.
##
## Protocol contract:
##   Any ``impl: theme_system`` card with timing T routes through the
##   corresponding derived class's hook. If the derived class does not
##   override the hook, the base-class no-op below silently drops the
##   effect. ``predator_system`` / ``druid_system`` / ``military_system``
##   override every hook they need; ``steampunk_system`` currently only
##   overrides process_event_card + apply_persistent + on_sell_trigger.
##   Any future sp_* card with BATTLE_START / POST_COMBAT timing and
##   ``impl: theme_system`` MUST add the matching override in
##   steampunk_system.gd, or the base class push_error below will flag
##   the missing handler at runtime.

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


func apply_persistent(_card: CardInstance) -> void:
	# Quiet no-op: chain_engine.process_persistent iterates ALL board cards
	# and dispatches any PERSISTENT-timed one through its theme_system, even
	# card_db impl cards with non-empty effects. Those are the exception
	# (current design has no card_db PERSISTENT card), so rather than fire a
	# push_error on every PERSISTENT card whose theme didn't override, the
	# silent inheritance is accepted. Derived classes that DO care (druid,
	# predator, steampunk) override and handle their specific card IDs.
	pass


func apply_battle_start(card: CardInstance, _idx: int, _board: Array) -> Dictionary:
	_warn_missing_override(card, "apply_battle_start")
	return {"events": [], "gold": 0, "terazin": 0}


func apply_post_combat(card: CardInstance, _idx: int, _board: Array,
		_won: bool) -> Dictionary:
	_warn_missing_override(card, "apply_post_combat")
	return {"events": [], "gold": 0, "terazin": 0}


## Fires when a theme_system-dispatched card reached a hook the derived
## class didn't override. Guards against silent-drop when e.g. a steampunk
## BS card is added without a matching steampunk_system.apply_battle_start
## override (backlog Phase 2 tech-debt "steampunk_system에 BS/PC 부재").
func _warn_missing_override(card: CardInstance, hook: String) -> void:
	var cid: String = card.get_base_id() if card != null else "<null>"
	push_error("ThemeSystem base %s() called for %s — derived class must override, otherwise the effect silently drops." % [hook, cid])
