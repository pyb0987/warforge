extends Node
## Game Manager — Phase FSM. BUILD → CHAIN → BATTLE → SETTLEMENT.

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
var _game_over: bool = false

@onready var build_phase: Control = $BuildPhase
@onready var chain_visual: Control = $ChainVisual
@onready var battle_phase: Node2D = $BattlePhase
@onready var battle_result_popup: ColorRect = $UILayer/BattleResultPopup
@onready var game_over_popup: ColorRect = $UILayer/GameOverPopup
@onready var upgrade_choice_popup: ColorRect = $UILayer/UpgradeChoicePopup
@onready var boss_reward_popup: ColorRect = $UILayer/BossRewardPopup
@onready var conscript_popup: ColorRect = $UILayer/ConscriptChoicePopup


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

	game_state = GameState.new()
	# Apply genome economy/starting state (mirrors headless_runner).
	game_state.gold = _genome.get_starting_gold()
	game_state.terazin = _genome.get_starting_terazin()
	game_state.levelup_current_cost = _genome.get_levelup_cost(2)
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

	# TODO: 커맨더 선택 UI — 현재 하드코딩 (NONE = 기존 동작)
	game_state.commander_type = Enums.CommanderType.NONE
	# TODO: 부적 선택 UI — 현재 하드코딩 (NONE = 기존 동작)
	game_state.talisman_type = Enums.TalismanType.NONE
	Talisman.init_run_state(game_state)

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

	upgrade_choice_popup.setup(_battle_rng)
	build_phase.setup(game_state, _battle_rng, _genome)
	build_phase.shop.card_purchased.connect(_on_shop_purchase)
	build_phase.set_upgrade_choice_popup(upgrade_choice_popup)
	build_phase.build_confirmed.connect(_on_build_confirmed)
	build_phase.sell_performed.connect(_on_sell_performed)
	build_phase.merge_performed.connect(_on_merge_performed)
	chain_visual.setup(build_phase._field_visuals)
	chain_visual.connect_engine(chain_engine)
	battle_phase.battle_finished.connect(_on_battle_finished)
	game_over_popup.restart_requested.connect(_on_restart)
	boss_reward_popup.reward_selected.connect(_on_boss_reward_selected)

	_enter_phase(Phase.BUILD)


func _setup_test_board() -> void:
	game_state.round_num = 1


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


func _run_chain() -> void:
	chain_visual.clear_links()

	# 무료 리롤은 이번 라운드 한정: 체인 시작(새 라운드) 시점에 리셋.
	# 이후 RS 카드(예: 폐품 상회)가 재충전.
	game_state.pending_free_rerolls = 0
	game_state.round_rerolls = 0

	# OBS-032: Snapshot gold before card effects — interest uses this, not post-effect gold.
	_gold_before_effects = game_state.gold

	var active_board := game_state.get_active_board()
	if active_board.is_empty():
		_enter_phase(Phase.BATTLE)
		return

	chain_visual.update_board_map(game_state.board)
	var result := chain_engine.run_growth_chain(active_board, true)
	print("[Chain] count=%d gold=%d" % [result["chain_count"], result["gold_earned"]])

	game_state.gold += result["gold_earned"]
	game_state.terazin += result["terazin_earned"]
	game_state.state_changed.emit()

	# Deferred conscription: 3-pick-1 UI for outpost self-conscription
	var pending: Array = result.get("pending_conscriptions", [])
	for req in pending:
		var card_ref: CardInstance = req["card_ref"]
		var count: int = req["count"]
		var mil_sys: MilitarySystem = chain_engine._theme_systems[Enums.CardTheme.MILITARY]
		for _i in count:
			var options: Array[String] = mil_sys.pick_conscript_options(_battle_rng, 3)
			conscript_popup.show_choices(options)
			var chosen_id: String = await conscript_popup.unit_chosen
			mil_sys.apply_conscript(card_ref, chosen_id)
		print("[Conscript] %s: %d picks done" % [card_ref.get_name(), count])

	build_phase.visible = true
	await get_tree().create_timer(1.0).timeout
	_enter_phase(Phase.BATTLE)


func _run_battle() -> void:
	build_phase.visible = false
	chain_visual.visible = false

	# Apply PERSISTENT effects (range_bonus, ATK buffs) then BATTLE_START
	chain_engine.process_persistent(game_state.get_active_board())
	_apply_battle_start_effects()

	# 🔄 물량의 법칙 (r12_6): 50기+ 카드 → ATK ×1.5, AS ×1.3
	if BossReward.has_reward(game_state, "r12_6"):
		for card in game_state.get_active_board():
			var c: CardInstance = card
			if c.get_total_units() >= 50:
				c.temp_mult_buff(1.5)
				# AS는 upgrade_as_mult에 곱하면 전투 종료 후 복원 필요 → temp로 처리
				c.theme_state["quantity_law_as"] = true

	# 📚 수집가: 유니크 카드 종류 × ATK +4% (temp buff)
	var collector_bonus: float = Commander.calc_collector_atk_bonus(game_state)
	if collector_bonus > 0.0:
		for card in game_state.get_active_board():
			(card as CardInstance).temp_mult_buff(1.0 + collector_bonus)
		print("[Commander] 수집가 ATK +%.0f%%" % (collector_bonus * 100))

	var ally_data := _materialize_army()
	var enemy_data: Array = EnemyDB.generate(game_state.round_num, _battle_rng, _genome)

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
			var as_mult_total: float = c.upgrade_as_mult * (1.0 + as_bonus)
			for _n in s["count"]:
				units.append({
					"atk": eff_atk * reroll_buff_mult,
					"hp": eff_hp,
					"attack_speed": ut["attack_speed"] * as_mult_total,
					"range": ut["range"] + c.upgrade_range + c.theme_state.get("range_bonus", 0),
					"move_speed": ut["move_speed"] + c.upgrade_move_speed + int(c.theme_state.get("ms_bonus", 0)),
					"def": c.upgrade_def,
					"mechanics": unit_mechs,
					"radius": 6.0,
				})
				_unit_card_map.append(card_idx)
	return units


func _on_battle_finished(result: Dictionary) -> void:
	var won: bool = result["player_won"]
	_last_battle_won = won
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
		var damage: int = result.get("enemy_survived", 1)
		hp_change = -damage
		game_state.hp -= damage
		print("[Settlement] Took %d damage (enemy survived), HP=%d" % [damage, game_state.hp])

	# Apply POST_COMBAT effects (패배 성장 등)
	var post := _apply_post_combat_effects(won)
	var card_effect_gold: int = post["gold"]
	_card_effect_gold = card_effect_gold

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
		game_over_popup.show_result(false, game_state.round_num, game_state.hp)
		return

	# 보스 라운드 승리 시 보상 팝업 (R4/R8/R12, R15 제외)
	if won and _is_boss_reward_round():
		_show_boss_reward_popup()
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


## Genome-driven interest calc — mirrors headless_runner._calc_interest.
func _calc_interest() -> int:
	var per_5: int = int(_genome.economy.get("interest_per_5g", 1))
	var max_i: int = int(_genome.economy.get("max_interest", 2))
	return mini(_gold_before_effects / 5 * per_5, max_i)


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

	# 🔄 전리품 회수 (r8_4): 승리 +3g, 패배 +2t
	var boss_gold: int = BossReward.get_settlement_gold_bonus(game_state, last_won)
	var boss_terazin: int = BossReward.get_settlement_terazin_bonus(game_state, last_won)
	if boss_gold > 0:
		game_state.gold += boss_gold
		print("[BossReward] 전리품 회수: +%dg" % boss_gold)
	if boss_terazin > 0:
		game_state.terazin += boss_terazin
		print("[BossReward] 전리품 회수: +%dt" % boss_terazin)

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
		game_over_popup.show_result(false, game_state.round_num - 1, game_state.hp)
		return
	if game_state.round_num > Enums.MAX_ROUNDS:
		_game_over = true
		print("[Game] VICTORY! Run complete!")
		if _logger:
			_logger.log_game_over(true, Enums.MAX_ROUNDS, game_state.hp)
			_logger.close_session()
		game_over_popup.show_result(true, Enums.MAX_ROUNDS, game_state.hp)
		return

	chain_visual.visible = true
	_enter_phase(Phase.BUILD)


## ON_SELL trigger: fire effects of cards with ON_SELL timing (e.g., sp_arsenal).
func _on_sell_performed(zone: String, idx: int, sold_card: CardInstance) -> void:
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
	if sold_card != null:
		chain_engine.process_sell_triggers(game_state.get_active_board(), sold_card)


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

	# 🔄 전장의 메아리 (r12_5): 아군 사망 시 나머지 아군 ATK +3%
	if BossReward.has_reward(game_state, "r12_5"):
		for ui in _unit_card_map.size():
			if engine.alive[ui] == 1 and engine.team[ui] == 1:
				engine.atk[ui] *= 1.03


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
	# r4_3: 연쇄 반응로 — 스폰 50% 추가
	var extra_spawn := 0.5 if BossReward.has_reward(game_state, "r4_3") else 0.0
	chain_engine.bonus_spawn_chance = Commander.get_bonus_spawn_chance(game_state) + extra_spawn
	chain_engine.propagate_bonus_spawn()

	# r4_5: 강화 증폭기 — enhance ×1.5 (부적 수은 방울과 곱연산)
	chain_engine.enhance_multiplier = Talisman.get_enhance_multiplier(game_state) \
		* BossReward.get_enhance_amp(game_state)

	# r8_3/r12_3: 과부하 엔진/연쇄 — 발동 상한 보너스
	chain_engine.activation_bonus = BossReward.get_activation_bonus(game_state)

	# r8_5: 광역 강화장 — 강화 시 인접 50%
	chain_engine.aoe_enhance = BossReward.has_reward(game_state, "r8_5")


func _is_boss_reward_round() -> bool:
	return game_state.round_num in [4, 8, 12]


func _show_boss_reward_popup() -> void:
	var boss_tier: int = game_state.round_num
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
		# 빌드 페이즈의 타겟 오버레이 재활용
		build_phase.visible = true
		build_phase.target_overlay.start_selection(
			build_phase._field_visuals, game_state.board)
		# 일시적으로 타겟 시그널 리다이렉트
		if not build_phase.target_overlay.target_selected.is_connected(_on_boss_target_selected):
			build_phase.target_overlay.target_selected.connect(_on_boss_target_selected)


func _on_boss_target_selected(field_idx: int) -> void:
	if _pending_boss_reward.is_empty():
		return
	var card: CardInstance = game_state.board[field_idx]
	if card == null:
		return

	var reward_id: String = _pending_boss_reward["reward_id"]
	BossReward.apply_with_target(reward_id, game_state, card, _battle_rng)
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
	game_state.state_changed.emit()
	print("[BossReward] 보상 적용 완료 → SETTLEMENT")
	_enter_phase(Phase.SETTLEMENT)


func _on_restart() -> void:
	if _logger:
		_logger.close_session()
	get_tree().reload_current_scene()


func _exit_tree() -> void:
	if _logger:
		_logger.close_session()


func _on_build_confirmed() -> void:
	if current_phase == Phase.BUILD:
		if _logger:
			_logger.log_build_confirm(game_state)
		_enter_phase(Phase.CHAIN)


func _on_shop_purchase(template_id: String, slot_idx: int, cost: int) -> void:
	if _logger:
		_logger.log_purchase(template_id, slot_idx, cost, game_state)


func _on_state_card_moved(from_zone, from_idx, to_zone, to_idx) -> void:
	if _logger:
		_logger.log_move(from_zone, from_idx, to_zone, to_idx)


func _on_upgrade_purchased_logged(upgrade_id: String, slot_idx: int, cost: int, terazin_after: int) -> void:
	if _logger:
		_logger.log_upgrade_purchase(upgrade_id, slot_idx, cost, terazin_after)


func _on_upgrade_refunded_logged(upgrade_id: String, cost: int, reason: String, terazin_after: int) -> void:
	if _logger:
		_logger.log_upgrade_refund(upgrade_id, cost, reason, terazin_after)


func _on_upgrade_attached_logged(upgrade_id: String, source: String, target_card_id: String, target_idx: int) -> void:
	if _logger:
		_logger.log_upgrade_attach(upgrade_id, source, target_card_id, target_idx)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_SPACE:
				if current_phase == Phase.BUILD:
					_on_build_confirmed()
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
						print("[Reroll] -%dg, Gold=%d" % [_genome.get_reroll_cost(), game_state.gold])
						if _logger:
							_logger.log_reroll(_genome.get_reroll_cost(), false, game_state.gold)
							_logger.log_shop_refresh("reroll", build_phase.get_shop_offered(), game_state.gold)
					else:
						print("[Reroll] Not enough gold")
			KEY_T:
				if current_phase == Phase.BUILD:
					if build_phase.reroll_upgrades():
						print("[UpgradeReroll] -%dt, Terazin=%d" % [Enums.UPGRADE_REROLL_COST, game_state.terazin])
						if _logger:
							_logger.log_upgrade_reroll(Enums.UPGRADE_REROLL_COST, game_state.terazin)
					else:
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
