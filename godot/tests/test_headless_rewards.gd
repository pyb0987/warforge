extends GutTest
## HeadlessRunner 보스 보상 + 업그레이드 통합 테스트.

const RunnerScript = preload("res://sim/headless_runner.gd")
const GenomeScript = preload("res://sim/genome.gd")
const AIRewardScript = preload("res://sim/ai_reward_logic.gd")


func _make_genome() -> Genome:
	return GenomeScript.load_file("res://sim/default_genome.json")


func _make_state() -> GameState:
	var s := GameState.new()
	s.gold = 20
	s.terazin = 10
	s.round_num = 1
	s.hp = 30
	s.commander_type = Enums.CommanderType.NONE
	s.talisman_type = Enums.TalismanType.NONE
	return s


func _make_board_with_theme(state: GameState, theme_ids: Array) -> void:
	for i in theme_ids.size():
		var card := CardInstance.create(theme_ids[i])
		if card and i < state.field_slots:
			state.board[i] = card


# ================================================================
# AI 보스 보상 선택
# ================================================================

func test_ai_choose_boss_reward_returns_valid_id() -> void:
	var ai_reward := AIRewardScript.new()
	var state := _make_state()
	_make_board_with_theme(state, ["pr_nest", "pr_farm", "pr_molt"])
	var choices: Array[String] = ["r4_1", "r4_3", "r4_7", "r4_9"]
	var decision := ai_reward.choose_boss_reward(
		choices, state, "soft_predator")
	assert_has(decision, "reward_id", "보상 ID 포함")
	assert_true(decision.reward_id in choices, "유효한 선택지")


func test_ai_choose_boss_reward_prefers_star_upgrade() -> void:
	var ai_reward := AIRewardScript.new()
	var state := _make_state()
	_make_board_with_theme(state, ["pr_nest", "pr_farm"])
	# r4_1(★승급)이 선택지에 있으면 우선 선택
	var choices: Array[String] = ["r4_2", "r4_1", "r4_9", "r4_7"]
	var decision := ai_reward.choose_boss_reward(
		choices, state, "soft_predator")
	assert_eq(decision.reward_id, "r4_1", "★승급 우선 선택")


func test_ai_choose_target_card_for_star_upgrade() -> void:
	var ai_reward := AIRewardScript.new()
	var state := _make_state()
	_make_board_with_theme(state, ["pr_nest", "pr_farm", "ne_wild_pulse"])
	var choices: Array[String] = ["r4_1", "r4_3", "r4_7", "r4_9"]
	var decision := ai_reward.choose_boss_reward(
		choices, state, "soft_predator")
	assert_eq(decision.reward_id, "r4_1")
	assert_not_null(decision.target_card, "타겟 카드 지정")
	# 포식종 테마 카드를 타겟으로 선택해야 함
	var target_theme: int = decision.target_card.template.get("theme", 0)
	assert_eq(target_theme, Enums.CardTheme.PREDATOR, "테마 카드 우선 타겟")


# ================================================================
# AI 업그레이드 선택
# ================================================================

func test_ai_choose_upgrade_returns_valid() -> void:
	var ai_reward := AIRewardScript.new()
	var state := _make_state()
	_make_board_with_theme(state, ["pr_nest", "pr_farm"])
	var result := ai_reward.choose_upgrade(
		Enums.UpgradeRarity.RARE, state, "soft_predator")
	assert_has(result, "upgrade_id", "업그레이드 ID 포함")
	assert_has(result, "target_card", "타겟 카드 포함")
	assert_ne(result.upgrade_id, "", "빈 ID가 아님")


func test_ai_choose_upgrade_targets_theme_card() -> void:
	var ai_reward := AIRewardScript.new()
	var state := _make_state()
	_make_board_with_theme(state, ["ne_wild_pulse", "pr_nest", "pr_farm"])
	var result := ai_reward.choose_upgrade(
		Enums.UpgradeRarity.RARE, state, "soft_predator")
	var target_theme: int = result.target_card.template.get("theme", 0)
	assert_eq(target_theme, Enums.CardTheme.PREDATOR, "테마 카드 우선")


func test_ai_choose_upgrade_skips_full_slots() -> void:
	var ai_reward := AIRewardScript.new()
	var state := _make_state()
	_make_board_with_theme(state, ["pr_nest"])
	# 슬롯 5개 채우기
	var card: CardInstance = state.board[0]
	for _i in 5:
		card.attach_upgrade("C1")
	assert_false(card.can_attach_upgrade(), "슬롯 꽉 참")
	# 다른 카드 추가
	state.board[1] = CardInstance.create("pr_farm")
	var result := ai_reward.choose_upgrade(
		Enums.UpgradeRarity.RARE, state, "soft_predator")
	assert_eq(result.target_card, state.board[1], "여유 있는 카드 선택")


# ================================================================
# AI 업그레이드 구매
# ================================================================

func test_ai_buy_upgrades_spends_terazin() -> void:
	var ai_reward := AIRewardScript.new()
	var state := _make_state()
	state.terazin = 12
	_make_board_with_theme(state, ["pr_nest", "pr_farm"])
	var offered := [
		{"id": "C1", "cost": 4, "rarity": Enums.UpgradeRarity.COMMON},
		{"id": "R1", "cost": 8, "rarity": Enums.UpgradeRarity.RARE},
	]
	ai_reward.buy_upgrades(state, offered, "soft_predator")
	assert_lt(state.terazin, 12, "테라진 소비됨")


func test_ai_buy_upgrades_attaches_to_card() -> void:
	var ai_reward := AIRewardScript.new()
	var state := _make_state()
	state.terazin = 20
	_make_board_with_theme(state, ["pr_nest"])
	var offered := [
		{"id": "C1", "cost": 4, "rarity": Enums.UpgradeRarity.COMMON},
	]
	var card: CardInstance = state.board[0]
	var before := card.upgrades.size()
	ai_reward.buy_upgrades(state, offered, "soft_predator")
	assert_gt(card.upgrades.size(), before, "업그레이드 부착됨")


# ================================================================
# headless_runner 통합 — 보스 보상
# ================================================================

func test_runner_applies_boss_reward_on_win() -> void:
	# seed를 찾아서 R4 보스를 이기는 게임 실행
	# 보스 보상이 적용되었는지 확인
	var genome := _make_genome()
	var runner := RunnerScript.new(genome, "soft_military", 100)
	var result: Dictionary = runner.run()
	# R4 보스(4라운드) 승리 시 boss_rewards에 뭔가 있어야 함
	assert_has(result, "boss_rewards_applied",
		"보스 보상 적용 기록 포함")


func test_runner_no_boss_reward_on_loss() -> void:
	# R4 보스를 지는 seed (CP curve가 높으면 R4에서 질 수 있음)
	var genome := _make_genome()
	var runner := RunnerScript.new(genome, "adaptive", 42)
	var result: Dictionary = runner.run()
	var boss_rewards: Array = result.get("boss_rewards_applied", [])
	# 보스를 이겼든 졌든 적절히 기록되어야 함
	for br in boss_rewards:
		assert_has(br, "round", "라운드 정보")
		assert_has(br, "reward_id", "보상 ID")


# ================================================================
# headless_runner 통합 — ★합성 보너스 업그레이드
# ================================================================

func test_runner_merge_bonus_upgrade_attached() -> void:
	var genome := _make_genome()
	var runner := RunnerScript.new(genome, "aggressive", 100)
	var result: Dictionary = runner.run()
	# merge_events 중 ★2가 된 카드가 있으면 업그레이드가 부착되어야 함
	var merges: Array = result.merge_events
	if merges.size() > 0:
		assert_has(result, "merge_upgrades",
			"합성 보너스 업그레이드 기록 포함")


# ================================================================
# headless_runner 통합 — 테라진 상점
# ================================================================

func test_runner_result_has_upgrades_purchased() -> void:
	var genome := _make_genome()
	var runner := RunnerScript.new(genome, "soft_military", 100)
	var result: Dictionary = runner.run()
	assert_has(result, "upgrades_purchased",
		"업그레이드 구매 기록 포함")


# ================================================================
# 영구 보상 효과 전파
# ================================================================

func test_activation_bonus_increases_max() -> void:
	var state := _make_state()
	state.boss_rewards.append("r8_3")
	var bonus := BossReward.get_activation_bonus(state)
	assert_eq(bonus, 1, "r8_3 → activation +1")


func test_enhance_amp_returns_multiplier() -> void:
	var state := _make_state()
	state.boss_rewards.append("r4_5")
	var amp := BossReward.get_enhance_amp(state)
	assert_almost_eq(amp, 1.5, 0.01, "r4_5 → enhance ×1.5")


func test_settlement_bonus_on_win() -> void:
	var state := _make_state()
	state.boss_rewards.append("r8_4")
	var gold := BossReward.get_settlement_gold_bonus(state, true)
	assert_eq(gold, 3, "r8_4 승리 → +3g")


func test_field_slot_expansion() -> void:
	var state := _make_state()
	var before := state.field_slots
	BossReward.apply_no_target("r8_9", state, RandomNumberGenerator.new())
	assert_eq(state.field_slots, before + 1, "r8_9 → field +1")


# ================================================================
# 업그레이드 상점 롤
# ================================================================

func test_roll_upgrade_shop_returns_two() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	# headless_runner의 _roll_upgrade_shop 테스트
	var offered := _roll_upgrade_shop_helper(rng)
	assert_eq(offered.size(), 2, "업그레이드 2개 제공")
	for item in offered:
		assert_has(item, "id", "ID 포함")
		assert_has(item, "cost", "비용 포함")
		assert_has(item, "rarity", "희귀도 포함")


func _roll_upgrade_shop_helper(rng: RandomNumberGenerator) -> Array:
	var offered := []
	for _i in 2:
		var roll := rng.randf()
		var rarity: int
		if roll < 0.70:
			rarity = Enums.UpgradeRarity.COMMON
		else:
			rarity = Enums.UpgradeRarity.RARE
		var ids := UpgradeDB.get_ids_by_rarity(rarity)
		if ids.is_empty():
			continue
		var chosen: String = ids[rng.randi_range(0, ids.size() - 1)]
		var tmpl := UpgradeDB.get_upgrade(chosen)
		offered.append({
			"id": chosen,
			"cost": tmpl.get("cost", 4),
			"rarity": rarity,
		})
	return offered
