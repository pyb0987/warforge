extends Node
## 보스 보상 적용 로직. Autoloaded as "BossReward".
## 참조: docs/design/boss-rewards.md (확정)
##
## Commander/Talisman 패턴: 데이터는 BossRewardDB, 로직은 여기.
## GameState를 직접 수정. UI 계층(팝업, 카드 선택)은 game_manager에서 처리.


# ================================================================
# 쿼리
# ================================================================

func has_reward(state: GameState, id: String) -> bool:
	return id in state.boss_rewards


# ================================================================
# 적용 — 대상 없음
# ================================================================

func apply_no_target(id: String, state: GameState,
		rng: RandomNumberGenerator) -> void:
	match id:
		# --- R4 ---
		"r4_2": _apply_r4_2(state)
		"r4_3", "r4_4", "r4_5", "r4_6":
			_register_permanent(state, id)
		"r4_9": _apply_r4_9(state)
		# --- R8 ---
		"r8_2": _apply_r8_2(state)
		"r8_3", "r8_4", "r8_5", "r8_6":
			_register_permanent(state, id)
		"r8_8": _apply_r8_8(state, rng)
		"r8_9": _apply_r8_9(state)
		# --- R12 ---
		"r12_2": _apply_r12_2(state)
		"r12_3", "r12_4", "r12_5", "r12_6":
			_register_permanent(state, id)
		"r12_9": _apply_r12_9(state)


# ================================================================
# 적용 — 대상 카드 있음
# ================================================================

func apply_with_target(id: String, state: GameState,
		card: CardInstance, rng: RandomNumberGenerator) -> void:
	match id:
		"r4_1": _apply_r4_1(state, card)
		"r4_7": _apply_r4_7(card)
		"r4_8": _apply_r4_8(card, rng)
		"r8_1": _apply_r8_1(card)
		"r8_7": _apply_r8_7(state, card, rng)
		"r12_1": _apply_r12_1(card)
		"r12_7": _apply_r12_7(state, card, rng)
		"r12_8": _apply_r12_8(card)


# ================================================================
# 영구 보상 효과 쿼리 (다른 시스템에서 호출)
# ================================================================

## 발동 상한 보너스: r8_3(+1) + r12_3(+2).
func get_activation_bonus(state: GameState) -> int:
	var bonus := 0
	if has_reward(state, "r8_3"):
		bonus += 1
	if has_reward(state, "r12_3"):
		bonus += 2
	return bonus


## 강화 효과 증폭 배율: r4_5 → ×1.5.
func get_enhance_amp(state: GameState) -> float:
	if has_reward(state, "r4_5"):
		return 1.5
	return 1.0


## 정산 골드 보너스: r8_4 승리 시 +3g.
func get_settlement_gold_bonus(state: GameState, won: bool) -> int:
	if has_reward(state, "r8_4") and won:
		return 3
	return 0


## 정산 테라진 보너스: r8_4 패배 시 +2t.
func get_settlement_terazin_bonus(state: GameState, won: bool) -> int:
	if has_reward(state, "r8_4") and not won:
		return 2
	return 0


## 상점 추가 슬롯: r4_4 → +1.
func get_shop_size_bonus(state: GameState) -> int:
	if has_reward(state, "r4_4"):
		return 1
	return 0


# ================================================================
# 내부 구현 — R4
# ================================================================

## r4_1: ★승급 + 4 테라진
func _apply_r4_1(state: GameState, card: CardInstance) -> void:
	card.evolve_star()
	state.terazin += 4


## r4_2: +10 골드 (상점 T3+ 갱신은 UI 레벨)
func _apply_r4_2(state: GameState) -> void:
	state.gold += 10


## r4_7: ATK +30%, HP +30%
func _apply_r4_7(card: CardInstance) -> void:
	card.multiply_stats(0.30, 0.30)


## r4_8: 유닛 +5기
func _apply_r4_8(card: CardInstance,
		rng: RandomNumberGenerator) -> void:
	for _i in 5:
		card.spawn_random(rng)


## r4_9: 벤치 +2칸
func _apply_r4_9(state: GameState) -> void:
	state.bench.append(null)
	state.bench.append(null)


# ================================================================
# 내부 구현 — R8
# ================================================================

## r8_1: ★승급 (에픽 업그레이드는 game_manager UI에서 처리)
func _apply_r8_1(card: CardInstance) -> void:
	card.evolve_star()


## r8_2: 15골드 + 8 테라진
func _apply_r8_2(state: GameState) -> void:
	state.gold += 15
	state.terazin += 8


## r8_7: 유닛 2배 + 레어 업그레이드 1개 부착
func _apply_r8_7(state: GameState, card: CardInstance,
		rng: RandomNumberGenerator) -> void:
	for s in card.stacks:
		s["count"] *= 2
	var attached: String = _attach_random_upgrade(card, Enums.UpgradeRarity.RARE, rng)
	if attached != "":
		state.upgrade_attached_to_card.emit(
			attached, "boss_reward", card.get_base_id(), _find_board_idx(state, card))


## r8_8: 전체 카드 +3기
func _apply_r8_8(state: GameState,
		rng: RandomNumberGenerator) -> void:
	for card in state.get_active_board():
		for _i in 3:
			card.spawn_random(rng)


## r8_9: 필드 +1칸
func _apply_r8_9(state: GameState) -> void:
	state.field_slots = mini(state.field_slots + 1, Enums.MAX_FIELD_SLOTS)


# ================================================================
# 내부 구현 — R12
# ================================================================

## r12_1: ★승급 (2장은 game_manager에서 2회 호출)
func _apply_r12_1(card: CardInstance) -> void:
	card.evolve_star()


## r12_2: 전체 ATK+20% HP+20% + 15 테라진
func _apply_r12_2(state: GameState) -> void:
	for card in state.get_active_board():
		card.multiply_stats(0.20, 0.20)
	state.terazin += 15


## r12_7: ATK ×2 + 에픽 업그레이드 부착
func _apply_r12_7(state: GameState, card: CardInstance,
		rng: RandomNumberGenerator) -> void:
	card.multiply_stats(1.0, 0.0)
	var attached: String = _attach_random_upgrade(card, Enums.UpgradeRarity.EPIC, rng)
	if attached != "":
		state.upgrade_attached_to_card.emit(
			attached, "boss_reward", card.get_base_id(), _find_board_idx(state, card))


## r12_8: 유닛 3배
func _apply_r12_8(card: CardInstance) -> void:
	for s in card.stacks:
		s["count"] *= 3


## r12_9: 필드+1 + 전체 업글슬롯+1
func _apply_r12_9(state: GameState) -> void:
	state.field_slots = mini(state.field_slots + 1, Enums.MAX_FIELD_SLOTS)
	for card in state.get_active_board():
		card.upgrade_slot_bonus += 1


# ================================================================
# 유틸리티
# ================================================================

func _register_permanent(state: GameState, id: String) -> void:
	if id not in state.boss_rewards:
		state.boss_rewards.append(id)


func _find_board_idx(state: GameState, card: CardInstance) -> int:
	for i in state.board.size():
		if state.board[i] == card:
			return i
	return -1


func _attach_random_upgrade(card: CardInstance, rarity: int,
		rng: RandomNumberGenerator) -> String:
	var ids := UpgradeDB.get_ids_by_rarity(rarity)
	if ids.is_empty():
		return ""
	var chosen: String = ids[rng.randi_range(0, ids.size() - 1)]
	card.attach_upgrade(chosen)
	return chosen
