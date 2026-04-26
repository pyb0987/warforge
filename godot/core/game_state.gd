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
## ne_council (오대 평의회) 5테마 보너스 활성 여부. 라운드 시작에 평가, true ↔ false
## 토글 시 field_slots 를 ±1. 보스 보상 등 다른 보너스와 직교적으로 누적/제거.
var council_field_bonus_active: bool = false

# --- Economy ---
var gold: int = 0
var terazin: int = 0
## Interest cap & rate — genome에서 주입 (game_manager / headless_runner init). 기본값은 Enums 상수.
## 2026-04-19: build_phase UI가 calc_interest() 경유 → 이 값이 표시에 반영됨.
var max_interest: int = Enums.MAX_INTEREST
var interest_per_5g: int = Enums.INTEREST_PER_5G
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


## Spawn a new card to bench and run auto-merge with fresh tracking.
## 모든 "신규 카드 생성" 경로의 단일 진입점 (구매/보스 보상/부적/카드효과).
## CardInstance.create + commander 보너스 + add_to_bench + try_merge(fresh_ref=card).
##
## Commander 보너스는 try_merge 전에 적용 — 이후 absorb_donor max 정책으로
## survivor에 자연스럽게 전파됨.
##
## Returns: {card, bench_idx, merge_steps} on success, {} if create failed,
##          {card, bench_idx=-1, merge_steps=[]} if bench full.
func spawn_card(template_id: String) -> Dictionary:
	var card := CardInstance.create(template_id)
	if card == null:
		return {}
	Commander.apply_card_bonuses(self, card)
	var bench_idx := add_to_bench(card)
	if bench_idx < 0:
		return {"card": card, "bench_idx": -1, "merge_steps": []}
	var merge_steps := try_merge(template_id, card)
	return {"card": card, "bench_idx": bench_idx, "merge_steps": merge_steps}


## Spawn a clone (system-created card, e.g. ne_clone_seed). 벤치에만 추가하고
## auto-merge는 트리거하지 않는다 — 클론은 라운드 종료 RS 결과로 들어오므로
## 동일 라운드 합성 흐름에서 분리됨.
func add_clone(template_id: String) -> CardInstance:
	var clone := CardInstance.create(template_id)
	if clone == null:
		return null
	if add_to_bench(clone) < 0:
		return null  # bench full → silent drop (기존 클론 동작 보존)
	return clone


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


## Calculate interest from stored economy params (genome-driven, fallback Enums).
func calc_interest() -> int:
	return mini(gold / 5 * interest_per_5g, max_interest)


## Try to merge 3 copies of same card → next ★, with cascade.
## Scans copies grouped by star_level and merges the LOWEST ★ group that has 3+
## copies. Repeats until no further merges possible (cascade).
## Returns Array[Dictionary] — each element is {card, old_star, new_star} for
## one merge step. Empty array if no merge happened.
## Cascade example: [★1→★2 step, ★2→★3 step].
##
## fresh_ref (2026-04-26): "갓 생성된" 카드를 인자로 전달하면 합성 시 해당 카드의
## 유닛 흡수를 skip하고 survivor 선정에서 후순위로 둠 (3장 → 2장분량 정책).
## 캐스케이드 시 fresh-include step의 survivor도 다음 step에서 fresh로 추적
## (로컬 set 전파). 카드 필드(is_fresh)는 도입하지 않음 — 호출 컨텍스트 한정.
func try_merge(template_id: String, fresh_ref: CardInstance = null) -> Array:
	var steps: Array = []
	# 캐스케이드 fresh 전파용 로컬 set (CardInstance ref들).
	var fresh_set: Array = []
	if fresh_ref != null:
		fresh_set.append(fresh_ref)
	while true:
		var step := _try_merge_once(template_id, fresh_set)
		if step.is_empty():
			break
		steps.append(step)
	return steps


## Perform a single merge step: find lowest ★ group with 3+ copies, merge 3.
## Returns {card, old_star, new_star} or {}.
## fresh_set: 이번 호출의 fresh 카드 ref 모음. 캐스케이드 단계에서 fresh-include시
## 결과 survivor도 fresh_set에 추가하여 다음 단계 전파.
func _try_merge_once(template_id: String, fresh_set: Array = []) -> Dictionary:
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

	# Survivor 선정 3-tier (2026-04-26):
	#   1. 업그레이드 수 max
	#   2. 동률 시 non-fresh 우선 (fresh_set에 없는 카드)
	#   3. 동률 시 iteration 순서 (board leftmost → bench leftmost)
	var survivor_idx := 0
	var max_upg: int = copies[0]["card"].upgrades.size()
	var survivor_is_fresh: bool = copies[0]["card"] in fresh_set
	for ci in range(1, copies.size()):
		var cand: CardInstance = copies[ci]["card"]
		var upg_count: int = cand.upgrades.size()
		var cand_is_fresh: bool = cand in fresh_set
		if upg_count > max_upg:
			max_upg = upg_count
			survivor_idx = ci
			survivor_is_fresh = cand_is_fresh
		elif upg_count == max_upg and survivor_is_fresh and not cand_is_fresh:
			# 업그레이드 동률 + 현 후보 fresh + cand non-fresh → 교체
			survivor_idx = ci
			survivor_is_fresh = false
	# Reorder so survivor is at index 0
	if survivor_idx != 0:
		var tmp = copies[0]
		copies[0] = copies[survivor_idx]
		copies[survivor_idx] = tmp

	var survivor: CardInstance = copies[0]["card"]
	var old_star := survivor.star_level
	# 이번 step에 fresh가 포함됐는지 (캐스케이드 전파용)
	var step_has_fresh: bool = false
	for ci in copies:
		if ci["card"] in fresh_set:
			step_has_fresh = true
			break

	# Absorb donors via CardInstance.absorb_donor (unified policy 2026-04-26).
	# Sum: 유닛/업그레이드/growth_*/tag_growth/upgrade_def·range·ms/shield/theme_state 그룹A
	# Mul: stack mult, upgrade_as_mult
	# Max: tenure, unit_cap_bonus, upgrade_slot_bonus, theme_state["rank"]
	# OR:  is_omni_theme, theme_state 그룹B
	# fresh_ref 정책: donor가 fresh_set이면 유닛 흡수만 skip (그 외 stat은 정상 흡수).
	for i in range(1, 3):
		var donor: CardInstance = copies[i]["card"]
		var skip_units: bool = donor in fresh_set
		survivor.absorb_donor(donor, skip_units)
		# Remove donor from board/bench
		var zone_arr := _get_zone(copies[i]["zone"])
		zone_arr[copies[i]["idx"]] = null

	# 합성 직후 같은 라운드 내 추가 발동을 허용 (플레이어 이득).
	survivor.activations_used = 0

	# Evolve to next star level (threshold_fired는 evolve_star가 false로 리셋)
	survivor.evolve_star()

	# 2026-04-20: 합성 보너스 ×1.30 ATK/HP 제거 (사용자 의도 외 — 업그레이드와 이중 스택으로
	# ★2 쏠림 유발). ★합성의 매력은 카드 효과 강화(★1→★2→★3 effect)만으로 확보.
	# r12_4 이중 합성 보스 보상은 별도 효과 없음 (기획 재검토 필요 시 episodes 기록).

	# OBS-060: 태엽 과급기 ★3 합성 시 1회 보너스 — 에픽 업그레이드 + 3 테라진
	if survivor.get_base_id() == "sp_charger" and survivor.star_level == 3:
		terazin += 3
		survivor.theme_state["pending_epic_upgrade"] = true

	# fresh 전파: 이번 step에 fresh donor가 있었으면 survivor도 fresh_set에 추가
	# → 캐스케이드 다음 step에서 이 survivor가 다시 fresh donor로 처리됨.
	if step_has_fresh and survivor not in fresh_set:
		fresh_set.append(survivor)

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


## 패배 시 플레이어 HP 데미지 = ceil(enemy_survived × 배수).
## 배수: R1=0.2 → R15=1.2 선형 증가, step = 1/14.
## 초반 라운드(방랑상인 등) 의도적 패배 전략 허용, 후반 도박 강하게 처벌.
## 정수 연산으로 float 오차 회피: multiplier = (18 + 10×round_num) / 140.
## enemy_survived ≥ 1 이면 ceil이 자동으로 최소 1 데미지 보장 (공짜 패배 방지).
static func compute_defeat_damage(round_num: int, enemy_survived: int) -> int:
	var numerator: int = enemy_survived * (18 + 10 * round_num)
	var denominator: int = 140
	return (numerator + denominator - 1) / denominator
