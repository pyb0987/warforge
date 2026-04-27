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
		"r4_3", "r4_5", "r4_6":
			_register_permanent(state, id)
		"r4_4": _apply_r4_4(state)
		"r4_8": _apply_r4_8(state, rng)
		"r4_9": _apply_r4_9(state)
		# --- R8 ---
		"r8_2": _apply_r8_2(state)
		"r8_3", "r8_4", "r8_5", "r8_6", "r8_8":
			_register_permanent(state, id)
		"r8_9": _apply_r8_9(state)
		# --- R12 ---
		"r12_2": _apply_r12_2(state)
		"r12_3", "r12_4", "r12_5", "r12_6", "r12_8":
			_register_permanent(state, id)
		"r12_9": _apply_r12_9(state)


# ================================================================
# 적용 — 대상 카드 있음
# ================================================================

## step: r12_1 전용. 1 = 첫 호출(★2→★3 강제), 2 = 둘째 호출(★1→★2 강제). 다른 보상 무시.
func apply_with_target(id: String, state: GameState,
		card: CardInstance, rng: RandomNumberGenerator,
		step: int = 1) -> void:
	match id:
		"r4_1": _apply_r4_1(state, card)
		"r4_7": _apply_r4_7(card)
		"r8_1": _apply_r8_1(state, card, rng)
		"r8_7": _apply_r8_7(state, card, rng)
		"r12_1": _apply_r12_1(card, step)
		"r12_7": _apply_r12_7(state, card, rng)


# ================================================================
# 영구 보상 효과 쿼리 (다른 시스템에서 호출)
# ================================================================

## 발동 상한 보너스: r12_3(+1). (r8_3은 효과 변경됨)
func get_activation_bonus(state: GameState) -> int:
	var bonus := 0
	if has_reward(state, "r12_3"):
		bonus += 1
	return bonus


## 강화 효과 증폭 배율: r4_5 → ×1.2.
func get_enhance_amp(state: GameState) -> float:
	if has_reward(state, "r4_5"):
		return 1.2
	return 1.0


## 라운드 시작 시 추가될 무료 리롤 (영구 + 1회성 즉시분 합).
## r4_4: 매 라운드 +1, r4_4 적용 직후 1번만 +5.
## r12_4: 매 라운드 +2.
func consume_round_start_free_rerolls(state: GameState) -> int:
	var bonus := 0
	if has_reward(state, "r4_4"):
		bonus += 1
	if has_reward(state, "r12_4"):
		bonus += 2
	if state.r4_4_initial_rerolls > 0:
		bonus += state.r4_4_initial_rerolls
		state.r4_4_initial_rerolls = 0
	return bonus


## 상점 슬롯 보너스: r12_4 보유 시 +2.
func get_shop_size_bonus(state: GameState) -> int:
	if has_reward(state, "r12_4"):
		return 2
	return 0


## r12_5 오색 군단: 보드의 distinct 테마 개수 (중립 포함, omni-theme = 5테마).
func count_board_themes(state: GameState) -> int:
	var themes_seen: Dictionary = {}
	for card in state.board:
		if card == null:
			continue
		var ci: CardInstance = card
		if ci.is_omni_theme:
			themes_seen[Enums.CardTheme.NEUTRAL] = true
			themes_seen[Enums.CardTheme.STEAMPUNK] = true
			themes_seen[Enums.CardTheme.MILITARY] = true
			themes_seen[Enums.CardTheme.DRUID] = true
			themes_seen[Enums.CardTheme.PREDATOR] = true
		else:
			var t: int = ci.template.get("theme", -1)
			if t >= 0:
				themes_seen[t] = true
	return themes_seen.size()


## r12_8 전사의 영혼: 전투 시작 시 보드 부활 풀 크기 (보유 시 20, 아니면 0).
func get_revive_pool_size(state: GameState) -> int:
	if has_reward(state, "r12_8"):
		return 20
	return 0


## R13 전투 승리 후 r8_9 추가 R12 보상 트리거 여부 + 1회 한정 소비.
func consume_r8_9_bonus(state: GameState) -> bool:
	if not state.r8_9_bonus_pending:
		return false
	state.r8_9_bonus_pending = false
	return true


## DEF 보너스: r8_8 → +2 (전체 카드 적용).
func get_def_bonus(state: GameState) -> int:
	if has_reward(state, "r8_8"):
		return 2
	return 0


## ★ 합성 환급액: r8_3 보유 시 합성 대상 티어 비용 환급.
func get_merge_refund(state: GameState, tier: int) -> int:
	if not has_reward(state, "r8_3"):
		return 0
	# T1=2, T2=3, T3=4, T4=5, T5=6 (card_db.gd:24와 일치)
	var tier_cost := {1: 2, 2: 3, 3: 4, 4: 5, 5: 6}
	return tier_cost.get(tier, 0)


## 이자 cap 우회: r8_4 보유 시 max_interest 무제한.
func is_interest_uncapped(state: GameState) -> bool:
	return has_reward(state, "r8_4")


# ================================================================
# 내부 구현 — R4
# ================================================================

## r4_1: ★승급 + 4 테라진
func _apply_r4_1(state: GameState, card: CardInstance) -> void:
	card.evolve_star()
	state.terazin += 4


## r4_2: +12 골드
func _apply_r4_2(state: GameState) -> void:
	state.gold += 12


## r4_4 상점 확장: 즉시 무료 리롤 5회 + 영구 매 라운드 시작 시 +1회.
## 즉시 5회는 다음 라운드 시작 시 적용 (현재는 SETTLEMENT 단계라 상점 사용 불가).
func _apply_r4_4(state: GameState) -> void:
	_register_permanent(state, "r4_4")
	state.r4_4_initial_rerolls = 5


## r4_7: ATK +30%, HP +30%
func _apply_r4_7(card: CardInstance) -> void:
	card.multiply_stats(0.30, 0.30)


## r4_8: 랜덤 T4 1장 + T3 1장. T4 우선, 벤치 만석 시 못 받음.
func _apply_r4_8(state: GameState,
		rng: RandomNumberGenerator) -> void:
	_grant_random_card_of_tier(state, 4, rng)
	_grant_random_card_of_tier(state, 3, rng)


func _grant_random_card_of_tier(state: GameState, tier: int,
		rng: RandomNumberGenerator) -> void:
	var ids: Array[String] = []
	for cid in CardDB.get_all_ids():
		var tmpl: Dictionary = CardDB.get_template(cid)
		if tmpl.get("tier", 0) == tier:
			ids.append(cid)
	if ids.is_empty():
		return
	var picked: String = ids[rng.randi_range(0, ids.size() - 1)]
	var card := CardInstance.create(picked)
	if card == null:
		return
	state.add_to_bench(card)  # -1 반환 시(만석) 무시


## r4_9: 벤치 +2칸
func _apply_r4_9(state: GameState) -> void:
	state.bench.append(null)
	state.bench.append(null)


# ================================================================
# 내부 구현 — R8
# ================================================================

## r8_1: ★승급 + 레어 업그레이드 1개 부착
func _apply_r8_1(state: GameState, card: CardInstance,
		rng: RandomNumberGenerator) -> void:
	card.evolve_star()
	var attached: String = _attach_random_upgrade(card, Enums.UpgradeRarity.RARE, rng)
	if attached != "":
		state.upgrade_attached_to_card.emit(
			attached, "boss_reward", card.get_base_id(), _find_board_idx(state, card))


## r8_2: 18골드 + 4 테라진
func _apply_r8_2(state: GameState) -> void:
	state.gold += 18
	state.terazin += 4


## r8_7: 에픽 업그레이드 1개 부착
func _apply_r8_7(state: GameState, card: CardInstance,
		rng: RandomNumberGenerator) -> void:
	var epic_id: String = _attach_random_upgrade(card, Enums.UpgradeRarity.EPIC, rng)
	if epic_id != "":
		state.upgrade_attached_to_card.emit(
			epic_id, "boss_reward", card.get_base_id(), _find_board_idx(state, card))


## r8_9 전선 확장: R13 전투 승리 시 R12 보상 풀에서 1개 추가 선택.
func _apply_r8_9(state: GameState) -> void:
	state.r8_9_bonus_pending = true


# ================================================================
# 내부 구현 — R12
# ================================================================

## r12_1: 두 단계 진화. step 1 = ★2 카드만 ★3 승급, step 2 = ★1 카드만 ★2 승급.
## ★1 카드를 한 보상에 ★3까지 못 올리도록 단계별 ★ 등급 강제.
## 잘못된 ★ 카드 또는 step 전달 시 효과 무시.
func _apply_r12_1(card: CardInstance, step: int) -> void:
	if step == 1 and card.star_level == 2:
		card.evolve_star()
	elif step == 2 and card.star_level == 1:
		card.evolve_star()


## r12_2: 전체 카드 ATK +25%, HP +25%
func _apply_r12_2(state: GameState) -> void:
	for card in state.get_active_board():
		card.multiply_stats(0.25, 0.25)


## r12_7: 에픽 + 레어 업그레이드 1개씩 부착
func _apply_r12_7(state: GameState, card: CardInstance,
		rng: RandomNumberGenerator) -> void:
	var epic_id: String = _attach_random_upgrade(card, Enums.UpgradeRarity.EPIC, rng)
	if epic_id != "":
		state.upgrade_attached_to_card.emit(
			epic_id, "boss_reward", card.get_base_id(), _find_board_idx(state, card))
	var rare_id: String = _attach_random_upgrade(card, Enums.UpgradeRarity.RARE, rng)
	if rare_id != "":
		state.upgrade_attached_to_card.emit(
			rare_id, "boss_reward", card.get_base_id(), _find_board_idx(state, card))


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
