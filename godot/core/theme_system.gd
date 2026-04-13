class_name ThemeSystem
extends RefCounted
## 테마 시스템 기본 클래스.
## 4개 테마 시스템(Steampunk/Druid/Predator/Military)이 구현해야 할 프로토콜.

## 양성가 보너스 (ChainEngine에서 전파).
var bonus_spawn_chance: float = 0.0
var bonus_rng: RandomNumberGenerator

## Genome card effect overrides (ChainEngine에서 전파).
var card_effects: Dictionary = {}


func process_rs_card(_card: CardInstance, _idx: int, _board: Array,
		_rng: RandomNumberGenerator) -> Dictionary:
	return {"events": [], "gold": 0, "terazin": 0}


func process_event_card(_card: CardInstance, _idx: int, _board: Array,
		_event: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
	return {"events": [], "gold": 0, "terazin": 0}


func apply_persistent(_card: CardInstance) -> void:
	pass


func apply_battle_start(_card: CardInstance, _idx: int, _board: Array) -> Dictionary:
	return {"events": [], "gold": 0, "terazin": 0}


func apply_post_combat(_card: CardInstance, _idx: int, _board: Array,
		_won: bool) -> Dictionary:
	return {"events": [], "gold": 0, "terazin": 0}
