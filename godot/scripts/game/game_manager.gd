extends Node
## Game Manager — Phase FSM. BUILD → CHAIN → BATTLE → SETTLEMENT.

enum Phase { INIT, BUILD, CHAIN, BATTLE, SETTLEMENT }

var current_phase: Phase = Phase.INIT
var game_state: GameState
var chain_engine: ChainEngine
var _battle_rng: RandomNumberGenerator
var _last_battle_won: bool = false

@onready var build_phase: Control = $BuildPhase
@onready var chain_visual: Control = $ChainVisual
@onready var battle_phase: Node2D = $BattlePhase
@onready var battle_result_popup: ColorRect = $UILayer/BattleResultPopup
@onready var game_over_popup: ColorRect = $UILayer/GameOverPopup
@onready var upgrade_choice_popup: ColorRect = $UILayer/UpgradeChoicePopup


func _ready() -> void:
	print("[GameManager] Warforge started.")
	print("[GameManager] Units: %d, Cards: %d" % [
		UnitDB.get_all_ids().size(), CardDB.get_all_ids().size()])

	game_state = GameState.new()
	chain_engine = ChainEngine.new()
	chain_engine.set_seed(42)
	_battle_rng = RandomNumberGenerator.new()
	_battle_rng.seed = 42

	_setup_test_board()

	upgrade_choice_popup.setup(_battle_rng)
	build_phase.setup(game_state, _battle_rng)
	build_phase.set_upgrade_choice_popup(upgrade_choice_popup)
	build_phase.build_confirmed.connect(_on_build_confirmed)
	build_phase.sell_performed.connect(_on_sell_performed)
	build_phase.merge_performed.connect(_on_merge_performed)
	chain_visual.setup(build_phase._field_visuals)
	chain_visual.connect_engine(chain_engine)
	battle_phase.battle_finished.connect(_on_battle_finished)
	game_over_popup.restart_requested.connect(_on_restart)

	_enter_phase(Phase.BUILD)


func _setup_test_board() -> void:
	game_state.gold = 10
	game_state.terazin = 2
	game_state.round_num = 1

	var test_cards := ["sp_assembly", "sp_workshop", "sp_circulator", "sp_line"]
	for i in test_cards.size():
		var card := CardInstance.create(test_cards[i])
		if card != null:
			game_state.board[i] = card

	var bench_cards := ["ne_earth_echo", "ne_wanderers", "ne_mana_crystal"]
	for i in bench_cards.size():
		var card := CardInstance.create(bench_cards[i])
		if card != null:
			game_state.bench[i] = card


func _enter_phase(phase: Phase) -> void:
	current_phase = phase
	match phase:
		Phase.BUILD:
			build_phase.visible = true
			battle_phase.stop()
			chain_visual.clear_links()
			build_phase.refresh_shop()
			print("[Phase] BUILD — R%d | Gold:%d" % [game_state.round_num, game_state.gold])
		Phase.CHAIN:
			_run_chain()
		Phase.BATTLE:
			_run_battle()
		Phase.SETTLEMENT:
			_run_settlement()


func _run_chain() -> void:
	chain_visual.clear_links()

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

	build_phase.visible = true
	await get_tree().create_timer(1.0).timeout
	_enter_phase(Phase.BATTLE)


func _run_battle() -> void:
	build_phase.visible = false
	chain_visual.visible = false

	# Apply BATTLE_START effects (buffs, shields)
	_apply_battle_start_effects()

	var ally_data := _materialize_army()
	var enemy_db := preload("res://core/data/enemy_db.gd")
	var enemy_data: Array = enemy_db.generate(game_state.round_num, _battle_rng)

	if ally_data.is_empty():
		print("[Battle] No allies, auto-loss")
		_on_battle_finished({"player_won": false, "ally_survived": 0, "enemy_survived": enemy_data.size()})
		return

	print("[Battle] R%d: %d allies vs %d enemies" % [game_state.round_num, ally_data.size(), enemy_data.size()])
	battle_phase.start_battle(ally_data, enemy_data)


## Apply BATTLE_START card effects (shields, buffs).
func _apply_battle_start_effects() -> void:
	var active := game_state.get_active_board()
	for card in active:
		var c: CardInstance = card
		var timing: int = c.template.get("trigger_timing", -1)
		if timing != Enums.TriggerTiming.BATTLE_START:
			continue
		# Execute effects directly (not through chain engine)
		for eff in c.template.get("effects", []):
			var action: String = eff.get("action", "")
			match action:
				"buff_pct":
					var tag_filter = eff.get("unit_tag_filter", "")
					if tag_filter == "":
						tag_filter = null
					c.temp_buff(tag_filter, eff.get("buff_atk_pct", 0.0))
				"shield_pct":
					c.shield_hp_pct += eff.get("shield_hp_pct", 0.0)


## Convert board CardInstances into flat unit arrays for combat engine.
func _materialize_army() -> Array:
	var units: Array = []
	var active := game_state.get_active_board()
	for card in active:
		var c: CardInstance = card
		var card_mechanics := c.get_all_mechanics()
		for s in c.stacks:
			var ut: Dictionary = s["unit_type"]
			var eff_atk := c.eff_atk_for(s)
			var eff_hp := c.eff_hp_for(s)
			for _n in s["count"]:
				units.append({
					"atk": eff_atk,
					"hp": eff_hp,
					"attack_speed": ut["attack_speed"] * c.upgrade_as_mult,
					"range": ut["range"] + c.upgrade_range,
					"move_speed": ut["move_speed"] + c.upgrade_move_speed,
					"def": c.upgrade_def,
					"mechanics": card_mechanics,
					"radius": 6.0,
				})
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
		game_state.gold += gold_change
		print("[Settlement] Victory bonus: +1g")
	else:
		var damage: int = result.get("enemy_survived", 1)
		hp_change = -damage
		game_state.hp -= damage
		print("[Settlement] Took %d damage (enemy survived), HP=%d" % [damage, game_state.hp])

	# Apply POST_COMBAT effects (패배 성장 등)
	_apply_post_combat_effects(won)

	# Show battle result popup → wait for fade → then settlement
	battle_result_popup.show_result(won, result["ally_survived"], result["enemy_survived"],
		gold_change, hp_change)
	await get_tree().create_timer(2.0).timeout
	_enter_phase(Phase.SETTLEMENT)


## Apply POST_COMBAT / POST_COMBAT_DEFEAT / POST_COMBAT_VICTORY effects.
func _apply_post_combat_effects(won: bool) -> void:
	var active := game_state.get_active_board()
	for card in active:
		var c: CardInstance = card
		var timing: int = c.template.get("trigger_timing", -1)
		var should_fire := false

		match timing:
			Enums.TriggerTiming.POST_COMBAT:
				should_fire = true
			Enums.TriggerTiming.POST_COMBAT_DEFEAT:
				should_fire = not won
			Enums.TriggerTiming.POST_COMBAT_VICTORY:
				should_fire = won

		if not should_fire:
			continue

		var max_act: int = c.template.get("max_activations", -1)
		if max_act != -1 and c.activations_used >= max_act:
			continue
		c.activations_used += 1

		for eff in c.template.get("effects", []):
			var action: String = eff.get("action", "")
			match action:
				"grant_gold":
					game_state.gold += eff.get("gold_amount", 0)
					print("    POST: %s → +%dg" % [c.get_name(), eff.get("gold_amount", 0)])
				"enhance_pct":
					var tag_filter = eff.get("unit_tag_filter", "")
					if tag_filter == "":
						tag_filter = null
					c.enhance(tag_filter, eff.get("enhance_atk_pct", 0.0), eff.get("enhance_hp_pct", 0.0))
					print("    POST: %s → enhance +%.0f%%ATK" % [c.get_name(), eff.get("enhance_atk_pct", 0.0) * 100])
				"spawn":
					for _n in eff.get("spawn_count", 1):
						c.spawn_random(chain_engine._rng)
					print("    POST: %s → +%d units" % [c.get_name(), eff.get("spawn_count", 1)])


func _run_settlement() -> void:
	# Reset round state for all cards (activations, tenure)
	for card in game_state.get_active_board():
		(card as CardInstance).reset_round()
	for card in game_state.bench:
		if card != null:
			(card as CardInstance).reset_round()

	# Income (upgrade.md: R1~5=5g, R6~10=6g, R11~15=7g)
	var base_income := 5
	if game_state.round_num >= 11:
		base_income = 7
	elif game_state.round_num >= 6:
		base_income = 6
	var interest := game_state.calc_interest()
	game_state.gold += base_income + interest

	# Terazin (upgrade.md: 승리+2, 패배+1)
	var last_won: bool = _last_battle_won
	game_state.terazin += 2 if last_won else 1

	print("[Settlement] R%d done | +%dg(+%d interest) | Gold=%d HP=%d" % [
		game_state.round_num, base_income, interest, game_state.gold, game_state.hp])

	game_state.round_num += 1
	game_state.state_changed.emit()

	if game_state.hp <= 0:
		print("[Game] GAME OVER at round %d" % (game_state.round_num - 1))
		game_over_popup.show_result(false, game_state.round_num - 1, game_state.hp)
		return
	if game_state.round_num > Enums.MAX_ROUNDS:
		print("[Game] VICTORY! Run complete!")
		game_over_popup.show_result(true, Enums.MAX_ROUNDS, game_state.hp)
		return

	chain_visual.visible = true
	_enter_phase(Phase.BUILD)


## ON_SELL trigger: fire effects of cards with ON_SELL timing (e.g., sp_arsenal).
func _on_sell_performed(zone: String, idx: int) -> void:
	# ON_SELL cards react when ANY card is sold.
	var active := game_state.get_active_board()
	for card in active:
		var c: CardInstance = card
		if c.template.get("trigger_timing", -1) == Enums.TriggerTiming.ON_SELL:
			# Effects will be handled by theme systems (e.g., steampunk_system)
			print("  ON_SELL: %s triggered" % c.get_name())


## ON_MERGE trigger: fire effects of cards with ON_MERGE timing (e.g., ne_spirit_blessing).
func _on_merge_performed(merged_card: CardInstance) -> void:
	var active := game_state.get_active_board()
	for card in active:
		var c: CardInstance = card
		if c.template.get("trigger_timing", -1) == Enums.TriggerTiming.ON_MERGE:
			var max_act: int = c.template.get("max_activations", -1)
			if max_act != -1 and c.activations_used >= max_act:
				continue
			c.activations_used += 1
			for eff in c.template.get("effects", []):
				var action: String = eff.get("action", "")
				match action:
					"grant_terazin":
						game_state.terazin += eff.get("terazin_amount", 0)
						print("  ON_MERGE: %s → +%d terazin" % [c.get_name(), eff.get("terazin_amount", 0)])
					"spawn":
						var target: String = eff.get("target", "self")
						var count: int = eff.get("spawn_count", 1)
						var target_card: CardInstance = merged_card if target == "event_target" else c
						for _n in count:
							target_card.spawn_random(chain_engine._rng)
						print("  ON_MERGE: %s → +%d units to %s" % [c.get_name(), count, target_card.get_name()])
	game_state.state_changed.emit()


func _on_restart() -> void:
	get_tree().reload_current_scene()


func _on_build_confirmed() -> void:
	if current_phase == Phase.BUILD:
		_enter_phase(Phase.CHAIN)


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
					if build_phase.reroll():
						print("[Reroll] -%dg, Gold=%d" % [Enums.REROLL_COST, game_state.gold])
					else:
						print("[Reroll] Not enough gold")
			KEY_T:
				if current_phase == Phase.BUILD:
					if build_phase.reroll_upgrades():
						print("[UpgradeReroll] -%dt, Terazin=%d" % [Enums.UPGRADE_REROLL_COST, game_state.terazin])
					else:
						print("[UpgradeReroll] Not available or not enough terazin")
