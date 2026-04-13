class_name GameState
extends RefCounted
## Manages player state: board, bench, economy, HP, round.

signal state_changed
signal card_moved(from_zone, from_idx, to_zone, to_idx)
## 업그레이드 라이프사이클 신호 (play_logger 가 구독).
## emit 사이트: build_phase(상점/머지 보너스), boss_reward(보스 보상), steampunk_system(salvage).
signal upgrade_purchased(upgrade_id: String, slot_idx: int, cost: int, terazin_after: int)
signal upgrade_refunded(upgrade_id: String, cost: int, reason: String, terazin_after: int)
signal upgrade_attached_to_card(upgrade_id: String, source: String, target_card_id: String, target_idx: int)
signal card_sold(sold_card: CardInstance)  # ON_SELL 트리거용 (game_manager, headless_runner 구독)

# --- Board & Bench ---
var board: Array = []  # Array[CardInstance | null], size = MAX_FIELD_SLOTS
var bench: Array = []  # Array[CardInstance | null], size = MAX_BENCH_SLOTS
var field_slots: int = Enums.STARTING_FIELD_SLOTS  # 현재 사용 가능 필드 슬롯 수 (최대 MAX_FIELD_SLOTS)

# --- Economy ---
var gold: int = 0
var terazin: int = 0
## 이번 라운드 한정 무료 리롤 저축분. 라운드 시작 시 0으로 리셋 후 카드 효과 등으로 재충전.
## Commander 확률 무료 리롤에 실패한 리롤 시점에 소비 (player-favorable).
var pending_free_rerolls: int = 0
## 이번 라운드 리롤 총 횟수 (유/무료 모두 포함). 라운드 시작 시 0으로 리셋.
## 증기 이자기 ★2/★3 전투 버프 산출에 사용.
var round_rerolls: int = 0

# --- Player ---
var hp: int = 30
var round_num: int = 0

# --- Commander ---
var commander_type: int = Enums.CommanderType.NONE
var commander_state: Dictionary = {}  # 커맨더별 동적 상태 (win_count 등)

# --- Talisman ---
var talisman_type: int = Enums.TalismanType.NONE
var talisman_state: Dictionary = {}  # 부적별 동적 상태 (1회 추적 등)

# --- Boss Rewards ---
var boss_rewards: Array[String] = []  # 획득한 영구 보상 ID 목록

# --- Shop ---
var shop_cards: Array = []  # Array[String] card template IDs
var shop_level: int = 1  # 상점 레벨 (티어 확률 영향)
var levelup_current_cost: int = 0  # _init()에서 동적 초기화
var card_pool: CardPool = null  # 카드 풀 고갈 메커니즘 (OBS-049)


func _init() -> void:
	board.resize(Enums.MAX_FIELD_SLOTS)
	board.fill(null)
	bench.resize(Enums.MAX_BENCH_SLOTS)
	bench.fill(null)
	var next_level := shop_level + 1
	if Enums.LEVELUP_BASE_COST.has(next_level):
		levelup_current_cost = Enums.LEVELUP_BASE_COST[next_level]


## Get the number of non-null cards on the board.
func board_count() -> int:
	var count := 0
	for card in board:
		if card != null:
			count += 1
	return count


## Get all non-null cards on the board (for chain engine).
func get_active_board() -> Array:
	var result: Array = []
	for card in board:
		if card != null:
			result.append(card)
	return result


## Move a card between zones (board/bench).
func move_card(from_zone: String, from_idx: int, to_zone: String, to_idx: int) -> bool:
	var from_arr := _get_zone(from_zone)
	var to_arr := _get_zone(to_zone)
	if from_arr.is_empty() or to_arr.is_empty():
		return false
	if from_idx < 0 or from_idx >= from_arr.size():
		return false
	if to_idx < 0 or to_idx >= to_arr.size():
		return false

	var card = from_arr[from_idx]
	if card == null:
		return false

	# Prevent placement beyond unlocked field slots
	if to_zone == "board" and to_idx >= field_slots:
		return false

	# Swap if target occupied, otherwise just move
	var target = to_arr[to_idx]
	to_arr[to_idx] = card
	from_arr[from_idx] = target  # null or swapped card

	card_moved.emit(from_zone, from_idx, to_zone, to_idx)
	state_changed.emit()
	return true


## Add card to first empty bench slot. Returns slot index or -1.
func add_to_bench(card: CardInstance) -> int:
	for i in bench.size():
		if bench[i] == null:
			bench[i] = card
			state_changed.emit()
			return i
	return -1  # bench full


## Remove card from zone. Returns the card or null.
func remove_card(zone: String, idx: int) -> CardInstance:
	var arr := _get_zone(zone)
	if arr.is_empty() or idx < 0 or idx >= arr.size():
		return null
	var card = arr[idx]
	arr[idx] = null
	if card != null:
		state_changed.emit()
	return card


## Sell a card: remove + refund gold.
func sell_card(zone: String, idx: int) -> int:
	var card := remove_card(zone, idx)
	if card == null:
		return 0
	var base_cost: int = card.template.get("cost", 0)
	# ★1=cost, ★2=cost×3 (3장 합성), ★3=cost×9 (9장 합성)
	var total_cost: int = base_cost * int(pow(3, card.star_level - 1))
	var refund := int(total_cost * Enums.SELL_REFUND_RATE)
	# ★2/★3 카드 판매 시 -1골드 패널티 (합성 비용 회수 방지)
	if card.star_level >= 2:
		refund = maxi(refund - 1, 0)
	gold += refund
	# 카드 풀에 복귀: ★1→1장, ★2→3장, ★3→9장
	if card_pool != null:
		var return_count: int = int(pow(3, card.star_level - 1))
		card_pool.return_cards(card.template_id, return_count)
	card_sold.emit(card)
	state_changed.emit()
	return refund


## Calculate interest: 1 per 5 gold, max 2.
func calc_interest() -> int:
	return mini(gold / 5, Enums.MAX_INTEREST)


## Try to merge 3 copies of same card → next ★, with cascade.
## Scans copies grouped by star_level and merges the LOWEST ★ group that has 3+
## copies. Repeats until no further merges possible (cascade).
## Returns Array[Dictionary] — each element is {card, old_star, new_star} for
## one merge step. Empty array if no merge happened.
## Cascade example: [★1→★2 step, ★2→★3 step].
func try_merge(template_id: String) -> Array:
	var steps: Array = []
	while true:
		var step := _try_merge_once(template_id)
		if step.is_empty():
			break
		steps.append(step)
	return steps


## Perform a single merge step: find lowest ★ group with 3+ copies, merge 3.
## Returns {card, old_star, new_star} or {}.
func _try_merge_once(template_id: String) -> Dictionary:
	# Group copies by star_level
	var by_star: Dictionary = {}  # int star -> Array[{zone, idx, card}]
	for i in board.size():
		if board[i] != null and board[i].template_id == template_id:
			var s: int = board[i].star_level
			if not by_star.has(s):
				by_star[s] = []
			by_star[s].append({"zone": "board", "idx": i, "card": board[i]})
	for i in bench.size():
		if bench[i] != null and bench[i].template_id == template_id:
			var s: int = bench[i].star_level
			if not by_star.has(s):
				by_star[s] = []
			by_star[s].append({"zone": "bench", "idx": i, "card": bench[i]})

	# Lowest ★ group with 3+ copies goes first (enables cascade)
	var stars: Array = by_star.keys()
	stars.sort()
	var copies: Array = []
	for s in stars:
		if by_star[s].size() >= 3:
			copies = by_star[s].slice(0, 3)
			break

	if copies.size() < 3:
		return {}

	# Survivor 선정: 업그레이드 수 최대 → 동점 시 iteration 순서 (board leftmost → bench leftmost)
	var survivor_idx := 0
	var max_upg: int = copies[0]["card"].upgrades.size()
	for ci in range(1, copies.size()):
		var upg_count: int = copies[ci]["card"].upgrades.size()
		if upg_count > max_upg:
			max_upg = upg_count
			survivor_idx = ci
	# Reorder so survivor is at index 0
	if survivor_idx != 0:
		var tmp = copies[0]
		copies[0] = copies[survivor_idx]
		copies[survivor_idx] = tmp

	var survivor: CardInstance = copies[0]["card"]
	var old_star := survivor.star_level

	# Absorb units + upgrades from donor 2 copies
	for i in range(1, 3):
		var donor: CardInstance = copies[i]["card"]
		for si in donor.stacks.size():
			if si < survivor.stacks.size():
				survivor.stacks[si]["count"] += donor.stacks[si]["count"]
		# Absorb donor upgrades (5-slot cap with truncate)
		for upg in donor.upgrades:
			if survivor.upgrades.size() < survivor.get_max_upgrade_slots():
				survivor.upgrades.append(upg)
			else:
				print("[Merge] Upgrade overflow: dropped '%s' (5-slot cap)" % upg.get("name", "???"))
		# Remove donor from board/bench
		var zone_arr := _get_zone(copies[i]["zone"])
		zone_arr[copies[i]["idx"]] = null

	# Evolve to next star level
	survivor.evolve_star()

	# ★2 bonus: ×1.30 ATK/HP (합성 보상의 스탯 증가 부분)
	# 🔄 이중 합성 (r12_4): 보너스 2배 (0.30→0.60)
	var merge_mult := 2.0 if "r12_4" in boss_rewards else 1.0
	if old_star == 1:
		survivor.multiply_stats(0.30 * merge_mult, 0.30 * merge_mult)

	# OBS-060: 태엽 과급기 ★3 합성 시 1회 보너스 — 에픽 업그레이드 + 3 테라진
	if survivor.get_base_id() == "sp_charger" and survivor.star_level == 3:
		terazin += 3
		survivor.theme_state["pending_epic_upgrade"] = true

	state_changed.emit()
	return {"card": survivor, "old_star": old_star, "new_star": survivor.star_level}


## Try to level up shop. Returns true on success.
func try_levelup() -> bool:
	if shop_level >= Enums.LEVELUP_MAX:
		return false
	if gold < levelup_current_cost:
		return false
	gold -= levelup_current_cost
	shop_level += 1
	# Reset to next level's base cost (or 0 if at max)
	var next_target := shop_level + 1
	if Enums.LEVELUP_BASE_COST.has(next_target):
		levelup_current_cost = Enums.LEVELUP_BASE_COST[next_target]
	else:
		levelup_current_cost = 0
	state_changed.emit()
	return true


## Apply round-start discount: -1g (min 0).
func apply_levelup_discount() -> void:
	levelup_current_cost = maxi(levelup_current_cost - 1, 0)


func _get_zone(zone: String) -> Array:
	match zone:
		"board": return board
		"bench": return bench
	return []
