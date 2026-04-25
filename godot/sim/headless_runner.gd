class_name HeadlessRunner
extends RefCounted
## Single headless game simulation. Replaces GameManager for autoresearch.
## Runs BUILD → UPGRADE SHOP → CHAIN → BATTLE → BOSS REWARD → SETTLEMENT.
## Collects per-round metrics for Evaluator.

var _genome: Genome
var _strategy: String
var _seed: int
var _tracer: RefCounted = null  # AITracer (optional)


func set_tracer(tracer: RefCounted) -> void:
	_tracer = tracer

## Collected metrics
var _round_data: Array = []       # Array[Dictionary] per round
var _purchase_log: Array = []     # Array[String] card IDs purchased
var _merge_events: Array = []     # Array[Dictionary] {round, card_id, new_star}
var _merge_upgrades: Array = []   # Array[Dictionary] merge bonus upgrades
var _boss_rewards_applied: Array = []  # Array[Dictionary] boss rewards
var _upgrades_purchased: Array = []    # Array[Dictionary] terazin shop purchases
var _chain_event_count: int = 0   # Per-round chain event counter
var _cross_activations: int = 0   # source_idx ≠ target_idx events
var _total_activations: int = 0   # All chain events

## EnemyDB script reference (static methods)
var _enemy_db = preload("res://core/data/enemy_db.gd")
const _AIRewardScript = preload("res://sim/ai_reward_logic.gd")


func _init(genome: Genome, strategy: String, seed_val: int) -> void:
	_genome = genome
	_strategy = strategy
	_seed = seed_val


## Run a full 15-round game. Returns result dictionary with all metrics.
func run() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed

	var state := GameState.new()
	state.gold = _genome.get_starting_gold()
	state.terazin = _genome.get_starting_terazin()
	state.round_num = 1
	state.commander_type = Enums.CommanderType.NONE
	state.talisman_type = Enums.TalismanType.NONE
	# Override levelup cost + interest params from genome
	state.levelup_current_cost = _genome.get_levelup_cost(2)
	state.max_interest = int(_genome.economy.get("max_interest", Enums.MAX_INTEREST))
	state.interest_per_5g = int(_genome.economy.get("interest_per_5g", Enums.INTEREST_PER_5G))
	# 카드 풀 고갈 (OBS-049) — genome에서 pool_sizes 오버라이드 가능
	state.card_pool = CardPool.new()
	state.card_pool.init_pool(_genome.pool_sizes if _genome else {})
	Talisman.init_run_state(state)

	var chain_engine := ChainEngine.new()
	chain_engine.set_seed(_seed)
	chain_engine.adjacency_range = Commander.get_adjacency_range(state)
	chain_engine.bonus_spawn_chance = Commander.get_bonus_spawn_chance(state)
	chain_engine.propagate_bonus_spawn()
	chain_engine.propagate_card_effects(_genome.card_effects)
	chain_engine.enhance_multiplier = Talisman.get_enhance_multiplier(state)

	# Connect chain events for cross-activation tracking
	chain_engine.chain_event_fired.connect(_on_chain_event)

	# ON_SELL triggers (e.g., sp_arsenal absorb, ne_hoarder tenure_gold,
	# ne_clone_seed ★3 transfer_upgrade, ne_masquerade transform_theme)
	state.card_sold.connect(func(sold_card: CardInstance):
		var sell_result: Dictionary = chain_engine.process_sell_triggers(
				state.get_active_board(), sold_card)
		var gold_delta: int = sell_result.get("gold", 0)
		var terazin_delta: int = sell_result.get("terazin", 0)
		if gold_delta != 0:
			state.gold = maxi(state.gold + gold_delta, 0)
		if terazin_delta != 0:
			state.terazin = maxi(state.terazin + terazin_delta, 0)
		# ne_clone_seed ★3 SELL: source 카드의 첫 업그레이드를 보드 첫 카드에 부착
		var transfer: Dictionary = sell_result.get("transfer_upgrade", {})
		if not transfer.is_empty():
			var src: CardInstance = transfer.get("source_card")
			if src != null and src.upgrades.size() > 0:
				var u_idx: int = transfer.get("source_upgrade_idx", 0)
				if u_idx >= 0 and u_idx < src.upgrades.size():
					var upg: Dictionary = src.upgrades[u_idx]
					for c in state.board:
						if c == null:
							continue
						var ct: CardInstance = c
						if ct.upgrades.size() < ct.get_max_upgrade_slots():
							ct.upgrades.append(upg)
							break
		# ne_masquerade SELL: target 카드 theme 변경 (★3 omni)
		var transform: Dictionary = sell_result.get("transform_theme", {})
		if not transform.is_empty():
			var target: CardInstance = transform.get("target_card")
			if target != null:
				if transform.get("omni", false):
					target.is_omni_theme = true
				else:
					var nth: int = transform.get("new_theme", -1)
					if nth >= 0:
						target.template["theme"] = nth
	)

	var shop := ShopLogic.new()
	shop.setup(state, rng, _genome)

	var ai := AIAgent.new(_strategy, rng, _genome)
	if _tracer != null:
		ai.set_tracer(_tracer)
	var ai_reward := _AIRewardScript.new()

	# Track purchases and merges
	shop.card_purchased.connect(func(card_id: String): _purchase_log.append(card_id))
	shop.card_merged.connect(func(card: CardInstance, old_star: int, new_star: int):
		_merge_events.append({
			"round": state.round_num,
			"card_id": card.get_base_id(),
			"new_star": new_star,
		})
		if _tracer != null and _tracer.enabled:
			_tracer.emit({"t": "merge", "round": state.round_num,
				"card_id": card.get_base_id(), "old_star": old_star, "new_star": new_star})
		# ★合성 bonus upgrade: ★1→★2 = rare, ★2→★3 = epic
		var bonus_rarity := -1
		if old_star == 1 and new_star == 2:
			bonus_rarity = Enums.UpgradeRarity.RARE
		elif old_star == 2 and new_star == 3:
			bonus_rarity = Enums.UpgradeRarity.EPIC
		if bonus_rarity >= 0 and card.can_attach_upgrade():
			var choice: Dictionary = ai_reward.choose_upgrade(bonus_rarity, state, _strategy)
			if choice.upgrade_id != "":
				card.attach_upgrade(choice.upgrade_id)
				_merge_upgrades.append({
					"round": state.round_num,
					"card_id": card.get_base_id(),
					"upgrade_id": choice.upgrade_id,
					"rarity": bonus_rarity,
				})
	)

	var rounds_played := 0

	for round_num in range(1, Enums.MAX_ROUNDS + 1):
		state.round_num = round_num
		Talisman.init_round_state(state)

		# Reset round state for all cards + apply genome activation cap overrides.
		# Unconditional assignment so a later round whose genome returns -1 for
		# this card clears the prior cap (previous template-mutation path
		# inherited stale values).
		for card in state.get_active_board():
			var c: CardInstance = card as CardInstance
			c.reset_round()
			c.max_activation_override = _genome.get_activation_cap(c.get_base_id())
		for card in state.bench:
			if card != null:
				(card as CardInstance).reset_round()

		# ---- BUILD ----
		shop.refresh_shop()
		ai.play_build_phase(state, shop)

		# ---- UPGRADE SHOP (테라진 상점, ShopLv >= 2) ----
		if state.shop_level >= 2:
			var offered := _AIRewardScript.roll_upgrade_shop(rng)
			var bought: Array[Dictionary] = ai_reward.buy_upgrades(state, offered, _strategy)
			_upgrades_purchased.append_array(bought)

		# ---- Propagate boss reward effects before chain ----
		# Activation bonus from r8_3/r12_3 — route through chain_engine.activation_bonus
		# (matches game_manager.gd), no template mutation.
		chain_engine.activation_bonus = BossReward.get_activation_bonus(state)
		# Enhance amp from r4_5
		var enhance_amp: float = BossReward.get_enhance_amp(state)
		if enhance_amp > 1.0:
			chain_engine.enhance_multiplier = Talisman.get_enhance_multiplier(state) * enhance_amp
		# Bonus spawn chance from r4_3
		if BossReward.has_reward(state, "r4_3"):
			chain_engine.bonus_spawn_chance = maxf(
				Commander.get_bonus_spawn_chance(state), 0.5)
			chain_engine.propagate_bonus_spawn()
		# Auto-conscript from r4_6: +1 unit per card per round
		if BossReward.has_reward(state, "r4_6"):
			for card in state.get_active_board():
				(card as CardInstance).spawn_random(rng)

		# ---- CHAIN ----
		_chain_event_count = 0
		_cross_activations = 0
		_total_activations = 0
		state.round_rerolls = 0
		# ne_council 보너스 평가 (game_manager._evaluate_council_field_bonus 와 동일 로직)
		_sim_evaluate_council_field_bonus(state)
		var active_board := state.get_active_board()
		var chain_result := chain_engine.run_growth_chain(active_board, false)
		state.gold += chain_result["gold_earned"]
		state.terazin += chain_result["terazin_earned"]
		# ne_clone_seed RS 복제본을 벤치에 추가 (chain_result.clones_to_bench)
		var sim_clones: Array = chain_result.get("clones_to_bench", [])
		for clone_spec in sim_clones:
			var clone_tid: String = clone_spec.get("template_id", "")
			if clone_tid == "":
				continue
			var clone_inst: CardInstance = CardInstance.create(clone_tid)
			if clone_inst != null:
				state.add_to_bench(clone_inst)

		# ---- BATTLE ----
		# Persistent + battle_start
		chain_engine.process_persistent(active_board)
		var bs_result := chain_engine.process_battle_start(active_board)
		state.gold += bs_result["gold"]
		state.terazin += bs_result["terazin"]

		# r12_6: 50+ units → ATK ×1.5, AS ×1.3
		if BossReward.has_reward(state, "r12_6"):
			for card in active_board:
				var c: CardInstance = card as CardInstance
				if c.get_total_units() >= 50:
					c.temp_mult_buff(1.5)
					c.upgrade_as_mult *= (1.0 / 1.3)  # Lower AS value = faster

		# Collector ATK bonus
		var collector_bonus: float = Commander.calc_collector_atk_bonus(state)
		if collector_bonus > 0.0:
			for card in active_board:
				(card as CardInstance).temp_mult_buff(1.0 + collector_bonus)

		# Materialize army
		var ally_data := _materialize_army(state)

		# Generate enemies using genome parameters
		var enemy_data: Array = _generate_enemies(round_num, rng)

		# War drum
		var drum_reduction: float = Talisman.calc_war_drum_reduction(
			state, ally_data.size(), enemy_data.size())
		if drum_reduction > 0.0:
			for e in enemy_data:
				e["atk"] *= (1.0 - drum_reduction)

		# Run combat
		var combat_result: Dictionary
		if ally_data.is_empty():
			combat_result = {
				"player_won": false,
				"ally_survived": 0,
				"enemy_survived": enemy_data.size(),
				"ticks": 0,
			}
		else:
			var engine := CombatEngine.new()
			engine.headless = true
			engine.setup(ally_data, enemy_data)
			while engine.tick():
				pass
			combat_result = {
				"player_won": engine.team.size() > 0 and _count_alive(engine, 1) > 0 and _count_alive(engine, 0) == 0,
				"ally_survived": _count_alive(engine, 1),
				"enemy_survived": _count_alive(engine, 0),
				"ticks": engine.get_tick(),
			}

		# Clear temp buffs
		for card in active_board:
			(card as CardInstance).clear_temp_buffs()
			(card as CardInstance).shield_hp_pct = 0.0

		# Post-combat
		var won: bool = combat_result["player_won"]
		ai.record_battle_result(won)
		if _tracer != null and _tracer.enabled:
			_tracer.emit({"t": "battle", "round": round_num, "won": won,
				"hp_after": state.hp,
				"ally_survived": combat_result["ally_survived"],
				"enemy_survived": combat_result["enemy_survived"]})
		var pc_result := chain_engine.process_post_combat(active_board, won)
		state.gold += pc_result["gold"]
		state.terazin += pc_result["terazin"]

		# ---- BOSS REWARD (R4, R8, R12 보스 승리 시) ----
		var is_boss := round_num in [4, 8, 12]
		if is_boss and won:
			_apply_boss_reward(round_num, state, ai_reward, rng, chain_engine)
		# r8_6: 승리 시 전체 ATK +3% (영구 누적)
		if won and BossReward.has_reward(state, "r8_6"):
			for card in state.get_active_board():
				(card as CardInstance).multiply_stats(0.03, 0.0)

		# ---- RECORD METRICS ----
		var card_cps: Array = []
		var total_units := 0
		var round_activations := 0
		var round_max_activations := 0
		for card in active_board:
			var c: CardInstance = card as CardInstance
			var cp: float = c.get_total_atk() + c.get_total_hp()
			card_cps.append(cp)
			total_units += c.get_total_units()
			round_activations += c.activations_used
			var max_act: int = c.template.get("max_activations", -1)
			if max_act > 0:
				round_max_activations += max_act

		_round_data.append({
			"round_num": round_num,
			"battle_won": won,
			"ally_survived": combat_result["ally_survived"],
			"enemy_survived": combat_result["enemy_survived"],
			"total_player_units": total_units,
			"total_enemy_units": enemy_data.size(),
			"card_cps": card_cps,
			"chain_events": _chain_event_count,
			"cross_activations": _cross_activations,
			"total_activations": round_activations,
			"max_activations": round_max_activations,
			"gold": state.gold,
			"board_size": active_board.size(),
		})

		# ---- SETTLEMENT ----
		if won:
			state.gold += 1  # Win bonus
		else:
			var damage: int = GameState.compute_defeat_damage(round_num, combat_result.get("enemy_survived", 1))
			state.hp -= damage

		# Income from genome
		var base_income: int = _genome.economy.base_income[round_num - 1]
		var interest: int = _calc_interest(state)
		state.gold += base_income + interest

		# Terazin
		state.terazin += _genome.economy.terazin_win if won else _genome.economy.terazin_lose

		# Boss reward settlement bonuses (r8_4)
		state.gold += BossReward.get_settlement_gold_bonus(state, won)
		state.terazin += BossReward.get_settlement_terazin_bonus(state, won)

		# Commander terazin
		var cmd_terazin: int = Commander.calc_settlement_terazin(state)
		state.terazin += cmd_terazin

		state.apply_levelup_discount()
		rounds_played = round_num

		if state.hp <= 0:
			break

	# ---- BUILD RESULT ----
	var final_deck: Array = []
	for card in state.get_active_board():
		var c: CardInstance = card as CardInstance
		var tmpl: Dictionary = CardDB.get_template(c.get_base_id())
		final_deck.append({
			"card_id": c.get_base_id(),
			"star_level": c.star_level,
			"theme": tmpl.get("theme", Enums.CardTheme.NEUTRAL),
			"position": state.board.find(card),
		})

	return {
		"rounds_played": rounds_played,
		"won": state.hp > 0,
		"final_hp": state.hp,
		"strategy": _strategy,
		"round_data": _round_data,
		"final_deck": final_deck,
		"purchase_log": _purchase_log,
		"merge_events": _merge_events,
		"merge_upgrades": _merge_upgrades,
		"boss_rewards_applied": _boss_rewards_applied,
		"upgrades_purchased": _upgrades_purchased,
	}


## Apply boss reward after defeating a boss.
func _apply_boss_reward(boss_round: int, state: GameState,
		ai_reward: RefCounted, rng: RandomNumberGenerator,
		chain_engine: ChainEngine) -> void:
	var choices := BossRewardDB.roll_choices(boss_round, 4, rng)
	if choices.is_empty():
		return

	var decision: Dictionary = ai_reward.choose_boss_reward(choices, state, _strategy)
	var reward_id: String = decision.reward_id
	if reward_id == "":
		return

	var data: Dictionary = BossRewardDB.get_data(reward_id)
	var needs_target: int = data.get("needs_target", 0)

	if needs_target == 0:
		BossReward.apply_no_target(reward_id, state, rng)
	elif needs_target == 1:
		var target: CardInstance = decision.target_card
		if target:
			BossReward.apply_with_target(reward_id, state, target, rng)
			# Handle upgrade choice for r8_1, r12_7
			var upgrade_choice: String = data.get("needs_upgrade_choice", "")
			if upgrade_choice == "epic" and target.can_attach_upgrade():
				var uc: Dictionary = ai_reward.choose_upgrade(
					Enums.UpgradeRarity.EPIC, state, _strategy)
				if uc.upgrade_id != "":
					target.attach_upgrade(uc.upgrade_id)
		else:
			BossReward.apply_no_target(reward_id, state, rng)
	elif needs_target == 2:
		# r12_1: 2 cards each get ★ upgrade
		for tc in decision.target_cards:
			if tc:
				BossReward.apply_with_target(reward_id, state, tc, rng)

	_boss_rewards_applied.append({
		"round": state.round_num,
		"reward_id": reward_id,
		"choices": choices,
	})

	# Propagate structural changes immediately
	# r4_3 spawn bonus
	if reward_id == "r4_3":
		chain_engine.bonus_spawn_chance = maxf(
			chain_engine.bonus_spawn_chance, 0.5)
		chain_engine.propagate_bonus_spawn()
	# r4_5 enhance amp
	if reward_id == "r4_5":
		chain_engine.enhance_multiplier *= 1.5


## Chain event handler for cross-activation tracking.
func _on_chain_event(source_idx: int, target_idx: int,
		_layer1: int, _layer2: int, _action: String) -> void:
	_chain_event_count += 1
	_total_activations += 1
	if source_idx != target_idx:
		_cross_activations += 1


## Materialize board cards into flat unit array for CombatEngine.
func _materialize_army(state: GameState) -> Array:
	var units: Array = []
	for card in state.get_active_board():
		var c: CardInstance = card as CardInstance
		var card_mechanics := c.get_all_mechanics()
		# 증기 이자기 ★2/★3: 리롤 횟수 × ATK 버프 (최대 5회분)
		var reroll_buff_mult := 1.0
		if c.get_base_id() == "sp_interest" and c.star_level >= 2:
			var rerolls := mini(state.round_rerolls, 5)
			var buff_pct: float = 0.05 if c.star_level == 2 else 0.08
			reroll_buff_mult = 1.0 + buff_pct * rerolls
		for s in c.stacks:
			var ut: Dictionary = s["unit_type"]
			var eff_atk := c.eff_atk_for(s)
			var eff_hp := c.eff_hp_for(s)
			for _n in s["count"]:
				units.append({
					"atk": eff_atk * reroll_buff_mult,
					"hp": eff_hp,
					"attack_speed": ut["attack_speed"] * c.upgrade_as_mult,
					"range": ut["range"] + c.upgrade_range + c.theme_state.get("range_bonus", 0),
					"move_speed": ut["move_speed"] + c.upgrade_move_speed,
					"def": c.upgrade_def,
					"mechanics": card_mechanics,
					"radius": 6.0,
				})
	return units


## Count alive units of a team in the combat engine.
func _count_alive(engine: CombatEngine, team_id: int) -> int:
	var count := 0
	for i in engine.count:
		if engine.alive[i] == 1 and engine.team[i] == team_id:
			count += 1
	return count


## Generate enemies using genome parameters (composition, stats, boss scaling, CP curve).
func _generate_enemies(round_num: int, rng: RandomNumberGenerator) -> Array:
	# Delegated to EnemyDB.generate (single source of truth for play+sim).
	return _enemy_db.generate(round_num, rng, _genome)


## Calculate interest — state에 주입된 genome 값 사용 (SSOT: game_state.calc_interest()).
func _calc_interest(state: GameState) -> int:
	return state.calc_interest()


## ne_council 평의회 보너스 평가 — game_manager._evaluate_council_field_bonus 와 동일 로직.
## 보드에 ne_council + 5테마 모두 존재 시 field_slots +1 활성, 깨지면 -1.
## Phase 3b-2b: sim 동작 일관성 (live game 동일 로직, omni-theme 인식).
func _sim_evaluate_council_field_bonus(state: GameState) -> void:
	var has_council := false
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
		if ci.get_base_id() == "ne_council":
			has_council = true
	var should_be_active := has_council and themes_seen.size() >= 5
	if should_be_active and not state.council_field_bonus_active:
		state.field_slots = mini(state.field_slots + 1, Enums.MAX_FIELD_SLOTS)
		state.council_field_bonus_active = true
	elif (not should_be_active) and state.council_field_bonus_active:
		state.field_slots = maxi(state.field_slots - 1, 0)
		state.council_field_bonus_active = false
