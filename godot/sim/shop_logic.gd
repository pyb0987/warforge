class_name ShopLogic
extends RefCounted
## Headless shop logic — pure RefCounted, no UI dependency.
## Mirrors shop.gd logic for tier rolling, card picking, purchase, reroll.

signal card_purchased(template_id: String)
signal card_merged(card: CardInstance, old_star: int, new_star: int)

var _game_state: GameState
var _rng: RandomNumberGenerator
var _genome: Genome

## Currently offered card IDs. "" = already purchased.
var offered_ids: Array[String] = []

## 양면 동전 슬롯 (Talisman integration).
var _coin_slots: Dictionary = {}

# Tier weights moved to ShopPicker.DEFAULT_TIER_WEIGHTS (single source of truth).


func setup(state: GameState, rng: RandomNumberGenerator, genome: Genome = null) -> void:
	_game_state = state
	_rng = rng
	_genome = genome


func refresh_shop() -> void:
	_return_unsold_to_pool()
	var level: int = _game_state.shop_level
	offered_ids.clear()

	var shop_size: int = 6 + BossReward.get_shop_size_bonus(_game_state)
	for i in shop_size:
		var tier := _roll_tier(level)
		var card_id := _pick_card_of_tier(tier)
		offered_ids.append(card_id)

	# 양면 동전
	_coin_slots = Talisman.roll_coin_slots(_game_state, offered_ids.size(), _rng)


func reroll() -> bool:
	var cost: int = _genome.get_reroll_cost() if _genome else Enums.REROLL_COST
	if _game_state.gold < cost:
		return false
	_game_state.gold -= cost
	_game_state.round_rerolls += 1
	refresh_shop()
	return true


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

	var card := CardInstance.create(card_id)
	if card == null:
		return false
	Commander.apply_card_bonuses(_game_state, card)

	var bench_idx := _game_state.add_to_bench(card)
	if bench_idx < 0:
		return false

	_game_state.gold -= cost
	offered_ids[slot_idx] = ""

	# Auto-merge check (cascade: emit each step)
	var merge_steps := _game_state.try_merge(card_id)
	for step in merge_steps:
		var merged: CardInstance = step["card"]
		card_merged.emit(merged, step["old_star"], step["new_star"])

	card_purchased.emit(card_id)
	return true


func _roll_tier(level: int) -> int:
	return ShopPicker.roll_tier(level, _rng, _genome)


func _pick_card_of_tier(tier: int) -> String:
	return ShopPicker.pick_card(tier, _rng, _game_state, _game_state.card_pool)


## 미구매 카드를 풀에 반환 (리롤/리프레시 전 호출).
func _return_unsold_to_pool() -> void:
	if _game_state.card_pool == null:
		return
	for id in offered_ids:
		if id != "":
			_game_state.card_pool.return_cards(id, 1)
