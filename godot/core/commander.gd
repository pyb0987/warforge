extends Node
## 커맨더 7종 데이터 정의 + 쿼리 메서드. Autoloaded as "Commander".
## 참조: docs/design/commanders.md (확정)
##
## 패턴: CardDB와 동일 — static 데이터 + 순수 함수 쿼리.
## GameState.commander_type을 읽어 현재 커맨더에 맞는 값을 반환.
##
## TODO: 커맨더 선택 UI (런 시작 전 화면)
## TODO: 전략가 영웅 능력 UI (빌드 페이즈 교환 모드)
## TODO: 단조사 시작 보너스 UI (커먼 업그레이드 3택1)
## TODO: 수집가 시작 상점 T2+ 4장 보장 UI

const CT = Enums.CommanderType

# --- 밸런스 파라미터 (commanders.md 확정, 플레이테스트 후 튜닝) ---
const GAMBLER_REROLL_FREE_CHANCE := 0.5
const GAMBLER_MERGE_REFUND_RATE := 0.5
const GAMBLER_START_GOLD := 3

const BREEDER_UNIT_CAP_BONUS := 20
const BREEDER_START_UNITS := 2
const BREEDER_BONUS_SPAWN_CHANCE := 0.3

const SMITH_UPGRADE_SLOT_BONUS := 1
const SMITH_COMMON_DISCOUNT := 1

const STRATEGIST_FIELD_BONUS := 1
const STRATEGIST_ADJ_RANGE := 2

const COLLECTOR_ATK_PER_TYPE := 0.04
const COLLECTOR_TERAZIN_THRESHOLD := 5

const RAIDER_START_ATK_BONUS := 0.20
const RAIDER_WIN_GOLD := 2
const RAIDER_UPGRADE_INTERVAL := 3

const ALCHEMIST_EPIC_COST := 16
const ALCHEMIST_ROUND_TERAZIN := 1


# --- 커맨더 데이터 ---

var _data := {}


func _init() -> void:
	_data = {
		CT.GAMBLER: {
			"name": "도박꾼",
			"icon": "🎲",
			"desc": "리롤 50% 무료. ★합성 시 구매비용 50% 환급.",
		},
		CT.BREEDER: {
			"name": "양성가",
			"icon": "🌱",
			"desc": "유닛 상한 +20. 유닛 추가 시 30% 확률로 1기 추가 생성.",
		},
		CT.SMITH: {
			"name": "단조사",
			"icon": "⚒️",
			"desc": "업그레이드 슬롯 +1. 커먼 비용 -1t.",
		},
		CT.STRATEGIST: {
			"name": "전략가",
			"icon": "📐",
			"desc": "필드 +1. 인접 범위 2칸. 영웅 능력: 배치 교환 1회.",
		},
		CT.COLLECTOR: {
			"name": "수집가",
			"icon": "📚",
			"desc": "카드 종류당 ATK +4%. 5종+ 시 +1t/라운드.",
		},
		CT.RAIDER: {
			"name": "약탈자",
			"icon": "⚔️",
			"desc": "승리 시 +2g. 3승마다 커먼 업그레이드.",
		},
		CT.ALCHEMIST: {
			"name": "연금술사",
			"icon": "💰",
			"desc": "에픽 업그레이드 상점 등장. 매 라운드 +1t.",
		},
	}


## 커맨더 데이터 조회. 없으면 빈 Dictionary.
func get_data(type: int) -> Dictionary:
	return _data.get(type, {})


# ================================================================
# 시작 보너스
# ================================================================

## 런 시작 시 커맨더별 보너스 적용. game_manager._ready()에서 호출.
## commander_state 초기화 포함 — 키 미존재 방지.
func apply_start_bonus(state: GameState, rng: RandomNumberGenerator) -> void:
	_init_commander_state(state)
	match state.commander_type:
		CT.GAMBLER:
			state.gold += GAMBLER_START_GOLD
		CT.BREEDER:
			_breeder_start(state, rng)
		CT.RAIDER:
			_raider_start(state)


## commander_state 키 초기화 — 모든 커맨더가 사용하는 키를 명시적으로 설정.
func _init_commander_state(state: GameState) -> void:
	var cs := state.commander_state
	# 전략가: 영웅 능력 사용 여부
	if not cs.has("hero_used"):
		cs["hero_used"] = false
	# 약탈자: 승리 누적 카운터
	if not cs.has("win_count"):
		cs["win_count"] = 0


func _breeder_start(state: GameState, rng: RandomNumberGenerator) -> void:
	for card in state.board:
		if card == null:
			continue
		for _i in BREEDER_START_UNITS:
			(card as CardInstance).spawn_random(rng)
	for card in state.bench:
		if card == null:
			continue
		for _i in BREEDER_START_UNITS:
			(card as CardInstance).spawn_random(rng)


func _raider_start(state: GameState) -> void:
	for card in state.board:
		if card == null:
			continue
		(card as CardInstance).multiply_stats(RAIDER_START_ATK_BONUS, 0.0)
	for card in state.bench:
		if card == null:
			continue
		(card as CardInstance).multiply_stats(RAIDER_START_ATK_BONUS, 0.0)


# ================================================================
# 도박꾼 — 리롤 / 합성
# ================================================================

## 리롤이 무료인지 판정. true면 골드 차감 안 함.
func is_reroll_free(state: GameState, rng: RandomNumberGenerator) -> bool:
	if state.commander_type != CT.GAMBLER:
		return false
	return rng.randf() < GAMBLER_REROLL_FREE_CHANCE


## ★합성 환급 골드 계산. merge_result는 GameState.try_merge() 반환값.
func calc_merge_refund(state: GameState, merge_result: Dictionary) -> int:
	if state.commander_type != CT.GAMBLER:
		return 0
	if merge_result.is_empty():
		return 0
	var card: CardInstance = merge_result["card"]
	var cost: int = card.template.get("cost", 0)
	# 합성에 사용된 3장의 구매 비용 합 (동일 카드이므로 cost × 3)
	var total_cost := cost * 3
	return int(total_cost * GAMBLER_MERGE_REFUND_RATE)


# ================================================================
# 양성가 — 유닛 상한 / 보너스 스폰
# ================================================================

## 카드 생성 후 커맨더 보너스 적용. shop 구매, 초기 배치 등에서 호출.
func apply_card_bonuses(state: GameState, card: CardInstance) -> void:
	card.unit_cap_bonus = get_unit_cap_bonus(state)
	card.upgrade_slot_bonus = get_upgrade_slot_bonus(state)


## 유닛 상한 보너스. CardInstance 생성 시 설정.
func get_unit_cap_bonus(state: GameState) -> int:
	if state.commander_type == CT.BREEDER:
		return BREEDER_UNIT_CAP_BONUS
	return 0


## 양성가 보너스 스폰 확률. 0이면 보너스 없음.
func get_bonus_spawn_chance(state: GameState) -> float:
	if state.commander_type == CT.BREEDER:
		return BREEDER_BONUS_SPAWN_CHANCE
	return 0.0


# ================================================================
# 단조사 — 업그레이드 슬롯 / 비용 할인
# ================================================================

func get_upgrade_slot_bonus(state: GameState) -> int:
	if state.commander_type == CT.SMITH:
		return SMITH_UPGRADE_SLOT_BONUS
	return 0


func get_common_upgrade_discount(state: GameState) -> int:
	if state.commander_type == CT.SMITH:
		return SMITH_COMMON_DISCOUNT
	return 0


# ================================================================
# 전략가 — 필드 / 인접 / 영웅 능력
# ================================================================

func get_field_size_bonus(state: GameState) -> int:
	if state.commander_type == CT.STRATEGIST:
		return STRATEGIST_FIELD_BONUS
	return 0


func get_adjacency_range(state: GameState) -> int:
	if state.commander_type == CT.STRATEGIST:
		return STRATEGIST_ADJ_RANGE
	return 1


## 영웅 능력: 보드 위 두 카드 위치 교환 (tenure 유지). 빌드당 1회.
## state.commander_state["hero_used"]로 사용 여부 추적.
func hero_swap(state: GameState, idx_a: int, idx_b: int) -> bool:
	if state.commander_type != CT.STRATEGIST:
		return false
	if state.commander_state.get("hero_used", false):
		return false
	if idx_a < 0 or idx_a >= state.board.size():
		return false
	if idx_b < 0 or idx_b >= state.board.size():
		return false
	if state.board[idx_a] == null or state.board[idx_b] == null:
		return false

	var temp = state.board[idx_a]
	state.board[idx_a] = state.board[idx_b]
	state.board[idx_b] = temp
	state.commander_state["hero_used"] = true
	return true


# ================================================================
# 수집가 — ATK 보너스 / 테라진
# ================================================================

## 필드 위 서로 다른 카드 종류 수.
func _count_unique_types(state: GameState) -> int:
	var seen := {}
	for card in state.board:
		if card == null:
			continue
		var base_id: String = (card as CardInstance).get_base_id()
		seen[base_id] = true
	return seen.size()


## 수집가 ATK 보너스 (전체 아군 temp buff 비율).
func calc_collector_atk_bonus(state: GameState) -> float:
	if state.commander_type != CT.COLLECTOR:
		return 0.0
	return _count_unique_types(state) * COLLECTOR_ATK_PER_TYPE


# ================================================================
# 약탈자 — 승리 골드 / 업그레이드
# ================================================================

## 전투 승리 시 추가 골드.
func calc_battle_win_gold(state: GameState) -> int:
	if state.commander_type == CT.RAIDER:
		return RAIDER_WIN_GOLD
	return 0


## 약탈자 3승 누적 체크. true면 커먼 업그레이드 부여. 카운터 리셋.
func check_raider_upgrade(state: GameState) -> bool:
	if state.commander_type != CT.RAIDER:
		return false
	var wins: int = state.commander_state.get("win_count", 0)
	if wins >= RAIDER_UPGRADE_INTERVAL:
		state.commander_state["win_count"] = 0
		return true
	return false


# ================================================================
# 연금술사 — 테라진 / 에픽 상점
# ================================================================

## 에픽 업그레이드 상점 등장 가능 여부.
func can_shop_epic(state: GameState) -> bool:
	return state.commander_type == CT.ALCHEMIST


# ================================================================
# 정산 — 커맨더별 추가 테라진
# ================================================================

## 정산 시 추가 테라진 (수집가 5종+, 연금술사 매라운드).
func calc_settlement_terazin(state: GameState) -> int:
	match state.commander_type:
		CT.COLLECTOR:
			if _count_unique_types(state) >= COLLECTOR_TERAZIN_THRESHOLD:
				return 1
			return 0
		CT.ALCHEMIST:
			return ALCHEMIST_ROUND_TERAZIN
	return 0
