class_name ShopLogic
extends RefCounted
## Headless shop logic — pure RefCounted, no UI dependency.
## Mirrors shop.gd logic for tier rolling, card picking, purchase, reroll.

signal card_purchased(template_id: String)
signal card_merged(card: CardInstance, old_star: int, new_star: int)

var _game_state: GameState
var _rng: RandomNumberGenerator
var _genome: Genome
const BASE_SHOP_SIZE := 6

## Currently offered card IDs. "" = already purchased.
var offered_ids: Array[String] = []

## 양면 동전 슬롯 (Talisman integration).
var _coin_slots: Dictionary = {}
var _reroll_trigger_callback: Callable = Callable()

## Last callback result for tests/tracing. Empty when no trigger callback ran.
var last_reroll_trigger_result: Dictionary = {}
var last_reroll_was_free: bool = false
var last_reroll_cost: int = 0

# Tier weights moved to ShopPicker.DEFAULT_TIER_WEIGHTS (single source of truth).


func setup(state: GameState, rng: RandomNumberGenerator, genome: Genome = null) -> void:
	_game_state = state
	_rng = rng
	_genome = genome


func set_reroll_trigger_callback(callback: Callable) -> void:
	_reroll_trigger_callback = callback


func refresh_shop() -> void:
	_return_unsold_to_pool()
	var level: int = _game_state.shop_level
	offered_ids.clear()

	var shop_size: int = _get_shop_size()
	for i in shop_size:
		var tier := _roll_tier(level)
		var card_id := _pick_card_of_tier(tier)
		offered_ids.append(card_id)

	_apply_collector_start_shop_guarantee()

	# 양면 동전
	_coin_slots = Talisman.roll_coin_slots(_game_state, offered_ids.size(), _rng)


func reroll() -> bool:
	last_reroll_trigger_result = {}
	last_reroll_was_free = false
	last_reroll_cost = 0
	if _game_state.pending_free_rerolls > 0:
		_game_state.pending_free_rerolls -= 1
		last_reroll_was_free = true
		_game_state.round_rerolls += 1
		refresh_shop()
		_apply_reroll_trigger()
		return true
	var cost: int = _get_reroll_cost()
	if _game_state.gold < cost:
		return false
	_game_state.gold -= cost
	last_reroll_cost = cost
	_game_state.round_rerolls += 1
	refresh_shop()
	_apply_reroll_trigger()
	return true


func can_reroll_with_reserve(gold_reserve: int = 0) -> bool:
	if _game_state.pending_free_rerolls > 0:
		return true
	var cost: int = _get_reroll_cost()
	return _game_state.gold >= cost + gold_reserve


func try_purchase(slot_idx: int) -> bool:
	if slot_idx < 0 or slot_idx >= offered_ids.size():
		return false
	var card_id: String = offered_ids[slot_idx]
	if card_id == "":
		return false

	var tmpl := CardDB.get_template(card_id)
	var base_cost: int = tmpl.get("cost", 99)
	var cost: int = Talisman.apply_coin_price(base_cost, slot_idx, _coin_slots)
	if _game_state.gold < cost:
		return false

	# spawn_card funnel: create + commander 보너스 + add_to_bench + try_merge(fresh_ref).
	# 구매한 ★1은 fresh 추적 → 합성 시 유닛 흡수에서 제외(2장분량 정책).
	var spawn_result := _game_state.spawn_card(card_id)
	if spawn_result.is_empty():
		return false
	var bench_idx: int = spawn_result["bench_idx"]
	if bench_idx < 0:
		return false

	_game_state.gold -= cost
	offered_ids[slot_idx] = ""

	for step in spawn_result["merge_steps"] as Array:
		var merged: CardInstance = step["card"]
		card_merged.emit(merged, step["old_star"], step["new_star"])

	card_purchased.emit(card_id)
	return true


func _roll_tier(level: int) -> int:
	return ShopPicker.roll_tier(level, _rng, _genome)


func _get_shop_size() -> int:
	var base_size := Difficulty.get_shop_size(BASE_SHOP_SIZE, _game_state.difficulty)
	return base_size + BossReward.get_shop_size_bonus(_game_state)


func _get_reroll_cost() -> int:
	var base_cost: int = _genome.get_reroll_cost() if _genome else Enums.REROLL_COST
	return Difficulty.get_reroll_cost(base_cost, _game_state.difficulty)


func _pick_card_of_tier(tier: int) -> String:
	return ShopPicker.pick_card(tier, _rng, _game_state, _game_state.card_pool)


func _apply_collector_start_shop_guarantee() -> void:
	if not Commander.should_apply_collector_start_shop(_game_state):
		return
	ShopPicker.apply_min_tier_guarantee(
		offered_ids,
		Commander.COLLECTOR_START_SHOP_MIN_TIER,
		Commander.COLLECTOR_START_SHOP_COUNT,
		_rng,
		_game_state,
		_game_state.card_pool)
	Commander.mark_collector_start_shop_used(_game_state)


func _apply_reroll_trigger() -> void:
	if not _reroll_trigger_callback.is_valid():
		return
	var result = _reroll_trigger_callback.call()
	if result is Dictionary:
		last_reroll_trigger_result = result


## 미구매 카드를 풀에 반환 (리롤/리프레시 전 호출).
func _return_unsold_to_pool() -> void:
	if _game_state.card_pool == null:
		return
	for id in offered_ids:
		if id != "":
			_game_state.card_pool.return_cards(id, 1)
