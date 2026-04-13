extends Node
## 부적 12종 데이터 정의 + 쿼리 메서드. Autoloaded as "Talisman".
## 참조: docs/design/talismans.md (확정)
##
## 패턴: Commander와 동일 — static 데이터 + 순수 함수 쿼리.
## GameState.talisman_type을 읽어 현재 부적에 맞는 값을 반환.

const TT = Enums.TalismanType

# --- 밸런스 파라미터 (talismans.md 확정, 플레이테스트 후 튜닝) ---
const BURST_SACK_EXTRA_SLOTS := 1          # 업그레이드 상점 +1 (2→3)
const WAR_DRUM_ATK_REDUCTION := 0.10       # 적 ATK -10%
const MERCURY_DROP_ENHANCE_BONUS := 0.25   # 강화 효과 +25%
const GLASS_EYE_WEIGHT_MULT := 1.15        # 보유 카드 확률 ×1.15
const TWO_FACED_COIN_DISCOUNT := 0.50      # 할인율 50%
const TWO_FACED_COIN_MARKUP := 0.50        # 할증율 50%
const GOLDEN_DIE_EXTRA_CHOICES := 2        # 보스 선택지 +2
const CRACKED_EGG_EXTRA_SPAWN := 1         # ★2+ 유닛추가 시 +1
const FLINT_FIRST_MULT := 2.0             # 첫 성장 효과량 배율
const CRACKED_SKULL_SURVIVE_HP := 1        # HP 1로 생존
const RUSTY_WRENCH_REFUND_RATE := 0.50     # 분리 시 테라진 50% 환급
const SOUL_JAR_DISTRIBUTE_RATE := 0.50     # 유닛 절반 배분
const COPPER_WIRE_PROPAGATE_RATE := 0.30   # 인접 전파율 30%


# --- 부적 데이터 ---

var _data := {}


func _init() -> void:
	_data = {
		TT.BURST_SACK: {
			"name": "터진 자루",
			"icon": "🎒",
			"desc": "업그레이드 상점 표시 +1개 (2→3).",
		},
		TT.WAR_DRUM: {
			"name": "전쟁 북",
			"icon": "🥁",
			"desc": "전투 시작 시 아군 유닛 수 > 적이면 적 ATK -10%.",
		},
		TT.MERCURY_DROP: {
			"name": "수은 방울",
			"icon": "💧",
			"desc": "강화 효과 발동 시 효과량 +25%.",
		},
		TT.GLASS_EYE: {
			"name": "유리 눈",
			"icon": "👁️",
			"desc": "리롤 시 보유 카드 등장 확률 ×1.15.",
		},
		TT.TWO_FACED_COIN: {
			"name": "양면 동전",
			"icon": "🪙",
			"desc": "상점 카드 중 랜덤 1장 50% 할인, 1장 50% 할증.",
		},
		TT.GOLDEN_DIE: {
			"name": "황금 주사위",
			"icon": "🎲",
			"desc": "보스 보상 선택지 +2 (4→6).",
		},
		TT.CRACKED_EGG: {
			"name": "깨진 알",
			"icon": "🥚",
			"desc": "★2+ 카드의 유닛 추가 시 +1기.",
		},
		TT.FLINT: {
			"name": "부싯돌",
			"icon": "🪨",
			"desc": "매 라운드 첫 성장 이벤트 효과량 ×2.",
		},
		TT.CRACKED_SKULL: {
			"name": "금간 해골",
			"icon": "💀",
			"desc": "각 유닛의 첫 치사 피격을 HP 1로 생존.",
		},
		TT.RUSTY_WRENCH: {
			"name": "녹슨 렌치",
			"icon": "🔧",
			"desc": "업그레이드 분리 가능. 분리 시 테라진 50% 환급.",
		},
		TT.SOUL_JAR: {
			"name": "영혼 항아리",
			"icon": "🏺",
			"desc": "라운드 첫 판매 시 유닛 절반을 전체 카드에 배분.",
		},
		TT.COPPER_WIRE: {
			"name": "구리 전선",
			"icon": "🔌",
			"desc": "풀슬롯 카드의 업그레이드 수치가 인접에 30% 전파.",
		},
	}


## 부적 데이터 조회. 없으면 빈 Dictionary.
func get_data(type: int) -> Dictionary:
	return _data.get(type, {})


# ================================================================
# 초기화
# ================================================================

## talisman_state 초기화 — 라운드 시작 시 호출.
func init_round_state(state: GameState) -> void:
	var ts := state.talisman_state
	match state.talisman_type:
		TT.FLINT:
			ts["first_growth_used"] = false
		TT.SOUL_JAR:
			ts["first_sell_used"] = false


## 런 시작 시 talisman_state 전체 초기화.
func init_run_state(state: GameState) -> void:
	state.talisman_state = {}
	init_round_state(state)


# ================================================================
# 터진 자루 — 업그레이드 상점 슬롯
# ================================================================

## 업그레이드 상점 슬롯 수.
func get_upgrade_shop_slots(state: GameState) -> int:
	if state.talisman_type == TT.BURST_SACK:
		return Enums.UPGRADE_SHOP_SLOTS + BURST_SACK_EXTRA_SLOTS
	return Enums.UPGRADE_SHOP_SLOTS


# ================================================================
# 전쟁 북 — 수적 우위 시 적 ATK 감소
# ================================================================

## 적 ATK 감소 배율 (0.0 or WAR_DRUM_ATK_REDUCTION).
func calc_war_drum_reduction(state: GameState, ally_count: int,
		enemy_count: int) -> float:
	if state.talisman_type != TT.WAR_DRUM:
		return 0.0
	if ally_count > enemy_count:
		return WAR_DRUM_ATK_REDUCTION
	return 0.0


# ================================================================
# 수은 방울 — 강화 효과 보너스
# ================================================================

## 강화 효과 배율. 1.0 = 보너스 없음.
func get_enhance_multiplier(state: GameState) -> float:
	if state.talisman_type == TT.MERCURY_DROP:
		return 1.0 + MERCURY_DROP_ENHANCE_BONUS
	return 1.0


# ================================================================
# 유리 눈 — 보유 카드 확률 가중치
# ================================================================

## 보유 카드 가중치 배율. 1.0 = 보너스 없음.
func get_owned_card_weight_mult(state: GameState) -> float:
	if state.talisman_type == TT.GLASS_EYE:
		return GLASS_EYE_WEIGHT_MULT
	return 1.0


# ================================================================
# 양면 동전 — 할인/할증
# ================================================================

## 상점 6장 중 할인/할증 인덱스 결정. {discount_idx, markup_idx}.
func roll_coin_slots(state: GameState, shop_size: int,
		rng: RandomNumberGenerator) -> Dictionary:
	if state.talisman_type != TT.TWO_FACED_COIN or shop_size < 2:
		return {}
	var discount_idx := rng.randi_range(0, shop_size - 1)
	var markup_idx := discount_idx
	while markup_idx == discount_idx:
		markup_idx = rng.randi_range(0, shop_size - 1)
	return {"discount_idx": discount_idx, "markup_idx": markup_idx}


## 코스트 보정. base_cost에 할인/할증 적용.
func apply_coin_price(base_cost: int, slot_idx: int,
		coin_slots: Dictionary) -> int:
	if coin_slots.is_empty():
		return base_cost
	if slot_idx == coin_slots.get("discount_idx", -1):
		return maxi(int(base_cost * (1.0 - TWO_FACED_COIN_DISCOUNT)), 0)
	if slot_idx == coin_slots.get("markup_idx", -1):
		return int(base_cost * (1.0 + TWO_FACED_COIN_MARKUP))
	return base_cost


# ================================================================
# 황금 주사위 — 보스 선택지 (stub)
# ================================================================

## 보스 보상 선택지 수.
func get_boss_reward_choices(state: GameState) -> int:
	var base := 4
	if state.talisman_type == TT.GOLDEN_DIE:
		return base + GOLDEN_DIE_EXTRA_CHOICES
	return base


# ================================================================
# 깨진 알 — ★2+ 유닛추가 보너스
# ================================================================

## ★2+ 카드의 추가 스폰 수. (card, state 순서 — Callable.bind 호환)
func get_extra_spawn(card: CardInstance, state: GameState) -> int:
	if state.talisman_type != TT.CRACKED_EGG:
		return 0
	if card.star_level >= 2:
		return CRACKED_EGG_EXTRA_SPAWN
	return 0


# ================================================================
# 부싯돌 — 첫 성장 효과 배율
# ================================================================

## 첫 성장 이벤트인지 확인하고, 배율을 반환 (1.0 or FLINT_FIRST_MULT).
## 호출 시 first_growth_used를 true로 설정.
func consume_flint_bonus(state: GameState) -> float:
	if state.talisman_type != TT.FLINT:
		return 1.0
	if state.talisman_state.get("first_growth_used", false):
		return 1.0
	state.talisman_state["first_growth_used"] = true
	return FLINT_FIRST_MULT


# ================================================================
# 금간 해골 — 첫 치사 HP1 생존
# ================================================================

## 금간 해골 활성 여부.
func has_cracked_skull(state: GameState) -> bool:
	return state.talisman_type == TT.CRACKED_SKULL


# ================================================================
# 녹슨 렌치 — 업그레이드 분리
# ================================================================

## 업그레이드 분리 가능 여부.
func can_detach_upgrade(state: GameState) -> bool:
	return state.talisman_type == TT.RUSTY_WRENCH


## 업그레이드 분리 실행. 환급 테라진을 반환.
func detach_upgrade(state: GameState, card: CardInstance,
		upgrade_idx: int) -> int:
	if not can_detach_upgrade(state):
		return 0
	if upgrade_idx < 0 or upgrade_idx >= card.upgrades.size():
		return 0
	var upg: Dictionary = card.upgrades[upgrade_idx]
	var cost: int = upg.get("cost", 0)
	var refund := int(cost * RUSTY_WRENCH_REFUND_RATE)
	# Remove upgrade and reverse stat mods
	card.upgrades.remove_at(upgrade_idx)
	_reverse_stat_mods(card, upg.get("stat_mods", {}))
	state.terazin += refund
	return refund


func _reverse_stat_mods(card: CardInstance, mods: Dictionary) -> void:
	if mods.is_empty():
		return
	var atk_pct: float = mods.get("atk_pct", 0.0)
	var hp_pct: float = mods.get("hp_pct", 0.0)
	if atk_pct != 0.0 or hp_pct != 0.0:
		# Reverse multiplicative: divide by (1 + pct)
		for s in card.stacks:
			if atk_pct != 0.0:
				s["upgrade_atk_mult"] /= (1.0 + atk_pct)
			if hp_pct != 0.0:
				s["upgrade_hp_mult"] /= (1.0 + hp_pct)
	card.upgrade_def -= int(mods.get("def", 0))
	card.upgrade_range -= int(mods.get("range", 0))
	card.upgrade_move_speed -= int(mods.get("move_speed", 0))
	var as_m: float = mods.get("as_mult", 0.0)
	if as_m > 0.0:
		card.upgrade_as_mult /= as_m
	card.stats_changed.emit()


# ================================================================
# 영혼 항아리 — 첫 판매 유닛 배분
# ================================================================

## 첫 판매 시 유닛 배분 처리. 배분된 유닛 수 반환.
func process_soul_jar_sell(state: GameState, sold_card: CardInstance,
		rng: RandomNumberGenerator) -> int:
	if state.talisman_type != TT.SOUL_JAR:
		return 0
	if state.talisman_state.get("first_sell_used", false):
		return 0
	state.talisman_state["first_sell_used"] = true

	var total_units := sold_card.get_total_units()
	var distribute := int(total_units * SOUL_JAR_DISTRIBUTE_RATE)
	if distribute <= 0:
		return 0

	var active := state.get_active_board()
	if active.is_empty():
		return 0

	var per_card := int(ceil(float(distribute) / active.size()))
	var distributed := 0
	for card in active:
		var c: CardInstance = card
		for _i in per_card:
			if distributed >= distribute:
				break
			if c.spawn_random(rng):
				distributed += 1
	return distributed


# ================================================================
# 구리 전선 — 풀슬롯 인접 전파
# ================================================================

## 풀슬롯 카드의 업그레이드 수치를 인접에 전파.
## 전투 전 호출 (process_persistent 시점과 유사).
func apply_copper_wire(state: GameState) -> void:
	if state.talisman_type != TT.COPPER_WIRE:
		return

	var board := state.board
	for i in board.size():
		var card: CardInstance = board[i]
		if card == null:
			continue
		if card.upgrades.size() < card.get_max_upgrade_slots():
			continue
		# 풀슬롯 카드: 인접에 수치 전파
		var total_atk_pct := 0.0
		var total_hp_pct := 0.0
		for upg in card.upgrades:
			var mods: Dictionary = upg.get("stat_mods", {})
			total_atk_pct += mods.get("atk_pct", 0.0)
			total_hp_pct += mods.get("hp_pct", 0.0)
		var prop_atk := total_atk_pct * COPPER_WIRE_PROPAGATE_RATE
		var prop_hp := total_hp_pct * COPPER_WIRE_PROPAGATE_RATE
		if prop_atk == 0.0 and prop_hp == 0.0:
			continue
		# 인접 카드에 temp buff로 적용 (전투 후 클리어됨)
		for offset in [-1, 1]:
			var adj_idx: int = i + offset
			if adj_idx < 0 or adj_idx >= board.size():
				continue
			var adj_card: CardInstance = board[adj_idx]
			if adj_card == null:
				continue
			if prop_atk != 0.0 or prop_hp != 0.0:
				adj_card.temp_mult_buff(
					1.0 + prop_atk if prop_atk != 0.0 else 1.0,
					1.0 + prop_hp if prop_hp != 0.0 else 1.0)
