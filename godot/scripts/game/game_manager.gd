extends Node
## Game Manager — Phase FSM. BUILD → CHAIN → BATTLE → SETTLEMENT.

const MetaProgressScript = preload("res://core/meta_progress.gd")

enum Phase { INIT, BUILD, CHAIN, BATTLE, SETTLEMENT }

var current_phase: Phase = Phase.INIT
var game_state: GameState
var chain_engine: ChainEngine
var _battle_rng: RandomNumberGenerator
var _genome: Genome = null
var _logger: PlayLogger = null
var _last_battle_won: bool = false
var _gold_before_effects: int = 0  # Snapshot for interest calc (OBS-032)
var _card_effect_gold: int = 0  # POST_COMBAT card gold for settlement log (OBS-018)
var _unit_card_map: Array[int] = []  # combat unit idx → board card idx
var _pending_boss_reward: Dictionary = {}  # {reward_id, needs_target, targets_remaining}
var _boss_reward_targets: Array = []  # field_idx list for logging
var _pending_council_bonus: bool = false  # ne_council 임계 도달 flag
var _game_over: bool = false
var _smith_start_upgrade_pending: bool = false
var _meta_progress = null
var _run_result_recorded: bool = false
var _run_stats: Dictionary = {}
var _current_win_streak: int = 0
var _last_ally_count: int = 0
var _last_enemy_count: int = 0

@onready var build_phase: Control = $BuildPhase
@onready var chain_visual: Control = $ChainVisual
@onready var battle_phase: Node2D = $BattlePhase
@onready var run_start_screen: ColorRect = $UILayer/RunStartScreen
@onready var battle_result_popup: ColorRect = $UILayer/BattleResultPopup
@onready var game_over_popup: ColorRect = $UILayer/GameOverPopup
@onready var upgrade_choice_popup: ColorRect = $UILayer/UpgradeChoicePopup
@onready var boss_reward_popup: ColorRect = $UILayer/BossRewardPopup
@onready var theme_choice_popup: ColorRect = $UILayer/ThemeChoicePopup
@onready var commander_select_popup: ColorRect = $UILayer/CommanderSelectPopup
@onready var talisman_select_popup: ColorRect = $UILayer/TalismanSelectPopup


func _ready() -> void:
	print("[GameManager] Warforge started.")
	print("[GameManager] Units: %d, Cards: %d" % [
		UnitDB.get_all_ids().size(), CardDB.get_all_ids().size()])

	# Load tuned genome (single source of truth shared with sim).
	# Falls back to defaults if best_genome.json is missing.
	_genome = Genome.load_file("res://sim/best_genome.json")
	if _genome == null:
		print("[GameManager] best_genome.json not found — using defaults")
		_genome = Genome.create_default()
	else:
		print("[GameManager] Loaded best_genome.json")

	_meta_progress = MetaProgressScript.new()
	_meta_progress.load_or_create()

	game_state = GameState.new()
	game_state.difficulty = _meta_progress.selected_difficulty
	_reset_run_stats()
	# Apply genome economy/starting state (mirrors headless_runner).
	_apply_starting_difficulty_state()
	game_state.terazin = _genome.get_starting_terazin()
	game_state.levelup_current_cost = _genome.get_levelup_cost(2)
	game_state.max_interest = int(_genome.economy.get("max_interest", Enums.MAX_INTEREST))
	game_state.interest_per_5g = int(_genome.economy.get("interest_per_5g", Enums.INTEREST_PER_5G))
	# 카드 풀 고갈 메커니즘 (OBS-049)
	game_state.card_pool = CardPool.new()
	game_state.card_pool.init_pool()

	chain_engine = ChainEngine.new()
	var _session_seed: int = randi()
	chain_engine.set_seed(_session_seed)
	chain_engine.propagate_card_effects(_genome.card_effects)
	_battle_rng = RandomNumberGenerator.new()
	_battle_rng.seed = _session_seed

	_setup_test_board()

	build_phase.visible = false
	chain_visual.visible = false
	battle_phase.stop()

	run_start_screen.show_progress(_meta_progress)
	var show_in_run_tutorial: bool = _meta_progress.should_show_tutorial()
	await run_start_screen.start_requested
	run_start_screen.hide_screen()
	game_state.difficulty = _meta_progress.selected_difficulty
	_apply_starting_difficulty_state()
	_meta_progress.mark_tutorial_seen()
	_meta_progress.record_run_started()
	_meta_progress.save()
	print("[Difficulty] Selected D%d" % game_state.difficulty)

	commander_select_popup.show_choices(_meta_progress.get_unlocked_commanders())
	var selected_commander: int = await commander_select_popup.commander_selected
	game_state.commander_type = selected_commander
	var commander_data: Dictionary = Commander.get_data(selected_commander)
	print("[Commander] Selected: %s" % commander_data.get("name", selected_commander))
	_smith_start_upgrade_pending = selected_commander == Enums.CommanderType.SMITH
	talisman_select_popup.show_choices(_meta_progress.get_unlocked_talismans())
	var selected_talisman: int = await talisman_select_popup.talisman_selected
	game_state.talisman_type = selected_talisman
	var talisman_data: Dictionary = Talisman.get_data(selected_talisman)
	print("[Talisman] Selected: %s" % talisman_data.get("name", selected_talisman))
	Talisman.init_run_state(game_state)
	_update_run_stats_snapshot()

	# Apply commander modifiers to chain engine
	chain_engine.adjacency_range = Commander.get_adjacency_range(game_state)
	chain_engine.bonus_spawn_chance = Commander.get_bonus_spawn_chance(game_state)
	chain_engine.propagate_bonus_spawn()

	# 📐 전략가: 필드 크기 +1
	var field_bonus: int = Commander.get_field_size_bonus(game_state)
	if field_bonus > 0:
		game_state.field_slots = mini(game_state.field_slots + field_bonus, Enums.MAX_FIELD_SLOTS)
		print("[Commander] 전략가 필드 +%d → %d슬롯" % [field_bonus, game_state.field_slots])

	# Apply commander start bonus
	Commander.apply_start_bonus(game_state, _battle_rng)

	# Apply talisman modifiers to chain engine
	chain_engine.enhance_multiplier = Talisman.get_enhance_multiplier(game_state)
	chain_engine.flint_callback = Callable(Talisman, "consume_flint_bonus").bind(game_state)
	chain_engine.cracked_egg_callback = Callable(Talisman, "get_extra_spawn").bind(game_state)
	chain_engine.pending_free_reroll_callback = Callable(self, "_grant_pending_free_rerolls")

	# Play session logger (auto-records state, user adds notes manually).
	_logger = PlayLogger.new()
	_logger.start_session(_session_seed)
	game_state.card_moved.connect(_on_state_card_moved)
	game_state.upgrade_purchased.connect(_on_upgrade_purchased_logged)
	game_state.upgrade_refunded.connect(_on_upgrade_refunded_logged)
	game_state.upgrade_attached_to_card.connect(_on_upgrade_attached_logged)
	# Reactive evaluators: 보드 구성 변경 시 파생 상태 재계산.
	# 단일 진입점으로 두어 향후 다른 PERSISTENT 카드도 같은 hook 에 묶을 수 있음 (P5 패턴 B).
	game_state.board_changed.connect(_on_board_changed)

	upgrade_choice_popup.setup(_battle_rng)
	theme_choice_popup.setup(_battle_rng)
	build_phase.setup(game_state, _battle_rng, _genome)
	build_phase.set_tutorial_enabled(show_in_run_tutorial)
	build_phase.tutorial_dismissed.connect(_on_build_tutorial_dismissed)
	build_phase.shop.card_purchased.connect(_on_shop_purchase)
	build_phase.set_upgrade_choice_popup(upgrade_choice_popup)
	build_phase.build_confirmed.connect(_on_build_confirmed)
	build_phase.sell_performed.connect(_on_sell_performed)
	build_phase.merge_performed.connect(_on_merge_performed)
	build_phase.upgrade_rerolled.connect(_on_upgrade_rerolled)
	chain_visual.setup(build_phase._field_visuals)
	chain_visual.connect_engine(chain_engine)
	battle_phase.battle_finished.connect(_on_battle_finished)
	game_over_popup.restart_requested.connect(_on_restart)
	boss_reward_popup.reward_selected.connect(_on_boss_reward_selected)

	_enter_phase(Phase.BUILD)


func _setup_test_board() -> void:
	game_state.round_num = 1


func _reset_run_stats() -> void:
	_current_win_streak = 0
	_last_ally_count = 0
	_last_enemy_count = 0
	_run_stats = {
		"max_field_units": 0,
		"max_attached_upgrades": 0,
		"max_unique_field_cards": 0,
		"best_win_streak": 0,
		"cards_sold": 0,
		"growth_events": 0,
		"max_star2_cards": 0,
		"unit_advantage_win": false,
	}


func _update_run_stats_snapshot() -> void:
	if game_state == null or _run_stats.is_empty():
		return
	var field_units := 0
	var unique_field_cards: Dictionary = {}
	for card in game_state.get_active_board():
		var ci: CardInstance = card
		field_units += ci.get_total_units()
		unique_field_cards[ci.get_base_id()] = true
	_run_stats["max_field_units"] = maxi(
		int(_run_stats.get("max_field_units", 0)), field_units)
	_run_stats["max_unique_field_cards"] = maxi(
		int(_run_stats.get("max_unique_field_cards", 0)), unique_field_cards.size())
	_run_stats["max_attached_upgrades"] = maxi(
		int(_run_stats.get("max_attached_upgrades", 0)), _count_attached_upgrades())
	_run_stats["max_star2_cards"] = maxi(
		int(_run_stats.get("max_star2_cards", 0)), _count_star2_cards())


func _count_attached_upgrades() -> int:
	var total := 0
	for card in _get_all_player_cards():
		var ci: CardInstance = card
		total += ci.upgrades.size()
	return total


func _count_star2_cards() -> int:
	var total := 0
	for card in _get_all_player_cards():
		var ci: CardInstance = card
		if ci.star_level >= 2:
			total += 1
	return total


func _get_all_player_cards() -> Array:
	var cards: Array = []
	if game_state == null:
		return cards
	for card in game_state.board:
		if card != null:
			cards.append(card)
	for card in game_state.bench:
		if card != null:
			cards.append(card)
	return cards


func _apply_starting_difficulty_state() -> void:
	var difficulty := Difficulty.clamp_difficulty(game_state.difficulty)
	game_state.difficulty = difficulty
	game_state.gold = Difficulty.get_starting_gold(_genome.get_starting_gold(), difficulty)
	game_state.hp = Difficulty.get_player_hp(30, difficulty)


func _enter_phase(phase: Phase) -> void:
	if _game_over:
		return
	current_phase = phase
	match phase:
		Phase.BUILD:
			build_phase.visible = true
			battle_phase.stop()
			chain_visual.clear_links()
			build_phase.refresh_shop()
			# 전략가 영웅 능력 리셋 (빌드당 1회)
			game_state.commander_state["hero_used"] = false
			# 부적 라운드 상태 리셋
			Talisman.init_round_state(game_state)
			# 🔄 자동 징집 (r4_6): 매 라운드 전체 +1기
			if BossReward.has_reward(game_state, "r4_6"):
				for card in game_state.get_active_board():
					(card as CardInstance).spawn_random(_battle_rng)
				print("[BossReward] 자동 징집: 전체 +1기")
			# ne_council (오대 평의회): 5테마 모두 보드에 존재 시 field_slots +1 동적
			_evaluate_council_field_bonus()
			# ne_council ★2/★3: 5테마 활성 시 council_counter +1, 임계 도달 시 1회 에픽 부여
			_evaluate_council_epic_grant()
			_update_run_stats_snapshot()
			print("[Phase] BUILD — R%d | Gold:%d" % [game_state.round_num, game_state.gold])
			if _logger:
				_logger.log_round_start(game_state, build_phase.get_shop_offered())
		Phase.CHAIN:
			_run_chain()
		Phase.BATTLE:
			_run_battle()
		Phase.SETTLEMENT:
			_run_settlement()


func _grant_pending_free_rerolls(n: int) -> void:
	game_state.pending_free_rerolls += n


func _on_build_tutorial_dismissed() -> void:
	if _meta_progress == null:
		return
	_meta_progress.mark_tutorial_seen()
	_meta_progress.save()


## board_changed 단일 hook — PERSISTENT 효과들의 reactive 재평가 진입점.
## 현재: ne_council 5테마 보너스 + 에픽 부여 임계 평가.
## 향후 PERSISTENT 카드 추가 시 여기에 평가 호출만 추가.
func _on_board_changed() -> void:
	_update_run_stats_snapshot()
	if current_phase != Phase.BUILD:
		return
	_evaluate_council_field_bonus()
	_evaluate_council_epic_grant()


## 전당포(ne_pawnbroker): REROLL 결과의 levelup_discount 누적치 적용. 0이면 no-op.
func _apply_reroll_levelup_discount(reroll_result: Dictionary) -> void:
	var amount: int = int(reroll_result.get("levelup_discount", 0))
	if amount > 0:
		game_state.apply_levelup_discount(amount)


## ne_council (오대 평의회) PERSISTENT 효과 평가:
## 보드에 5테마(NEUTRAL+STEAMPUNK+MILITARY+DRUID+PREDATOR) 모두 존재하고
## ne_council 도 보드에 있으면 field_slots +1 활성. 조건 깨지면 비활성.
## 보스 보상 등 다른 보너스와 직교 (active 상태 토글로만 ±1).
func _evaluate_council_field_bonus() -> void:
	var has_council := false
	var themes_seen: Dictionary = {}
	for card in game_state.board:
		if card == null:
			continue
		var ci: CardInstance = card
		# omni-theme 카드는 5테마 모두에 매치 — 단독으로 5테마 조건 충족
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
		if ci.get_base_id() == "ne_council":
			has_council = true
	var should_be_active := has_council and themes_seen.size() >= 5
	if should_be_active and not game_state.council_field_bonus_active:
		game_state.field_slots = mini(game_state.field_slots + 1, Enums.MAX_FIELD_SLOTS)
		game_state.council_field_bonus_active = true
		print("[ne_council] 5테마 활성 — field_slots +1 → %d" % game_state.field_slots)
	elif (not should_be_active) and game_state.council_field_bonus_active:
		game_state.field_slots = maxi(game_state.field_slots - 1, 0)
		game_state.council_field_bonus_active = false
		print("[ne_council] 5테마 깨짐 — field_slots -1 → %d" % game_state.field_slots)


## ne_council ★2/★3: 5테마 활성 + ne_council 보드 보유 시 council_counter +1 누적.
## 임계 도달 (★2=5, ★3=3) → 임계만큼 차감 + 에픽 부여 (반복 가능, 매번 5/3 차감).
func _evaluate_council_epic_grant() -> void:
	if not game_state.council_field_bonus_active:
		return
	# 보드의 ne_council ★ 등급 확인 (가장 높은 ★ 사용)
	var council_star := 0
	for card in game_state.board:
		if card == null:
			continue
		var ci: CardInstance = card
		if ci.get_base_id() == "ne_council":
			council_star = maxi(council_star, ci.star_level)
	if council_star < 2:
		return  # ★1은 카운터 없음
	game_state.council_counter += 1
	var threshold: int = 5 if council_star == 2 else 3
	# 보드 ne_council 카드에 카운터 mirror (tooltip 표시용)
	_mirror_council_counter()
	print("[ne_council] 카운터 %d/%d (★%d)" % [
		game_state.council_counter, threshold, council_star])
	if game_state.council_counter >= threshold:
		game_state.council_counter -= threshold  # 임계만큼 차감 (반복 가능)
		_mirror_council_counter()
		print("[ne_council] 임계 도달 — 카운터 -%d, 에픽 업글 부여 trigger" % threshold)
		_pending_council_bonus = true
		# build_phase 진입 직전 popup. 단순화: 현재 turn에서 보드 카드 자동 선택 + 3택1 popup.
		call_deferred("_show_council_epic_choice")


## 보드 ne_council 카드의 theme_state에 카운터 동기화 (tooltip용).
func _mirror_council_counter() -> void:
	for card in game_state.board:
		if card == null:
			continue
		var ci: CardInstance = card
		if ci.get_base_id() == "ne_council":
			ci.theme_state["council_counter"] = game_state.council_counter


func _show_council_epic_choice() -> void:
	# 보드 카드 1장 선택 — 단순화: 가장 높은 CP 카드 자동 선택 (UI 단순화)
	var best_card: CardInstance = null
	var best_cp: float = -1.0
	for card in game_state.board:
		if card == null:
			continue
		var ci: CardInstance = card
		var cp: float = ci.get_total_cp()
		if cp > best_cp:
			best_cp = cp
			best_card = ci
	if best_card == null:
		_pending_council_bonus = false
		return
	# 에픽 업글 3택1 popup
	upgrade_choice_popup.show_choices(Enums.UpgradeRarity.EPIC)
	var chosen_id: String = await upgrade_choice_popup.upgrade_chosen
	if chosen_id != "" and best_card.can_attach_upgrade():
		best_card.attach_upgrade(chosen_id)
		game_state.upgrade_attached_to_card.emit(
			chosen_id, "ne_council", best_card.get_base_id(),
			_find_board_idx(best_card))
		print("[ne_council] 에픽 %s → %s 부착" % [chosen_id, best_card.get_base_id()])
	_pending_council_bonus = false
	game_state.state_changed.emit()


func _find_board_idx(card: CardInstance) -> int:
	for i in game_state.board.size():
		if game_state.board[i] == card:
			return i
	return -1


func _run_chain() -> void:
	chain_visual.clear_links()

	# 무료 리롤은 이번 라운드 한정: 체인 시작(새 라운드) 시점에 리셋.
	# 이후 RS 카드(예: 폐품 상회)가 재충전.
	game_state.pending_free_rerolls = 0
	game_state.round_rerolls = 0
	# r4_4 상점 확장 + r12_4 상점 대확장: 영구 매턴 리롤 + r4_4 즉시 5회분 가산.
	game_state.pending_free_rerolls += BossReward.consume_round_start_free_rerolls(game_state)

	# r12_5 오색 군단: 보드 distinct 테마 개수 × ATK/HP +10% (매 라운드 갱신).
	# temp_mult_buff: 전투 종료 시 자동 리셋 → 다음 라운드 시작 시 재계산.
	if BossReward.has_reward(game_state, "r12_5"):
		var theme_count: int = BossReward.count_board_themes(game_state)
		if theme_count > 0:
			var mult: float = 1.0 + 0.10 * theme_count
			for card in game_state.get_active_board():
				(card as CardInstance).temp_mult_buff(mult, mult)

	# OBS-032: Snapshot gold before card effects — interest uses this, not post-effect gold.
	_gold_before_effects = game_state.gold

	var active_board := game_state.get_active_board()
	if active_board.is_empty():
		_update_run_stats_snapshot()
		_enter_phase(Phase.BATTLE)
		return

	chain_visual.update_board_map(game_state.board)
	var result := chain_engine.run_growth_chain(active_board, true)
	print("[Chain] count=%d gold=%d" % [result["chain_count"], result["gold_earned"]])
	_run_stats["growth_events"] = int(_run_stats.get("growth_events", 0)) \
		+ int(result.get("chain_count", 0))

	game_state.gold += result["gold_earned"]
	game_state.terazin += result["terazin_earned"]
	_update_run_stats_snapshot()

	game_state.state_changed.emit()

	# Deferred conscription UI 제거 (2026-04-21): ml_conscript self 징집이
	# 3택1 팝업이었으나 실전에서 UI 트리거 안 되던 상태 (dead feature).
	# 자동 랜덤 징집으로 전환 — military_system._outpost() 가 인라인 처리.

	build_phase.visible = true
	await get_tree().create_timer(1.0).timeout
	_enter_phase(Phase.BATTLE)


func _run_battle() -> void:
	build_phase.visible = false
	chain_visual.visible = false

	# Apply PERSISTENT effects (range_bonus, ATK buffs) then BATTLE_START
	chain_engine.process_persistent(game_state.get_active_board())
	_apply_battle_start_effects()

	# 🔄 물량의 법칙 (r12_6): 50기+ 카드 → ATK ×1.4, AS ×1.2 (전투 한정 buff)
	if BossReward.has_reward(game_state, "r12_6"):
		for card in game_state.get_active_board():
			var c: CardInstance = card
			if c.get_total_units() >= 50:
				c.temp_mult_buff(1.4)
				# AS ×1.2 = 공격속도 20% 증가 → AS 값 ×(1/1.2). temp_as_mult는 clear_temp_buffs로 리셋.
				c.temp_as_mult *= (1.0 / 1.2)

	# 📚 수집가: 유니크 카드 종류 × ATK +4% (temp buff)
	var collector_bonus: float = Commander.calc_collector_atk_bonus(game_state)
	if collector_bonus > 0.0:
		for card in game_state.get_active_board():
			(card as CardInstance).temp_mult_buff(1.0 + collector_bonus)
		print("[Commander] 수집가 ATK +%.0f%%" % (collector_bonus * 100))

	var ally_data := _materialize_army()
	var enemy_data: Array = EnemyDB.generate(
		game_state.round_num, _battle_rng, _genome, game_state.difficulty)
	_last_ally_count = ally_data.size()
	_last_enemy_count = enemy_data.size()

	if ally_data.is_empty():
		print("[Battle] No allies, auto-loss")
		_on_battle_finished({"player_won": false, "ally_survived": 0, "enemy_survived": enemy_data.size()})
		return

	# 🥁 전쟁 북: 아군 수적 우위 시 적 ATK -10%
	var drum_reduction: float = Talisman.calc_war_drum_reduction(
		game_state, ally_data.size(), enemy_data.size())
	if drum_reduction > 0.0:
		for e in enemy_data:
			e["atk"] *= (1.0 - drum_reduction)
		print("[Talisman] 전쟁 북: 적 ATK -%.0f%%" % (drum_reduction * 100))

	# 🔌 구리 전선: 풀슬롯 카드 업그레이드 인접 전파
	Talisman.apply_copper_wire(game_state)

	print("[Battle] R%d: %d allies vs %d enemies" % [game_state.round_num, ally_data.size(), enemy_data.size()])
	battle_phase.start_battle(ally_data, enemy_data)

	# r12_8 전사의 영혼: 보드 부활 풀 (아군 첫 사망 N기 100% HP 부활)
	var revive_pool: int = BossReward.get_revive_pool_size(game_state)
	if revive_pool > 0:
		var rp_engine = battle_phase.get_engine()
		if rp_engine != null:
			rp_engine.board_revive_pool = revive_pool

	# 💀 금간 해골: 아군 유닛에 undying 설정
	if Talisman.has_cracked_skull(game_state):
		var engine = battle_phase.get_engine()
		if engine != null:
			for i in engine.count:
				if engine.team[i] == 1 and engine.alive[i] == 1:
					engine.undying[i] = 1

	# Connect combat events → chain_engine for combat chain
	var engine = battle_phase.get_engine()
	if engine != null:
		if not engine.unit_attacked.is_connected(_on_combat_attack):
			engine.unit_attacked.connect(_on_combat_attack)
		if not engine.unit_died.is_connected(_on_combat_death):
			engine.unit_died.connect(_on_combat_death)


## Apply BATTLE_START card effects: delegate to chain_engine.process_battle_start().
func _apply_battle_start_effects() -> void:
	var result := chain_engine.process_battle_start(game_state.get_active_board())
	game_state.gold += result["gold"]
	game_state.terazin += result["terazin"]


## Convert board CardInstances into flat unit arrays for combat engine.
## Also builds _unit_card_map for combat→chain bridge.
func _materialize_army() -> Array:
	var units: Array = []
	_unit_card_map.clear()
	var active := game_state.get_active_board()
	# 군대 통합사령부 revive scope 계산:
	# MilitarySystem.resolve_command_revive가 YAML base revive + r_conditional
	# revive_scope_override.target을 직접 평가한다. rank 조건부 분기도 YAML에
	# 선언된 target 문자열을 그대로 사용하므로, 설계자가 YAML target을 변경하면
	# 코드 수정 없이 동작이 따라온다 (trace 014, fragile drift 제거).
	# theme_state 경유 없음 — apply_persistent 경로가 RS timing이라 호출되지
	# 않았던 이전 버그는 2026-04-16 (trace 012)에 수정됨.
	var revive_scope_map: Dictionary = {}
	var mil_sys: MilitarySystem = (
		chain_engine._theme_systems[Enums.CardTheme.MILITARY])
	for ci in range(active.size()):
		var cmd_card: CardInstance = active[ci]
		if cmd_card.get_base_id() != "ml_command":
			continue
		var revive_cfg: Dictionary = mil_sys.resolve_command_revive(cmd_card)
		if revive_cfg["hp_pct"] <= 0 or revive_cfg["limit"] <= 0:
			continue
		if String(revive_cfg["target"]) == "":
			continue  # YAML에 target 선언 없음 → revive 미동작
		var scope: Dictionary = mil_sys.resolve_revive_scope(
			revive_cfg["target"], ci, active.size())
		for target_ci in scope["card_indices"]:
			revive_scope_map[target_ci] = {
				"hp_pct": revive_cfg["hp_pct"],
				"limit": revive_cfg["limit"],
				"only_enhanced": scope["only_enhanced"],
			}
	var card_idx := -1
	for card in active:
		card_idx += 1
		var c: CardInstance = card
		var card_mechanics := c.get_all_mechanics()
		var atk_stack_pct: float = c.theme_state.get("attack_stack_pct", 0.0)
		# 증기 이자기 ★2/★3: 리롤 횟수 × ATK 버프 (최대 5회분)
		var reroll_buff_mult := 1.0
		if c.get_base_id() == "sp_interest" and c.star_level >= 2:
			var rerolls := mini(game_state.round_rerolls, 5)
			var buff_pct: float = 0.05 if c.star_level == 2 else 0.08
			reroll_buff_mult = 1.0 + buff_pct * rerolls
		# 군대 돌격편대 R10 lifesteal: _apply_lifesteal이 BS에서
		# theme_state["lifesteal_pct"]에 저장 → 여기서 mechanic으로 주입.
		var lifesteal_pct: float = c.theme_state.get("lifesteal_pct", 0.0)
		# 군대 특수작전대 ★/R crit: _apply_crit_buff/_apply_crit_splash가
		# theme_state["crit_chance"/"crit_mult"/"crit_splash_pct"]에 저장.
		var crit_chance: float = c.theme_state.get("crit_chance", 0.0)
		var crit_mult: float = c.theme_state.get("crit_mult", 2.0)
		var crit_splash_pct: float = c.theme_state.get("crit_splash_pct", 0.0)
		# 군대 전술사령부 R10: theme_state["as_bonus"]가 attack_speed에 %로 반영.
		var as_bonus: float = c.theme_state.get("as_bonus", 0.0)
		for s in c.stacks:
			var ut: Dictionary = s["unit_type"]
			var eff_atk := c.eff_atk_for(s)
			var eff_hp := c.eff_hp_for(s)
			# ★3 전쟁 기계: #firearm 유닛에 attack_stack mechanic 부여
			var unit_mechs: Array = card_mechanics.duplicate()
			if atk_stack_pct > 0.0:
				var ut_tags: PackedStringArray = ut.get("tags", PackedStringArray())
				if "firearm" in ut_tags:
					unit_mechs = unit_mechs.duplicate()
					unit_mechs.append({"type": "attack_stack", "atk_pct": atk_stack_pct})
			if lifesteal_pct > 0.0:
				unit_mechs = unit_mechs.duplicate()
				unit_mechs.append({"type": "lifesteal", "steal_pct": lifesteal_pct})
			if crit_chance > 0.0:
				unit_mechs = unit_mechs.duplicate()
				var crit_mech: Dictionary = {"type": "critical", "crit_chance": crit_chance, "crit_mult": crit_mult}
				if crit_splash_pct > 0.0:
					crit_mech["splash_pct"] = crit_splash_pct
				unit_mechs.append(crit_mech)
			# as_bonus (전술사령부 R10): attack_speed *= (1 + as_bonus).
			# 수치가 1.0 증가하면 AS 2배가 아닌 (1 + 0.15) = 1.15배. 기존 SC1 스타일 유지.
			# temp_as_mult: 전투 한정 AS modifier (ne_void_force ★3 등). clear_temp_buffs 리셋.
			var as_mult_total: float = c.upgrade_as_mult * c.unique_as_mult * c.temp_as_mult * (1.0 + as_bonus)
			# 군대 revive: 이 카드가 통합사령부 scope에 속하면 revive 필드 주입.
			var revive_info: Dictionary = revive_scope_map.get(card_idx, {})
			var revive_limit_val: int = 0
			var revive_hp_pct_val: float = 0.0
			if not revive_info.is_empty():
				var ut_tags: PackedStringArray = ut.get("tags", PackedStringArray())
				var is_enhanced: bool = "enhanced" in ut_tags
				if not revive_info["only_enhanced"] or is_enhanced:
					revive_limit_val = int(revive_info["limit"])
					revive_hp_pct_val = float(revive_info["hp_pct"])
			for _n in s["count"]:
				units.append({
					"atk": eff_atk * reroll_buff_mult,
					"hp": eff_hp,
					"attack_speed": ut["attack_speed"] * as_mult_total,
					"range": ut["range"] + c.upgrade_range + c.theme_state.get("range_bonus", 0),
					"move_speed": ut["move_speed"] + c.upgrade_move_speed + int(c.theme_state.get("ms_bonus", 0)),
					"def": c.upgrade_def + BossReward.get_def_bonus(game_state),
					"mechanics": unit_mechs,
					"radius": 6.0,
					"revive_limit": revive_limit_val,
					"revive_hp_pct": revive_hp_pct_val,
				})
				_unit_card_map.append(card_idx)
	return units


func _on_battle_finished(result: Dictionary) -> void:
	var won: bool = result["player_won"]
	_last_battle_won = won
	if won:
		_current_win_streak += 1
		_run_stats["best_win_streak"] = maxi(
			int(_run_stats.get("best_win_streak", 0)), _current_win_streak)
		if _last_ally_count > _last_enemy_count:
			_run_stats["unit_advantage_win"] = true
	else:
		_current_win_streak = 0
	print("[Battle] %s — survived: %d ally, %d enemy" % [
		"WIN" if won else "LOSS", result["ally_survived"], result["enemy_survived"]])

	# Clear temp buffs from BATTLE_START
	for card in game_state.get_active_board():
		(card as CardInstance).clear_temp_buffs()
		(card as CardInstance).shield_hp_pct = 0.0

	var gold_change := 0
	var hp_change := 0
	if won:
		gold_change = 1
		# ⚔️ 약탈자: 승리 시 추가 +2골드
		var raider_gold: int = Commander.calc_battle_win_gold(game_state)
		gold_change += raider_gold
		game_state.gold += gold_change

		# 약탈자 승수 추적
		if game_state.commander_type == Enums.CommanderType.RAIDER:
			game_state.commander_state["win_count"] = game_state.commander_state.get("win_count", 0) + 1
			if Commander.check_raider_upgrade(game_state):
				# TODO: 커먼 업그레이드 자동 부여 UI
				print("[Commander] 약탈자 3승 → 커먼 업그레이드 획득!")

		print("[Settlement] Victory bonus: +%dg" % gold_change)
	else:
		var damage: int = GameState.compute_defeat_damage(game_state.round_num, result.get("enemy_survived", 1))
		hp_change = -damage
		game_state.hp -= damage
		print("[Settlement] Took %d damage (enemy survived ×R%d 배수), HP=%d" % [damage, game_state.round_num, game_state.hp])

	# Apply POST_COMBAT effects (패배 성장 등)
	var post := _apply_post_combat_effects(won)
	var card_effect_gold: int = post["gold"]
	_card_effect_gold = card_effect_gold
	_update_run_stats_snapshot()

	# Show battle result popup → wait for fade
	if _logger:
		_logger.log_battle_result(game_state.round_num, won,
			result["ally_survived"], result["enemy_survived"], game_state.hp, gold_change)

	battle_result_popup.show_result(won, result["ally_survived"], result["enemy_survived"],
		gold_change, hp_change, card_effect_gold)
	await get_tree().create_timer(2.0).timeout

	# HP≤0 → 게임 오버 (settlement 진입 전 조기 차단)
	if game_state.hp <= 0:
		_game_over = true
		print("[Game] GAME OVER at round %d" % game_state.round_num)
		if _logger:
			_logger.log_game_over(false, game_state.round_num, game_state.hp)
			_logger.close_session()
		_record_run_finished(false, game_state.round_num)
		game_over_popup.show_result(false, game_state.round_num, game_state.hp)
		return

	# 보스 라운드 생존 시 보상 팝업 (R4/R8/R12, R15 제외).
	# 2026-04-23: 승리 → 생존. HP≤0 게임오버는 line 408에서 이미 조기 차단됨.
	# 이유: 보스에서 졌으나 살아남은 경우 보상이 없으면 후속 R이 사실상 불가 (user 지적).
	if _is_boss_reward_round():
		_show_boss_reward_popup()
	elif game_state.round_num == 13 and _last_battle_won \
			and BossReward.consume_r8_9_bonus(game_state):
		# r8_9 전선 확장: R13 전투 승리 시 R12 보상 풀에서 1개 추가 (1회 한정).
		_show_boss_reward_popup(12)
	else:
		_enter_phase(Phase.SETTLEMENT)


## Apply POST_COMBAT effects: delegate to chain_engine.process_post_combat().
## Returns {"gold": int, "terazin": int} from post-combat card effects.
func _apply_post_combat_effects(won: bool) -> Dictionary:
	var active := game_state.get_active_board()
	var result := chain_engine.process_post_combat(active, won)
	game_state.gold += result["gold"]
	game_state.terazin += result["terazin"]
	if result["gold"] > 0 or result["terazin"] > 0:
		print("    POST: +%dg +%dt" % [result["gold"], result["terazin"]])
	return {"gold": result["gold"], "terazin": result["terazin"]}


## Settlement용 이자 — `_gold_before_effects` 스냅샷 사용 (OBS-032).
## game_state.calc_interest()는 현재 gold 기반이라 별도 로직.
## r8_4 무한 금고 보유 시 cap 우회.
func _calc_interest() -> int:
	var raw: int = _gold_before_effects / 5 * game_state.interest_per_5g
	if BossReward.is_interest_uncapped(game_state):
		return raw
	return mini(raw, game_state.max_interest)


func _run_settlement() -> void:
	# Reset round state for all cards (activations, tenure)
	for card in game_state.get_active_board():
		(card as CardInstance).reset_round()
	for card in game_state.bench:
		if card != null:
			(card as CardInstance).reset_round()

	# Income from genome (mirrors headless_runner / sim).
	var income_arr: Array = _genome.economy.get("base_income", [])
	var base_income: int = 5
	if income_arr.size() == 15 and game_state.round_num >= 1 and game_state.round_num <= 15:
		base_income = int(income_arr[game_state.round_num - 1])
	var interest := _calc_interest()
	game_state.gold += base_income + interest

	# Terazin from genome.
	var last_won: bool = _last_battle_won
	var terazin_gain: int = int(_genome.economy.get(
		"terazin_win" if last_won else "terazin_lose",
		2 if last_won else 1))
	game_state.terazin += terazin_gain


	# 🔄 승전 의지 (r8_6): 승리 시 전체 ATK +3%
	if last_won and BossReward.has_reward(game_state, "r8_6"):
		for card in game_state.get_active_board():
			(card as CardInstance).enhance(null, 0.03, 0.0)
		print("[BossReward] 승전 의지: 전체 ATK +3%%")

	# 커맨더 추가 테라진 (📚 수집가 5종+, 💰 연금술사 매라운드)
	var cmd_terazin: int = Commander.calc_settlement_terazin(game_state)
	if cmd_terazin > 0:
		game_state.terazin += cmd_terazin
		print("[Commander] +%dt" % cmd_terazin)

	print("[Settlement] R%d done | +%dg(+%d interest) | Gold=%d HP=%d" % [
		game_state.round_num, base_income, interest, game_state.gold, game_state.hp])

	if _logger:
		_logger.log_settlement(game_state.round_num, base_income, interest,
			terazin_gain, game_state.gold, game_state.terazin, _card_effect_gold)

	game_state.round_num += 1
	game_state.apply_levelup_discount()
	game_state.state_changed.emit()

	if game_state.hp <= 0:
		_game_over = true
		print("[Game] GAME OVER at round %d" % (game_state.round_num - 1))
		if _logger:
			_logger.log_game_over(false, game_state.round_num - 1, game_state.hp)
			_logger.close_session()
		_record_run_finished(false, game_state.round_num - 1)
		game_over_popup.show_result(false, game_state.round_num - 1, game_state.hp)
		return
	if game_state.round_num > Enums.MAX_ROUNDS:
		_game_over = true
		print("[Game] VICTORY! Run complete!")
		if _logger:
			_logger.log_game_over(true, Enums.MAX_ROUNDS, game_state.hp)
			_logger.close_session()
		_record_run_finished(true, Enums.MAX_ROUNDS)
		game_over_popup.show_result(true, Enums.MAX_ROUNDS, game_state.hp)
		return

	chain_visual.visible = true
	_enter_phase(Phase.BUILD)


## ON_SELL trigger: fire effects of cards with ON_SELL timing (e.g., sp_arsenal).
func _on_sell_performed(zone: String, idx: int, sold_card: CardInstance) -> void:
	if sold_card != null:
		_run_stats["cards_sold"] = int(_run_stats.get("cards_sold", 0)) + 1
	if _logger and sold_card != null:
		# refund already applied; recompute approx from sold_card
		_logger.log_sell(zone, idx, sold_card.get_base_id(), sold_card.template.get("cost", 0), game_state)
	# 🏺 영혼 항아리: 첫 판매 시 유닛 절반 배분
	if sold_card != null:
		var distributed: int = Talisman.process_soul_jar_sell(
			game_state, sold_card, _battle_rng)
		if distributed > 0:
			print("[Talisman] 영혼 항아리: %d기 배분" % distributed)

	# ON_SELL cards react when ANY card is sold (e.g., sp_arsenal absorb).
	# 또한 sold_card 본인의 SELL block 효과(예: ne_hoarder tenure_gold)를 자원에 적용.
	if sold_card != null:
		var sell_result: Dictionary = chain_engine.process_sell_triggers(
				game_state.get_active_board(), sold_card)
		var gold_delta: int = sell_result.get("gold", 0)
		var terazin_delta: int = sell_result.get("terazin", 0)
		if gold_delta != 0:
			game_state.gold = maxi(game_state.gold + gold_delta, 0)
		if terazin_delta != 0:
			game_state.terazin = maxi(game_state.terazin + terazin_delta, 0)

		# UI target select: ne_masquerade / ne_awakening 판매 시 사용자 카드 선택 popup.
		# sell_result에 needs_target_select가 있으면 target_overlay 시작 + 효과 적용.
		var needs_select: String = sell_result.get("needs_target_select", "")
		if needs_select != "":
			_start_sell_target_select(needs_select, sell_result)
			# UI 분기로 효과는 callback에서 적용. 자원만 emit.
			if gold_delta != 0 or terazin_delta != 0:
				game_state.state_changed.emit()
			return

		# ne_clone_seed ★3 SELL: source 카드의 업그레이드 1개를 보드 첫 카드로 이전
		# (sim 결정성, live UI 분기는 Phase 6 deferred)
		var transfer: Dictionary = sell_result.get("transfer_upgrade", {})
		if not transfer.is_empty():
			_apply_upgrade_transfer(transfer)

		if gold_delta != 0 or terazin_delta != 0 or not transfer.is_empty():
			game_state.state_changed.emit()
	_update_run_stats_snapshot()


## ne_clone_seed ★3 업그레이드 이전 처리. source 카드는 이미 판매된 상태이므로
## 인스턴스만 보유 (board 슬롯에 없음). 보드 첫 카드(target_idx 0)에 부착.
func _apply_upgrade_transfer(transfer: Dictionary) -> void:
	var source: CardInstance = transfer.get("source_card")
	if source == null or source.upgrades.is_empty():
		return
	var idx: int = transfer.get("source_upgrade_idx", 0)
	if idx < 0 or idx >= source.upgrades.size():
		return
	var upg: Dictionary = source.upgrades[idx]
	# 보드 첫 비-null 카드에 부착 (sim 결정성)
	for c in game_state.board:
		if c == null:
			continue
		var target: CardInstance = c
		if target.upgrades.size() < target.get_max_upgrade_slots():
			target.upgrades.append(upg)
			print("[ne_clone_seed] 업그레이드 '%s' → '%s'" % [
					upg.get("name", "?"), target.get_name()])
			break


## SELL target_overlay UI flow 시작 — ne_masquerade / ne_awakening 판매 시 카드 선택.
## sell_result는 needs_target_select handler_id + 자동 default target dict 보유.
## 사용자 선택 후 _on_sell_target_selected에서 효과 적용 (자동 target은 보드 비어 시 fallback).
var _pending_sell_select: Dictionary = {}

func _start_sell_target_select(handler_id: String, sell_result: Dictionary) -> void:
	_pending_sell_select = {
		"handler_id": handler_id,
		"sell_result": sell_result,
	}
	# build_phase가 visible 상태 (판매는 BUILD phase에서만 가능). target_overlay 시작.
	# eligible_predicate=null → 모든 비-null 카드 선택 가능 (theme transform / unit transfer는 슬롯 무관)
	build_phase.target_overlay.start_selection(
		build_phase._field_visuals, game_state.board)
	if not build_phase.target_overlay.target_selected.is_connected(_on_sell_target_selected):
		build_phase.target_overlay.target_selected.connect(_on_sell_target_selected)
	# ESC cancel 처리: 효과는 무시하나 _pending_sell_select 정리 (환불은 이미 적용됨, 사용자 손실 알림)
	if not build_phase.target_overlay.target_cancelled.is_connected(_on_sell_target_cancelled):
		build_phase.target_overlay.target_cancelled.connect(_on_sell_target_cancelled)


## ESC cancel design intent (의도적 비대칭, 2026-04-28 multi-review 2차 결정):
## sell_card → 환불 + 카드 제거 + 효과 트리거가 atomic 묶음.
## ESC는 부분 취소 — 효과만 무시, 환불 + 카드 제거는 그대로 유지.
##
## 사용자 영향: 손해 없음 (환불 받음, 효과 안 받음 = 의도적 ESC). 시스템 비대칭이지만 의도적.
## 대안 검토:
##   A) 현재 상태 (효과 무시, 환불 유지) — 채택 [docs/episodes/2026-04-28-sell-esc-asymmetry.md]
##   B) 환불 회수 — 카드 복원 안 하면 사용자 더 큰 손해 (UX ↓)
##   C) 카드+환불 모두 복원 — 구현 복잡, sell signal 측면 부작용
func _on_sell_target_cancelled() -> void:
	if _pending_sell_select.is_empty():
		return
	if build_phase.target_overlay.target_selected.is_connected(_on_sell_target_selected):
		build_phase.target_overlay.target_selected.disconnect(_on_sell_target_selected)
	if build_phase.target_overlay.target_cancelled.is_connected(_on_sell_target_cancelled):
		build_phase.target_overlay.target_cancelled.disconnect(_on_sell_target_cancelled)
	print("[SELL] target select cancelled — effect 무시 (환불은 의도적 비대칭으로 유지)")
	_pending_sell_select = {}


func _on_sell_target_selected(field_idx: int) -> void:
	if _pending_sell_select.is_empty():
		return
	# 시그널 정리 (selected + cancelled 둘 다)
	if build_phase.target_overlay.target_selected.is_connected(_on_sell_target_selected):
		build_phase.target_overlay.target_selected.disconnect(_on_sell_target_selected)
	if build_phase.target_overlay.target_cancelled.is_connected(_on_sell_target_cancelled):
		build_phase.target_overlay.target_cancelled.disconnect(_on_sell_target_cancelled)
	var target: CardInstance = game_state.board[field_idx]
	if target == null:
		_pending_sell_select = {}
		return
	var handler_id: String = _pending_sell_select["handler_id"]
	var sell_result: Dictionary = _pending_sell_select["sell_result"]
	match handler_id:
		"ne_masquerade":
			var transform: Dictionary = sell_result.get("transform_theme", {}).duplicate()
			transform["target_card"] = target
			if transform.get("omni", false):
				# ★3 omni: 테마 선택 불필요, 즉시 적용.
				_apply_theme_transform(transform)
				_pending_sell_select = {}
				_update_run_stats_snapshot()
				game_state.state_changed.emit()
				return
			# ★1/★2: 사용자가 노출된 N 테마 중 1개 선택. _on_theme_chosen 에서 finalize.
			_pending_theme_transform = transform
			var offer_count: int = int(transform.get("offer_count", 3))
			var allow_self: bool = transform.get("allow_self", true)
			var current_theme: int = target.template.get("theme", -1)
			if not theme_choice_popup.theme_chosen.is_connected(_on_theme_chosen):
				theme_choice_popup.theme_chosen.connect(_on_theme_chosen)
			theme_choice_popup.show_choices(offer_count, current_theme, allow_self)
			# state_changed emit 은 _on_theme_chosen 에서 (transform 적용 후).
			_pending_sell_select = {}
			return
		"ne_awakening":
			var awakening: Dictionary = sell_result.get("awakening_transfer", {}).duplicate()
			awakening["target_card"] = target
			_apply_awakening_transfer(awakening)
		"ne_hoarder":
			var hoard: Dictionary = sell_result.get("hoarder_transfer", {}).duplicate()
			hoard["target_card"] = target
			_apply_hoarder_transfer(hoard)
	_pending_sell_select = {}
	_update_run_stats_snapshot()
	game_state.state_changed.emit()


## ne_masquerade ★1/★2 테마 선택 finalize. user 가 popup 에서 1개 선택.
var _pending_theme_transform: Dictionary = {}

func _on_theme_chosen(theme_int: int) -> void:
	if theme_choice_popup.theme_chosen.is_connected(_on_theme_chosen):
		theme_choice_popup.theme_chosen.disconnect(_on_theme_chosen)
	if _pending_theme_transform.is_empty():
		return
	var transform: Dictionary = _pending_theme_transform
	transform["new_theme"] = theme_int
	_apply_theme_transform(transform)
	_pending_theme_transform = {}
	_update_run_stats_snapshot()
	game_state.state_changed.emit()


## ne_awakening SELL 효과 적용: source 카드의 유닛 stack + 무작위 N등급 업글 1개 → target 카드.
## - transfer_units=true (★2/★3): source.stacks를 target.stacks에 그대로 append (cap 60 적용)
## - 부착 업글 중 rarity 매치 무작위 1개를 target에 부착 (target 슬롯 부족 시 silent fail)
func _apply_awakening_transfer(awakening: Dictionary) -> void:
	var source: CardInstance = awakening.get("source_card")
	var target: CardInstance = awakening.get("target_card")
	if source == null or target == null:
		return
	var rarity_str: String = awakening.get("rarity", "common")
	var transfer_units: bool = awakening.get("transfer_units", false)
	var rarity_int: int = _rarity_str_to_int(rarity_str)
	# 1) 무작위 매치 등급 업글 1개 이전
	var matching: Array = []
	for upg in source.upgrades:
		if int(upg.get("rarity", -1)) == rarity_int:
			matching.append(upg)
	if not matching.is_empty():
		var picked: Dictionary = matching[_battle_rng.randi_range(0, matching.size() - 1)]
		if target.upgrades.size() < target.get_max_upgrade_slots():
			target.upgrades.append(picked)
			print("[ne_awakening] 업그레이드 '%s' (%s) → '%s'" % [
				picked.get("name", "?"), rarity_str, target.get_name()])
	# 2) ★2/★3: 유닛 stack 이전 (cap 60 적용)
	if transfer_units:
		for s in source.stacks:
			if target.get_total_units() >= target.get_unit_cap():
				break
			var room: int = target.get_unit_cap() - target.get_total_units()
			var take: int = mini(int(s.get("count", 0)), room)
			if take <= 0:
				continue
			var new_stack: Dictionary = s.duplicate(true)
			new_stack["count"] = take
			target.stacks.append(new_stack)
			print("[ne_awakening] 유닛 %d기 → '%s'" % [take, target.get_name()])
	target.stats_changed.emit() if target.has_signal("stats_changed") else null


## ne_hoarder SELL: source 의 모든 stack 을 target 에 이전 (cap 적용) +
## source.tenure 비례 영구 ATK/HP 강화 + (★3) bonus_unit_cap.
func _apply_hoarder_transfer(transfer: Dictionary) -> void:
	var source: CardInstance = transfer.get("source_card")
	var target: CardInstance = transfer.get("target_card")
	if source == null or target == null:
		return
	var atk_per_tenure: float = transfer.get("atk_per_tenure", 0.0)
	var hp_per_tenure: float = transfer.get("hp_per_tenure", 0.0)
	var bonus_unit_cap: int = transfer.get("bonus_unit_cap", 0)
	var tenure: int = source.tenure
	# 1) bonus_unit_cap 먼저 적용 — 유닛 이전이 늘어난 cap 까지 채울 수 있도록.
	if bonus_unit_cap > 0:
		target.unit_cap_bonus += bonus_unit_cap
	# 2) 유닛 stack 이전 (cap 적용 — awakening 과 동일 정책)
	for s in source.stacks:
		if target.get_total_units() >= target.get_unit_cap():
			break
		var room: int = target.get_unit_cap() - target.get_total_units()
		var take: int = mini(int(s.get("count", 0)), room)
		if take <= 0:
			continue
		var new_stack: Dictionary = s.duplicate(true)
		new_stack["count"] = take
		target.stacks.append(new_stack)
	# 3) 체류 R 비례 영구 강화. tenure=0 이면 no-op.
	if tenure > 0 and (atk_per_tenure > 0.0 or hp_per_tenure > 0.0):
		target.enhance(null, atk_per_tenure * tenure, hp_per_tenure * tenure)
	target.stats_changed.emit()
	print("[ne_hoarder] tenure=%d → '%s' (+%.0f%% atk / +%.0f%% hp%s)" % [
		tenure, target.get_name(),
		atk_per_tenure * tenure * 100.0,
		hp_per_tenure * tenure * 100.0,
		" / cap+%d" % bonus_unit_cap if bonus_unit_cap > 0 else ""])


func _rarity_str_to_int(s: String) -> int:
	match s:
		"common": return Enums.UpgradeRarity.COMMON
		"rare": return Enums.UpgradeRarity.RARE
		"epic": return Enums.UpgradeRarity.EPIC
	return Enums.UpgradeRarity.COMMON


## ne_masquerade theme transform 처리. handler가 CardInstance 참조 직접 전달.
## ★3 omni: card.is_omni_theme = true (모든 theme 비교에 매치).
func _apply_theme_transform(transform: Dictionary) -> void:
	var target: CardInstance = transform.get("target_card")
	if target == null:
		return
	var omni: bool = transform.get("omni", false)
	if omni:
		target.is_omni_theme = true
		print("[ne_masquerade] %s → omni-theme" % target.get_name())
	else:
		var new_theme: int = transform.get("new_theme", -1)
		if new_theme >= 0:
			target.template["theme"] = new_theme
			print("[ne_masquerade] %s → theme=%d" % [target.get_name(), new_theme])


## ON_MERGE trigger: delegate to chain_engine.process_merge_triggers().
func _on_merge_performed(merged_card: CardInstance) -> void:
	if _logger:
		_logger.log_merge(merged_card.get_base_id(), merged_card.star_level - 1, merged_card.star_level)
	var active := game_state.get_active_board()
	var result := chain_engine.process_merge_triggers(active, merged_card)
	game_state.terazin += result["terazin"]
	game_state.gold += result["gold"]
	if result["terazin"] > 0 or result["gold"] > 0:
		print("  ON_MERGE: +%dt +%dg" % [result["terazin"], result["gold"]])

	# 🎲 도박꾼: ★합성 시 구매비용 합 50% 환급
	var merge_info := {"card": merged_card, "old_star": merged_card.star_level - 1, "new_star": merged_card.star_level}
	var refund: int = Commander.calc_merge_refund(game_state, merge_info)
	if refund > 0:
		game_state.gold += refund
		print("[Commander] 도박꾼 합성 환급: +%dg" % refund)

	_update_run_stats_snapshot()
	game_state.state_changed.emit()


## Combat chain: on ally attack → trigger ON_COMBAT_ATTACK cards.
func _on_combat_attack(attacker_idx: int, _defender_idx: int) -> void:
	if attacker_idx < 0 or attacker_idx >= _unit_card_map.size():
		return
	var engine = battle_phase.get_engine()
	if engine == null:
		return
	var card_idx: int = _unit_card_map[attacker_idx]
	var active := game_state.get_active_board()
	var result := chain_engine.process_combat_event(active, "attack", card_idx)
	_apply_combat_buffs(result["buffs"], engine, active)


## Combat chain: on ally death → trigger death-reactive cards.
func _on_combat_death(unit_idx: int) -> void:
	var engine = battle_phase.get_engine()
	if engine == null:
		return
	# Only process ally deaths
	if unit_idx >= engine.count or engine.team[unit_idx] != 1:
		return
	var card_idx: int = -1
	if unit_idx < _unit_card_map.size():
		card_idx = _unit_card_map[unit_idx]
	var active := game_state.get_active_board()
	var result := chain_engine.process_combat_event(active, "ally_death", card_idx)
	_apply_combat_buffs(result["buffs"], engine, active)


## Apply combat chain buffs back to combat engine units.
func _apply_combat_buffs(buffs: Array, engine, active: Array) -> void:
	for buff in buffs:
		var ci: int = buff["card_idx"]
		if ci < 0 or ci >= active.size():
			continue
		var atk_pct: float = buff.get("atk_pct", 0.0)
		# Apply buff to all combat units belonging to this card
		for ui in _unit_card_map.size():
			if _unit_card_map[ui] == ci and engine.alive[ui] == 1:
				engine.atk[ui] *= 1.0 + atk_pct


# ================================================================
# 보스 보상
# ================================================================

## 보스 보상 영구 효과를 chain_engine에 반영.
func _apply_boss_reward_modifiers() -> void:
	# r4_3: 연쇄 반응로 — 스폰 25% 추가
	var extra_spawn := 0.25 if BossReward.has_reward(game_state, "r4_3") else 0.0
	chain_engine.bonus_spawn_chance = Commander.get_bonus_spawn_chance(game_state) + extra_spawn
	chain_engine.propagate_bonus_spawn()

	# r4_5: 강화 증폭기 — enhance ×1.2 (부적 수은 방울과 곱연산)
	chain_engine.enhance_multiplier = Talisman.get_enhance_multiplier(game_state) \
		* BossReward.get_enhance_amp(game_state)

	# r12_3: 과부하 연쇄 — 발동 상한 보너스
	chain_engine.activation_bonus = BossReward.get_activation_bonus(game_state)

	# r8_5: 광역 강화장 — 강화 시 인접 50%
	chain_engine.aoe_enhance = BossReward.has_reward(game_state, "r8_5")


func _is_boss_reward_round() -> bool:
	return game_state.round_num in [4, 8, 12]


func _show_boss_reward_popup(override_tier: int = -1) -> void:
	var boss_tier: int = override_tier if override_tier > 0 else game_state.round_num
	var choice_count: int = Talisman.get_boss_reward_choices(game_state)
	var choices := BossRewardDB.roll_choices(boss_tier, choice_count, _battle_rng)
	print("[BossReward] R%d 보스 보상 %d개 선택지: %s" % [boss_tier, choices.size(), choices])
	if _logger:
		_logger.log_boss_reward_offered(game_state.round_num, choices)
	boss_reward_popup.show_choices(choices)


func _on_boss_reward_selected(reward_id: String) -> void:
	var data: Dictionary = BossRewardDB.get_data(reward_id)
	var needs_target: int = data.get("needs_target", 0)
	print("[BossReward] 선택: %s (%s)" % [data.get("name", reward_id), reward_id])
	if _logger:
		_logger.log_boss_reward_selected(reward_id)

	_boss_reward_targets = []
	if needs_target == 0:
		BossReward.apply_no_target(reward_id, game_state, _battle_rng)
		_finish_boss_reward(reward_id)
	else:
		_pending_boss_reward = {
			"reward_id": reward_id,
			"needs_target": needs_target,
			"targets_remaining": needs_target,
		}
		# 빌드 페이즈의 타겟 오버레이 재활용.
		# Attach 보상(r8_1/r8_7/r12_7)은 can_attach_upgrade predicate로 슬롯 만석 카드 제외 →
		# attach_upgrade silent fail UX 회귀 방지 (multi-review 2차 발견).
		# 다른 보상(r4_1/r4_7/r12_1 등)은 슬롯 무관이라 default null.
		build_phase.visible = true
		var predicate: Callable = Callable()
		if reward_id in ["r8_1", "r8_7", "r12_7"]:
			predicate = Callable(self, "_can_attach_upgrade_predicate")
		build_phase.target_overlay.start_selection(
			build_phase._field_visuals, game_state.board, predicate)
		# 일시적으로 타겟 시그널 리다이렉트
		if not build_phase.target_overlay.target_selected.is_connected(_on_boss_target_selected):
			build_phase.target_overlay.target_selected.connect(_on_boss_target_selected)


## Boss reward attach 보상용 predicate — can_attach_upgrade 카드만 선택 가능.
func _can_attach_upgrade_predicate(card) -> bool:
	if card == null:
		return false
	return (card as CardInstance).can_attach_upgrade()


func _on_boss_target_selected(field_idx: int) -> void:
	if _pending_boss_reward.is_empty():
		return
	var card: CardInstance = game_state.board[field_idx]
	if card == null:
		return

	var reward_id: String = _pending_boss_reward["reward_id"]
	# r12_1 단계 강제: step 1 = ★2→★3, step 2 = ★1→★2 (★1→★3 직행 방지)
	var step: int = _pending_boss_reward["needs_target"] - _pending_boss_reward["targets_remaining"] + 1
	BossReward.apply_with_target(reward_id, game_state, card, _battle_rng, step)
	_boss_reward_targets.append({"field_idx": field_idx, "card_id": card.get_base_id()})
	_pending_boss_reward["targets_remaining"] -= 1

	if _pending_boss_reward["targets_remaining"] > 0:
		# r12_1: 2장 선택 — 다시 오버레이
		# call_deferred: 현재 시그널 핸들러의 end_selection()이 완료된 후 실행
		build_phase.target_overlay.start_selection.call_deferred(
			build_phase._field_visuals, game_state.board)
		return

	# 타겟 선택 완료 — 시그널 정리
	if build_phase.target_overlay.target_selected.is_connected(_on_boss_target_selected):
		build_phase.target_overlay.target_selected.disconnect(_on_boss_target_selected)
	build_phase.visible = false

	_finish_boss_reward(reward_id)


func _finish_boss_reward(reward_id: String) -> void:
	var data: Dictionary = BossRewardDB.get_data(reward_id)
	var upgrade_choice: String = data.get("needs_upgrade_choice", "")

	if upgrade_choice != "":
		# 에픽/레어 업그레이드 선택 팝업
		var rarity: int = Enums.UpgradeRarity.EPIC if upgrade_choice == "epic" \
			else Enums.UpgradeRarity.RARE
		upgrade_choice_popup.show_choices(rarity)
		var chosen_id: String = await upgrade_choice_popup.upgrade_chosen
		# 대상 카드에 부착 (마지막 타겟)
		if not _pending_boss_reward.is_empty():
			# apply_with_target에서 이미 랜덤 업글 부착됨 — UI 선택은 추후 확장
			pass
		_pending_boss_reward = {}

	_pending_boss_reward = {}
	_apply_boss_reward_modifiers()
	if _logger:
		_logger.log_boss_reward_applied(game_state.round_num, reward_id, _boss_reward_targets)
	_update_run_stats_snapshot()
	game_state.state_changed.emit()
	print("[BossReward] 보상 적용 완료 → SETTLEMENT")
	_enter_phase(Phase.SETTLEMENT)


func _on_restart() -> void:
	if _logger:
		_logger.close_session()
	get_tree().reload_current_scene()


func _record_run_finished(victory: bool, final_round: int) -> void:
	if _run_result_recorded or _meta_progress == null:
		return
	_run_result_recorded = true
	_update_run_stats_snapshot()
	var unlocks: Array[String] = _meta_progress.record_run_finished(
		victory, final_round, _run_stats)
	if not unlocks.is_empty():
		print("[MetaProgress] Unlocks: %s" % ", ".join(unlocks))
	var err: int = _meta_progress.save()
	if err != OK:
		push_warning("[MetaProgress] save failed: %s" % err)


func _exit_tree() -> void:
	if _logger:
		_logger.close_session()


func _on_build_confirmed() -> void:
	if current_phase == Phase.BUILD:
		if _smith_start_upgrade_pending and _has_smith_start_upgrade_target():
			var applied: bool = await _run_smith_start_upgrade_flow()
			if not applied:
				return
		if _logger:
			_logger.log_build_confirm(game_state)
		_enter_phase(Phase.CHAIN)


func _has_smith_start_upgrade_target() -> bool:
	for card in game_state.board:
		if card != null and (card as CardInstance).can_attach_upgrade():
			return true
	return false


func _run_smith_start_upgrade_flow() -> bool:
	upgrade_choice_popup.show_choices(Enums.UpgradeRarity.COMMON, 3)
	var chosen_id: String = await upgrade_choice_popup.upgrade_chosen
	if chosen_id == "":
		return false
	build_phase.start_free_upgrade_selection(chosen_id, "smith_start")
	var applied: bool = await build_phase.free_upgrade_finished
	if applied:
		_smith_start_upgrade_pending = false
		print("[Commander] 단조사 시작 보너스 적용: %s" % chosen_id)
	return applied


func _on_shop_purchase(template_id: String, slot_idx: int, cost: int) -> void:
	if _logger:
		_logger.log_purchase(template_id, slot_idx, cost, game_state)
	_update_run_stats_snapshot()


func _on_state_card_moved(from_zone, from_idx, to_zone, to_idx) -> void:
	if _logger:
		_logger.log_move(from_zone, from_idx, to_zone, to_idx)


func _on_upgrade_purchased_logged(upgrade_id: String, slot_idx: int, cost: int, terazin_after: int) -> void:
	if _logger:
		_logger.log_upgrade_purchase(upgrade_id, slot_idx, cost, terazin_after)


func _on_upgrade_refunded_logged(upgrade_id: String, cost: int, reason: String, terazin_after: int) -> void:
	if _logger:
		_logger.log_upgrade_refund(upgrade_id, cost, reason, terazin_after)


func _on_upgrade_rerolled(cost: int, terazin_after: int) -> void:
	print("[UpgradeReroll] -%dt, Terazin=%d" % [cost, terazin_after])
	if _logger:
		_logger.log_upgrade_reroll(cost, terazin_after)


func _on_upgrade_attached_logged(upgrade_id: String, source: String, target_card_id: String, target_idx: int) -> void:
	if _logger:
		_logger.log_upgrade_attach(upgrade_id, source, target_card_id, target_idx)
	_update_run_stats_snapshot()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_SPACE:
				if current_phase == Phase.BUILD:
					_on_build_confirmed()
			KEY_H:
				if current_phase == Phase.BUILD:
					build_phase.begin_strategist_swap()
			KEY_D:
				if current_phase == Phase.BUILD:
					build_phase.begin_rusty_wrench_detach()
			KEY_1:
				battle_phase.set_speed(1.0)
			KEY_2:
				battle_phase.set_speed(2.0)
			KEY_4:
				battle_phase.set_speed(4.0)
			KEY_R:
				if current_phase == Phase.BUILD:
					# 🎲 도박꾼: 50% 확률 무료 리롤. 실패 시 pending_free_rerolls(폐품 상회 등) 소비.
					var free_reroll: bool = Commander.is_reroll_free(game_state, _battle_rng)
					if free_reroll:
						# 무료(도박꾼): 골드 차감 없이 상점 갱신. pending은 보존.
						game_state.round_rerolls += 1
						build_phase.refresh_shop()
						var reroll_result := chain_engine.process_reroll_triggers(game_state.get_active_board())
						game_state.terazin += reroll_result["terazin"]
						game_state.gold += reroll_result["gold"]
						_apply_reroll_levelup_discount(reroll_result)
						game_state.state_changed.emit()
						print("[Reroll] FREE (gambler)! Gold=%d" % game_state.gold)
						if _logger:
							_logger.log_reroll(0, true, game_state.gold)
							_logger.log_shop_refresh("reroll", build_phase.get_shop_offered(), game_state.gold)
					elif game_state.pending_free_rerolls > 0:
						# 무료(저축분): 도박꾼 실패 후 저축된 무료 리롤 우선 소비.
						game_state.pending_free_rerolls -= 1
						game_state.round_rerolls += 1
						build_phase.refresh_shop()
						var reroll_result := chain_engine.process_reroll_triggers(game_state.get_active_board())
						game_state.terazin += reroll_result["terazin"]
						game_state.gold += reroll_result["gold"]
						_apply_reroll_levelup_discount(reroll_result)
						game_state.state_changed.emit()
						print("[Reroll] FREE (pending, %d left)! Gold=%d" % [
							game_state.pending_free_rerolls, game_state.gold])
						if _logger:
							_logger.log_reroll(0, true, game_state.gold)
							_logger.log_shop_refresh("reroll", build_phase.get_shop_offered(), game_state.gold)
					elif build_phase.reroll():
						var reroll_result := chain_engine.process_reroll_triggers(game_state.get_active_board())
						game_state.terazin += reroll_result["terazin"]
						game_state.gold += reroll_result["gold"]
						_apply_reroll_levelup_discount(reroll_result)
						print("[Reroll] -%dg, Gold=%d" % [_genome.get_reroll_cost(), game_state.gold])
						if _logger:
							_logger.log_reroll(_genome.get_reroll_cost(), false, game_state.gold)
							_logger.log_shop_refresh("reroll", build_phase.get_shop_offered(), game_state.gold)
					else:
						print("[Reroll] Not enough gold")
			KEY_T:
				if current_phase == Phase.BUILD:
					if not build_phase.reroll_upgrades():
						print("[UpgradeReroll] Not available or not enough terazin")
			KEY_F:
				if current_phase == Phase.BUILD:
					var cost := game_state.levelup_current_cost
					if game_state.try_levelup():
						# Mirror sim: override next-level cost from genome.
						var next_lv := game_state.shop_level + 1
						if next_lv <= Enums.LEVELUP_MAX:
							game_state.levelup_current_cost = _genome.get_levelup_cost(next_lv)
						print("[LevelUp] Lv%d (-%dg) | Gold=%d | Next=%dg" % [
							game_state.shop_level, cost, game_state.gold,
							game_state.levelup_current_cost])
						if _logger:
							_logger.log_levelup(game_state.shop_level, cost,
								game_state.gold, game_state.levelup_current_cost)
					else:
						if game_state.shop_level >= Enums.LEVELUP_MAX:
							print("[LevelUp] Already max level (Lv%d)" % game_state.shop_level)
						else:
							print("[LevelUp] Not enough gold (%d < %d)" % [
								game_state.gold, game_state.levelup_current_cost])
