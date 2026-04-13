class_name CardPool
extends RefCounted
## 카드 풀 고갈 메커니즘 (OBS-049).
## TFT식 공유 카드 풀: 티어별 복사본 수 제한.
## 구매 시 draw(), 판매/리롤 반환 시 return_cards().

## 티어별 기본 복사본 수.
const DEFAULT_POOL_SIZES := {1: 22, 2: 18, 3: 15, 4: 13, 5: 11}

## { card_id: String → remaining: int }
var _pool: Dictionary = {}

## { card_id: String → initial: int } — 초기 수량 (초과 반환 방지용)
var _initial: Dictionary = {}


## 카드 풀 초기화. custom_sizes가 없으면 DEFAULT_POOL_SIZES 사용.
func init_pool(custom_sizes: Dictionary = {}) -> void:
	_pool.clear()
	_initial.clear()
	var sizes: Dictionary = custom_sizes if not custom_sizes.is_empty() else DEFAULT_POOL_SIZES
	for id in CardDB.get_all_ids():
		var tmpl := CardDB.get_template(id)
		var tier: int = tmpl.get("tier", 1)
		var count: int = sizes.get(tier, sizes.get(1, 22))
		_pool[id] = count
		_initial[id] = count


## 카드 1장 소모. 성공 시 true, 잔여 0이면 false.
func draw(card_id: String) -> bool:
	if not _pool.has(card_id):
		return false
	if _pool[card_id] <= 0:
		return false
	_pool[card_id] -= 1
	return true


## 카드 반환 (판매/리롤 시). 초기 수량 초과 불가.
func return_cards(card_id: String, count: int) -> void:
	if not _pool.has(card_id):
		return
	_pool[card_id] = mini(_pool[card_id] + count, _initial[card_id])


## 특정 티어에서 잔여 > 0인 카드 ID 배열.
func available_of_tier(tier: int) -> Array[String]:
	var result: Array[String] = []
	for id in _pool:
		if _pool[id] > 0:
			var tmpl := CardDB.get_template(id)
			if tmpl.get("tier", 0) == tier:
				result.append(id)
	return result


## 티어별 잔여 총합. { tier: int → remaining: int }
func remaining_per_tier() -> Dictionary:
	var result := {}
	for id in _pool:
		var tmpl := CardDB.get_template(id)
		var tier: int = tmpl.get("tier", 1)
		result[tier] = result.get(tier, 0) + _pool[id]
	return result


## 특정 카드의 잔여 수량. 미등록이면 0.
func get_remaining(card_id: String) -> int:
	return _pool.get(card_id, 0)
