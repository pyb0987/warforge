class_name DiagnosticGame
extends RefCounted
## Runs a single game with verbose per-round output for pattern extraction.

var _enemy_db = preload("res://core/data/enemy_db.gd")
const _AIRewardScript = preload("res://sim/ai_reward_logic.gd")


func run_game(args: Dictionary) -> void:
	var strat: String = args.get("strategy", "adaptive")
	var seed_val: int = args.get("seed", 42)
	var genome_path: String = args.get("genome", "res://sim/default_genome.json")

	var genome := Genome.load_file(genome_path)
	if genome == null:
		printerr("ERROR: Failed to load genome")
		return

	print("=" .repeat(72))
	print("DIAGNOSTIC GAME — strategy=%s  seed=%d" % [strat, seed_val])
	print("=" .repeat(72))

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	var state := GameState.new()
	state.gold = 10
	state.terazin = 2
	state.round_num = 1
	state.commander_type = Enums.CommanderType.NONE
	state.talisman_type = Enums.TalismanType.NONE
	state.levelup_current_cost = genome.get_levelup_cost(2)
	# 카드 풀 고갈 (OBS-049)
	state.card_pool = CardPool.new()
	state.card_pool.init_pool(genome.pool_sizes if genome else {})
	Talisman.init_run_state(state)

	var chain_engine := ChainEngine.new()
	chain_engine.set_seed(seed_val)
	chain_engine.adjacency_range = Commander.get_adjacency_range(state)
	chain_engine.bonus_spawn_chance = Commander.get_bonus_spawn_chance(state)
	chain_engine.propagate_bonus_spawn()
	chain_engine.enhance_multiplier = Talisman.get_enhance_multiplier(state)
	chain_engine.propagate_card_effects(genome.card_effects)

	var shop := ShopLogic.new()
	shop.setup(state, rng, genome)

	var ai := AIAgent.new(strat, rng, genome)
	var ai_reward := _AIRewardScript.new()

	# Merge bonus upgrade handler
	shop.card_merged.connect(func(card: CardInstance, old_star: int, new_star: int):
		var bonus_rarity := -1
		if old_star == 1 and new_star == 2:
			bonus_rarity = Enums.UpgradeRarity.RARE
		elif old_star == 2 and new_star == 3:
			bonus_rarity = Enums.UpgradeRarity.EPIC
		if bonus_rarity >= 0 and card.can_attach_upgrade():
			var choice: Dictionary = ai_reward.choose_upgrade(bonus_rarity, state, strat)
			if choice.upgrade_id != "":
				card.attach_upgrade(choice.upgrade_id)
				print("  [MERGE BONUS] %s ★%d → attached %s (%s)" % [
					card.get_name(), new_star, choice.upgrade_id,
					"rare" if bonus_rarity == Enums.UpgradeRarity.RARE else "epic"])
	)

	for round_num in range(1, Enums.MAX_ROUNDS + 1):
		state.round_num = round_num
		Talisman.init_round_state(state)

		# -1 clears any prior override (see headless_runner for rationale).
		for card in state.get_active_board():
			var c: CardInstance = card as CardInstance
			c.reset_round()
			c.max_activation_override = genome.get_activation_cap(c.get_base_id())
		for card in state.bench:
			if card != null:
				(card as CardInstance).reset_round()

		print("\n" + "-" .repeat(72))
		print("ROUND %d  |  HP=%d  Gold=%d  Terazin=%d  ShopLv=%d  LvUpCost=%d" % [
			round_num, state.hp, state.gold, state.terazin,
			state.shop_level, state.levelup_current_cost])
		print("-" .repeat(72))

		_print_section("BOARD before build")
		_print_board(state)

		shop.refresh_shop()
		_print_section("SHOP offerings")
		for i in shop.offered_ids.size():
			var cid: String = shop.offered_ids[i]
			if cid == "":
				continue
			var tmpl: Dictionary = CardDB.get_template(cid)
			print("  [%d] %s (T%d %s %s) cost=%dg" % [
				i, tmpl.get("name", cid), tmpl.get("tier", 1),
				_theme_name(tmpl.get("theme", 0)),
				_timing_name(tmpl.get("trigger_timing", 0)),
				tmpl.get("cost", 99)])

		var gold_before := state.gold
		var board_snap := _snap(state.board)
		var bench_snap := _snap(state.bench)
		ai.play_build_phase(state, shop)

		print("\n[BUILD] spent %dg (%d -> %d)  ShopLv=%d" % [
			gold_before - state.gold, gold_before, state.gold, state.shop_level])
		var added := _diff(board_snap, bench_snap, _snap(state.board), _snap(state.bench))
		var removed := _diff(_snap(state.board), _snap(state.bench), board_snap, bench_snap)
		if not added.is_empty():
			print("  Bought: %s" % ", ".join(added))
		if not removed.is_empty():
			print("  Sold:   %s" % ", ".join(removed))

		# --- UPGRADE SHOP ---
		if state.shop_level >= 2:
			var offered := _AIRewardScript.roll_upgrade_shop(rng)
			var bought: Array[Dictionary] = ai_reward.buy_upgrades(
				state, offered, strat)
			if not bought.is_empty():
				print("\n[UPGRADE SHOP] %d purchased (terazin=%d)" % [
					bought.size(), state.terazin])
				for item in bought:
					print("  %s → %s (cost=%d)" % [
						item.get("id", "?"), item.get("target", "?"),
						item.get("cost", 0)])

		_print_section("BOARD after build")
		_print_board(state)

		# --- Propagate boss reward effects before chain ---
		# Activation bonus routed through chain_engine.activation_bonus (matches
		# game_manager.gd:632 and headless_runner) — no template mutation.
		chain_engine.activation_bonus = BossReward.get_activation_bonus(state)
		var enh_amp: float = BossReward.get_enhance_amp(state)
		if enh_amp > 1.0:
			chain_engine.enhance_multiplier = enh_amp

		# --- CHAIN ---
		var active := state.get_active_board()

		# Snapshot before chain for delta comparison
		var pre_stats: Array = []
		for card in active:
			var c: CardInstance = card as CardInstance
			pre_stats.append({
				"name": c.get_name(), "units": c.get_total_units(),
				"atk": c.get_total_atk(), "hp": c.get_total_hp(),
				"trees": c.theme_state.get("trees", 0),
			})

		var cr := chain_engine.run_growth_chain(active, true)
		state.gold += cr["gold_earned"]
		state.terazin += cr["terazin_earned"]
		print("\n[CHAIN] events=%d  gold+=%d  terazin+=%d" % [
			cr["chain_count"], cr["gold_earned"], cr["terazin_earned"]])

		_print_section("STATS after chain (delta)")
		for i in active.size():
			var c: CardInstance = active[i] as CardInstance
			var ma: int = c.get_max_activations()
			var pre: Dictionary = pre_stats[i]
			var d_units: int = c.get_total_units() - pre["units"]
			var d_atk: float = c.get_total_atk() - pre["atk"]
			var d_hp: float = c.get_total_hp() - pre["hp"]
			var d_trees: int = c.theme_state.get("trees", 0) - pre["trees"]
			var delta_parts: Array = []
			if d_units != 0:
				delta_parts.append("units%+d" % d_units)
			if absf(d_atk) > 0.01:
				delta_parts.append("ATK%+.1f" % d_atk)
			if absf(d_hp) > 0.01:
				delta_parts.append("HP%+.1f" % d_hp)
			if d_trees != 0:
				delta_parts.append("🌳%+d" % d_trees)
			var delta_str := " | Δ: " + ", ".join(delta_parts) if not delta_parts.is_empty() else ""
			print("  %s S%d: units=%d ATK=%.0f HP=%.0f act=%d/%s%s" % [
				c.get_name(), c.star_level, c.get_total_units(),
				c.get_total_atk(), c.get_total_hp(), c.activations_used,
				str(ma) if ma > 0 else "inf", delta_str])

		# --- BATTLE ---
		chain_engine.process_persistent(active)
		var bsr := chain_engine.process_battle_start(active)
		state.gold += bsr["gold"]
		state.terazin += bsr["terazin"]

		var collector_bonus: float = Commander.calc_collector_atk_bonus(state)
		if collector_bonus > 0.0:
			for card in active:
				(card as CardInstance).temp_mult_buff(1.0 + collector_bonus)

		var allies := _materialize(state)
		var enemies := _gen_enemies(round_num, rng, genome)

		var drum := Talisman.calc_war_drum_reduction(state, allies.size(), enemies.size())
		if drum > 0.0:
			for e in enemies:
				e["atk"] *= (1.0 - drum)

		var acp := 0.0
		for u in allies:
			acp += u["atk"] / maxf(u.get("attack_speed", 1.0), 0.1) * u["hp"]
		var ecp := 0.0
		for u in enemies:
			ecp += u["atk"] / maxf(u.get("attack_speed", 1.0), 0.1) * u["hp"]

		print("\n[BATTLE] %d allies (CP=%.0f) vs %d enemies (CP=%.0f)" % [
			allies.size(), acp, enemies.size(), ecp])

		var result: Dictionary
		if allies.is_empty():
			result = {"player_won": false, "ally_survived": 0,
				"enemy_survived": enemies.size()}
		else:
			var eng := CombatEngine.new()
			eng.setup(allies, enemies)
			while eng.tick():
				pass
			result = {
				"player_won": eng.team.size() > 0 and _alive(eng, 1) > 0 and _alive(eng, 0) == 0,
				"ally_survived": _alive(eng, 1),
				"enemy_survived": _alive(eng, 0),
			}

		for card in active:
			(card as CardInstance).clear_temp_buffs()
			(card as CardInstance).shield_hp_pct = 0.0

		var won: bool = result["player_won"]
		var pcr := chain_engine.process_post_combat(active, won)
		state.gold += pcr["gold"]
		state.terazin += pcr["terazin"]

		if won:
			print("  -> WIN (%d survived)" % result["ally_survived"])
		else:
			print("  -> LOSS (%d enemies left)" % result["enemy_survived"])

		# --- BOSS REWARD ---
		var is_boss_round := round_num in [4, 8, 12]
		if is_boss_round and won:
			var choices := BossRewardDB.roll_choices(round_num, 4, rng)
			if not choices.is_empty():
				var decision: Dictionary = ai_reward.choose_boss_reward(
					choices, state, strat)
				var reward_id: String = decision.reward_id
				if reward_id != "":
					var data: Dictionary = BossRewardDB.get_data(reward_id)
					var needs_target: int = data.get("needs_target", 0)
					if needs_target == 0:
						BossReward.apply_no_target(reward_id, state, rng)
					elif needs_target >= 1:
						var target: CardInstance = decision.target_card
						if target:
							BossReward.apply_with_target(
								reward_id, state, target, rng)
						else:
							BossReward.apply_no_target(reward_id, state, rng)
					if needs_target == 2:
						for tc in decision.target_cards:
							if tc and tc != decision.target_card:
								BossReward.apply_with_target(
									reward_id, state, tc, rng)
					state.boss_rewards.append(reward_id)
					print("\n[BOSS REWARD] R%d choices=%s → picked %s" % [
						round_num, str(choices), reward_id])
					if decision.target_card:
						print("  target: %s" % decision.target_card.get_name())

		# --- SETTLEMENT ---
		if won:
			state.gold += 1
			state.gold += BossReward.get_settlement_gold_bonus(state, true)
			state.terazin += BossReward.get_settlement_terazin_bonus(state, true)
		else:
			state.hp -= result.get("enemy_survived", 1)

		var inc: int = genome.economy.base_income[round_num - 1]
		var interest: int = mini(state.gold / 5 * genome.economy.interest_per_5g,
			genome.economy.max_interest)
		state.gold += inc + interest
		state.terazin += genome.economy.terazin_win if won else genome.economy.terazin_lose
		state.terazin += Commander.calc_settlement_terazin(state)
		state.apply_levelup_discount()

		print("[SETTLE] income=%d interest=%d -> Gold=%d HP=%d" % [
			inc, interest, state.gold, state.hp])

		if state.hp <= 0:
			print("\n*** DEFEATED at Round %d ***" % round_num)
			break

	if state.hp > 0:
		print("\n*** VICTORY — HP=%d ***" % state.hp)

	print("\n" + "=" .repeat(72))
	print("FINAL BOARD")
	_print_board(state)


# ================================================================
func _print_section(title: String) -> void:
	print("\n[%s]" % title)

func _print_board(state: GameState) -> void:
	var any := false
	for i in state.board.size():
		if state.board[i] != null:
			var c: CardInstance = state.board[i]
			print("  board[%d] %s S%d (%s T%d) units=%d ATK=%.0f HP=%.0f" % [
				i, c.get_name(), c.star_level,
				_theme_name(c.template.get("theme", 0)),
				c.template.get("tier", 1), c.get_total_units(),
				c.get_total_atk(), c.get_total_hp()])
			any = true
	for i in state.bench.size():
		if state.bench[i] != null:
			var c: CardInstance = state.bench[i]
			print("  bench[%d] %s S%d" % [i, c.get_name(), c.star_level])
			any = true
	if not any:
		print("  (empty)")

func _snap(arr: Array) -> Dictionary:
	var d := {}
	for card in arr:
		if card != null:
			var cid: String = (card as CardInstance).get_base_id()
			d[cid] = d.get(cid, 0) + 1
	return d

func _diff(a_b: Dictionary, a_n: Dictionary, b_b: Dictionary, b_n: Dictionary) -> Array:
	var a := {}
	for k in a_b:
		a[k] = a.get(k, 0) + a_b[k]
	for k in a_n:
		a[k] = a.get(k, 0) + a_n[k]
	var b := {}
	for k in b_b:
		b[k] = b.get(k, 0) + b_b[k]
	for k in b_n:
		b[k] = b.get(k, 0) + b_n[k]
	var out: Array = []
	for k in b:
		for _i in b[k] - a.get(k, 0):
			out.append(k)
	return out

func _theme_name(t: int) -> String:
	match t:
		1: return "SP"
		2: return "DR"
		3: return "PR"
		4: return "ML"
		_: return "NE"

func _timing_name(t: int) -> String:
	match t:
		0: return "RS"
		1: return "OE"
		2: return "BS"
		3: return "CA"
		4: return "PC"
		5: return "PD"
		6: return "PV"
		7: return "RR"
		8: return "MG"
		9: return "SL"
		10: return "CD"
		11: return "PS"
		_: return "??"

func _materialize(state: GameState) -> Array:
	var units: Array = []
	for card in state.get_active_board():
		var c: CardInstance = card as CardInstance
		var mechs := c.get_all_mechanics()
		for s in c.stacks:
			var ut: Dictionary = s["unit_type"]
			for _n in s["count"]:
				units.append({
					"atk": c.eff_atk_for(s), "hp": c.eff_hp_for(s),
					"attack_speed": ut["attack_speed"] * c.upgrade_as_mult,
					"range": ut["range"] + c.upgrade_range + c.theme_state.get("range_bonus", 0),
					"move_speed": ut["move_speed"] + c.upgrade_move_speed,
					"def": c.upgrade_def, "mechanics": mechs, "radius": 6.0,
				})
	return units

func _gen_enemies(rn: int, rng: RandomNumberGenerator, genome: Genome) -> Array:
	var is_boss := rn in [4, 8, 12, 15]
	var preset: String
	if is_boss:
		match rn:
			4: preset = "swarm"
			8: preset = "heavy"
			12: preset = "sniper"
			_: preset = "balanced"
	else:
		preset = ["swarm", "heavy", "sniper", "balanced"][rng.randi_range(0, 3)]

	var comp: Dictionary = genome.get_enemy_comp(preset)
	var units: Array = []
	var cp_m: float = genome.enemy_cp_curve[rn - 1]

	for key in comp:
		if not key.ends_with("_base"):
			continue
		var tn: String = key.replace("_base", "")
		var cnt: int = maxi(int(int(comp[key]) + rn * comp.get(tn + "_per_r", 0.0)), 1)
		var st: Dictionary = genome.get_enemy_stat(tn)
		var sm := 1.0
		if preset == "swarm" and tn == "ranged": sm = 0.8
		elif preset == "heavy" and tn == "melee": sm = 0.9
		elif preset == "heavy" and tn == "ranged": sm = 0.7
		elif preset == "sniper" and tn == "melee": sm = 0.8
		elif preset == "balanced" and tn == "swarm": sm = 0.9

		for _i in cnt:
			units.append({
				"atk": st.get("atk", 3.0) * cp_m * sm,
				"hp": st.get("hp", 20.0) * cp_m * sm,
				"attack_speed": st.get("as", 1.0),
				"range": _enemy_db.BASE.get(tn + "_range", 0),
				"move_speed": _enemy_db.BASE.get(tn + "_ms", 2),
				"radius": 6.0,
			})

	if is_boss:
		var bm: Dictionary = genome.get_boss_mult()
		for u in units:
			u["atk"] *= bm.get("atk_mult", 1.3)
			u["hp"] *= bm.get("hp_mult", 1.3)
	return units

func _alive(eng: CombatEngine, team: int) -> int:
	var c := 0
	for i in eng.count:
		if eng.alive[i] == 1 and eng.team[i] == team: c += 1
	return c
