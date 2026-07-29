extends GutTest
## End-to-end live-scene smoke for the main run flow.

const MainScene = preload("res://scenes/main.tscn")
const MetaProgressScript = preload("res://core/meta_progress.gd")
const LiveUiProbe = preload("res://tools/live_ui_probe.gd")
const TEST_META_PATH := "user://meta_progress_live_smoke_test.cfg"


func before_each() -> void:
	var progress = MetaProgressScript.new()
	assert_eq(progress.save(TEST_META_PATH), OK,
		"smoke test profile reset")


func test_live_run_start_reaches_build_phase() -> void:
	var main = await _start_main_to_build()

	assert_eq(main.current_phase, main.Phase.BUILD)
	assert_true(main.build_phase.visible, "BuildPhase visible after run setup")
	assert_false(main.run_start_screen.visible, "RunStartScreen hidden after start")
	assert_false(main.commander_select_popup.visible, "Commander popup closed")
	assert_false(main.talisman_select_popup.visible, "Talisman popup closed")
	assert_eq(main.game_state.commander_type, Enums.CommanderType.GAMBLER)
	assert_eq(main.game_state.talisman_type, Enums.TalismanType.FLINT)
	assert_eq(main._meta_progress.runs_started, 1)
	assert_false(main._meta_progress.should_show_tutorial(),
		"run start marks tutorial seen")
	var ui := LiveUiProbe.snapshot(main)
	var identity: Dictionary = ui.get("identity", {})
	var identity_text := str(identity.get("text", ""))
	assert_true(bool(identity.get("visible", false)),
		"commander/talisman identity HUD is visible in the live observer")
	assert_string_contains(identity_text, "커맨더:")
	assert_string_contains(identity_text, "도박꾼")
	assert_string_contains(identity_text, "부적:")
	assert_string_contains(identity_text, "부싯돌")
	assert_string_contains(identity_text, "첫 성장 효과 ×2 준비")
	assert_false(identity_text.contains("C:"),
		"live identity HUD avoids commander shorthand")
	assert_false(identity_text.contains("T:"),
		"live identity HUD avoids talisman shorthand")
	var identity_rect: Dictionary = identity.get("rect", {})
	assert_gt(float(identity_rect.get("w", 0.0)), 0.0)
	assert_gt(float(identity_rect.get("h", 0.0)), 0.0)
	var shop: Dictionary = ui.get("shop", {})
	var offer_ids: Array = shop.get("card_offer_ids", [])
	var offer_roles: Array = shop.get("card_offer_roles", [])
	assert_eq(offer_roles.size(), offer_ids.size(),
		"live observer binds one rendered role summary per shop offer")
	for i in offer_ids.size():
		if str(offer_ids[i]) == "":
			continue
		var summary: Dictionary = offer_roles[i]
		assert_eq(summary.get("slot_idx", -1), i)
		assert_eq(str(summary.get("card_id", "")), str(offer_ids[i]))
		assert_true(bool(summary.get("visible", false)),
			"shop role summary comes from a visible card face")
		assert_ne(str(summary.get("role_text", "")).strip_edges(), "",
			"shop offer exposes a compact role cue")
		var role_rect: Dictionary = summary.get("rect", {})
		assert_gt(float(role_rect.get("w", 0.0)), 0.0)
		assert_gt(float(role_rect.get("h", 0.0)), 0.0)


func test_live_two_faced_coin_marks_discount_and_markup_shop_slots() -> void:
	var main = await _start_main_to_build(Enums.TalismanType.TWO_FACED_COIN)

	assert_eq(main.game_state.talisman_type, Enums.TalismanType.TWO_FACED_COIN)
	assert_false(main.build_phase.shop._coin_slots.is_empty(),
		"Two-Faced Coin rolls shop modifier slots")
	var discount_idx: int = int(main.build_phase.shop._coin_slots.get("discount_idx", -1))
	var markup_idx: int = int(main.build_phase.shop._coin_slots.get("markup_idx", -1))
	assert_ne(discount_idx, markup_idx)
	assert_gte(discount_idx, 0)
	assert_gte(markup_idx, 0)

	var discount_visual = main.build_phase.shop._shop_slots[discount_idx]
	var markup_visual = main.build_phase.shop._shop_slots[markup_idx]
	assert_true(discount_visual.visible, "discount slot is visible")
	assert_true(markup_visual.visible, "markup slot is visible")
	assert_eq(discount_visual.get_shop_price_note(), "-50%")
	assert_eq(markup_visual.get_shop_price_note(), "+50%")
	assert_string_contains(discount_visual.get_face_tier_text(), "COIN -50%")
	assert_string_contains(markup_visual.get_face_tier_text(), "COIN +50%")

	var identity_text: String = main.build_phase.get_identity_text()
	assert_string_contains(identity_text, "커맨더:")
	assert_string_contains(identity_text, "부적:")
	assert_string_contains(identity_text, "양면 동전")
	assert_string_contains(identity_text, "할인 %d" % (discount_idx + 1))
	assert_string_contains(identity_text, "할증 %d" % (markup_idx + 1))
	assert_false(identity_text.contains("C:"))
	assert_false(identity_text.contains("T:"))


func test_live_merge_reward_popup_selection_attaches_upgrade() -> void:
	var main = await _start_main_to_build()
	_clear_run_cards(main)
	main.game_state.gold = 10
	main.game_state.bench[0] = CardInstance.create("sp_assembly")
	main.game_state.bench[1] = CardInstance.create("sp_assembly")
	main.game_state.state_changed.emit()
	await wait_process_frames(1)

	assert_gt(main.build_phase.shop._offered_ids.size(), 0,
		"live shop has at least one purchase slot")
	main.build_phase.shop._offered_ids[0] = "sp_assembly"
	main.build_phase.shop._coin_slots.clear()
	main.build_phase.shop._update_visuals()

	assert_true(main.build_phase.shop.try_purchase(0),
		"buying the third visible copy triggers the live merge signal")
	await wait_process_frames(2)

	assert_true(main.upgrade_choice_popup.visible,
		"★1→★2 merge opens the real upgrade reward popup")
	var ui := LiveUiProbe.snapshot(main)
	assert_eq(ui["active_modals"], [LiveUiProbe.UPGRADE_CHOICE],
		"merge reward popup owns the live UI")
	assert_true(ui["actionable"][LiveUiProbe.UPGRADE_CHOICE],
		"merge reward popup has an actionable selection")
	var choices: Array[String] = LiveUiProbe.choice_ids(main, LiveUiProbe.UPGRADE_CHOICE)
	assert_eq(choices.size(), 3,
		"merge reward popup offers three upgrades")
	var selected_upgrade: String = choices[0]
	var survivor: CardInstance = main.game_state.bench[0]
	assert_not_null(survivor)
	assert_eq(survivor.star_level, 2)
	assert_eq(survivor.upgrades.size(), 0,
		"merge reward waits for popup selection before attachment")

	assert_true(LiveUiProbe.select_choice(main, LiveUiProbe.UPGRADE_CHOICE, 0),
		"popup selection path accepts the visible merge reward")
	await wait_process_frames(2)

	ui = LiveUiProbe.snapshot(main)
	assert_false(ui["has_modal"],
		"merge reward selection returns modal ownership to build")
	assert_false(ui["chain_visible"],
		"merge reward selection does not leave chain feedback visible")
	assert_false(main.upgrade_choice_popup.visible,
		"merge reward popup closes through its own selection path")
	assert_eq(LiveUiProbe.choice_ids(main, LiveUiProbe.UPGRADE_CHOICE).size(), 0,
		"merge reward popup clears choices after selection")
	assert_eq(survivor.upgrades.size(), 1,
		"selected merge reward attaches to the survivor")
	assert_true(_card_has_upgrade_id(survivor, selected_upgrade),
		"the exact selected upgrade is attached through merge_bonus")
	assert_true(main.build_phase.visible,
		"build phase remains actionable after merge reward selection")


func test_live_first_build_shows_chain_feedback_before_battle() -> void:
	var main = await _start_main_to_build()
	main.chain_feedback_delay_sec = 0.01
	main.chain_feedback_delay_per_event_sec = 0.0
	main.game_state.board[0] = CardInstance.create("ne_wanderers")
	main.build_phase._refresh_all()

	main.build_phase.confirm_button.pressed.emit()

	assert_eq(main.current_phase, main.Phase.CHAIN,
		"BUILD COMPLETE enters visible chain phase before battle")
	assert_true(main.chain_visual.visible,
		"first growth chain feedback is visible")
	assert_string_contains(main.chain_visual.counter_label.text, "Triggers")
	await main.get_tree().create_timer(0.03).timeout
	assert_eq(main.current_phase, main.Phase.BATTLE,
		"test drains the short chain pause before cleanup")
	var ui := LiveUiProbe.snapshot(main)
	var battle_status: Dictionary = ui.get("battle_status", {})
	var battle_text := str(battle_status.get("text", ""))
	var battle_data: Dictionary = battle_status.get("data", {})
	assert_true(bool(battle_status.get("visible", false)),
		"battle start status is visible after real battle start")
	assert_string_contains(battle_text, "BATTLE R1")
	assert_string_contains(battle_text, "Start")
	assert_string_contains(battle_text, "Now")
	assert_eq(int(battle_data.get("round", 0)), 1)
	assert_gt(int(battle_data.get("ally_start", 0)), 0)
	assert_gt(int(battle_data.get("enemy_start", 0)), 0)
	assert_gte(int(battle_data.get("ally_remaining", -1)), 0)
	assert_gte(int(battle_data.get("enemy_remaining", -1)), 0)
	assert_lte(
		int(battle_data.get("ally_remaining", 0)),
		int(battle_data.get("ally_start", 0)))
	assert_lte(
		int(battle_data.get("enemy_remaining", 0)),
		int(battle_data.get("enemy_start", 0)))
	main.battle_phase.stop()


func test_live_chain_event_history_is_readable_before_battle() -> void:
	var main = await _start_main_to_build()
	main.chain_feedback_delay_sec = 0.03
	main.chain_feedback_delay_per_event_sec = 0.0
	main.game_state.board[0] = CardInstance.create("sp_assembly")
	main.game_state.board[1] = CardInstance.create("sp_workshop")
	main.build_phase._refresh_all()

	main.build_phase.confirm_button.pressed.emit()

	assert_eq(main.current_phase, main.Phase.CHAIN)
	assert_true(main.chain_visual.visible)
	assert_true(main.chain_visual.event_panel.visible,
		"real chain events open the readability panel")
	var log: String = main.chain_visual.get_event_log_text()
	assert_string_contains(log, "증기 조립소 -> 태엽 공방")
	assert_string_contains(log, "+Unit")
	assert_string_contains(log, "+Stats")
	assert_string_contains(log, "Complete:")
	assert_string_contains(main.chain_visual.counter_label.text, "Triggers:")
	var ui := LiveUiProbe.snapshot(main)
	assert_eq(ui["phase"], "CHAIN")
	assert_true(ui["layout_rects"].get("chain_event_panel", {}).get("visible", false),
		"observer exports visible chain event panel rect")
	assert_string_contains(ui["chain_feedback"].get("event_log_text", ""), "Complete:")
	await main.get_tree().create_timer(0.05).timeout
	assert_eq(main.current_phase, main.Phase.BATTLE)
	main.battle_phase.stop()

	await main._on_battle_finished({
		"player_won": true,
		"ally_survived": 1,
		"enemy_survived": 0,
	})

	assert_eq(main.current_phase, main.Phase.BUILD)
	assert_true(main.build_phase.is_last_chain_history_visible(),
		"next build keeps a reviewable last-chain history")
	var last_chain: String = main.build_phase.get_last_chain_history_text()
	assert_string_contains(last_chain, "Complete:")
	assert_string_contains(last_chain, "증기 조립소 -> 태엽 공방")
	ui = LiveUiProbe.snapshot(main)
	assert_true(ui["layout_rects"].get("last_chain_panel", {}).get("visible", false),
		"observer exports visible last-chain panel rect")
	assert_false(ui["layout_rects"].get("battle_status", {}).get("visible", false),
		"observer confirms battle status is hidden after returning to build")
	assert_true(ui["last_chain_history"].get("visible", false))


func test_live_chain_feedback_delay_scales_and_can_be_skipped_once() -> void:
	var main = await _start_main_to_build()
	main.chain_feedback_delay_sec = 0.12
	main.chain_feedback_delay_per_event_sec = 0.10
	main.chain_feedback_max_delay_sec = 0.25
	assert_almost_eq(main._get_chain_feedback_delay(1), 0.12, 0.001)
	assert_almost_eq(main._get_chain_feedback_delay(4), 0.25, 0.001)
	main.game_state.board[0] = CardInstance.create("sp_assembly")
	main.game_state.board[1] = CardInstance.create("sp_workshop")
	main.build_phase._refresh_all()

	main.build_phase.confirm_button.pressed.emit()

	assert_eq(main.current_phase, main.Phase.CHAIN)
	assert_true(main.skip_chain_feedback(),
		"manual skip advances out of the readable chain pause")
	assert_eq(main.current_phase, main.Phase.BATTLE)
	assert_false(main.skip_chain_feedback(),
		"skip is idempotent after the phase has already advanced")
	await main.get_tree().create_timer(0.28).timeout
	assert_eq(main.current_phase, main.Phase.BATTLE,
		"the original timer cannot advance the phase a second time")
	main.battle_phase.stop()


func test_live_battle_result_settlement_and_gameover_save_meta() -> void:
	var main = await _start_main_to_build()
	main.game_state.board[0] = CardInstance.create("sp_assembly")
	main._gold_before_effects = main.game_state.gold

	await main._on_battle_finished({
		"player_won": false,
		"ally_survived": 0,
		"enemy_survived": 1,
	})

	assert_eq(main.game_state.round_num, 2,
		"nonfatal battle result advances through settlement to next round")
	assert_eq(main.current_phase, main.Phase.BUILD)
	assert_false(main.game_over_popup.visible,
		"nonfatal settlement does not show game over")

	main.game_state.hp = 1
	main._gold_before_effects = main.game_state.gold
	await main._on_battle_finished({
		"player_won": false,
		"ally_survived": 0,
		"enemy_survived": 10,
	})

	assert_true(main._game_over, "fatal battle result sets game over flag")
	assert_true(main.game_over_popup.visible, "fatal result shows game over popup")
	assert_eq(main._meta_progress.runs_finished, 1)
	assert_eq(main._meta_progress.last_result, "defeat")

	var loaded = MetaProgressScript.new()
	loaded.load_or_create(TEST_META_PATH)
	assert_eq(loaded.runs_started, 1)
	assert_eq(loaded.runs_finished, 1)
	assert_eq(loaded.last_result, "defeat")


func test_live_battle_result_popup_explains_aftermath_before_settlement() -> void:
	var main = await _start_main_to_build()
	main.battle_result_delay_sec = 0.08
	main.game_state.round_num = 3
	main.game_state.hp = 30
	main.game_state.gold = 12
	main._gold_before_effects = main.game_state.gold
	main._last_ally_count = 4
	main._last_enemy_count = 9

	main._on_battle_finished({
		"player_won": false,
		"ally_survived": 0,
		"enemy_survived": 3,
	})
	await wait_process_frames(2)

	var ui := LiveUiProbe.snapshot(main)
	assert_eq(ui["active_modals"], [LiveUiProbe.BATTLE_RESULT],
		"battle result popup owns the UI before settlement continues")
	var details: Dictionary = ui["battle_result"]
	assert_eq(details.get("result_text", ""), "DEFEAT")
	var detail_text := str(details.get("detail_text", ""))
	assert_string_contains(detail_text, "Round 3 lost")
	assert_string_contains(detail_text, "Enemies: 3/9 survived")
	assert_string_contains(detail_text, "HP: 30 ->")
	assert_string_contains(detail_text, "Gold: 12 ->")
	assert_string_contains(detail_text, "Next:")
	var context: Dictionary = details.get("context", {})
	assert_eq(int(context.get("damage", -1)),
		GameState.compute_defeat_damage(3, 3),
		"popup context records the exact HP damage basis")

	await main.get_tree().create_timer(0.1).timeout
	assert_eq(main.current_phase, main.Phase.BUILD,
		"battle result auto-continues to settlement after the readable pause")
	ui = LiveUiProbe.snapshot(main)
	var recap: Dictionary = ui.get("last_settlement_recap", {})
	assert_true(bool(recap.get("visible", false)),
		"next BUILD shows a settlement recap after income is applied")
	var recap_text := str(recap.get("text", ""))
	assert_string_contains(recap_text, "LAST SETTLEMENT R3")
	assert_string_contains(recap_text, "Gold:")
	assert_string_contains(recap_text, "income")
	assert_string_contains(recap_text, "interest")
	assert_string_contains(recap_text, "Terazin:")
	assert_string_contains(recap_text, "Next: R4 BUILD")
	assert_string_contains(recap_text, "R4 boss reward this fight")
	var recap_data: Dictionary = recap.get("data", {})
	assert_eq(int(recap_data.get("round", -1)), 3)
	assert_eq(int(recap_data.get("next_round", -1)), 4)
	assert_eq(int(recap_data.get("gold_before", -1)), 12)
	assert_eq(int(recap_data.get("interest_basis_gold", -1)), 12)
	assert_eq(int(recap_data.get("gold_after", -1)),
		int(recap_data.get("gold_before", 0))
		+ int(recap_data.get("base_income", 0))
		+ int(recap_data.get("interest", 0)))


func test_live_first_boss_reward_pause_is_visible_and_actionable() -> void:
	var main = await _start_main_to_build()
	main.game_state.board[0] = CardInstance.create("sp_assembly")
	main.game_state.round_num = 4
	main._gold_before_effects = main.game_state.gold
	main.current_phase = main.Phase.BATTLE
	main.build_phase.visible = false

	await main._on_battle_finished({
		"player_won": true,
		"ally_survived": 1,
		"enemy_survived": 0,
	})

	assert_true(main.boss_reward_popup.visible,
		"surviving R4 pauses on boss reward choices")
	assert_false(main.battle_result_popup.visible,
		"battle result is cleared before reward selection")
	assert_eq(main.current_phase, main.Phase.BATTLE,
		"reward selection pauses before settlement advances")
	assert_eq(main.game_state.round_num, 4,
		"reward selection does not advance the round before a choice")
	var ui := LiveUiProbe.snapshot(main)
	assert_eq(ui["active_modals"], [LiveUiProbe.BOSS_REWARD],
		"boss reward popup owns the live UI")
	assert_true(ui["actionable"][LiveUiProbe.BOSS_REWARD],
		"boss reward popup has at least one visible selection")
	var choice_ids: Array[String] = LiveUiProbe.choice_ids(main, LiveUiProbe.BOSS_REWARD)
	assert_gt(choice_ids.size(), 0,
		"reward popup has selectable choices")
	var boss_details: Dictionary = ui.get("boss_reward", {})
	var summaries: Array = boss_details.get("choice_summaries", [])
	assert_eq(summaries.size(), choice_ids.size(),
		"observer exports rendered text for each boss reward card")
	assert_true(_boss_reward_summaries_have_rendered_text(summaries, choice_ids))

	var no_target_idx := _first_no_target_reward_index(choice_ids)
	assert_gte(no_target_idx, 0, "smoke chooses an immediately actionable reward")
	assert_false(bool(summaries[no_target_idx].get("needs_target", true)),
		"rendered summary marks the immediate reward as no-target")
	var no_target_reward := choice_ids[no_target_idx]
	assert_true(LiveUiProbe.select_choice(main, LiveUiProbe.BOSS_REWARD, no_target_idx),
		"popup selection path accepts the immediate reward")
	await wait_process_frames(2)

	assert_eq(main.game_state.round_num, 5,
		"selecting a reward settles R4 and advances to R5 build")
	assert_eq(main.current_phase, main.Phase.BUILD)
	assert_true(main.build_phase.visible, "build phase resumes after reward")
	ui = LiveUiProbe.snapshot(main)
	assert_false(ui["chain_visible"],
		"boss reward settlement returns to build without stale chain feedback")
	assert_false(main.boss_reward_popup.visible,
		"reward popup closes through its own selection path")
	assert_eq(LiveUiProbe.choice_ids(main, LiveUiProbe.BOSS_REWARD).size(), 0,
		"reward popup clears choices after selection")


func test_live_targeted_boss_reward_uses_target_overlay_and_applies_effect() -> void:
	var main = await _start_main_to_build()
	_clear_run_cards(main)
	var target: CardInstance = CardInstance.create("sp_assembly")
	var max_star_card: CardInstance = CardInstance.create("sp_workshop")
	max_star_card.evolve_star()
	max_star_card.evolve_star()
	main.game_state.board[0] = target
	main.game_state.board[1] = max_star_card
	main.game_state.terazin = 0
	main.game_state.round_num = 4
	main._gold_before_effects = main.game_state.gold
	main.current_phase = main.Phase.BATTLE
	main.build_phase.visible = false
	main.build_phase._refresh_all()

	var forced_choices: Array[String] = ["r4_1"]
	main.boss_reward_popup.show_choices(forced_choices)
	await wait_process_frames(1)

	var ui := LiveUiProbe.snapshot(main)
	assert_eq(ui["active_modals"], [LiveUiProbe.BOSS_REWARD],
		"forced targeted boss reward owns the live UI before selection")
	assert_eq(ui["choices"][LiveUiProbe.BOSS_REWARD], ["r4_1"])
	var boss_details: Dictionary = ui.get("boss_reward", {})
	var summaries: Array = boss_details.get("choice_summaries", [])
	assert_eq(summaries.size(), 1)
	assert_true(_boss_reward_summaries_have_rendered_text(summaries, ["r4_1"]))
	assert_true(bool(summaries[0].get("needs_target", false)),
		"rendered summary marks targeted rewards before target overlay opens")
	assert_true(LiveUiProbe.select_choice(main, LiveUiProbe.BOSS_REWARD, 0),
		"popup selection path accepts the targeted reward")
	await wait_process_frames(2)

	ui = LiveUiProbe.snapshot(main)
	assert_eq(ui["active_modals"], [LiveUiProbe.TARGET_SELECT],
		"targeted reward opens the field target overlay")
	assert_true(ui["actionable"][LiveUiProbe.TARGET_SELECT],
		"target overlay has an eligible field target")
	assert_true(main.build_phase.visible,
		"build surface is visible while choosing a boss reward target")
	assert_false(main.boss_reward_popup.visible,
		"boss reward popup closes before target selection")
	assert_eq(LiveUiProbe.target_field_indices(main), [0],
		"only non-max-star card is selectable for r4_1")
	var target_details: Dictionary = ui["target_select"]
	var preview_text := "\n".join(target_details.get("preview_texts", []))
	assert_string_contains(str(target_details.get("instruction", "")),
		"choose target card")
	assert_string_contains(preview_text, "★1 -> ★2")
	assert_string_contains(preview_text, "MAX ★3")
	var layout_rects: Dictionary = ui["layout_rects"]
	assert_true(layout_rects.get("target_instruction", {}).get("visible", false),
		"observer exports visible target instruction rect")
	assert_true(layout_rects.get("target_detail", {}).get("visible", false),
		"observer exports visible target detail rect")
	assert_true(layout_rects.get("confirm_button", {}).get("visible", false),
		"observer exports visible confirm button rect")

	assert_eq(target.star_level, 1)
	assert_eq(main.game_state.terazin, 0)
	assert_true(LiveUiProbe.select_target(main, 0),
		"public target overlay selection accepts the eligible card")
	await wait_process_frames(2)

	ui = LiveUiProbe.snapshot(main)
	assert_eq(target.star_level, 2,
		"r4_1 evolves the selected target")
	assert_gte(main.game_state.terazin, 4,
		"r4_1 grants its target reward terazin before settlement income")
	assert_eq(main.game_state.round_num, 5,
		"targeted reward settles R4 and advances to R5")
	assert_eq(main.current_phase, main.Phase.BUILD)
	assert_true(main.build_phase.visible)
	assert_false(ui["has_modal"],
		"targeted reward selection returns modal ownership to build")
	assert_false(ui["chain_visible"],
		"targeted reward settlement does not leave stale chain feedback")
	assert_false(main.build_phase.target_overlay.visible,
		"target overlay closes after target selection")


func test_live_boss_reward_continuity_r4_r8_r12() -> void:
	var main = await _start_main_to_build()
	main.game_state.board[0] = CardInstance.create("sp_assembly")
	var selected_rewards: Array[String] = []

	for boss_round in [4, 8, 12]:
		var selected_reward: String = await _win_boss_round_and_select_immediate_reward(
			main, boss_round)
		selected_rewards.append(selected_reward)

	assert_eq(main.current_phase, main.Phase.BUILD)
	assert_eq(main.game_state.round_num, 13)
	assert_true(main.build_phase.visible,
		"R12 reward settlement resumes the R13 build")
	assert_false(main.boss_reward_popup.visible)
	assert_false(main.battle_result_popup.visible)
	assert_eq(selected_rewards.size(), 3,
		"three boss reward selections completed")
	for reward_id in selected_rewards:
		assert_ne(reward_id, "")


func test_live_final_round_victory_saves_meta() -> void:
	var main = await _start_main_to_build()
	main.game_state.board[0] = CardInstance.create("sp_assembly")
	main.game_state.round_num = Enums.MAX_ROUNDS
	main.game_state.hp = 7
	main._gold_before_effects = main.game_state.gold

	await main._on_battle_finished({
		"player_won": true,
		"ally_survived": 1,
		"enemy_survived": 0,
	})

	assert_true(main._game_over, "final-round win ends the run")
	assert_true(main.game_over_popup.visible, "victory result shows overlay")
	assert_eq(main.game_over_popup.title_label.text, "VICTORY!")
	assert_string_contains(main.game_over_popup.summary_label.text,
		"New unlocks available")
	assert_string_contains(main.game_over_popup.summary_label.text, "난이도 2")
	var ui := LiveUiProbe.snapshot(main)
	assert_eq(ui["active_modals"], [LiveUiProbe.GAME_OVER],
		"observer reports game-over ownership")
	assert_string_contains(ui["game_over"].get("summary_text", ""),
		"New unlocks available")
	assert_eq(main._meta_progress.runs_finished, 1)
	assert_eq(main._meta_progress.last_result, "victory")

	var loaded = MetaProgressScript.new()
	loaded.load_or_create(TEST_META_PATH)
	assert_eq(loaded.runs_started, 1)
	assert_eq(loaded.runs_finished, 1)
	assert_eq(loaded.last_result, "victory")
	assert_eq(loaded.max_difficulty_unlocked, 2)


func _start_main_to_build(
		talisman_type: int = Enums.TalismanType.FLINT):
	var main = MainScene.instantiate()
	main.meta_progress_save_path = TEST_META_PATH
	main.battle_result_delay_sec = 0.0
	main.play_logger_enabled = false
	add_child_autofree(main)
	await wait_process_frames(2)

	var ui := LiveUiProbe.snapshot(main)
	assert_eq(ui["active_modals"], [LiveUiProbe.RUN_START],
		"main scene starts with run-start owning the UI")
	assert_true(ui["actionable"][LiveUiProbe.RUN_START],
		"run-start screen has an actionable start button")
	assert_true(LiveUiProbe.press_run_start(main),
		"observer presses the run-start button")
	await wait_process_frames(2)

	ui = LiveUiProbe.snapshot(main)
	assert_eq(ui["active_modals"], [LiveUiProbe.COMMANDER_SELECT],
		"commander selection owns the UI after start")
	assert_true(str(Enums.CommanderType.GAMBLER) in ui["choices"][LiveUiProbe.COMMANDER_SELECT],
		"requested commander is visible")
	var commander_details: Dictionary = ui.get("commander_select", {})
	var commander_context: String = str(commander_details.get("context_text", ""))
	assert_string_contains(commander_context, "커맨더")
	assert_string_contains(commander_context, "런 전체")
	assert_true(_rect_is_visible(commander_details.get("context_rect", {})),
		"commander selection context is visible")
	assert_true(LiveUiProbe.select_commander(main, Enums.CommanderType.GAMBLER),
		"observer selects the requested commander")
	await wait_process_frames(2)

	ui = LiveUiProbe.snapshot(main)
	assert_eq(ui["active_modals"], [LiveUiProbe.TALISMAN_SELECT],
		"talisman selection owns the UI after commander")
	assert_true(str(talisman_type) in ui["choices"][LiveUiProbe.TALISMAN_SELECT],
		"requested talisman is visible")
	var talisman_details: Dictionary = ui.get("talisman_select", {})
	var talisman_context: String = str(talisman_details.get("context_text", ""))
	assert_string_contains(talisman_context, "선택한 커맨더")
	assert_string_contains(talisman_context, "도박꾼")
	assert_string_contains(talisman_context, "부적")
	assert_true(_rect_is_visible(talisman_details.get("context_rect", {})),
		"talisman selection context is visible")
	assert_true(LiveUiProbe.select_talisman(main, talisman_type),
		"observer selects the requested talisman")
	await wait_process_frames(3)

	ui = LiveUiProbe.snapshot(main)
	assert_false(ui["has_modal"],
		"run setup returns control to the build phase")
	var readiness: Dictionary = ui.get("build_readiness", {})
	var readiness_text: String = str(readiness.get("text", ""))
	assert_true(bool(readiness.get("visible", false)),
		"BUILD readiness cue is visible after real run setup")
	assert_string_contains(readiness_text, "FIELD:")
	assert_string_contains(readiness_text, "체인/전투")
	assert_string_contains(readiness_text, "BENCH:")
	assert_string_contains(readiness_text, "ENEMY:")
	assert_string_contains(readiness_text, "Next:")
	assert_true(_rect_is_visible(readiness.get("rect", {})),
		"BUILD readiness cue has a visible rect")
	var milestone: Dictionary = ui.get("run_milestone", {})
	var milestone_text := str(milestone.get("text", ""))
	var round_label_text := str(milestone.get("round_label_text", ""))
	assert_true(bool(milestone.get("visible", false)),
		"run milestone is visible in the BUILD HUD")
	assert_string_contains(milestone_text, "Goal:")
	assert_string_contains(milestone_text, "R4 boss reward")
	assert_string_contains(round_label_text, "Round 1/15")
	assert_string_contains(round_label_text, "R4 boss reward")
	assert_true(_rect_is_visible(milestone.get("rect", {})),
		"run milestone has a visible rect")
	var enemy_preview: Dictionary = ui.get("enemy_pressure_preview", {})
	var enemy_preview_text := str(enemy_preview.get("text", ""))
	var enemy_preview_data: Dictionary = enemy_preview.get("data", {})
	assert_true(bool(enemy_preview.get("visible", false)),
		"enemy pressure preview is visible before BUILD COMPLETE")
	assert_string_contains(enemy_preview_text, "ENEMY:")
	assert_string_contains(enemy_preview_text, "ATK")
	assert_string_contains(enemy_preview_text, "HP")
	assert_false(bool(enemy_preview_data.get("exact", true)),
		"enemy pressure preview is explicitly non-exact")
	var rects: Dictionary = ui.get("layout_rects", {})
	assert_false(_rects_intersect(
		readiness.get("rect", {}),
		rects.get("confirm_button", {})),
		"BUILD readiness cue does not overlap BUILD COMPLETE")
	assert_false(_rects_intersect(
		readiness.get("rect", {}),
		rects.get("field_container", {})),
		"BUILD readiness cue does not overlap FIELD cards")

	return main


func _first_no_target_reward_index(reward_ids: Array[String]) -> int:
	for i in reward_ids.size():
		if int(BossRewardDB.get_data(reward_ids[i]).get("needs_target", 0)) == 0:
			return i
	return -1


func _clear_run_cards(main) -> void:
	for i in main.game_state.board.size():
		main.game_state.board[i] = null
	for i in main.game_state.bench.size():
		main.game_state.bench[i] = null


func _card_has_upgrade_id(card: CardInstance, upgrade_id: String) -> bool:
	for upgrade in card.upgrades:
		if upgrade.get("id", "") == upgrade_id:
			return true
	return false


func _boss_reward_summaries_have_rendered_text(
		summaries: Array, ids: Array[String]) -> bool:
	if summaries.size() != ids.size():
		return false
	for i in summaries.size():
		var summary: Dictionary = summaries[i]
		if str(summary.get("id", "")) != ids[i]:
			return false
		for key in ["name", "type", "desc", "text"]:
			if str(summary.get(key, "")).strip_edges() == "":
				return false
		var text := str(summary.get("text", ""))
		if not text.contains(str(summary.get("name", ""))):
			return false
		if not text.contains(str(summary.get("desc", ""))):
			return false
		var rect: Dictionary = summary.get("rect", {})
		if float(rect.get("w", 0.0)) <= 0.0 or float(rect.get("h", 0.0)) <= 0.0:
			return false
	return true


func _rect_is_visible(value) -> bool:
	var rect: Dictionary = value if value is Dictionary else {}
	return bool(rect.get("visible", false)) \
		and float(rect.get("w", 0.0)) > 0.0 \
		and float(rect.get("h", 0.0)) > 0.0


func _rects_intersect(a_value, b_value) -> bool:
	var a: Dictionary = a_value if a_value is Dictionary else {}
	var b: Dictionary = b_value if b_value is Dictionary else {}
	if not bool(a.get("visible", false)) or not bool(b.get("visible", false)):
		return false
	var ax := float(a.get("x", 0.0))
	var ay := float(a.get("y", 0.0))
	var aw := float(a.get("w", 0.0))
	var ah := float(a.get("h", 0.0))
	var bx := float(b.get("x", 0.0))
	var by := float(b.get("y", 0.0))
	var bw := float(b.get("w", 0.0))
	var bh := float(b.get("h", 0.0))
	return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by


func _win_boss_round_and_select_immediate_reward(main, boss_round: int) -> String:
	main.game_state.round_num = boss_round
	main._gold_before_effects = main.game_state.gold
	main.current_phase = main.Phase.BATTLE
	main.build_phase.visible = false

	await main._on_battle_finished({
		"player_won": true,
		"ally_survived": 1,
		"enemy_survived": 0,
	})

	assert_true(main.boss_reward_popup.visible,
		"R%d survival pauses on boss reward choices" % boss_round)
	assert_false(main.battle_result_popup.visible,
		"R%d clears battle result before reward choice" % boss_round)
	assert_eq(main.current_phase, main.Phase.BATTLE,
		"R%d reward pauses before settlement" % boss_round)
	assert_eq(main.game_state.round_num, boss_round,
		"R%d does not advance until reward is selected" % boss_round)
	var ui := LiveUiProbe.snapshot(main)
	assert_eq(ui["active_modals"], [LiveUiProbe.BOSS_REWARD],
		"R%d boss reward owns the live UI" % boss_round)
	assert_true(ui["actionable"][LiveUiProbe.BOSS_REWARD],
		"R%d boss reward has actionable choices" % boss_round)
	var choice_ids: Array[String] = LiveUiProbe.choice_ids(main, LiveUiProbe.BOSS_REWARD)
	assert_gt(choice_ids.size(), 0,
		"R%d has selectable reward choices" % boss_round)

	var no_target_idx := _first_no_target_reward_index(choice_ids)
	assert_gte(no_target_idx, 0,
		"R%d smoke chooses an immediately actionable reward" % boss_round)
	var no_target_reward := choice_ids[no_target_idx]
	assert_true(LiveUiProbe.select_choice(main, LiveUiProbe.BOSS_REWARD, no_target_idx),
		"R%d popup selection path accepts the immediate reward" % boss_round)
	await wait_process_frames(2)

	assert_eq(main.game_state.round_num, boss_round + 1,
		"R%d reward settles and advances one round" % boss_round)
	assert_eq(main.current_phase, main.Phase.BUILD,
		"R%d reward resumes build phase" % boss_round)
	assert_true(main.build_phase.visible,
		"R%d build phase visible after reward" % boss_round)
	var ui_after := LiveUiProbe.snapshot(main)
	assert_false(ui_after["chain_visible"],
		"R%d reward settlement returns to build without stale chain feedback" % boss_round)
	assert_false(main.boss_reward_popup.visible,
		"R%d reward popup closed after selection" % boss_round)
	assert_eq(LiveUiProbe.choice_ids(main, LiveUiProbe.BOSS_REWARD).size(), 0,
		"R%d reward popup choices cleared after selection" % boss_round)
	assert_false(main.battle_result_popup.visible,
		"R%d battle result remains cleared after settlement" % boss_round)
	return no_target_reward
